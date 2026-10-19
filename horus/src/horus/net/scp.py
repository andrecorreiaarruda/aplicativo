"""O listener: o Horus como SCP de verificação, armazenamento e Q/R.

No Horos, o AppController inicia o DCMTKQueryRetrieveSCP, que roda o
`dcmqrscp` modificado do DCMTK: recebe C-STORE em INCOMING.noindex, de
onde a base importa os arquivos, e atende C-FIND/C-MOVE/C-GET consultando
a base Core Data. Aqui:

* cada C-STORE é gravado como chegou (bytes originais, sem decodificar)
  em `INCOMING.noindex/<aleatório>.part`, renomeado para `.dcm` quando
  completo — um arquivo pela metade nunca é importado;
* uma única thread importa os arquivos em lote para a base (o SQLite tem
  um só escritor de cada vez), movendo-os para DATABASE.noindex;
* C-FIND consulta a base pelo QueryEngine; C-MOVE só envia para nós
  cadastrados (o destino é escolhido pelo AE title); C-GET devolve pela
  própria associação.

No Windows, a primeira vez que o executável abre a porta, o Firewall do
Windows Defender pergunta se libera o acesso; sem liberar, equipamentos
de outras máquinas não conseguem enviar.
"""

from __future__ import annotations

import logging
import queue
import shutil
import ssl
import threading
import time
import uuid
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from logging.handlers import RotatingFileHandler
from pathlib import Path

import pydicom
from pynetdicom import AE, evt
from pynetdicom.dsutils import encode_file_meta
from pynetdicom.presentation import AllStoragePresentationContexts
from pynetdicom.sop_class import (
    PatientRootQueryRetrieveInformationModelFind,
    PatientRootQueryRetrieveInformationModelGet,
    PatientRootQueryRetrieveInformationModelMove,
    StudyRootQueryRetrieveInformationModelFind,
    StudyRootQueryRetrieveInformationModelGet,
    StudyRootQueryRetrieveInformationModelMove,
    Verification,
)

from .. import paths
from ..database import ORIGIN_RECEIVED, Database
from .config import SEND_KEEP, LocalSettings, NetworkConfig, Node
from .query import PATIENT_ROOT, STUDY_ROOT, QueryEngine, QueryError, RetrieveItem
from .scu import client_ssl_context
from .transfer import (
    ACCEPTED_SYNTAXES,
    FileInfo,
    accepted_for,
    build_contexts,
    prepare_for,
)

_FIND = {PatientRootQueryRetrieveInformationModelFind: PATIENT_ROOT, StudyRootQueryRetrieveInformationModelFind: STUDY_ROOT}
QR_CLASSES = [
    PatientRootQueryRetrieveInformationModelFind,
    PatientRootQueryRetrieveInformationModelMove,
    PatientRootQueryRetrieveInformationModelGet,
    StudyRootQueryRetrieveInformationModelFind,
    StudyRootQueryRetrieveInformationModelMove,
    StudyRootQueryRetrieveInformationModelGet,
]
FAILED_DIR = "FALHAS"
# AE impossível de ocorrer (tem espaço interno), usado para recusar todos
# quando só nós cadastrados são aceitos e a lista está vazia: no pynetdicom
# uma lista vazia em require_calling_aet significa "aceitar qualquer um".
_NOBODY = "HORUS NO PEER"

EventFn = Callable[[str, dict], None]


class ListenerError(RuntimeError):
    pass


@dataclass
class ListenerStats:
    associations: int = 0
    received: int = 0
    imported: int = 0
    duplicates: int = 0
    rejected_files: int = 0
    queries: int = 0
    retrieves: int = 0


def server_ssl_context(local: LocalSettings) -> ssl.SSLContext:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(local.tls_cert_file, local.tls_key_file)
    if local.tls_require_client_cert:
        if local.tls_ca_file:
            ctx.load_verify_locations(local.tls_ca_file)
        else:
            ctx.load_default_certs(ssl.Purpose.CLIENT_AUTH)
        ctx.verify_mode = ssl.CERT_REQUIRED
    return ctx


class DicomListener:
    def __init__(self, database: Database, config: NetworkConfig, on_event: EventFn | None = None):
        self.db = database
        self.config = config
        self.on_event = on_event or (lambda kind, data: None)
        self.engine = QueryEngine(database, config.local.max_find_results)
        self.incoming = database.base_dir / paths.INCOMING_DIR_NAME
        self.failed_dir = self.incoming / FAILED_DIR
        self.stats = ListenerStats()
        self.activity: deque[tuple[float, str]] = deque(maxlen=500)
        self._server = None
        self._queue: queue.Queue[Path | None] = queue.Queue()
        self._importer: threading.Thread | None = None
        self._flush = threading.Event()
        self._disk_checked_at = -1e9
        self._disk_low = False
        self._logger = self._make_logger()

    # ------------------------------------------------------------ registro

    def _make_logger(self) -> logging.Logger:
        logger = logging.getLogger(f"horus.net.{id(self)}")
        logger.setLevel(logging.INFO)
        logger.propagate = False
        log_dir = self.db.base_dir / "logs"
        try:
            log_dir.mkdir(exist_ok=True)
            handler = RotatingFileHandler(log_dir / "rede.log", maxBytes=1_000_000, backupCount=5, encoding="utf-8")
            handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
            logger.addHandler(handler)
        except OSError:
            pass
        return logger

    def _log(self, text: str, level: int = logging.INFO) -> None:
        self.activity.append((time.time(), text))
        self._logger.log(level, text)
        self.on_event("log", {"text": text})

    # ------------------------------------------------------ ciclo de vida

    @property
    def running(self) -> bool:
        return self._server is not None

    def address(self) -> str:
        local = self.config.local
        return f"{local.ae_title}@{local.bind_address or '0.0.0.0'}:{local.port}"

    def start(self) -> None:
        if self._server is not None:
            return
        local = self.config.local.validate()
        self.incoming.mkdir(parents=True, exist_ok=True)
        paths.mark_not_indexed(self.incoming)
        ae = self._build_ae(local)
        handlers = [
            (evt.EVT_C_STORE, self._on_store),
            (evt.EVT_C_FIND, self._on_find),
            (evt.EVT_C_MOVE, self._on_move),
            (evt.EVT_C_GET, self._on_get),
            (evt.EVT_ACCEPTED, self._on_accepted),
            (evt.EVT_REJECTED, self._on_rejected),
            (evt.EVT_RELEASED, lambda e: self._flush.set()),
            (evt.EVT_ABORTED, self._on_aborted),
        ]
        ssl_context = server_ssl_context(local) if local.tls_enabled else None
        try:
            self._server = ae.start_server(
                (local.bind_address or "", local.port),
                block=False,
                evt_handlers=handlers,
                ssl_context=ssl_context,
            )
        except OSError as exc:
            raise ListenerError(
                f"não foi possível abrir a porta {local.port}: {exc.strerror or exc}. "
                "Outro programa (ou outra cópia do Horus) pode estar usando a porta."
            ) from exc
        self._importer = threading.Thread(target=self._import_loop, name="horus-incoming", daemon=True)
        self._importer.start()
        self._recover_incoming()
        self._log(f"listener ativo em {self.address()}" + (" com TLS" if ssl_context else ""))
        self.on_event("state", {"running": True})

    def stop(self) -> None:
        if self._server is None:
            return
        self._server.shutdown()
        self._server = None
        self._queue.put(None)
        if self._importer is not None:
            self._importer.join(timeout=30)
            self._importer = None
        self._log("listener parado")
        self.on_event("state", {"running": False})

    def restart(self, config: NetworkConfig | None = None) -> None:
        self.stop()
        if config is not None:
            self.config = config
        self.start()

    def _build_ae(self, local: LocalSettings) -> AE:
        ae = AE(ae_title=local.ae_title)
        ae.acse_timeout = local.acse_timeout
        ae.dimse_timeout = local.dimse_timeout
        ae.network_timeout = local.network_timeout
        ae.maximum_pdu_size = local.max_pdu
        ae.maximum_associations = local.max_associations
        ae.require_called_aet = local.require_called_ae
        if not local.accept_unknown_callers:
            known = [n.ae_title for n in self.config.nodes]
            ae.require_calling_aet = known or [_NOBODY]
        ae.add_supported_context(Verification)
        for cx in AllStoragePresentationContexts:
            # scp_role=True aceita o papel de SCP proposto por quem pede
            # C-GET (as imagens voltam para ele na mesma associação).
            ae.add_supported_context(cx.abstract_syntax, ACCEPTED_SYNTAXES, scu_role=False, scp_role=True)
        if local.qr_server_enabled:
            for sop in QR_CLASSES:
                ae.add_supported_context(sop)
        return ae

    # ------------------------------------------------------------ eventos

    def _on_accepted(self, event) -> None:
        self.stats.associations += 1
        req = event.assoc.requestor
        self._log(f"associação aceita de {req.ae_title} ({req.address})")

    def _on_rejected(self, event) -> None:
        req = event.assoc.requestor
        self._log(f"associação recusada de {req.ae_title} ({req.address})", logging.WARNING)

    def _on_aborted(self, event) -> None:
        self._flush.set()
        self._log("associação interrompida (A-ABORT)", logging.WARNING)

    def _caller_node(self, event) -> Node | None:
        return self.config.node_by_ae(event.assoc.requestor.ae_title)

    # ------------------------------------------------------------ C-STORE

    def _disk_full(self) -> bool:
        """Mesmo critério do Horos: menos de min(300 MB, 1% do volume) livre.

        A consulta ao disco é refeita no máximo a cada 20 s, como lá
        (isFileSystemFreeSizeLimitReached).
        """
        now = time.monotonic()
        if now - self._disk_checked_at > 20:
            self._disk_checked_at = now
            try:
                usage = shutil.disk_usage(self.incoming)
                self._disk_low = usage.free < min(300 * 1024 * 1024, usage.total // 100)
            except OSError:
                self._disk_low = False
        return self._disk_low

    def _on_store(self, event) -> int:
        if self._disk_full():
            self._log("C-STORE recusado: disco da base quase cheio", logging.ERROR)
            return 0xA700  # sem recursos
        name = uuid.uuid4().hex
        part = self.incoming / f"{name}.part"
        final = self.incoming / f"{name}.dcm"
        try:
            # Bytes do objeto como chegaram, sem decodificar; só a meta de
            # arquivo é montada aqui, com o AE de quem enviou em Source
            # Application Entity Title (putSrcAETitleInSourceApplication-
            # EntityTitle, ligado por padrão no Horos).
            meta = event.file_meta
            meta.SourceApplicationEntityTitle = event.assoc.requestor.ae_title
            data = b"".join((b"\x00" * 128, b"DICM", encode_file_meta(meta), event.request.DataSet.getvalue()))
        except Exception as exc:
            self._log(f"C-STORE ilegível: {exc}", logging.ERROR)
            return 0xC210  # não foi possível entender o objeto
        try:
            part.write_bytes(data)
            part.replace(final)
        except OSError as exc:
            part.unlink(missing_ok=True)
            self._log(f"falha ao gravar o objeto recebido: {exc}", logging.ERROR)
            return 0xA700  # sem recursos (disco cheio, permissão)
        self.stats.received += 1
        self._queue.put(final)
        return 0x0000

    def _recover_incoming(self) -> None:
        """Retoma arquivos que ficaram em INCOMING num encerramento anterior."""
        for leftover in sorted(self.incoming.glob("*.part")):
            leftover.unlink(missing_ok=True)
        for leftover in sorted(self.incoming.glob("*.dcm")):
            self._queue.put(leftover)

    def _import_loop(self) -> None:
        batch: list[Path] = []
        stop = False
        while not stop:
            try:
                item = self._queue.get(timeout=0.5)
                if item is None:
                    stop = True
                else:
                    batch.append(item)
                    if len(batch) < 200 and not self._flush.is_set():
                        continue
            except queue.Empty:
                pass
            if batch and (stop or self._queue.empty() or len(batch) >= 200):
                self._import_batch(batch)
                batch = []
                self._flush.clear()

    def _import_batch(self, batch: list[Path]) -> None:
        try:
            result = self.db.add_files(batch, move=True, origin=ORIGIN_RECEIVED)
        except Exception as exc:  # base travada, disco cheio
            self._log(f"falha ao importar {len(batch)} objeto(s): {exc}", logging.ERROR)
            return
        errors = {Path(p) for p, _ in result.errors}
        for path in batch:
            if not path.exists():
                continue  # movido para a base
            if path in errors:
                self.failed_dir.mkdir(exist_ok=True)
                shutil.move(str(path), self.failed_dir / path.name)
                self.stats.rejected_files += 1
            else:
                path.unlink(missing_ok=True)  # duplicado: a base já tem
                self.stats.duplicates += 1
        self.stats.imported += result.added
        if result.added:
            self._log(f"{result.added} imagem(ns) recebida(s) importada(s)")
        for p, msg in result.errors:
            self._log(f"objeto recebido recusado ({Path(p).name}): {msg}", logging.WARNING)
        self.on_event("imported", {"added": result.added, "study_ids": sorted(result.study_ids)})

    def wait_idle(self, timeout: float = 10.0) -> bool:
        """Espera a fila de importação esvaziar (testes e encerramento)."""
        deadline = time.time() + timeout
        self._flush.set()
        while time.time() < deadline:
            if self._queue.unfinished_tasks == 0 or self._queue.empty():
                time.sleep(0.6)
                if self._queue.empty():
                    return True
            time.sleep(0.1)
        return False

    # ------------------------------------------------------------- C-FIND

    def _on_find(self, event):
        model = _FIND.get(event.request.AffectedSOPClassUID, STUDY_ROOT)
        self.stats.queries += 1
        caller = event.assoc.requestor.ae_title
        try:
            matches = self.engine.find(event.identifier, model, retrieve_ae=self.config.local.ae_title)
            count = 0
            for ds in matches:
                if event.is_cancelled:
                    yield 0xFE00, None
                    return
                count += 1
                yield 0xFF00, ds
            self._log(f"C-FIND de {caller}: {count} resultado(s)")
        except QueryError as exc:
            self._log(f"C-FIND de {caller} recusado: {exc}", logging.WARNING)
            yield 0xA900, None  # identificador não corresponde ao modelo

    # ------------------------------------------------------ C-MOVE/C-GET

    def _load(self, items: list[RetrieveItem]) -> list[RetrieveItem]:
        present = [i for i in items if Path(i.path).exists()]
        if len(present) != len(items):
            self._log(f"{len(items) - len(present)} arquivo(s) da base não encontrado(s) no disco", logging.WARNING)
        return present

    def probe(self, node: Node, infos: list[FileInfo]) -> dict[str, list]:
        """Sintaxes que o destino aceita, por classe SOP.

        O pynetdicom abre a sub-associação do C-MOVE sozinho e não expõe o
        resultado da negociação; uma associação curta, só de negociação,
        descobre o que o destino aceita para cada imagem sair numa sintaxe
        válida — comprimida quando ele aceita, sem compressão quando não.
        """
        from .scu import NetworkError, associate, make_ae

        accepted: dict[str, list] = {}
        local = self.config.local
        for contexts in build_contexts(infos, SEND_KEEP):
            try:
                assoc = associate(make_ae(local), node, local, contexts=contexts)
            except NetworkError:
                return {}
            for cx in assoc.accepted_contexts:
                accepted.setdefault(cx.abstract_syntax, []).append(cx.transfer_syntax[0])
            assoc.release()
        return accepted

    def _on_move(self, event):
        destination = event.move_destination
        if isinstance(destination, bytes):
            destination = destination.decode("ascii", "replace")
        destination = destination.strip()
        caller = event.assoc.requestor.ae_title
        node = self.config.node_by_ae(destination)
        if node is None:
            self._log(f"C-MOVE de {caller} para destino desconhecido '{destination}'", logging.WARNING)
            yield None, None  # o pynetdicom responde 0xA801
            return
        items = self._load(self.engine.retrieve(event.identifier))
        infos = [FileInfo(i.path, i.sop_class_uid, i.sop_instance_uid, i.transfer_syntax_uid or "1.2.840.10008.1.2.1") for i in items]
        accepted = self.probe(node, infos) if infos else {}
        contexts = build_contexts(infos, SEND_KEEP)
        kwargs = {"contexts": contexts[0] if contexts else None, "max_pdu": self.config.local.max_pdu}
        if node.tls:
            kwargs["tls_args"] = (client_ssl_context(node, self.config.local), node.host)
        if len(contexts) > 1:
            self._log("C-MOVE com mais de 128 contextos; parte das classes SOP pode falhar", logging.WARNING)
        self.stats.retrieves += 1
        self._log(f"C-MOVE de {caller}: {len(items)} imagem(ns) para {node.describe()}")
        yield node.host, node.port, kwargs
        yield len(items)
        for item in items:
            if event.is_cancelled:
                yield 0xFE00, None
                return
            ds = pydicom.dcmread(item.path, force=True)
            if accepted:
                try:
                    ds = prepare_for(ds, [pydicom.uid.UID(t) for t in accepted.get(item.sop_class_uid, [])], SEND_KEEP)
                except ValueError:
                    pass  # o pynetdicom contará a sub-operação como falha
            yield 0xFF00, ds

    def _on_get(self, event):
        caller = event.assoc.requestor.ae_title
        items = self._load(self.engine.retrieve(event.identifier))
        self.stats.retrieves += 1
        self._log(f"C-GET de {caller}: {len(items)} imagem(ns)")
        yield len(items)
        for item in items:
            if event.is_cancelled:
                yield 0xFE00, None
                return
            ds = pydicom.dcmread(item.path, force=True)
            try:
                ds = prepare_for(ds, accepted_for(event.assoc, item.sop_class_uid), SEND_KEEP)
            except ValueError:
                pass  # classe não negociada: o pynetdicom contará falha
            yield 0xFF00, ds
