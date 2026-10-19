from __future__ import annotations

import shutil
from pathlib import Path

from pydicom.dataset import FileMetaDataset

from conftest import make_dataset, write
from horus.burn.dicomdir import build_dicomdir
from horus.database import Database, patient_uid
from horus.importer import collect_files, is_dicom_file


def test_detects_dicom_files(mixed_folder: Path, tmp_path: Path):
    assert is_dicom_file(mixed_folder / "ct" / "ct0.dcm")
    assert not is_dicom_file(mixed_folder / "notes.txt")
    # Objeto sem preâmbulo nem meta (comum em discos antigos).
    ds = make_dataset()
    ds.file_meta = FileMetaDataset()
    raw = tmp_path / "raw"
    ds.save_as(raw, enforce_file_format=False, implicit_vr=True, little_endian=True)
    assert raw.read_bytes()[128:132] != b"DICM"
    assert is_dicom_file(raw)


def test_import_copies_into_database_layout(tmp_path: Path, mixed_folder: Path):
    db = Database(tmp_path / "base")
    result = db.add_files([mixed_folder])
    assert result.added == 6 and not result.errors
    first = tmp_path / "base" / "DATABASE.noindex" / "10000" / "1.dcm"
    assert first.exists()

    studies = db.studies()
    names = sorted({s.patient_name for s in studies})
    assert names == ["SILVA JOAO", "SOUZA MARIA"]
    ct = next(s for s in studies if s.number_of_images == 3)
    assert ct.modalities == "CT"
    series = db.series_for_study(ct.id)
    assert len(series) == 1 and series[0].number_of_images == 3


def test_reimport_skips_duplicates(tmp_path: Path, mixed_folder: Path):
    db = Database(tmp_path / "base")
    db.add_files([mixed_folder])
    again = db.add_files([mixed_folder])
    assert again.added == 0 and again.duplicates == 6


def test_multiframe_counts_frames(tmp_path: Path, mixed_folder: Path):
    db = Database(tmp_path / "base")
    db.add_files([mixed_folder / "mf"])
    (study,) = db.studies()
    assert study.number_of_images == 3


def test_search(tmp_path: Path, mixed_folder: Path):
    db = Database(tmp_path / "base")
    db.add_files([mixed_folder])
    assert {s.patient_id for s in db.studies("souza")} == {"PAC002"}
    assert {s.patient_id for s in db.studies("PAC001")} == {"PAC001"}


def test_reference_without_copy(tmp_path: Path, mixed_folder: Path):
    db = Database(tmp_path / "base")
    db.add_files([mixed_folder / "ct"], copy=False)
    images = db.images_for(study_ids=[s.id for s in db.studies()])
    assert all(Path(i.path).parent == mixed_folder / "ct" for i in images)
    assert all(not i.stored_in_database for i in images)
    # Apagar da base não apaga arquivos que a base não copiou.
    db.delete(study_ids=[s.id for s in db.studies()])
    assert (mixed_folder / "ct" / "ct0.dcm").exists()
    assert db.studies() == []


def test_delete_series_removes_copied_files_and_empty_study(tmp_path: Path, mixed_folder: Path):
    db = Database(tmp_path / "base")
    db.add_files([mixed_folder / "ct"])
    (study,) = db.studies()
    (series,) = db.series_for_study(study.id)
    paths = [Path(i.path) for i in db.images_for_series(series.id)]
    db.delete(series_ids=[series.id])
    assert not any(p.exists() for p in paths)
    assert db.studies() == []


def test_index_continues_after_restart(tmp_path: Path, mixed_folder: Path):
    Database(tmp_path / "base").add_files([mixed_folder / "ct"])
    db = Database(tmp_path / "base")
    db.add_files([mixed_folder / "dx"])
    files = sorted((tmp_path / "base" / "DATABASE.noindex" / "10000").iterdir())
    assert [f.name for f in files] == ["1.dcm", "2.dcm", "3.dcm", "4.dcm"]


def test_import_from_disc_uses_dicomdir(tmp_path: Path, mixed_folder: Path):
    disc = tmp_path / "disc"
    (disc / "DICOM").mkdir(parents=True)
    for i, f in enumerate(sorted(mixed_folder.rglob("*.dcm"))):
        shutil.copyfile(f, disc / "DICOM" / f"{i:05d}")
    build_dicomdir(disc)
    # Um arquivo DICOM fora do índice não deve ser lido quando há DICOMDIR.
    write(make_dataset(patient_id="FORA"), disc / "EXTRA" / "x.dcm")
    found = list(collect_files([disc]))
    assert len(found) == 6
    assert all("EXTRA" not in str(p) for p in found)


def test_patient_uid_normalization():
    assert patient_uid("Conceição^José", "a1", "19700101") == patient_uid("CONCEICAO JOSE", "A1", "19700101")
