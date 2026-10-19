"""Rede de ponta a ponta: o cliente do Horus contra o listener do Horus.

Tudo roda de verdade em 127.0.0.1 — associação, negociação, DIMSE —, só
que nas duas pontas está o próprio Horus.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pydicom
import pytest
from conftest import make_dataset, write
from netutil import free_port, local, node, running_listener
from pydicom.dataset import Dataset
from pydicom.uid import JPEG2000Lossless, generate_uid

from horus.database import Database
from horus.net import scu
from horus.net.config import SEND_EXPLICIT
from horus.net.scp import ListenerError


def _series(tmp_path: Path, n: int = 4, **kw) -> list[Path]:
    study, series = generate_uid(), generate_uid()
    return [
        write(make_dataset(study_uid=study, series_uid=series, instance_number=i + 1, **kw), tmp_path / "src" / f"{i}.dcm")
        for i in range(n)
    ]


def test_echo(tmp_path):
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        res = scu.echo(local("CLI"), node("SRV", lst.config.local.port))
        assert res.ok, res.message
    bad = scu.echo(local("CLI"), node("SRV", free_port()))
    assert not bad.ok and "sem resposta" in bad.message


def test_send_is_imported_with_source_ae(tmp_path):
    files = _series(tmp_path)
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        res = scu.send(local("MODALIDADE"), node("SRV", lst.config.local.port), files)
        assert res.ok and res.sent == 4, res.failed
        assert lst.wait_idle()
        db = lst.db
        (study,) = db.studies()
        images = db.images_for(study_ids=[study.id])
        assert len(images) == 4
        stored = pydicom.dcmread(images[0].path)
        assert stored.file_meta.SourceApplicationEntityTitle == "MODALIDADE"
        # Nada sobra em INCOMING.
        assert not list(lst.incoming.glob("*.dcm")) and not list(lst.incoming.glob("*.part"))

        again = scu.send(local("MODALIDADE"), node("SRV", lst.config.local.port), files)
        assert again.ok
        assert lst.wait_idle()
        assert len(db.images_for(study_ids=[study.id])) == 4  # duplicados ignorados
        assert lst.stats.duplicates == 4


def test_compressed_object_is_stored_as_received(tmp_path):
    px = (np.arange(32 * 32, dtype=np.uint16).reshape(32, 32) * 3) % 4096
    ds = make_dataset(pixels=px)
    ds.compress(JPEG2000Lossless, generate_instance_uid=False)
    src = write(ds, tmp_path / "src" / "j2k.dcm")
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        assert scu.send(local("CLI"), node("SRV", lst.config.local.port), [src]).ok
        assert lst.wait_idle()
        (img,) = lst.db.images_for(study_ids=[s.id for s in lst.db.studies()])
        stored = pydicom.dcmread(img.path)
        assert stored.file_meta.TransferSyntaxUID == JPEG2000Lossless
        assert stored.PixelData == pydicom.dcmread(src).PixelData  # bytes idênticos


def test_send_explicit_converts_compressed(tmp_path):
    px = (np.arange(32 * 32, dtype=np.uint16).reshape(32, 32) * 5) % 4096
    ds = make_dataset(pixels=px)
    ds.compress(JPEG2000Lossless, generate_instance_uid=False)
    src = write(ds, tmp_path / "src" / "j2k.dcm")
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        target = node("SRV", lst.config.local.port, send_syntax=SEND_EXPLICIT)
        assert scu.send(local("CLI"), target, [src]).ok
        assert lst.wait_idle()
        (img,) = lst.db.images_for(study_ids=[s.id for s in lst.db.studies()])
        stored = pydicom.dcmread(img.path)
        assert not stored.file_meta.TransferSyntaxUID.is_compressed
        assert np.array_equal(stored.pixel_array, px)
        assert stored.SOPInstanceUID == ds.SOPInstanceUID


def test_find_get_and_move(tmp_path):
    files = _series(tmp_path, n=3)
    dest_port = free_port()
    with running_listener(tmp_path / "dest", ae="DEST", port=dest_port) as dest:
        with running_listener(tmp_path / "srv", ae="SRV", nodes=[node("DEST", dest_port)]) as srv:
            port = srv.config.local.port
            assert scu.send(local("CLI"), node("SRV", port), files).ok
            assert srv.wait_idle()

            ident = Dataset()
            ident.QueryRetrieveLevel = "STUDY"
            ident.PatientName = "silva"
            ident.StudyInstanceUID = ""
            ident.NumberOfStudyRelatedInstances = ""
            found = scu.find(local("CLI"), node("SRV", port), ident)
            (match,) = found.matches
            assert int(match.NumberOfStudyRelatedInstances) == 3
            assert match.RetrieveAETitle == "SRV"

            # C-GET: as imagens voltam pela mesma associação.
            got = scu.get(local("CLI"), node("SRV", port), "STUDY", [match.StudyInstanceUID], tmp_path / "got")
            assert got.completed == 3 and len(got.files) == 3

            # C-MOVE: o SRV abre outra associação até o DEST.
            moved = scu.move(local("CLI"), node("SRV", port), "STUDY", [match.StudyInstanceUID], destination="DEST")
            assert moved.completed == 3, moved.message
            assert dest.wait_idle()
            assert sum(s.number_of_images for s in dest.db.studies()) == 3

            # Destino que o SRV não conhece: 0xA801 com mensagem explicativa.
            with pytest.raises(scu.NetworkError, match="destino do C-MOVE"):
                scu.move(local("CLI"), node("SRV", port), "STUDY", [match.StudyInstanceUID], destination="NINGUEM")


def test_move_converts_for_destination_that_refuses_compression(tmp_path):
    px = (np.arange(64 * 64, dtype=np.uint16).reshape(64, 64) * 7) % 4096
    ds = make_dataset(pixels=px)
    ds.compress(JPEG2000Lossless, generate_instance_uid=False)
    src = write(ds, tmp_path / "src" / "j2k.dcm")
    from pydicom.uid import ExplicitVRLittleEndian, ImplicitVRLittleEndian
    from pynetdicom import AE, evt
    from pynetdicom.presentation import AllStoragePresentationContexts

    received = []

    def on_store(event):
        received.append(event.context.transfer_syntax)
        return 0x0000

    # Destino que só aceita sintaxes sem compressão.
    dest_port = free_port()
    ae = AE(ae_title="SEMJ2K")
    for cx in AllStoragePresentationContexts:
        ae.add_supported_context(cx.abstract_syntax, [ExplicitVRLittleEndian, ImplicitVRLittleEndian])
    server = ae.start_server(("127.0.0.1", dest_port), block=False, evt_handlers=[(evt.EVT_C_STORE, on_store)])
    try:
        with running_listener(tmp_path / "srv", ae="SRV", nodes=[node("SEMJ2K", dest_port)]) as srv:
            port = srv.config.local.port
            assert scu.send(local("CLI"), node("SRV", port), [src]).ok
            assert srv.wait_idle()
            res = scu.move(local("CLI"), node("SRV", port), "IMAGE", [ds.SOPInstanceUID], destination="SEMJ2K",
                           study_uid=ds.StudyInstanceUID, series_uid=ds.SeriesInstanceUID)
            assert res.completed == 1 and res.failed == 0
            assert received and not received[0].is_compressed
            # O arquivo da base continua comprimido (o Horos o descomprimia no lugar).
            (img,) = srv.db.images_for(study_ids=[s.id for s in srv.db.studies()])
            assert pydicom.dcmread(img.path).file_meta.TransferSyntaxUID == JPEG2000Lossless
    finally:
        server.shutdown()


def test_only_known_callers(tmp_path):
    with running_listener(tmp_path / "srv", ae="SRV", nodes=[node("AMIGO", 1)], accept_unknown_callers=False) as lst:
        port = lst.config.local.port
        assert scu.echo(local("AMIGO"), node("SRV", port)).ok
        refused = scu.echo(local("ESTRANHO"), node("SRV", port))
        assert not refused.ok and "recusou" in refused.message


def test_port_in_use(tmp_path):
    with running_listener(tmp_path / "a", ae="A") as first:
        db = Database(tmp_path / "b")
        from horus.net.config import NetworkConfig
        from horus.net.scp import DicomListener

        clash = DicomListener(db, NetworkConfig(local("B", port=first.config.local.port)))
        with pytest.raises(ListenerError, match="porta"):
            clash.start()


def test_leftovers_in_incoming_are_imported_on_start(tmp_path):
    base = tmp_path / "srv"
    incoming = base / "INCOMING.noindex"
    incoming.mkdir(parents=True)
    write(make_dataset(), incoming / "sobrou.dcm")
    (incoming / "pela-metade.part").write_bytes(b"lixo")
    with running_listener(base, ae="SRV") as lst:
        assert lst.wait_idle()
        assert len(lst.db.studies()) == 1
        assert not (incoming / "pela-metade.part").exists()


def test_empty_status_means_no_answer():
    # O pynetdicom devolve um Dataset vazio em timeout ou aborto.
    assert scu._code(Dataset()) is None and scu._code(None) is None
    ok = Dataset()
    ok.Status = 0
    assert scu._code(ok) == 0


def test_cancel_reaches_a_silent_pacs(tmp_path, monkeypatch):
    """Um PACS que não manda respostas pendentes ainda pode ser cancelado.

    O servidor abaixo aceita o C-GET e trava antes da primeira sub-operação,
    como um PACS buscando o exame em fita. O C-CANCEL não é atendido, então
    o Horus aborta a associação depois da tolerância.
    """
    import threading
    import time

    from pynetdicom import AE, evt
    from pynetdicom.sop_class import StudyRootQueryRetrieveInformationModelGet

    release = threading.Event()

    def stalled(event):
        yield 1
        release.wait(30)
        yield 0xFE00, None

    port = free_port()
    ae = AE(ae_title="LENTO")
    ae.add_supported_context(StudyRootQueryRetrieveInformationModelGet)
    server = ae.start_server(("127.0.0.1", port), block=False, evt_handlers=[(evt.EVT_C_GET, stalled)])
    monkeypatch.setattr(scu, "CANCEL_GRACE", 0.5)
    try:
        start = time.monotonic()
        res = scu.get(
            local("CLI"), node("LENTO", port), "STUDY", [generate_uid()], tmp_path / "in",
            cancelled=lambda: time.monotonic() - start > 0.5,
        )
        assert res.message == "recuperação cancelada"
        assert time.monotonic() - start < 10
    finally:
        release.set()
        server.shutdown()


def test_send_with_parallel_associations(tmp_path):
    files = _series(tmp_path, n=7)
    with running_listener(tmp_path / "srv", ae="SRV") as lst:
        seen = []
        res = scu.send(local("CLI"), node("SRV", lst.config.local.port), files, progress=lambda d, t, p: seen.append((d, t)), associations=4)
        assert res.ok and res.sent == 7
        assert max(seen) == (7, 7)
        assert lst.stats.associations >= 4  # uma associação por bloco
        assert lst.wait_idle()
        assert len(lst.db.images_for(study_ids=[s.id for s in lst.db.studies()])) == 7


def test_tls_configuration_error_is_a_network_error(tmp_path):
    """Achado GU8/CL1: CA ausente levantava FileNotFoundError fora do NetworkError,
    e uma busca em vários nós perdia o resultado de todos."""
    bad = node("PACS", free_port(), tls=True, tls_ca_file=str(tmp_path / "nao-existe.pem"))
    res = scu.echo(local("CLI"), bad)
    assert not res.ok and "TLS" in res.message
    with pytest.raises(scu.NetworkError, match="TLS"):
        scu.associate(scu.make_ae(local("CLI")), bad, local("CLI"))
