"""Interoperabilidade com o DCMTK — a biblioteca que o Horos usa por dentro.

Nos dois sentidos:
* clientes do DCMTK (echoscu, storescu, findscu, getscu, movescu) contra o
  listener do Horus;
* o cliente do Horus contra servidores do DCMTK (storescp e dcmqrscp, o
  servidor de Q/R de que o Horos derivou o seu).

Os testes só rodam onde as ferramentas do DCMTK estão instaladas (no CI do
Linux, pelo apt); no resto são pulados.
"""

from __future__ import annotations

import shutil
import subprocess
import time
from pathlib import Path

import pydicom
import pytest
from conftest import make_dataset, write
from netutil import free_port, local, node, running_listener
from pydicom.dataset import Dataset
from pydicom.uid import generate_uid

from horus.database import Database
from horus.net import scu
from horus.net.config import NetworkConfig
from horus.net.scp import DicomListener

TOOLS = ("echoscu", "storescu", "findscu", "getscu", "movescu", "storescp", "dcmqrscp", "dcmqridx")
pytestmark = pytest.mark.skipif(
    any(shutil.which(t) is None for t in TOOLS), reason="ferramentas do DCMTK não instaladas"
)


def _run(*args: str, timeout: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)


def _wait_dicom(ae: str, port: int, timeout: float = 15) -> None:
    """Espera o servidor responder a C-ECHO.

    Uma sondagem TCP crua (conectar e fechar) atrapalha o dcmqrscp em modo
    de processo único, que fica preso tratando a conexão vazia; o C-ECHO é
    a forma DICOM de saber se o servidor está pronto.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        if scu.echo(local("PROBE"), node(ae, port)).ok:
            return
        time.sleep(0.2)
    raise TimeoutError(f"{ae} na porta {port} não respondeu")


def _study(tmp_path: Path, n: int = 3) -> tuple[list[Path], str]:
    study, series = generate_uid(), generate_uid()
    files = [
        write(make_dataset(patient_name="PAZ^ANA", patient_id="DC1", study_uid=study, series_uid=series, instance_number=i + 1), tmp_path / "src" / f"im{i}.dcm")
        for i in range(n)
    ]
    return files, study


# ------------------------------------------- DCMTK → listener do Horus


def test_dcmtk_clients_against_horus(tmp_path):
    files, study_uid = _study(tmp_path)
    move_port = free_port()
    with running_listener(tmp_path / "srv", ae="HORUS", nodes=[node("MOVESCU", move_port)]) as lst:
        port = str(lst.config.local.port)

        echo = _run("echoscu", "-aet", "DCMTK", "-aec", "HORUS", "127.0.0.1", port)
        assert echo.returncode == 0, echo.stderr

        store = _run("storescu", "-aet", "MODAL", "-aec", "HORUS", "127.0.0.1", port, *files)
        assert store.returncode == 0, store.stderr
        assert lst.wait_idle()
        assert sum(s.number_of_images for s in lst.db.studies()) == 3

        out = tmp_path / "find"
        out.mkdir()
        find = _run(
            "findscu", "-S", "-aet", "DCMTK", "-aec", "HORUS", "-X", "-od", out,
            "-k", "QueryRetrieveLevel=STUDY", "-k", "PatientName=paz", "-k", "StudyInstanceUID",
            "-k", "NumberOfStudyRelatedInstances", "127.0.0.1", port,
        )
        assert find.returncode == 0, find.stderr
        responses = [pydicom.dcmread(p) for p in sorted(out.glob("rsp*.dcm"))]
        assert [r.StudyInstanceUID for r in responses] == [study_uid]
        assert int(responses[0].NumberOfStudyRelatedInstances) == 3

        got = tmp_path / "get"
        got.mkdir()
        get = _run(
            "getscu", "-S", "-aet", "DCMTK", "-aec", "HORUS", "-od", got,
            "-k", "QueryRetrieveLevel=STUDY", "-k", f"StudyInstanceUID={study_uid}", "127.0.0.1", port,
        )
        assert get.returncode == 0, get.stderr
        assert len(list(got.iterdir())) == 3

        moved = tmp_path / "move"
        moved.mkdir()
        move = _run(
            "movescu", "-S", "-aet", "MOVESCU", "-aec", "HORUS", "-aem", "MOVESCU", "--port", str(move_port), "-od", moved,
            "-k", "QueryRetrieveLevel=STUDY", "-k", f"StudyInstanceUID={study_uid}", "127.0.0.1", port,
        )
        assert move.returncode == 0, move.stderr
        assert len(list(moved.iterdir())) == 3


# ------------------------------------------- Horus → servidores DCMTK


def test_horus_sends_to_storescp(tmp_path):
    files, _ = _study(tmp_path)
    out = tmp_path / "storescp"
    out.mkdir()
    port = free_port()
    proc = subprocess.Popen(["storescp", "-aet", "PACS", "-od", str(out), str(port)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        _wait_dicom("PACS", port)
        res = scu.send(local("HORUS"), node("PACS", port), files)
        assert res.ok and res.sent == 3, res.failed
    finally:
        proc.terminate()
        proc.wait(timeout=10)
    received = sorted(out.iterdir())
    assert len(received) == 3
    assert {pydicom.dcmread(p).SOPInstanceUID for p in received} == {pydicom.dcmread(f).SOPInstanceUID for f in files}


def test_horus_queries_and_retrieves_from_dcmqrscp(tmp_path):
    files, study_uid = _study(tmp_path)
    storage = tmp_path / "qr" / "PACS"
    storage.mkdir(parents=True)
    for f in files:
        shutil.copy(f, storage / f.name)
    idx = _run("dcmqridx", storage, *[storage / f.name for f in files])
    assert idx.returncode == 0, idx.stderr

    qr_port = free_port()
    lst_port = free_port()
    cfg = tmp_path / "qr" / "dcmqrscp.cfg"
    cfg.write_text(
        f"NetworkTCPPort = {qr_port}\nMaxPDUSize = 16384\nMaxAssociations = 16\n\n"
        "HostTable BEGIN\n"
        f"horus = (HORUS, 127.0.0.1, {lst_port})\n"
        "HostTable END\n\nVendorTable BEGIN\nVendorTable END\n\n"
        "AETable BEGIN\n"
        f"PACS {storage} RW (100, 1024mb) ANY\n"
        "AETable END\n"
    )
    # Modo padrão (um processo por associação): o --single-process do
    # DCMTK 3.6.7 termina com segmentation fault depois da primeira
    # associação, mesmo com o echoscu do próprio DCMTK.
    proc = subprocess.Popen(["dcmqrscp", "-c", str(cfg)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        _wait_dicom("PACS", qr_port)
        pacs = node("PACS", qr_port)
        me = local("HORUS", port=lst_port)

        ident = Dataset()
        ident.QueryRetrieveLevel = "STUDY"
        ident.PatientName = "PAZ*"
        ident.StudyInstanceUID = ""
        found = scu.find(me, pacs, ident)
        assert [m.StudyInstanceUID for m in found.matches] == [study_uid]

        series_q = Dataset()
        series_q.QueryRetrieveLevel = "SERIES"
        series_q.StudyInstanceUID = study_uid
        series_q.SeriesInstanceUID = ""
        series_q.Modality = ""
        (series,) = scu.find(me, pacs, series_q).matches
        assert series.Modality == "CT"

        # C-GET: sem listener, pela própria associação.
        got = scu.get(me, pacs, "STUDY", [study_uid], tmp_path / "got")
        assert got.completed == 3 and len(got.files) == 3

        # C-MOVE: o dcmqrscp abre associação até o listener do Horus.
        db = Database(tmp_path / "horus-db")
        listener = DicomListener(db, NetworkConfig(me))
        listener.start()
        try:
            moved = scu.move(me, pacs, "STUDY", [study_uid])
            assert moved.completed == 3, moved.message
            assert listener.wait_idle()
            assert sum(s.number_of_images for s in db.studies()) == 3
        finally:
            listener.stop()
    finally:
        proc.terminate()
        proc.wait(timeout=10)
