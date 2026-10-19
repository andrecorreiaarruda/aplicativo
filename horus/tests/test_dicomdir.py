from __future__ import annotations

import shutil
from pathlib import Path

import pydicom
import pytest
from pydicom.fileset import FileSet

from conftest import make_dataset, write
from horus.burn.dicomdir import build_dicomdir, file_id_for


def _copy_flat(sources: list[Path], root: Path) -> None:
    (root / "DICOM").mkdir(parents=True)
    for i, src in enumerate(sources):
        shutil.copyfile(src, root / "DICOM" / f"{i:05d}")


def test_dicomdir_is_readable_and_complete(tmp_path: Path, mixed_folder: Path):
    sources = sorted(p for p in mixed_folder.rglob("*.dcm"))
    root = tmp_path / "disc"
    _copy_flat(sources, root)

    out = build_dicomdir(root, "TESTE")

    ds = pydicom.dcmread(out)
    assert ds.file_meta.MediaStorageSOPClassUID == "1.2.840.10008.1.3.10"
    assert ds.FileSetID == "TESTE"
    # O FileSet do pydicom percorre a árvore pelos deslocamentos: se algum
    # estiver errado, a leitura falha ou perde instâncias.
    fs = FileSet(ds)
    assert len(fs) == len(sources)
    assert sorted(fs.find_values("PatientID")) == ["PAC001", "PAC002"]
    for instance in fs:
        assert Path(instance.path).exists()
        assert instance.ReferencedFileID[0] == "DICOM"
    records = [r.DirectoryRecordType for r in ds.DirectoryRecordSequence]
    assert records.count("PATIENT") == 2
    assert records.count("IMAGE") == len(sources)


def test_offsets_point_at_items(tmp_path: Path, ct_series: list[Path]):
    root = tmp_path / "disc"
    _copy_flat(ct_series, root)
    out = build_dicomdir(root)
    raw = out.read_bytes()
    ds = pydicom.dcmread(out)
    first = ds.OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity
    # O deslocamento é contado desde o primeiro byte do arquivo (preâmbulo).
    assert raw[first : first + 4] == b"\xfe\xff\x00\xe0"
    for rec in ds.DirectoryRecordSequence:
        for kw in ("OffsetOfTheNextDirectoryRecord", "OffsetOfReferencedLowerLevelDirectoryEntity"):
            off = rec[kw].value
            if off:
                assert raw[off : off + 4] == b"\xfe\xff\x00\xe0"


def test_images_ordered_by_instance_number(tmp_path: Path, ct_series: list[Path]):
    root = tmp_path / "disc"
    _copy_flat(ct_series, root)
    ds = pydicom.dcmread(build_dicomdir(root))
    numbers = [int(r.InstanceNumber) for r in ds.DirectoryRecordSequence if r.DirectoryRecordType == "IMAGE"]
    assert numbers == [1, 2, 3, 4, 5]


def test_invent_mode_fills_missing_type1(tmp_path: Path):
    root = tmp_path / "disc"
    ds = make_dataset(patient_id="", series_number=None, instance_number=None)
    del ds.StudyID
    del ds.StudyDate
    write(ds, root / "DICOM" / "00000")

    dd = pydicom.dcmread(build_dicomdir(root))
    recs = {r.DirectoryRecordType: r for r in dd.DirectoryRecordSequence}
    assert recs["PATIENT"].PatientID.startswith("HORUSPAT")
    assert recs["STUDY"].StudyID == "1"
    assert recs["STUDY"].StudyDate
    assert int(recs["SERIES"].SeriesNumber) == 1
    assert int(recs["IMAGE"].InstanceNumber) == 1
    # O arquivo em si não é alterado (como no +I do DCMTK).
    assert pydicom.dcmread(root / "DICOM" / "00000").PatientID == ""


def test_non_ascii_names_use_utf8(tmp_path: Path):
    root = tmp_path / "disc"
    write(make_dataset(patient_name="CONCEIÇÃO^JOSÉ", charset="ISO_IR 100"), root / "DICOM" / "00000")
    dd = pydicom.dcmread(build_dicomdir(root))
    patient = next(r for r in dd.DirectoryRecordSequence if r.DirectoryRecordType == "PATIENT")
    assert patient.SpecificCharacterSet == "ISO_IR 192"
    assert str(patient.PatientName) == "CONCEIÇÃO^JOSÉ"


def test_file_id_rejects_non_conformant_names(tmp_path: Path):
    with pytest.raises(ValueError):
        file_id_for(tmp_path, tmp_path / "dicom" / "imagem_muito_longa.dcm")
    assert file_id_for(tmp_path, tmp_path / "DICOM" / "00001") == ["DICOM", "00001"]
