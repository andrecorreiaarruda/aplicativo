"""Auto-roteamento: reenviar imagens novas a outros nós por regra.

Equivale ao DicomDatabase+Routing do Horos. Lá, cada lote de imagens
acrescentado à base passa pelas regras ativas; as que batem entram numa
fila em memória, e um NSTimer de 10 s dispara uma thread que envia a fila
com o StoreSCU, uma associação por paciente, e devolve à fila os grupos
que falharam (failureRetry - 1).

Diferenças deliberadas, todas por bugs apontados no código do Horos:

- a fila mora numa tabela da base SQLite e sobrevive a um encerramento ou
  queda (no Horos ela se perde ao fechar o programa);
- a regra aponta para o id do nó, não para a descrição;
- a nova tentativa espera os 30 s que a interface do Horos promete (lá ela
  vem no tique seguinte do timer, depois de 4 s de espera);
- só os arquivos que falharam voltam à fila, não o grupo inteiro.
"""

from __future__ import annotations

import logging
import threading
import time
from pathlib import Path
from typing import Callable

from ..database import Database, ImportResult, fold_text
from .config import ROUTE_ALL, NetworkConfig, RoutingRule

INTERVAL = 10.0  # o NSTimer do Horos
RETRY_DELAY = 30.0  # "Try N times each 30 secs"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS routing_queue (
    id INTEGER PRIMARY KEY,
    rule_id TEXT NOT NULL,
    node_id TEXT NOT NULL,
    image_id INTEGER NOT NULL REFERENCES image(id) ON DELETE CASCADE,
    retries_left INTEGER NOT NULL,
    next_attempt REAL NOT NULL,
    state TEXT NOT NULL DEFAULT 'pending',
    last_error TEXT NOT NULL DEFAULT '',
    UNIQUE (node_id, image_id)
);
CREATE INDEX IF NOT EXISTS routing_queue_due ON routing_queue (state, next_attempt);
"""

EventFn = Callable[[str, dict], None]


def rule_matches(rule: RoutingRule, row, origin: str | None) -> bool:
    """A imagem (linha de image + series + study) passa no filtro da regra?

    `origin` None é a aplicação manual ("Apply this Routing Rule to
    Selection" no Horos), que não olha a origem.
    """
    if origin is not None and rule.origin != ROUTE_ALL and rule.origin != origin:
        return False
    if rule.modalities and str(row["modality"] or "").upper() not in rule.modalities:
        return False
    if rule.calling_ae and str(row["source_ae"] or "").strip().upper() != rule.calling_ae.upper():
        return False
    if rule.description and fold_text(rule.description) not in fold_text(row["study_description"]):
        return False
    return True


class Router:
    def __init__(self, database: Database, config: Callable[[], NetworkConfig], on_event: EventFn | None = None):
        self.db = database
        self.config = config
        self.on_event = on_event or (lambda kind, data: None)
        self._logger = logging.getLogger("horus.net.routing")
        self._wake = threading.Event()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._busy = threading.Lock()
        with self.db.connect() as conn:
            conn.executescript(_SCHEMA)

    # ------------------------------------------------------ ciclo de vida

    def start(self) -> None:
        if self._thread is not None:
            return
        self._stop.clear()
        if self.on_added not in self.db.added_hooks:
            self.db.added_hooks.append(self.on_added)
        self._thread = threading.Thread(target=self._run, name="horus-roteamento", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        if self.on_added in self.db.added_hooks:
            self.db.added_hooks.remove(self.on_added)
        if self._thread is None:
            return
        self._stop.set()
        self._wake.set()
        self._thread.join(timeout=30)
        self._thread = None

    def _log(self, text: str, level: int = logging.INFO) -> None:
        self._logger.log(level, text)
        self.on_event("log", {"text": "roteamento: " + text})

    # ------------------------------------------------------------- fila

    def on_added(self, result: ImportResult) -> None:
        """Gancho da base: imagens novas passam pelas regras ativas."""
        config = self.config()
        if not config.routing_enabled or not result.image_ids:
            return
        try:
            self.enqueue(result.image_ids, origin=result.origin)
        except Exception as exc:  # o roteamento nunca derruba a importação
            self._log(f"falha ao avaliar as regras: {exc}", logging.ERROR)

    def enqueue(self, image_ids: list[int], origin: str | None = None, rules: list[RoutingRule] | None = None) -> int:
        """Põe na fila as imagens que batem com as regras; devolve quantas.

        Sem `origin`, é a aplicação manual: vale mesmo com o auto-roteamento
        desligado, mas só para regras ativas, como no Horos.
        """
        config = self.config()
        active = [r for r in (rules if rules is not None else config.rules) if r.enabled]
        if not active or not image_ids:
            return 0
        now = time.time()
        queued = 0
        with self.db.connect() as conn:
            for start in range(0, len(image_ids), 500):
                chunk = image_ids[start:start + 500]
                marks = ",".join("?" * len(chunk))
                rows = conn.execute(
                    f"""SELECT image.id, image.source_ae, series.modality, study.study_description
                        FROM image JOIN series ON series.id = image.series_id
                        JOIN study ON study.id = series.study_id
                        WHERE image.id IN ({marks})""",
                    chunk,
                ).fetchall()
                for rule in active:
                    for row in rows:
                        if rule_matches(rule, row, origin):
                            cur = conn.execute(
                                """INSERT OR IGNORE INTO routing_queue
                                   (rule_id, node_id, image_id, retries_left, next_attempt)
                                   VALUES (?, ?, ?, ?, ?)""",
                                (rule.id, rule.destination, row["id"], int(rule.retries), now),
                            )
                            queued += cur.rowcount
        if queued:
            self._log(f"{queued} imagem(ns) na fila")
            self._wake.set()
        return queued

    def counts(self) -> dict[str, int]:
        with self.db.connect() as conn:
            rows = conn.execute("SELECT state, COUNT(*) AS n FROM routing_queue GROUP BY state").fetchall()
        found = {r["state"]: r["n"] for r in rows}
        return {"pending": found.get("pending", 0), "failed": found.get("failed", 0)}

    def retry_failed(self) -> int:
        with self.db.connect() as conn:
            cur = conn.execute(
                "UPDATE routing_queue SET state = 'pending', retries_left = 0, next_attempt = ? WHERE state = 'failed'",
                (time.time(),),
            )
        self._wake.set()
        return cur.rowcount

    def discard_failed(self) -> int:
        with self.db.connect() as conn:
            return conn.execute("DELETE FROM routing_queue WHERE state = 'failed'").rowcount

    # ------------------------------------------------------------ envio

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                self.process_due()
            except Exception as exc:
                self._log(f"erro inesperado: {exc}", logging.ERROR)
            self._wake.wait(INTERVAL)
            self._wake.clear()

    def process_due(self) -> int:
        """Envia o que está vencido na fila; devolve quantas imagens foram."""
        from . import scu

        if not self._busy.acquire(blocking=False):
            return 0
        try:
            with self.db.connect() as conn:
                rows = conn.execute(
                    """SELECT q.id, q.node_id, q.retries_left, image.path, study.patient_id
                       FROM routing_queue q JOIN image ON image.id = q.image_id
                       JOIN series ON series.id = image.series_id
                       JOIN study ON study.id = series.study_id
                       WHERE q.state = 'pending' AND q.next_attempt <= ?
                       ORDER BY q.node_id, study.patient_id, q.id""",
                    (time.time(),),
                ).fetchall()
            if not rows:
                return 0
            config = self.config()
            sent_total = 0
            groups: dict[tuple[str, str], list] = {}
            for row in rows:
                groups.setdefault((row["node_id"], row["patient_id"]), []).append(row)
            for (node_id, patient_id), items in groups.items():
                if self._stop.is_set():
                    break
                node = config.node_by_id(node_id)
                if node is None:
                    self._fail(items, "o nó de destino foi removido", final=True)
                    continue
                present = [r for r in items if Path(r["path"]).exists()]
                missing = [r for r in items if not Path(r["path"]).exists()]
                if missing:
                    self._fail(missing, "arquivo não encontrado", final=True)
                if not present:
                    continue
                # Uma associação por paciente, como o Horos.
                result = scu.send(config.local, node, [r["path"] for r in present], cancelled=self._stop.is_set)
                sent = set(result.sent_paths)
                errors = dict(result.failed)
                done = [r for r in present if r["path"] in sent]
                failed = [r for r in present if r["path"] in errors]
                with self.db.connect() as conn:
                    conn.executemany("DELETE FROM routing_queue WHERE id = ?", [(r["id"],) for r in done])
                for reason in sorted({errors[r["path"]] for r in failed}):
                    self._fail([r for r in failed if errors[r["path"]] == reason], reason)
                sent_total += len(done)
                label = f"paciente {patient_id}" if patient_id else "sem ID de paciente"
                if done:
                    self._log(f"{len(done)} imagem(ns) enviada(s) a {node.describe()} ({label})")
                if failed:
                    self._log(f"{len(failed)} imagem(ns) não enviada(s) a {node.describe()}: {next(iter(errors.values()))}", logging.WARNING)
            return sent_total
        finally:
            self._busy.release()

    def _fail(self, rows, reason: str, final: bool = False) -> None:
        """Conta uma tentativa; sem tentativas restantes, a linha fica como falha."""
        now = time.time()
        with self.db.connect() as conn:
            for r in rows:
                left = -1 if final else r["retries_left"] - 1
                if left < 0:
                    conn.execute("UPDATE routing_queue SET state = 'failed', last_error = ? WHERE id = ?", (reason, r["id"]))
                else:
                    conn.execute(
                        "UPDATE routing_queue SET retries_left = ?, next_attempt = ?, last_error = ? WHERE id = ?",
                        (left, now + RETRY_DELAY, reason, r["id"]),
                    )
