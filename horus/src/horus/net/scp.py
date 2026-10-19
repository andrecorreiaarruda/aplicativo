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
import sys
import threading
import time
import uuid
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from logging.handlers import RotatingFileHandler
from pathlib import Path

import pydicom
from pydicom.dataset import Dataset
from pynetdicom import AE, evt
from pynetdicom.dsutils import encode_file_meta
from pynetdicom.presentation import AllStoragePresentationContexts
from pynetdicom.transport import ThreadedAssociationServer
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
# Arquivos que falharam por motivo passageiro voltam à fila depois de
# RETRY_IMPORT_SECONDS × tentativa (até 60 s), no máximo MAX_IMPORT_ATTEMPTS.
RETRY_IMPORT_SECONDS = 5.0
MAX_IMPORT_ATTEMPTS = 10
GET_FOLDER_STALE_SECONDS = 15 * 60
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


class _ListenerServer(ThreadedAssociationServer):
    """Servidor do pynetdicom que não divide a porta com outro processo.

    O pynetdicom liga SO_REUSEADDR no socket de escuta. No Linux e no macOS
    isso só deixa reabrir uma porta com conexões em TIME_WAIT; no Windows,
    deixa um segundo processo abrir a MESMA porta que já está em escuta, e
    duas cópias do Horus (ou o Horus e outro PACS) passam a dividir as
    conexões sem erro nenhum. No Windows o socket fica sem a opção, como
    faz o socket.create_server do próprio Python: aí o segundo bind falha
    e o conflito aparece. (O Windows já permite reabrir uma porta com
    conexões em TIME_WAIT sem SO_REUSEADDR.)
    """

    def server_bind(self) -> None:
        if sys.platform != "win32":
            super().server_bind()
            return
        if self.ae.network_timeout is not None:
            self.socket.settimeout(self.ae.network_timeout)
        self.socket.bind(self.server_address)
        self.server_address = self.socket.getsockname()

    # Com TLS, o pynetdicom faz o handshake dentro de get_request, na thread
    # única que aceita conexões e sem prazo: uma conexão TCP que nunca manda
    # o ClientHello (varredura de portas, verificação de um balanceador)
    # travava o listener inteiro até o par desistir. Aqui o handshake vai
    # para a thread da associação, com o prazo do ACSE.

    def get_request(self):
        client, address = self.socket.accept()
        if self.ssl_context:
            client.settimeout(self.ae.acse_timeout or 30)
            client = self.ssl_context.wrap_socket(client, server_side=True, do_handshake_on_connect=False)
        return client, address

    def process_request_thread(self, request, client_address) -> None:
        if isinstance(request, ssl.SSLSocket):
            try:
                request.do_handshake()
                request.settimeout(None)
            except (OSError, ValueError):  # inclui ssl.SSLError e socket.timeout
                self.shutdown_request(request)
                return
        super().process_request_thread(request, client_address)


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
        self._attempts: dict[Path, int] = {}
        self._logger = logging.Logger("horus.net.listener", logging.INFO)
        self._log_handler: logging.Handler | None = None

    # ------------------------------------------------------------ registro

    def _open_log(self) -> None:
        """Abre logs/rede.log enquanto o listener estiver ativo.

        O arquivo é fechado em stop(): no Windows um arquivo aberto não pode
        ser apagado nem renomeado, e um rede.log esquecido aberto impedia
        apagar a pasta da base (e quebrava o autoteste do executável). O
        logger é próprio deste listener, fora da árvore do `logging`, para
        que dois listeners não somem handlers um no outro.
        """
        if self._log_handler is not None:
            return
        log_dir = self.db.base_dir / "logs"
        try:
            log_dir.mkdir(exist_ok=True)
            handler = RotatingFileHandler(log_dir / "rede.log", maxBytes=1_000_000, backupCount=5, encoding="utf-8")
        except OSError:
            return
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        self._logger.addHandler(handler)
        self._log_handler = handler

    def _close_log(self) -> None:
        if self._log_handler is not None:
            self._logger.removeHandler(self._log_handler)
            self._log_handler.close()
            self._log_handler = None

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
        self._open_log()
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
            # O equivalente a ae.start_server(block=False), com o servidor
            # acima no lugar do ThreadedAssociationServer padrão.
            server = ae.make_server(
                (local.bind_address or "", local.port),
                evt_handlers=handlers,
                ssl_context=ssl_context,
                server_class=_ListenerServer,
            )
        except OSError as exc:
            self._close_log()
            raise ListenerError(
                f"não foi possível abrir a porta {local.port}: {exc.strerror or exc}. "
                "Outro programa (ou outra cópia do Horus) pode estar usando a porta."
            ) from exc
        threading.Thread(target=server.serve_forever, name="horus-listener", daemon=True).start()
        ae._servers.append(server)  # como o start_server: shutdown() o retira daí
        self._server = server
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
        self._close_log()
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
            # Aceita o papel que o outro lado propuser na negociação de
            # papéis, como o Horos: SCU (quem envia com C-STORE e manda o
            # item de papel explícito) e SCP (quem pede C-GET e recebe as
            # imagens na mesma associação). Com scu_role=False, um
            # equipamento que mandava "SCU=1" tinha o contexto recusado.
            ae.add_supported_context(cx.abstract_syntax, ACCEPTED_SYNTAXES, scu_role=True, scp_role=True)
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
        """Retoma arquivos que ficaram em INCOMING num encerramento anterior.

        Inclui as pastas de C-GET (INCOMING/GET/<id>) abandonadas por uma
        queda no meio da recuperação; uma pasta mexida nos últimos minutos
        ainda pode ser de uma recuperação em andamento e fica para depois.
        """
        for leftover in sorted(self.incoming.glob("*.part")):
            leftover.unlink(missing_ok=True)
        for leftover in sorted(self.incoming.glob("*.dcm")):
            self._queue.put(leftover)
        stale = time.time() - GET_FOLDER_STALE_SECONDS
        for folder in sorted(self.incoming.glob("GET/*")):
            try:
                if not folder.is_dir() or folder.stat().st_mtime > stale:
                    continue
            except OSError:
                continue
            for leftover in sorted(folder.glob("*.dcm")):
                self._queue.put(leftover)

    def _import_loop(self) -> None:
        batch: list[Path] = []
        stop = False
        while not stop:
            try:
                item = self._queue.get(timeout=0.5)
                if item is None:
                    self._queue.task_done()
                    stop = True
                else:
                    batch.append(item)
                    if len(batch) < 200 and not self._flush.is_set():
                        continue
            except queue.Empty:
                pass
            if batch and (stop or self._queue.empty() or len(batch) >= 200):
                try:
                    self._import_batch(batch)
                except Exception as exc:  # a thread de importação não pode morrer
                    self._log(f"erro inesperado ao importar: {exc}", logging.ERROR)
                    self._retry_later([p for p in batch if p.exists()])
                finally:
                    for _ in batch:
                        self._queue.task_done()
                batch = []
                self._flush.clear()

    def _retry_later(self, items: list[Path]) -> None:
        """Devolve arquivos à fila depois de um tempo, até um limite.

        Para o que falhou por motivo passageiro: base travada por uma
        importação longa, arquivo preso pelo antivírus. O que passar do
        limite fica em INCOMING e é retomado quando o listener reiniciar.
        """
        again = []
        for path in items:
            n = self._attempts.get(path, 0) + 1
            if n > MAX_IMPORT_ATTEMPTS:
                self._attempts.pop(path, None)
                self._log(f"{path.name} continua em INCOMING após {MAX_IMPORT_ATTEMPTS} tentativas", logging.ERROR)
                continue
            self._attempts[path] = n
            again.append(path)
        if not again:
            return
        delay = min(60.0, RETRY_IMPORT_SECONDS * self._attempts[again[0]])

        def requeue() -> None:
            if self._server is not None:
                for path in again:
                    if path.exists():
                        self._queue.put(path)

        timer = threading.Timer(delay, requeue)
        timer.daemon = True
        timer.start()

    def _import_batch(self, batch: list[Path]) -> None:
        try:
            result = self.db.add_files(batch, move=True, origin=ORIGIN_RECEIVED)
        except Exception as exc:  # base travada, disco cheio
            # O que já foi confirmado saiu de INCOMING; o resto (inclusive o
            # que add_files devolveu ao lugar) volta à fila mais tarde.
            self._log(f"falha ao importar {len(batch)} objeto(s): {exc}; nova tentativa em instantes", logging.ERROR)
            self._retry_later([p for p in batch if p.exists()])
            return
        for p in result.duplicate_paths:
            # Só o que add_files disse ser duplicado é apagado: a base já tem
            # a imagem. Nunca "o que sobrou".
            try:
                Path(p).unlink(missing_ok=True)
                self.stats.duplicates += 1
            except OSError as exc:
                self._log(f"não foi possível apagar o duplicado {Path(p).name}: {exc}", logging.WARNING)
        for p, msg in result.errors:
            try:
                self.failed_dir.mkdir(exist_ok=True)
                shutil.move(str(p), self.failed_dir / Path(p).name)
                self.stats.rejected_files += 1
            except OSError as exc:
                self._log(f"não foi possível mover {Path(p).name} para {FAILED_DIR}: {exc}", logging.WARNING)
            self._log(f"objeto recebido recusado ({Path(p).name}): {msg}", logging.WARNING)
        if result.transient:
            self._retry_later([Path(p) for p, _ in result.transient if Path(p).exists()])
        for path in batch:
            if not path.exists():
                self._attempts.pop(path, None)
        self.stats.imported += result.added
        if result.added:
            self._log(f"{result.added} imagem(ns) recebida(s) importada(s)")
        self.on_event("imported", {"added": result.added, "study_ids": sorted(result.study_ids)})

    def wait_idle(self, timeout: float = 10.0) -> bool:
        """Espera tudo o que chegou ser importado (testes e encerramento).

        Conta as tarefas da fila, não o tamanho dela: um lote já tirado da
        fila mas ainda dentro de add_files continua pendente.
        """
        deadline = time.time() + timeout
        self._flush.set()
        while time.time() < deadline:
            if self._queue.unfinished_tasks == 0:
                return True
            time.sleep(0.05)
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
            syntaxes = [pydicom.uid.UID(t) for t in accepted.get(item.sop_class_uid, [])] if accepted else None
            yield 0xFF00, self._sub_operation(item, syntaxes)

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
            yield 0xFF00, self._sub_operation(item, accepted_for(event.assoc, item.sop_class_uid))

    def _sub_operation(self, item: RetrieveItem, syntaxes) -> Dataset:
        """O objeto de uma sub-operação, sem derrubar as outras.

        Uma exceção dentro do gerador encerra o C-MOVE/C-GET inteiro com
        0xC511/0xC411; uma imagem ilegível ou impossível de converter tem de
        contar só como uma sub-operação com falha. Para isso vai um objeto
        que o pynetdicom não consegue enviar: ele registra a falha e o UID
        em FailedSOPInstanceUIDList e segue para a próxima.
        """
        try:
            ds = pydicom.dcmread(item.path, force=True)
        except Exception as exc:  # arquivo sumiu, preso pelo antivírus, corrompido
            self._log(f"imagem {item.sop_instance_uid} ilegível ({exc}); sub-operação com falha", logging.WARNING)
            failed = Dataset()
            failed.SOPInstanceUID = item.sop_instance_uid
            return failed
        if syntaxes is not None:
            try:
                ds = prepare_for(ds, syntaxes, SEND_KEEP)
            except Exception as exc:  # pixels que não decodificam, codec ausente
                self._log(f"imagem {item.sop_instance_uid} não pôde ser convertida ({exc})", logging.WARNING)
        return ds
