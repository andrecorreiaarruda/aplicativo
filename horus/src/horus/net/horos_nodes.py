"""Lista de nós do Horos (DICOMNodes.plist) para o Horus e de volta.

O painel "Locations" do Horos salva e carrega a lista de nós como um
plist com um array de dicionários (OSILocationsPreferencePanePref.m,
saveAs:/loadFrom:). Importar esse arquivo poupa quem migra do Mac para o
Windows de recadastrar cada PACS; exportar permite levar a lista de volta.

Os tipos no plist são frouxos: Port pode ser texto ou número, Activated
pode ser "1" ou booleano, e Send/QR ausentes valem "sim"
(DCMNetServiceDelegate.m).
"""

from __future__ import annotations

import plistlib
from pathlib import Path

from .config import (
    MAX_SEND_ASSOCIATIONS,
    RETRIEVE_GET,
    RETRIEVE_MOVE,
    SEND_EXPLICIT,
    SEND_IMPLICIT,
    SEND_J2K,
    SEND_KEEP,
    SEND_RLE,
    ConfigError,
    Node,
)

# enum TransferSyntaxCodes (SendController.h) -> sintaxe de envio do Horus.
# O Horus não gera JPEG com perdas, JPEG-LS nem JPEG 2000 com perdas: esses
# nós passam a enviar sem recomprimir (como estiver na base, com reserva
# sem compressão).
_FROM_HOROS = {0: SEND_EXPLICIT, 1: SEND_J2K, 9: SEND_IMPLICIT, 10: SEND_RLE, 11: SEND_EXPLICIT, 12: SEND_EXPLICIT}
_HOROS_NAMES = {
    2: "JPEG 2000 com perdas", 3: "JPEG 2000 com perdas", 4: "JPEG 2000 com perdas",
    5: "JPEG sem perdas", 6: "JPEG com perdas", 7: "JPEG com perdas", 8: "JPEG com perdas",
    13: "JPEG-LS", 14: "JPEG-LS com perdas", 15: "JPEG-LS com perdas", 16: "JPEG-LS com perdas",
}
_TO_HOROS = {SEND_EXPLICIT: 0, SEND_KEEP: 0, SEND_J2K: 1, SEND_IMPLICIT: 9, SEND_RLE: 10}


def _flag(value, default: bool = True) -> bool:
    if value is None:
        return default
    if isinstance(value, str):
        return value.strip().lower() in ("1", "yes", "true", "sim")
    return bool(value)


def _int(value, default: int) -> int:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def load_horos_nodes(path: str | Path) -> tuple[list[Node], list[str]]:
    """Lê um DICOMNodes.plist; devolve os nós e avisos para o usuário."""
    try:
        with open(path, "rb") as fh:
            data = plistlib.load(fh)
    except Exception as exc:  # o plistlib levanta ExpatError, AttributeError, IndexError...
        raise ConfigError(f"não foi possível ler a lista do Horos ({path}): {exc}") from exc
    if not isinstance(data, list):
        raise ConfigError("o arquivo não é uma lista de nós do Horos (DICOMNodes.plist)")

    nodes: list[Node] = []
    notes: list[str] = []
    seen: set[tuple[str, str, int]] = set()
    for entry in data:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("Description") or entry.get("AETitle") or "").strip()
        ae = str(entry.get("AETitle") or "").strip()
        host = str(entry.get("Address") or "").strip()
        port = _int(entry.get("Port"), 104)
        key = (ae, host, port)
        if key in seen:  # o Horos também descarta AE+endereço+porta repetidos
            continue
        seen.add(key)

        mode = _int(entry.get("retrieveMode"), 1 if _flag(entry.get("CGET"), False) else 0)
        retrieve = RETRIEVE_GET if mode == 1 else RETRIEVE_MOVE
        if mode == 2:
            notes.append(f"{name}: recuperação por WADO não existe no Horus; ficou C-MOVE")
        code = _int(entry.get("TransferSyntax"), 0)
        syntax = _FROM_HOROS.get(code, SEND_KEEP)
        if code in _HOROS_NAMES:
            notes.append(f"{name}: envio em {_HOROS_NAMES[code]} não existe no Horus; envia como está na base")
        active = _flag(entry.get("Activated"))
        node = Node(
            name=name,
            ae_title=ae,
            host=host,
            port=port,
            query=active and _flag(entry.get("QR")),
            send=active and _flag(entry.get("Send")),
            retrieve=retrieve,
            send_syntax=syntax,
            send_associations=max(1, min(MAX_SEND_ASSOCIATIONS, _int(entry.get("SendControllerConcurrentThreads"), 1))),
            tls=_flag(entry.get("TLSEnabled"), False),
            # 2 = Ignore no Horos; ausente vale 0 = exigir (DICOMTLS.h).
            tls_verify=_int(entry.get("TLSCertificateVerification"), 0) != 2,
        )
        if node.tls and _flag(entry.get("TLSAuthenticated"), False):
            notes.append(f"{name}: o certificado de cliente do Horos fica no Keychain do Mac; configure-o no Horus")
        if not active:
            notes.append(f"{name}: estava desativado no Horos; importado sem consulta nem envio")
        try:
            nodes.append(node.validate())
        except ConfigError as exc:
            notes.append(f"{name or ae or host}: ignorado ({exc})")
    return nodes, notes


def save_horos_nodes(nodes: list[Node], path: str | Path) -> Path:
    """Grava os nós no formato que o painel Locations do Horos carrega."""
    items = []
    for n in nodes:
        items.append({
            "Description": n.name,
            "AETitle": n.ae_title,
            "Address": n.host,
            "Port": int(n.port),
            "Activated": True,
            "QR": bool(n.query),
            "Send": bool(n.send),
            "TransferSyntax": _TO_HOROS.get(n.send_syntax, 0),
            "retrieveMode": 1 if n.retrieve == RETRIEVE_GET else 0,
            "SendControllerConcurrentThreads": int(n.send_associations),
            "TLSEnabled": bool(n.tls),
            "TLSCertificateVerification": 0 if n.tls_verify else 2,  # exigir / ignorar
        })
    path = Path(path)
    with open(path, "wb") as fh:
        plistlib.dump(items, fh)
    return path
