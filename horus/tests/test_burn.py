from __future__ import annotations

import io
from pathlib import Path

import numpy as np
import pycdlib
import pydicom
import pytest
from pydicom.fileset import FileSet
from pydicom.uid import ExplicitVRBigEndian, JPEG2000Lossless

from conftest import make_dataset, write
from horus.anonymize import AnonymizationOptions
from horus.burn.destinations import burn_disc, check_capacity, write_iso, write_usb
from horus.burn.iso import build_iso, sanitize_volume_label
from horus.burn.prepare import COMPRESS, DECOMPRESS, DiscOptions, default_label, prepare_disc
from horus.platform import BurnError, BurnToolUnavailable, Platform, Recorder, Volume


def _sources(folder: Path) -> list[Path]:
    return sorted(folder.rglob("*.dcm"))


def test_prepare_layout_matches_horos(tmp_path: Path, mixed_folder: Path):
    files = _sources(mixed_folder)
    disc = prepare_disc(files, DiscOptions(label="Silva João"), staging_root=tmp_path / "stage")

    assert disc.label == "SILVA_JOAO"
    assert disc.folder == tmp_path / "stage" / "SILVA_JOAO"
    names = sorted(p.name for p in (disc.folder / "DICOM").iterdir())
    assert names == [f"{i:05d}" for i in range(len(files))]
    # Sem conversão, a cópia é byte a byte.
    assert (disc.folder / "DICOM" / "00000").read_bytes() == files[0].read_bytes()
    fs = FileSet(pydicom.dcmread(disc.folder / "DICOMDIR"))
    assert len(fs) == len(files)
    assert (disc.folder / "INDEX.HTM").exists()
    assert len(list((disc.folder / "IMAGES").glob("*.PNG"))) >= 4
    assert disc.file_count == len(files) and disc.size_bytes > 0


def test_prepare_with_anonymization(tmp_path: Path, mixed_folder: Path):
    disc = prepare_disc(
        _sources(mixed_folder),
        DiscOptions(label="x", anonymize=AnonymizationOptions()),
        staging_root=tmp_path / "stage",
    )
    for f in (disc.folder / "DICOM").iterdir():
        assert str(pydicom.dcmread(f).PatientName) == "ANONIMO"
    html = (disc.folder / "INDEX.HTM").read_text(encoding="utf-8")
    assert "SILVA" not in html and "SOUZA" not in html
    # A pasta temporária da anonimização não sobra.
    assert not (tmp_path / "stage" / "X_anon").exists()


def test_compress_is_lossless_and_keeps_identity(tmp_path: Path):
    px = (np.arange(64 * 64, dtype=np.uint16).reshape(64, 64) * 7) % 4096
    src = write(make_dataset(pixels=px), tmp_path / "src" / "a.dcm")
    disc = prepare_disc([src], DiscOptions(label="c", compression=COMPRESS, include_html=False), tmp_path / "stage")
    out = pydicom.dcmread(disc.folder / "DICOM" / "00000")
    assert out.file_meta.TransferSyntaxUID == JPEG2000Lossless
    assert out.SOPInstanceUID == pydicom.dcmread(src).SOPInstanceUID
    assert np.array_equal(out.pixel_array, px)

    # E o caminho de volta.
    back = prepare_disc([disc.folder / "DICOM" / "00000"], DiscOptions(label="d", compression=DECOMPRESS, include_html=False), tmp_path / "stage")
    plain = pydicom.dcmread(back.folder / "DICOM" / "00000")
    assert not plain.file_meta.TransferSyntaxUID.is_compressed
    assert np.array_equal(plain.pixel_array, px)
    assert plain.SOPInstanceUID == out.SOPInstanceUID


def test_big_endian_is_converted(tmp_path: Path):
    px = np.array([[1, 256], [4095, 2]], dtype=np.uint16)
    ds = make_dataset(pixels=px)
    ds.file_meta.TransferSyntaxUID = ExplicitVRBigEndian
    ds.PixelData = px.astype(">u2").tobytes()
    lut = np.array([0, 1, 512], dtype=np.uint16)
    ds.add_new(0x00283006, "OW", lut.astype(">u2").tobytes())  # LUTData
    src = tmp_path / "be.dcm"
    pydicom.dcmwrite(src, ds, enforce_file_format=True)
    disc = prepare_disc([src], DiscOptions(label="be", include_html=False), tmp_path / "stage")
    out = pydicom.dcmread(disc.folder / "DICOM" / "00000")
    assert out.file_meta.TransferSyntaxUID == pydicom.uid.ExplicitVRLittleEndian
    assert out.pixel_array.tolist() == px.tolist()
    assert (out.Rows, out.Columns) == (2, 2)
    assert np.frombuffer(out[0x00283006].value, dtype="<u2").tolist() == [0, 1, 512]


def test_supplementary_folder_and_viewer(tmp_path: Path, ct_series):
    extra = tmp_path / "extra"
    (extra / "laudos").mkdir(parents=True)
    (extra / "laudos" / "laudo.pdf").write_bytes(b"%PDF-1.4")
    viewer = tmp_path / "viewer"
    viewer.mkdir()
    (viewer / "Horus.exe").write_bytes(b"MZ")
    disc = prepare_disc(
        ct_series,
        DiscOptions(label="v", supplementary_dir=extra, include_viewer=True, viewer_source=viewer, include_html=False),
        tmp_path / "stage",
    )
    assert (disc.folder / "laudos" / "laudo.pdf").exists()
    assert (disc.folder / "HORUS" / "Horus.exe").exists()
    autorun = (disc.folder / "AUTORUN.INF").read_text()
    assert "label=V" in autorun and "open=HORUS\\Horus.exe --disc" in autorun


def test_encrypted_zip(tmp_path: Path, ct_series):
    pyzipper = pytest.importorskip("pyzipper")
    with pytest.raises(ValueError):
        prepare_disc(ct_series, DiscOptions(label="z", zip_password="curta"), tmp_path / "stage")
    disc = prepare_disc(ct_series, DiscOptions(label="z", zip_password="senha-forte-123", include_html=False), tmp_path / "stage")
    assert sorted(p.name for p in disc.folder.iterdir()) == ["DICOM.ZIP", "LEIAME.TXT"]
    with pyzipper.AESZipFile(disc.folder / "DICOM.ZIP") as zf:
        zf.setpassword(b"senha-forte-123")
        assert "DICOMDIR" in zf.namelist()
        assert zf.read("DICOM/00000")[128:132] == b"DICM"


def test_default_label_rules():
    assert default_label(["Conceição^Maria"], False, False) == "CONCEICAO_MARIA"
    assert default_label(["A", "B"], True, False).startswith("EXAMES_")
    assert len(default_label([], True, False)) <= 15
    assert sanitize_volume_label("a" * 40) == "A" * 15
    assert sanitize_volume_label("!!!") == "DICOM"


def test_iso_roundtrip(tmp_path: Path, mixed_folder: Path):
    disc = prepare_disc(_sources(mixed_folder), DiscOptions(label="Teste ISO"), tmp_path / "stage")
    (disc.folder / "Leia-me com nome longo.txt").write_text("olá")
    iso_path = build_iso(disc.folder, tmp_path / "out.iso", disc.label)

    iso = pycdlib.PyCdlib()
    iso.open(str(iso_path))
    try:
        assert iso.pvd.volume_identifier.decode().strip() == "TESTE_ISO"
        # Nome ISO 9660 nível 1 dos objetos DICOM é o próprio File ID.
        buf = io.BytesIO()
        iso.get_file_from_iso_fp(buf, iso_path="/DICOMDIR.;1")
        assert buf.getvalue() == (disc.folder / "DICOMDIR").read_bytes()
        buf = io.BytesIO()
        iso.get_file_from_iso_fp(buf, iso_path="/DICOM/00000.;1")
        assert buf.getvalue() == (disc.folder / "DICOM" / "00000").read_bytes()
        # Joliet guarda o nome original para o Windows.
        buf = io.BytesIO()
        iso.get_file_from_iso_fp(buf, joliet_path="/Leia-me com nome longo.txt")
        assert buf.getvalue().decode() == "olá"
        names = [c.file_identifier().decode() for c in iso.list_children(iso_path="/")]
        assert "LEIA_ME_.TXT;1" in names
    finally:
        iso.close()


class FakePlatform(Platform):
    name = "teste"

    def __init__(self, label_ok=(True,), burn_error: Exception | None = None, interactive=True):
        self.labels: list[str] = []
        self.label_ok = list(label_ok)
        self.ejected = False
        self.burned: list[tuple] = []
        self.burn_error = burn_error
        self.interactive = interactive
        self.iso_given: Path | None = None

    def set_volume_label(self, volume, label):
        self.labels.append(label)
        return self.label_ok.pop(0) if self.label_ok else False

    def eject(self, volume):
        self.ejected = True
        return True

    def burn_folder(self, folder, label, recorder, iso_path, on_event, eject=True):
        if self.burn_error:
            raise self.burn_error
        self.burned.append((folder, label, recorder.id))
        on_event("Gravando o disco", None)

    def burn_iso_interactive(self, iso_path, recorder):
        self.iso_given = iso_path
        return self.interactive


def test_usb_erases_copies_and_renames(tmp_path: Path, ct_series):
    disc = prepare_disc(ct_series, DiscOptions(label="Paciente Com Nome Grande"), tmp_path / "stage")
    usb = tmp_path / "usb"
    (usb / "velho").mkdir(parents=True)
    (usb / "velho" / "lixo.txt").write_text("x")
    (usb / "System Volume Information").mkdir()
    platform = FakePlatform(label_ok=(False, False, True))
    events: list[str] = []
    warnings = write_usb(disc, Volume(str(usb), "OLD"), platform, lambda m, f: events.append(m))

    assert not (usb / "velho").exists()
    assert (usb / "System Volume Information").exists()
    assert (usb / "DICOMDIR").exists() and (usb / "DICOM" / "00000").exists()
    # Tentativas na ordem do Horos: nome (≤11 no FAT), 10 caracteres, DICOM.
    assert platform.labels == ["PACIENTE_CO", "PACIENTE_C", "DICOM"]
    assert platform.ejected and warnings == []


def test_capacity_check(tmp_path: Path, ct_series):
    disc = prepare_disc(ct_series, DiscOptions(label="cap"), tmp_path / "stage")
    with pytest.raises(BurnError, match="Use um DVD"):
        check_capacity(disc, Recorder("0", "R", media_present=True, media_writable=True, free_bytes=1024))
    with pytest.raises(BurnError, match="Não há mídia"):
        check_capacity(disc, Recorder("0", "R"))
    check_capacity(disc, Recorder("0", "R", media_present=True, media_writable=True, free_bytes=700_000_000))


def test_burn_disc_native_and_fallback(tmp_path: Path, ct_series):
    disc = prepare_disc(ct_series, DiscOptions(label="b"), tmp_path / "stage")
    rec = Recorder("1", "R", drive="E:", media_present=True, media_writable=True, free_bytes=700_000_000)

    native = FakePlatform()
    burn_disc(disc, rec, native, lambda m, f: None, tmp_path / "stage")
    assert native.burned == [(disc.folder, "B", "1")]

    blocked = FakePlatform(burn_error=BurnToolUnavailable("política"))
    handed: list[Path] = []
    burn_disc(disc, rec, blocked, lambda m, f: None, tmp_path / "stage", on_fallback=handed.append)
    assert blocked.iso_given == tmp_path / "stage" / "B.iso" and blocked.iso_given.exists()
    assert handed == [blocked.iso_given]

    nowhere = FakePlatform(burn_error=BurnToolUnavailable("sem ferramenta"), interactive=False)
    with pytest.raises(BurnToolUnavailable):
        burn_disc(disc, rec, nowhere, lambda m, f: None, tmp_path / "stage")


def test_write_iso_reports_progress(tmp_path: Path, ct_series):
    disc = prepare_disc(ct_series, DiscOptions(label="p"), tmp_path / "stage")
    fractions: list[float | None] = []
    write_iso(disc, tmp_path / "p.iso", lambda m, f: fractions.append(f))
    assert fractions[0] == 0.0 and fractions[-1] == 1.0
    assert (tmp_path / "p.iso").stat().st_size % 2048 == 0
