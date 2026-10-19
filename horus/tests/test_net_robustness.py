"""Falhas que a revisão adversarial da rede encontrou e reproduziu.

Cada teste refaz o cenário de um achado confirmado — base travada por uma
importação longa, PACS que cai entre dois arquivos, imagem corrompida no
meio de um C-GET, conexão TLS que nunca faz o handshake — e confere o
comportamento corrigido.
"""

from __future__ import annotations

import shutil
import socket
import sqlite3
import subprocess
import threading
import time
from pathlib import Path

import numpy as np
import pydicom
import pytest
from pydicom.dataelem import RawDataElement
from pydicom.dataset import Dataset
from pydicom.encaps import encapsulate, generate_fragmented_frames
from pydicom.tag import Tag
from pydicom.uid import CTImageStorage, ExplicitVRLittleEndian, JPEG2000Lossless, generate_uid
from pynetdicom import AE, build_context, build_role, evt
from pynetdicom.sop_class import StudyRootQueryRetrieveInformationModelFind, StudyRootQueryRetrieveInformationModelGet

from conftest import make_dataset, write
from horus import database
from horus.database import Database
from horus.net import routing, scp, scu
from horus.net.config import NetworkConfig, RoutingRule
from horus.net.routing import Router
from netutil import free_port, local, node, running_listener


def _series(folder: Path, n: int, **kw) -> list[Path]:
    study, series = generate_uid(), generate_uid()
    return [write(make_dataset(study_uid=study, series_uid=series, instance_number=i + 1, **kw), folder / f"{i}.dcm") for i in range(n)]


def _images(db: Database) -> int:
    with db.connect() as conn:
        return conn.execute("SELECT COUNT(*) FROM image").fetchone()[0]


def _wait(cond, timeout: float = 15.0) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.05)
    return cond()


# ------------------------------------------------------------- importação


def test_received_images_survive_a_locked_database(tmp_path, monkeypatch):
    """Achado PR2/CL3/WI1: base travada por outra importação.

    Antes, o primeiro arquivo do lote era movido para DATABASE.noindex e
    ficava órfão (sem linha na base) quando o INSERT esgotava o tempo, e o
    resto do lote esperava em INCOMING até reiniciar o programa.
    """
    monkeypatch.setattr(database, "BUSY_TIMEOUT", 0.3)
    monkeypatch.setattr(scp, "RETRY_IMPORT_SECONDS", 0.2)
    files = _series(tmp_path / "src", 3)
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        locker = sqlite3.connect(lst.db.sql_path)
        locker.execute("BEGIN IMMEDIATE")  # como uma importação de CD em andamento
        try:
            assert scu.send(local("MODALIDADE"), node("SRV", lst.config.local.port), files).ok
            time.sleep(1.0)
            assert _images(lst.db) == 0
            # Nenhum arquivo foi movido para a base sem a sua linha.
            assert not list(lst.db.data_dir.rglob("*.dcm"))
        finally:
            locker.rollback()
            locker.close()
        assert _wait(lambda: _images(lst.db) == 3)
        assert lst.wait_idle()
        assert len(list(lst.db.data_dir.rglob("*.dcm"))) == 3
        assert not list(lst.incoming.glob("*.dcm"))


def test_one_bad_object_does_not_abort_the_batch(tmp_path, monkeypatch):
    """Achado WI1: um valor que o SQLite não aceita (IS com 20 dígitos)."""
    monkeypatch.setattr(pydicom.config.settings, "writing_validation_mode", pydicom.config.IGNORE)
    incoming = tmp_path / "in"
    paths = []
    for i in range(3):
        ds = make_dataset(instance_number=i + 1)
        if i == 1:
            raw = b"99999999999999999999"
            ds[Tag(0x00200013)] = RawDataElement(Tag(0x00200013), "IS", len(raw), raw, 0, False, True)
        paths.append(write(ds, incoming / f"{i}.dcm"))
    db = Database(tmp_path / "base")
    result = db.add_files(paths, move=True)
    assert result.added == 2 and len(result.errors) == 1
    assert _images(db) == 2
    # O arquivo recusado ficou onde estava; os aceitos foram para a base.
    assert [p.exists() for p in paths] == [False, True, False]
    assert len(list(db.data_dir.rglob("*.dcm"))) == 2


def test_duplicates_are_reported_by_path(tmp_path):
    files = _series(tmp_path / "src", 2)
    db = Database(tmp_path / "base")
    db.add_files(files)
    again = db.add_files(files, copy=False)
    assert again.duplicates == 2 and sorted(again.duplicate_paths) == sorted(map(str, files))


def test_importer_thread_survives_errors(tmp_path, monkeypatch):
    """Achado WI2: um PermissionError ao mover para FALHAS matava a thread."""
    real_move = shutil.move

    def locked(src, dst, *a, **k):
        if scp.FAILED_DIR in str(dst):
            raise PermissionError(32, "arquivo em uso por outro processo")
        return real_move(src, dst, *a, **k)

    monkeypatch.setattr(scp.shutil, "move", locked)
    broken = make_dataset()
    del broken.StudyInstanceUID  # vai para FALHAS
    bad = write(broken, tmp_path / "src" / "bad.dcm")
    good = _series(tmp_path / "src2", 1)
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        target = node("SRV", lst.config.local.port)
        assert scu.send(local("CLI"), target, [bad]).ok
        assert lst.wait_idle()
        assert scu.send(local("CLI"), target, good).ok
        assert lst.wait_idle()
        assert _images(lst.db) == 1
        assert lst._importer.is_alive()


def test_wait_idle_counts_the_batch_being_imported(tmp_path, monkeypatch):
    """wait_idle voltava com a fila vazia e o lote ainda em add_files."""
    files = _series(tmp_path / "src", 3)
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        real = lst.db.add_files

        def slow(*a, **k):
            time.sleep(1.0)
            return real(*a, **k)

        monkeypatch.setattr(lst.db, "add_files", slow)
        assert scu.send(local("CLI"), node("SRV", lst.config.local.port), files).ok
        assert lst.wait_idle(15)
        assert _images(lst.db) == 3


def test_log_file_is_closed_on_stop(tmp_path):
    """Achado WI4: rede.log ficava aberto e, no Windows, impedia apagar a pasta."""
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        handler = lst._log_handler
        assert handler is not None and not handler.stream.closed
    assert lst._log_handler is None and handler.stream is None or handler.stream.closed
    assert not lst._logger.handlers
    assert "listener parado" in (tmp_path / "srv" / "logs" / "rede.log").read_text(encoding="utf-8")


# ------------------------------------------------------------- servidor


def test_store_with_explicit_scu_role(tmp_path):
    """Achado PR3: quem envia com o item de papel "SCU" tinha o contexto recusado."""
    (path,) = _series(tmp_path / "src", 1)
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        ae = AE(ae_title="MODALIDADE")
        assoc = ae.associate(
            "127.0.0.1", lst.config.local.port, [build_context(CTImageStorage, ExplicitVRLittleEndian)],
            ae_title="SRV", ext_neg=[build_role(CTImageStorage, scu_role=True, scp_role=False)],
        )
        assert assoc.is_established
        try:
            assert assoc.send_c_store(pydicom.dcmread(path)).Status == 0x0000
        finally:
            assoc.release()
        assert lst.wait_idle()
        assert _images(lst.db) == 1


def test_corrupt_image_fails_only_its_own_suboperation(tmp_path):
    """Achado PR4: uma imagem que não decodifica encerrava o C-GET inteiro."""
    study, series = generate_uid(), generate_uid()
    src = []
    for i in range(3):
        px = (np.arange(64 * 64, dtype=np.uint16).reshape(64, 64) * (i + 3)) % 4096
        ds = make_dataset(study_uid=study, series_uid=series, instance_number=i + 1, pixels=px)
        ds.compress(JPEG2000Lossless, generate_instance_uid=False)
        if i == 1:  # código JPEG 2000 truncado no meio
            cs = b"".join(next(generate_fragmented_frames(ds.PixelData)))
            ds.PixelData = encapsulate([cs[: len(cs) // 3]])
        src.append(write(ds, tmp_path / "src" / f"{i}.dcm"))
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        lst.db.add_files(src)
        received = []

        def on_store(event):
            received.append(event.dataset.SOPInstanceUID)
            return 0x0000

        ae = AE(ae_title="VISOR")
        ae.add_requested_context(StudyRootQueryRetrieveInformationModelGet)
        ae.add_requested_context(CTImageStorage, ExplicitVRLittleEndian)  # só aceita sem compressão
        assoc = ae.associate(
            "127.0.0.1", lst.config.local.port, ae_title="SRV",
            ext_neg=[build_role(CTImageStorage, scp_role=True)], evt_handlers=[(evt.EVT_C_STORE, on_store)],
        )
        ident = Dataset()
        ident.QueryRetrieveLevel = "STUDY"
        ident.StudyInstanceUID = study
        last = None
        for status, _ in assoc.send_c_get(ident, StudyRootQueryRetrieveInformationModelGet):
            last = status
        assoc.release()
        assert len(received) == 2  # a primeira e a terceira
        assert last.Status == 0xB000 and last.NumberOfFailedSuboperations == 1


def _self_signed(folder: Path) -> tuple[Path, Path]:
    if shutil.which("openssl") is None:
        pytest.skip("openssl indisponível para gerar o certificado de teste")
    folder.mkdir(parents=True, exist_ok=True)
    cert, key = folder / "cert.pem", folder / "key.pem"
    subprocess.run(
        ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key), "-out", str(cert),
         "-days", "1", "-subj", "/CN=127.0.0.1"],
        check=True, capture_output=True, timeout=60,
    )
    return cert, key


def test_tls_idle_connection_does_not_block_the_listener(tmp_path):
    """Achado PR1: uma conexão TCP muda travava o handshake de todas as outras."""
    cert, key = _self_signed(tmp_path / "tls")
    with running_listener(tmp_path / "srv", ae="SRV", tls_enabled=True, tls_cert_file=str(cert), tls_key_file=str(key)) as lst:
        target = node("SRV", lst.config.local.port, tls=True, tls_verify=False)
        idle = socket.create_connection(("127.0.0.1", lst.config.local.port))
        try:
            time.sleep(0.3)
            start = time.monotonic()
            res = scu.echo(local("CLI", acse_timeout=5, connection_timeout=5), target)
            assert res.ok, res.message
            assert time.monotonic() - start < 4
        finally:
            idle.close()


# ------------------------------------------------------------- cliente


def test_send_reconnects_when_the_peer_drops_between_files(tmp_path, monkeypatch):
    """Achado CL2: o PACS confirma o 2º arquivo e encerra logo depois.

    A leitura do 3º arquivo demora (arquivo grande, compressão), e o aborto
    chega enquanto isso — entre dois C-STORE. Antes, o envio inteiro
    terminava em RuntimeError, sem resultado.
    """
    files = _series(tmp_path / "src", 5)
    got = []
    port = free_port()
    real_read = pydicom.dcmread

    def slow_read(path, *a, **k):
        if str(path) == str(files[2]):
            time.sleep(0.4)
        return real_read(path, *a, **k)

    monkeypatch.setattr(pydicom, "dcmread", slow_read)

    def on_store(event):
        got.append(event.request.AffectedSOPInstanceUID)
        if len(got) == 2:
            threading.Timer(0.05, event.assoc.abort).start()
        return 0x0000

    ae = AE(ae_title="PACS")
    ae.add_supported_context(CTImageStorage, [ExplicitVRLittleEndian, "1.2.840.10008.1.2"])
    server = ae.start_server(("127.0.0.1", port), block=False, evt_handlers=[(evt.EVT_C_STORE, on_store)])
    try:
        res = scu.send(local("CLI"), node("PACS", port), files)
        assert res.ok, res.failed
        assert res.sent == 5 and len(set(got)) == 5
    finally:
        server.shutdown()


def test_find_limit_is_enforced_when_the_pacs_ignores_cancel(tmp_path, monkeypatch):
    """Achado CL7: um PACS que ignora C-CANCEL mandava tudo para a memória."""
    monkeypatch.setattr(scu, "CANCEL_GRACE", 0.3)
    port = free_port()

    def flood(event):
        for i in range(5000):
            ds = Dataset()
            ds.QueryRetrieveLevel = "STUDY"
            ds.StudyInstanceUID = f"1.2.3.{i}"
            yield 0xFF00, ds
            time.sleep(0.001)
        yield 0x0000, None

    ae = AE(ae_title="PACS")
    ae.add_supported_context(StudyRootQueryRetrieveInformationModelFind)
    server = ae.start_server(("127.0.0.1", port), block=False, evt_handlers=[(evt.EVT_C_FIND, flood)])
    try:
        ident = Dataset()
        ident.QueryRetrieveLevel = "STUDY"
        ident.StudyInstanceUID = ""
        start = time.monotonic()
        found = scu.find(local("CLI"), node("PACS", port), ident, limit=50)
        assert len(found.matches) == 50 and "50" in found.warning
        assert time.monotonic() - start < 4
    finally:
        server.shutdown()


# ------------------------------------------------------------- roteamento


def _router(tmp_path, nodes, rules) -> tuple[Database, Router]:
    config = NetworkConfig(local("ROTEADOR"), nodes, True, rules).validate()
    db = Database(tmp_path / "rot")
    router = Router(db, lambda: config)
    db.added_hooks.append(router.on_added)
    return db, router


def test_one_bad_group_does_not_block_the_routing_queue(tmp_path):
    """Achado CL1: um arquivo que fazia o envio levantar exceção travava a fila."""
    with running_listener(tmp_path / "pacs", ae="PACS") as pacs:
        dest = node("PACS", pacs.config.local.port)
        db, router = _router(tmp_path, [dest], [RoutingRule(name="tudo", destination=dest.id, retries=0)])
        poison = make_dataset(patient_id="AAA")
        del poison.SOPClassUID  # só na meta: a base aceita, o C-STORE não
        db.add_files([write(poison, tmp_path / "src" / "poison.dcm")])
        db.add_files(_series(tmp_path / "src2", 2, patient_id="BBB"))
        router.process_due()
        assert pacs.wait_idle()
        assert _images(pacs.db) == 2  # o paciente BBB chegou
        assert router.counts() == {"pending": 0, "failed": 1}  # e o AAA conta tentativa


def test_unreachable_node_is_tried_once_per_cycle(tmp_path, monkeypatch):
    """Achado CL6: cada paciente esperava o seu próprio timeout de conexão."""
    dead = node("MORTO", free_port())
    db, router = _router(tmp_path, [dead], [RoutingRule(name="tudo", destination=dead.id)])
    for pid in ("P1", "P2", "P3"):
        db.add_files(_series(tmp_path / pid, 1, patient_id=pid))
    attempts = []
    real = scu.associate

    def counting(ae, n, *a, **k):
        attempts.append(n.ae_title)
        return real(ae, n, *a, **k)

    monkeypatch.setattr(scu, "associate", counting)
    router.process_due()
    assert attempts == ["MORTO"]
    assert router.counts()["pending"] == 3  # continuam na fila para a próxima tentativa


def test_router_stop_does_not_block_and_old_thread_stays_stopped(tmp_path, monkeypatch):
    """Achado CL5: stop() prendia a interface 30 s e o start() seguinte
    reaproveitava o sinal de parada da thread antiga."""
    dest = node("PACS", free_port())
    db, router = _router(tmp_path, [dest], [RoutingRule(name="tudo", destination=dest.id)])
    sending = threading.Event()

    def slow_send(local_, node_, paths, cancelled=lambda: False, **k):
        sending.set()
        while not cancelled():
            time.sleep(0.05)
        return scu.SendResult(total=len(paths), cancelled=True)

    monkeypatch.setattr(scu, "send", slow_send)
    monkeypatch.setattr(routing, "INTERVAL", 0.1)
    router.start()
    db.add_files(_series(tmp_path / "src", 1))
    assert sending.wait(5)
    old = router._thread
    start = time.monotonic()
    router.stop(wait=0.5)
    assert time.monotonic() - start < 2
    router.start()
    assert router._thread is not old
    old.join(5)
    assert not old.is_alive()  # a antiga viu o próprio sinal e terminou
    router.stop()
