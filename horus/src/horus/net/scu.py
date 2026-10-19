"""O Horus como cliente: C-ECHO, C-STORE, C-FIND, C-MOVE e C-GET.

Equivalentes no Horos: DCMTKVerifySCU (botão "Verify" dos nós),
DCMTKStoreSCU (envio), DCMTKQueryNode (consulta e recuperação, usado pela
janela Query/Retrieve).
"""

from __future__ import annotations

import ssl
import threading
import time
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

import pydicom
from pydicom.dataset import Dataset
from pynetdicom import AE, build_role, evt
from pynetdicom.presentation import StoragePresentationContexts, build_context
from pynetdicom.sop_class import (
    PatientRootQueryRetrieveInformationModelFind,
    PatientRootQueryRetrieveInformationModelGet,
    PatientRootQueryRetrieveInformationModelMove,
    StudyRootQueryRetrieveInformationModelFind,
    StudyRootQueryRetrieveInformationModelGet,
    StudyRootQueryRetrieveInformationModelMove,
    Verification,
)

from .config import LocalSettings, Node
from .query import PATIENT_ROOT
from .transfer import (
    ACCEPTED_SYNTAXES,
    FileInfo,
    accepted_for,
    build_contexts,
    file_info,
    prepare_for,
)

FIND_MODELS = {"STUDY": StudyRootQueryRetrieveInformationModelFind, "PATIENT": PatientRootQueryRetrieveInformationModelFind}
MOVE_MODELS = {"STUDY": StudyRootQueryRetrieveInformationModelMove, "PATIENT": PatientRootQueryRetrieveInformationModelMove}
GET_MODELS = {"STUDY": StudyRootQueryRetrieveInformationModelGet, "PATIENT": PatientRootQueryRetrieveInformationModelGet}

# Status de aviso do C-STORE (PS3.4 B.2.3 e PS3.7 C): a imagem foi
# gravada. O Horos só aceita 0xBxxx e trata 0x0107/0x0116 como falha.
STORE_WARNINGS = {0xB000, 0xB006, 0xB007, 0x0107, 0x0116}

# Segundos entre o C-CANCEL e o A-ABORT quando o PACS não atende ao pedido.
CANCEL_GRACE = 10.0

# Prioridade DIMSE: o Horos pede LOW no C-FIND e MEDIUM no C-MOVE/C-GET.
PRIORITY_MEDIUM, PRIORITY_LOW = 0x0000, 0x0002

ProgressFn = Callable[[int, int, str], None]


class NetworkError(RuntimeError):
    """Falha de rede com mensagem pronta para o usuário."""


def _code(status: Dataset | None) -> int | None:
    """Status de uma resposta DIMSE, ou None quando ela não veio.

    O pynetdicom devolve um Dataset vazio (e não None) quando o tempo de
    espera se esgota, o par aborta ou a resposta é inválida.
    """
    if status is None or "Status" not in status:
        return None
    return int(status.Status)


class _CancelWatch:
    """Cancela uma operação mesmo que o PACS fique mudo.

    O pynetdicom só devolve o controle a cada resposta; um PACS que não
    manda respostas pendentes (são opcionais no C-MOVE/C-GET) deixaria o
    botão Cancelar sem efeito. Esta thread manda o C-CANCEL assim que o
    usuário pede e, se o PACS ignorar, aborta a associação. O Horos não
    envia C-CANCEL: aborta a associação ou, no C-MOVE, derruba as
    associações de entrada do listener.
    """

    def __init__(self, assoc, cancelled: Callable[[], bool], msg_id: int, cx_id: int):
        self.assoc, self.cancelled, self.msg_id, self.cx_id = assoc, cancelled, msg_id, cx_id
        self.grace = CANCEL_GRACE
        self.sent = False
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="horus-cancel", daemon=True)

    def __enter__(self) -> _CancelWatch:
        self._thread.start()
        return self

    def __exit__(self, *exc) -> None:
        self._stop.set()
        self._thread.join(timeout=2)

    def cancel(self) -> None:
        with self._lock:
            if self.sent or not self.assoc.is_established:
                return
            self.sent = True
        try:
            self.assoc.send_c_cancel(self.msg_id, self.cx_id)
        except Exception:  # associação caindo ao mesmo tempo
            pass

    def _run(self) -> None:
        while not self._stop.wait(0.2):
            if self.cancelled():
                self.cancel()
                if not self._stop.wait(self.grace) and self.assoc.is_established:
                    self.assoc.abort()
                    # Só o aborto vindo do par acorda quem espera resposta;
                    # o nosso não, e a espera do C-MOVE/C-GET não tem prazo.
                    self.assoc.dimse.msg_queue.put((None, None))
                return


def _status_text(status: int) -> str:
    known = {
        0xA700: "sem recursos no destino (disco cheio?)",
        0xA701: "sem recursos para calcular as correspondências",
        0xA702: "sem recursos para as sub-operações",
        0xA801: "o destino do C-MOVE é desconhecido para o PACS — cadastre o AE, IP e porta do Horus nele",
        0xA900: "o identificador não corresponde à classe SOP",
        0xC000: "o PACS não conseguiu processar o pedido",
        0xFE00: "cancelado",
    }
    return known.get(status, f"status 0x{status:04X}")


def client_ssl_context(node: Node, local: LocalSettings) -> ssl.SSLContext:
    """Contexto TLS do cliente.

    Sem arquivo de autoridade certificadora, usa o repositório do sistema:
    no Windows o Python lê o repositório de certificados do próprio
    Windows, que é onde o setor de TI costuma instalar a CA do hospital.
    """
    ctx = ssl.create_default_context(cafile=node.tls_ca_file or None)
    if not node.tls_verify:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    if local.tls_cert_file and local.tls_key_file:
        ctx.load_cert_chain(local.tls_cert_file, local.tls_key_file)
    return ctx


def make_ae(local: LocalSettings) -> AE:
    ae = AE(ae_title=local.ae_title)
    ae.acse_timeout = local.acse_timeout
    ae.dimse_timeout = local.dimse_timeout
    ae.network_timeout = local.network_timeout
    ae.connection_timeout = local.connection_timeout
    ae.maximum_pdu_size = local.max_pdu
    return ae


def associate(ae: AE, node: Node, local: LocalSettings, contexts=None, ext_neg=None, evt_handlers=None):
    tls_args = (client_ssl_context(node, local), node.host) if node.tls else None
    try:
        assoc = ae.associate(
            node.host,
            node.port,
            contexts=contexts,
            ae_title=node.ae_title,
            max_pdu=local.max_pdu,
            ext_neg=ext_neg,
            tls_args=tls_args,
            evt_handlers=evt_handlers,
        )
    except (OSError, ssl.SSLError) as exc:
        raise NetworkError(f"não foi possível conectar a {node.host}:{node.port}: {exc}") from exc
    if assoc.is_established:
        return assoc
    if assoc.is_rejected:
        raise NetworkError(
            f"{node.describe()} recusou a associação. Confira se o AE title "
            f"'{local.ae_title}' do Horus está cadastrado no destino e se o AE "
            f"title '{node.ae_title}' está correto."
        )
    if assoc.is_aborted and not assoc.acse.is_aborted("a-p-abort"):
        raise NetworkError(f"{node.describe()} interrompeu a associação (A-ABORT)")
    # A-P-ABORT local: a conexão TCP nem chegou a ser feita (porta fechada,
    # endereço errado, firewall) ou caiu antes da resposta.
    raise NetworkError(
        f"sem resposta de {node.host}:{node.port}. Confira endereço, porta e firewall "
        "(no Windows, o Firewall do Windows Defender pode bloquear a conexão)."
    )


def _context_id(assoc, sop, node: Node) -> int:
    for cx in assoc.accepted_contexts:
        if cx.abstract_syntax == sop:
            return cx.context_id
    assoc.release()
    raise NetworkError(f"{node.describe()} aceitou a associação mas não oferece {sop.name}")


# ------------------------------------------------------------------ C-ECHO


@dataclass
class EchoResult:
    ok: bool
    message: str
    elapsed_ms: float = 0.0


def echo(local: LocalSettings, node: Node) -> EchoResult:
    """Teste de conexão (botão "Verify" do Horos)."""
    ae = make_ae(local)
    start = time.perf_counter()
    try:
        assoc = associate(ae, node, local, contexts=[build_context(Verification)])
    except NetworkError as exc:
        return EchoResult(False, str(exc))
    try:
        code = _code(assoc.send_c_echo())
    finally:
        if assoc.is_established:
            assoc.release()
    elapsed = (time.perf_counter() - start) * 1000
    # O Horos roda o echoscu e só olha o código de saída; aqui o status da
    # resposta precisa ser 0x0000.
    if code == 0x0000:
        return EchoResult(True, f"{node.describe()} respondeu em {elapsed:.0f} ms", elapsed)
    return EchoResult(False, f"{node.describe()} não confirmou o C-ECHO ({_status_text(code) if code is not None else 'sem resposta'})", elapsed)


# ----------------------------------------------------------------- C-STORE


@dataclass
class SendResult:
    total: int = 0
    sent: int = 0
    warnings: int = 0
    failed: list[tuple[str, str]] = field(default_factory=list)
    cancelled: bool = False

    @property
    def ok(self) -> bool:
        return not self.failed and not self.cancelled


def send(
    local: LocalSettings,
    node: Node,
    paths: list[str | Path],
    progress: ProgressFn | None = None,
    cancelled: Callable[[], bool] = lambda: False,
    associations: int | None = None,
) -> SendResult:
    """Envia arquivos ao nó, convertendo a sintaxe quando preciso.

    Com mais de uma associação, os arquivos são divididos em blocos
    contíguos de ceil(n/k) e cada bloco segue por uma associação própria,
    em paralelo — o "Number of associations" (1, 2 ou 4) do envio do Horos.
    """
    k = max(1, min(int(associations or node.send_associations), len(paths) or 1))
    if k == 1:
        return _send_one(local, node, paths, progress, cancelled)
    size = -(-len(paths) // k)
    chunks = [paths[i:i + size] for i in range(0, len(paths), size)]
    done = [0] * len(chunks)
    lock = threading.Lock()

    def chunk_progress(index: int) -> ProgressFn:
        def report(n: int, _total: int, path: str) -> None:
            with lock:
                done[index] = n
                total_done = sum(done)
            if progress:
                progress(total_done, len(paths), path)
        return report

    from concurrent.futures import ThreadPoolExecutor

    with ThreadPoolExecutor(max_workers=len(chunks), thread_name_prefix="horus-envio") as pool:
        parts = list(pool.map(lambda i: _send_one(local, node, chunks[i], chunk_progress(i), cancelled), range(len(chunks))))
    result = SendResult(total=len(paths))
    for part in parts:
        result.sent += part.sent
        result.warnings += part.warnings
        result.failed.extend(part.failed)
        result.cancelled = result.cancelled or part.cancelled
    return result


def _send_one(
    local: LocalSettings,
    node: Node,
    paths: list[str | Path],
    progress: ProgressFn | None,
    cancelled: Callable[[], bool],
) -> SendResult:
    result = SendResult(total=len(paths))
    infos: list[FileInfo] = []
    for p in paths:
        try:
            infos.append(file_info(p))
        except Exception as exc:
            result.failed.append((str(p), f"arquivo ilegível: {exc}"))
    by_class: dict[str, list[FileInfo]] = {}
    for info in infos:
        by_class.setdefault(info.sop_class_uid, []).append(info)

    done = len(result.failed)
    for contexts in build_contexts(infos, node.send_syntax):
        classes = {cx.abstract_syntax for cx in contexts}
        batch = [i for c in classes for i in by_class.get(c, [])]
        pending = list(batch)
        retried = False
        while pending:
            if cancelled():
                result.cancelled = True
                return result
            ae = make_ae(local)
            try:
                assoc = associate(ae, node, local, contexts=contexts)
            except NetworkError as exc:
                for info in pending:
                    result.failed.append((info.path, str(exc)))
                done += len(pending)
                break
            dropped = False
            try:
                while pending:
                    if cancelled():
                        result.cancelled = True
                        return result
                    info = pending[0]
                    try:
                        ds = pydicom.dcmread(info.path, force=True)
                        ds = prepare_for(ds, accepted_for(assoc, info.sop_class_uid), node.send_syntax)
                    except Exception as exc:
                        result.failed.append((info.path, str(exc)))
                        pending.pop(0)
                        done += 1
                        if progress:
                            progress(done, result.total, info.path)
                        continue
                    status = assoc.send_c_store(ds)
                    code = _code(status)
                    if code is None or not assoc.is_established:
                        # Associação caiu no meio: o arquivo corrente volta
                        # para a fila e a associação é refeita uma vez.
                        dropped = True
                        break
                    if code == 0x0000:
                        result.sent += 1
                    elif code in STORE_WARNINGS:
                        result.sent += 1
                        result.warnings += 1
                    else:
                        comment = str(status.get("ErrorComment", ""))
                        result.failed.append((info.path, f"{_status_text(code)}{': ' + comment if comment else ''}"))
                    pending.pop(0)
                    done += 1
                    if progress:
                        progress(done, result.total, info.path)
            finally:
                if assoc.is_established:
                    assoc.release()
            if dropped:
                if retried:
                    for info in pending:
                        result.failed.append((info.path, "a associação caiu durante o envio"))
                    done += len(pending)
                    break
                retried = True
    return result


# ------------------------------------------------------------------ C-FIND


@dataclass
class FindResult:
    matches: list[Dataset] = field(default_factory=list)
    cancelled: bool = False
    warning: str = ""


def find(
    local: LocalSettings,
    node: Node,
    identifier: Dataset,
    model: str = "STUDY",
    cancelled: Callable[[], bool] = lambda: False,
    limit: int = 10000,
) -> FindResult:
    sop = FIND_MODELS[model]
    ae = make_ae(local)
    assoc = associate(ae, node, local, contexts=[build_context(sop)])
    result = FindResult()
    try:
        cx_id = _context_id(assoc, sop, node)
        with _CancelWatch(assoc, cancelled, 1, cx_id) as watch:
            for status, ds in assoc.send_c_find(identifier, sop, msg_id=1, priority=PRIORITY_LOW):
                code = _code(status)
                if code is None:
                    if watch.sent:
                        result.cancelled = True
                        break
                    raise NetworkError(f"{node.describe()} parou de responder durante a consulta")
                if code in (0xFF00, 0xFF01):
                    if ds is not None:
                        result.matches.append(ds)
                    if len(result.matches) >= limit and not watch.sent:
                        # O Horos para de guardar após o limite mas deixa o
                        # PACS mandar o resto; aqui o C-CANCEL encerra a busca.
                        watch.cancel()
                        result.warning = f"consulta interrompida em {limit} resultados"
                    continue
                if code == 0xFE00:
                    result.cancelled = cancelled()
                elif code != 0x0000:
                    raise NetworkError(f"consulta recusada por {node.describe()}: {_status_text(code)}")
    finally:
        if assoc.is_established:
            assoc.release()
    return result


# ------------------------------------------------------- C-MOVE e C-GET


@dataclass
class RetrieveResult:
    completed: int = 0
    failed: int = 0
    warning: int = 0
    message: str = ""
    files: list[str] = field(default_factory=list)


def _retrieve_identifier(level: str, uids: list[str], study_uid: str = "", series_uid: str = "", patient_id: str = "") -> Dataset:
    ds = Dataset()
    ds.QueryRetrieveLevel = level
    key = {"PATIENT": "PatientID", "STUDY": "StudyInstanceUID", "SERIES": "SeriesInstanceUID", "IMAGE": "SOPInstanceUID"}[level]
    setattr(ds, key, uids if len(uids) > 1 else uids[0])
    # Níveis abaixo de STUDY levam as chaves únicas dos níveis acima
    # (recuperação hierárquica, PS3.4 C.4.2.2.1).
    if level in ("SERIES", "IMAGE") and study_uid:
        ds.StudyInstanceUID = study_uid
    if level == "IMAGE" and series_uid:
        ds.SeriesInstanceUID = series_uid
    if patient_id and level != "PATIENT":
        ds.PatientID = patient_id
    return ds


def _run_retrieve(assoc, responses, result: RetrieveResult, node: Node, cancelled, cx_id: int, progress: ProgressFn | None) -> None:
    """Laço comum de respostas do C-MOVE e do C-GET."""
    # Como o Horos (DIMSE bloqueante) e o movescu do DCMTK, a espera por
    # respostas não tem prazo: um PACS com arquivo em fita ou "nearline"
    # pode levar minutos até a primeira sub-operação, e as respostas
    # pendentes são opcionais. O usuário continua podendo cancelar.
    assoc.dimse_timeout = None
    with _CancelWatch(assoc, cancelled, 1, cx_id) as watch:
        for status, _ds in responses:
            code = _code(status)
            if code is None:
                if watch.sent:
                    result.message = "recuperação cancelada"
                    return
                raise NetworkError(f"{node.describe()} parou de responder durante a recuperação")
            _track(status, result, progress)
            if code == 0xFF00:
                continue
            if code == 0x0000:
                result.message = "recuperação concluída"
            elif code == 0xB000:
                result.message = f"recuperação concluída com {result.failed} falha(s)"
            elif code == 0xFE00:
                result.message = "recuperação cancelada"
            else:
                raise NetworkError(f"recuperação recusada por {node.describe()}: {_status_text(code)}")


def _track(rsp: Dataset, result: RetrieveResult, progress: ProgressFn | None) -> None:
    done = int(rsp.get("NumberOfCompletedSuboperations", 0) or 0)
    failed = int(rsp.get("NumberOfFailedSuboperations", 0) or 0)
    warn = int(rsp.get("NumberOfWarningSuboperations", 0) or 0)
    remaining = int(rsp.get("NumberOfRemainingSuboperations", 0) or 0)
    result.completed, result.failed, result.warning = done, failed, warn
    if progress:
        progress(done + failed + warn, done + failed + warn + remaining, "")


def move(
    local: LocalSettings,
    node: Node,
    level: str,
    uids: list[str],
    destination: str | None = None,
    model: str = "STUDY",
    study_uid: str = "",
    series_uid: str = "",
    patient_id: str = "",
    progress: ProgressFn | None = None,
    cancelled: Callable[[], bool] = lambda: False,
) -> RetrieveResult:
    """C-MOVE: o PACS abre uma nova associação e envia ao destino.

    O destino padrão é o próprio Horus, cujo listener precisa estar ativo e
    cadastrado no PACS (AE title, IP e porta) — a causa mais comum de falha.
    """
    sop = MOVE_MODELS[model if level != "PATIENT" else PATIENT_ROOT]
    identifier = _retrieve_identifier(level, uids, study_uid, series_uid, patient_id)
    ae = make_ae(local)
    assoc = associate(ae, node, local, contexts=[build_context(sop)])
    result = RetrieveResult()
    try:
        cx_id = _context_id(assoc, sop, node)
        responses = assoc.send_c_move(identifier, destination or local.ae_title, sop, msg_id=1, priority=PRIORITY_MEDIUM)
        _run_retrieve(assoc, responses, result, node, cancelled, cx_id, progress)
    finally:
        if assoc.is_established:
            assoc.release()
    return result


def get_contexts(model_sop) -> tuple[list, list]:
    """Contextos do C-GET: o modelo de Q/R e as classes de armazenamento.

    No C-GET as imagens voltam na mesma associação, então o Horus precisa
    propor de antemão as classes SOP que aceita receber (no papel de SCP,
    via negociação de papéis). Cabem 127, além do contexto do modelo.
    """
    contexts = [build_context(model_sop)]
    roles = []
    for cx in StoragePresentationContexts[: 127]:
        contexts.append(build_context(cx.abstract_syntax, ACCEPTED_SYNTAXES))
        roles.append(build_role(cx.abstract_syntax, scp_role=True))
    return contexts, roles


def get(
    local: LocalSettings,
    node: Node,
    level: str,
    uids: list[str],
    incoming_dir: Path,
    model: str = "STUDY",
    study_uid: str = "",
    series_uid: str = "",
    patient_id: str = "",
    progress: ProgressFn | None = None,
    cancelled: Callable[[], bool] = lambda: False,
) -> RetrieveResult:
    """C-GET: as imagens chegam pela própria associação.

    Não exige listener nem cadastro do Horus no PACS — útil atrás de NAT ou
    firewall —, mas nem todo PACS oferece C-GET.
    """
    sop = GET_MODELS[model if level != "PATIENT" else PATIENT_ROOT]
    identifier = _retrieve_identifier(level, uids, study_uid, series_uid, patient_id)
    incoming_dir.mkdir(parents=True, exist_ok=True)
    result = RetrieveResult()

    def on_store(event):
        target = incoming_dir / f"{uuid.uuid4().hex}.dcm"
        part = target.with_suffix(".part")
        try:
            part.write_bytes(event.encoded_dataset())
            part.replace(target)
        except OSError:
            part.unlink(missing_ok=True)
            return 0xA700
        result.files.append(str(target))
        return 0x0000

    contexts, roles = get_contexts(sop)
    ae = make_ae(local)
    assoc = associate(ae, node, local, contexts=contexts, ext_neg=roles, evt_handlers=[(evt.EVT_C_STORE, on_store)])
    try:
        cx_id = _context_id(assoc, sop, node)
        responses = assoc.send_c_get(identifier, sop, msg_id=1, priority=PRIORITY_MEDIUM)
        _run_retrieve(assoc, responses, result, node, cancelled, cx_id, progress)
    finally:
        if assoc.is_established:
            assoc.release()
    return result
