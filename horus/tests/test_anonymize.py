from __future__ import annotations

from pathlib import Path

import pydicom

from conftest import make_dataset, write
from horus.anonymize import AnonymizationOptions, Anonymizer, anonymize_to_folder


def test_identity_removed_and_uids_consistent(tmp_path: Path, ct_series):
    produced = anonymize_to_folder(ct_series, tmp_path / "anon")
    originals = [pydicom.dcmread(p) for p in ct_series]
    copies = [pydicom.dcmread(produced[str(p)]) for p in ct_series]

    for orig, anon in zip(originals, copies, strict=True):
        assert str(anon.PatientName) == "ANONIMO"
        assert anon.PatientID.startswith("ANON") and anon.PatientID != orig.PatientID
        assert anon.PatientBirthDate == ""
        assert anon.AccessionNumber == ""
        assert "InstitutionName" not in anon
        assert str(anon.ReferringPhysicianName) == ""
        assert anon.PatientIdentityRemoved == "YES"
        assert anon.SOPInstanceUID != orig.SOPInstanceUID
        assert anon.file_meta.MediaStorageSOPInstanceUID == anon.SOPInstanceUID
        # Pixels intactos.
        assert anon.PixelData == orig.PixelData

    # A hierarquia continua: todos no mesmo estudo e série novos.
    assert len({c.StudyInstanceUID for c in copies}) == 1
    assert len({c.SeriesInstanceUID for c in copies}) == 1
    assert copies[0].StudyInstanceUID != originals[0].StudyInstanceUID
    assert len({c.PatientID for c in copies}) == 1


def test_private_tags_removed(tmp_path: Path):
    ds = make_dataset()
    block = ds.private_block(0x0011, "ACME", create=True)
    block.add_new(0x01, "LO", "segredo")
    src = write(ds, tmp_path / "p.dcm")
    out = anonymize_to_folder([src], tmp_path / "anon")
    anon = pydicom.dcmread(out[str(src)])
    assert not any(e.tag.is_private for e in anon)


def test_batches_are_not_correlatable():
    ds1, ds2 = make_dataset(), make_dataset()
    ds2.PatientID = ds1.PatientID
    ds2.PatientName = ds1.PatientName
    a = Anonymizer().apply(ds1)
    b = Anonymizer().apply(ds2)
    assert a.PatientID != b.PatientID


def test_custom_name_and_fixed_id():
    ds = Anonymizer(AnonymizationOptions(patient_name="PESQUISA^001", patient_id="P001")).apply(make_dataset())
    assert str(ds.PatientName) == "PESQUISA^001"
    assert ds.PatientID == "P001"
