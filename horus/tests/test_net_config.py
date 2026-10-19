from __future__ import annotations

import json

import pytest
from pydicom.uid import (
    ExplicitVRLittleEndian,
    ImplicitVRLittleEndian,
    JPEG2000Lossless,
    JPEGBaseline8Bit,
)

from horus.net import config as cfg
from horus.net.config import (
    ConfigError,
    LocalSettings,
    NetworkConfig,
    Node,
    validate_ae_title,
)
from horus.net.transfer import FileInfo, build_contexts, proposed_syntaxes


def test_ae_title_rules():
    assert validate_ae_title("  PACS  ") == "PACS"
    for bad in ("", "   ", "A" * 17, "COM\\BARRA", "ACENTUAÇÃO"):
        with pytest.raises(ConfigError):
            validate_ae_title(bad)


def test_default_ae_title_comes_from_hostname(monkeypatch):
    monkeypatch.setattr(cfg.socket, "gethostname", lambda: "estacao-raio.x.hospital.local")
    assert cfg.default_ae_title() == "ESTACAO-RAIO"
    monkeypatch.setattr(cfg.socket, "gethostname", lambda: "um-nome-de-maquina-muito-grande")
    assert cfg.default_ae_title() == "UM-NOME-DE-MAQUI"
    monkeypatch.setattr(cfg.socket, "gethostname", lambda: "")
    assert cfg.default_ae_title() == "HORUS"


def test_roundtrip_and_unknown_fields(tmp_path):
    c = NetworkConfig(LocalSettings(ae_title="EU", port=4242), [Node("PACS", "PACS", "10.0.0.5", 104, retrieve="get")])
    c.save(tmp_path)
    data = json.loads((tmp_path / "network.json").read_text(encoding="utf-8"))
    data["local"]["campo_do_futuro"] = 1  # versões novas não quebram as antigas
    (tmp_path / "network.json").write_text(json.dumps(data), encoding="utf-8")
    back = NetworkConfig.load(tmp_path)
    assert back.local.ae_title == "EU" and back.local.port == 4242
    assert back.nodes[0].retrieve == "get" and back.nodes[0].id == c.nodes[0].id
    assert not list(tmp_path.glob(".network-*"))  # nada de temporário sobrando


def test_invalid_config_is_not_saved(tmp_path):
    c = NetworkConfig(LocalSettings(ae_title="EU"), [Node("a", "PACS", "h"), Node("b", "PACS", "h2")])
    with pytest.raises(ConfigError, match="repetido"):
        c.save(tmp_path)
    assert not (tmp_path / "network.json").exists()
    with pytest.raises(ConfigError):
        LocalSettings(port=70000).validate()
    with pytest.raises(ConfigError, match="certificado"):
        LocalSettings(tls_enabled=True).validate()


def test_corrupt_file_is_reported(tmp_path):
    (tmp_path / "network.json").write_text("{não é json", encoding="utf-8")
    with pytest.raises(ConfigError, match="ilegível"):
        NetworkConfig.load(tmp_path)


def test_proposed_syntaxes():
    # Mantém a nativa comprimida e oferece a reserva sem compressão.
    assert proposed_syntaxes(JPEGBaseline8Bit, "keep") == [[JPEGBaseline8Bit], [ExplicitVRLittleEndian, ImplicitVRLittleEndian]]
    assert proposed_syntaxes(ExplicitVRLittleEndian, "keep") == [[ExplicitVRLittleEndian, ImplicitVRLittleEndian]]
    assert proposed_syntaxes(JPEGBaseline8Bit, "explicit") == [[ExplicitVRLittleEndian, ImplicitVRLittleEndian]]
    assert proposed_syntaxes(ExplicitVRLittleEndian, "j2k")[0] == [JPEG2000Lossless]


def test_contexts_respect_128_limit():
    infos = [FileInfo(f"/x/{i}", f"1.2.3.{i}", f"9.{i}", JPEGBaseline8Bit) for i in range(100)]
    batches = build_contexts(infos, "keep")
    assert all(len(b) <= 128 for b in batches)
    assert sum(len(b) for b in batches) == 200  # 2 contextos por classe SOP


def test_import_horos_node_list(tmp_path):
    import plistlib

    from horus.net.horos_nodes import load_horos_nodes, save_horos_nodes

    horos = [
        # O nó de exemplo que o Horos cria (DefaultsOsiriX.m): Port em texto.
        {"Activated": "1", "Address": "127.0.0.1", "AETitle": "Horos", "Port": "4444", "TransferSyntax": 0, "Description": "This is an example"},
        {"Address": "10.0.0.5", "AETitle": "PACS", "Port": 104, "Description": "PACS central", "retrieveMode": 1,
         "TransferSyntax": 6, "QR": True, "Send": False, "SendControllerConcurrentThreads": 4,
         "TLSEnabled": True, "TLSCertificateVerification": 2},
        {"Address": "10.0.0.5", "AETitle": "PACS", "Port": 104, "Description": "repetido"},
        {"Address": "10.0.0.6", "AETitle": "ANTIGO", "Port": 104, "Activated": False, "CGET": True},
        {"Address": "10.0.0.7", "AETitle": "WADO", "Port": 8080, "retrieveMode": 2},
        {"Address": "", "AETitle": "SEMHOST", "Port": 104},
    ]
    src = tmp_path / "DICOMNodes.plist"
    with open(src, "wb") as fh:
        plistlib.dump(horos, fh)
    nodes, notes = load_horos_nodes(src)
    by_ae = {n.ae_title: n for n in nodes}
    assert list(by_ae) == ["Horos", "PACS", "ANTIGO", "WADO"]
    assert by_ae["Horos"].port == 4444 and by_ae["Horos"].send_syntax == cfg.SEND_EXPLICIT
    pacs = by_ae["PACS"]
    assert pacs.retrieve == cfg.RETRIEVE_GET and pacs.query and not pacs.send
    assert pacs.send_syntax == cfg.SEND_KEEP and pacs.send_associations == 4
    assert pacs.tls and not pacs.tls_verify
    assert by_ae["ANTIGO"].retrieve == cfg.RETRIEVE_GET and not by_ae["ANTIGO"].query
    assert by_ae["WADO"].retrieve == cfg.RETRIEVE_MOVE
    joined = "\n".join(notes)
    assert "WADO" in joined and "JPEG com perdas" in joined and "desativado" in joined and "SEMHOST" in joined

    # E de volta, no formato que o Horos lê.
    out = save_horos_nodes(nodes, tmp_path / "volta.plist")
    with open(out, "rb") as fh:
        back = plistlib.load(fh)
    assert back[1]["AETitle"] == "PACS" and back[1]["retrieveMode"] == 1 and back[1]["Port"] == 104
    again, _ = load_horos_nodes(out)
    assert [n.ae_title for n in again] == [n.ae_title for n in nodes]


def test_import_rejects_non_list(tmp_path):
    import plistlib

    from horus.net.horos_nodes import load_horos_nodes

    src = tmp_path / "x.plist"
    with open(src, "wb") as fh:
        plistlib.dump({"SERVERS": []}, fh)
    with pytest.raises(ConfigError):
        load_horos_nodes(src)
    (tmp_path / "y.plist").write_text("lixo", encoding="utf-8")
    with pytest.raises(ConfigError):
        load_horos_nodes(tmp_path / "y.plist")


def test_loose_types_and_bad_structure(tmp_path):
    data = {
        "local": {"ae_title": "EU", "port": "4242", "listener_enabled": "false"},
        "nodes": [{"name": "P", "ae_title": 123, "host": "h", "port": "104", "query": 1}],
    }
    (tmp_path / "network.json").write_text(json.dumps(data), encoding="utf-8")
    c = NetworkConfig.load(tmp_path)
    assert c.local.port == 4242 and c.local.listener_enabled is False
    assert c.nodes[0].port == 104 and c.nodes[0].ae_title == "123" and c.nodes[0].query is True

    for broken in ({"nodes": {}}, {"local": []}, {"nodes": [{"name": "sem host"}]}, {"local": {"port": "abc"}}, []):
        (tmp_path / "network.json").write_text(json.dumps(broken), encoding="utf-8")
        with pytest.raises(ConfigError):
            NetworkConfig.load(tmp_path)
        # O arquivo estragado é guardado com outro nome, nunca sobrescrito.
        assert not (tmp_path / "network.json").exists()
    assert len(list(tmp_path.glob("network.json.ilegivel-*"))) >= 1
