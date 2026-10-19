"""Regras de correspondência do C-FIND (PS3.4 C.2.2.2) sobre a base local."""

from __future__ import annotations

import warnings
from pathlib import Path

import pytest
from conftest import make_dataset, write
from pydicom.dataset import Dataset
from pydicom.uid import generate_uid

from horus.database import Database
from horus.net.query import (
    PATIENT_ROOT,
    STUDY_ROOT,
    QueryEngine,
    QueryError,
    match_clause,
)


@pytest.fixture
def engine(tmp_path: Path) -> QueryEngine:
    src = tmp_path / "src"
    ct_study, ct_series = generate_uid(), generate_uid()
    for i in range(3):
        ds = make_dataset(patient_name="SILVA^JOAO", patient_id="P1", study_uid=ct_study, series_uid=ct_series, instance_number=i + 1, modality="CT")
        ds.StudyDate, ds.StudyTime, ds.AccessionNumber = "20240115", "101500", "A100"
        write(ds, src / f"ct{i}.dcm")
    mr = make_dataset(patient_name="SILVA^JOAO", patient_id="P1", modality="MR", series_number=2)
    mr.StudyDate, mr.AccessionNumber, mr.StudyDescription = "20240310", "A200", "CRANIO"
    mr.StudyTime = "153000"
    write(mr, src / "mr.dcm")
    other = make_dataset(patient_name="CONCEIÇÃO^MARIA", patient_id="P2", modality="DX", charset="ISO_IR 100")
    other.StudyDate, other.AccessionNumber, other.StudyTime = "20231201", "A300", "080000"
    write(other, src / "dx.dcm")
    db = Database(tmp_path / "base")
    assert db.add_files([src]).added == 5
    return QueryEngine(db)


def q(level: str, **keys) -> Dataset:
    ds = Dataset()
    ds.QueryRetrieveLevel = level
    for k, v in keys.items():
        setattr(ds, k, v)
    return ds


def test_universal_match_returns_requested_keys(engine):
    results = list(engine.find(q("STUDY", PatientName="", StudyInstanceUID="", StudyDate="", NumberOfStudyRelatedInstances="")))
    assert len(results) == 3
    first = results[0]  # mais recente primeiro
    assert first.StudyDate == "20240310"
    assert str(first.PatientName) == "SILVA^JOAO"  # nome no formato DICOM, com ^
    assert int(first.NumberOfStudyRelatedInstances) == 1
    ct = next(r for r in results if r.StudyDate == "20240115")
    assert int(ct.NumberOfStudyRelatedInstances) == 3


def test_wildcards_and_case(engine):
    assert len(list(engine.find(q("STUDY", PatientName="silva*")))) == 2
    assert len(list(engine.find(q("STUDY", PatientName="S?LVA^JOAO")))) == 2
    assert len(list(engine.find(q("STUDY", AccessionNumber="A1*")))) == 1
    assert len(list(engine.find(q("STUDY", AccessionNumber="a100")))) == 1  # sem maiúsculas
    assert len(list(engine.find(q("STUDY", AccessionNumber="A10")))) == 0  # sem curinga é exato


def test_patient_name_matches_like_horos(engine):
    # Palavras: a primeira abre o nome, as demais aparecem em qualquer ponto,
    # sem acentos nem maiúsculas (patientsnamePredicate do Horos).
    assert len(list(engine.find(q("STUDY", PatientName="silva")))) == 2
    assert len(list(engine.find(q("STUDY", PatientName="SILVA^JOAO")))) == 2
    assert len(list(engine.find(q("STUDY", PatientName="joao")))) == 0
    assert len(list(engine.find(q("STUDY", PatientName="*joao")))) == 2
    assert len(list(engine.find(q("STUDY", PatientName="conceicao maria")))) == 1


def test_retrieve_ae_title_in_responses(engine):
    (hit,) = engine.find(q("STUDY", AccessionNumber="A100"), retrieve_ae="HORUS1")
    assert hit.RetrieveAETitle == "HORUS1"


def test_date_ranges(engine):
    assert {r.AccessionNumber for r in engine.find(q("STUDY", StudyDate="20240101-", AccessionNumber=""))} == {"A100", "A200"}
    assert {r.AccessionNumber for r in engine.find(q("STUDY", StudyDate="-20231231", AccessionNumber=""))} == {"A300"}
    assert {r.AccessionNumber for r in engine.find(q("STUDY", StudyDate="20240101-20240131", AccessionNumber=""))} == {"A100"}
    assert {r.AccessionNumber for r in engine.find(q("STUDY", StudyTime="1000-1100", AccessionNumber=""))} == {"A100"}


def test_modalities_in_study(engine):
    hits = list(engine.find(q("STUDY", ModalitiesInStudy="MR", AccessionNumber="")))
    assert [r.AccessionNumber for r in hits] == ["A200"]
    assert hits[0].ModalitiesInStudy == "MR"
    both = list(engine.find(q("STUDY", ModalitiesInStudy=["CT", "DX"], AccessionNumber="")))
    assert {r.AccessionNumber for r in both} == {"A100", "A300"}


def test_modalities_in_study_universal_and_wildcards(engine):
    def found(value):
        return {str(r.AccessionNumber) for r in engine.find(q("STUDY", ModalitiesInStudy=value, AccessionNumber=""))}

    # "*" sozinho é a correspondência universal; curingas valem por modalidade.
    assert found("*") == {"A100", "A200", "A300"}
    assert found("C*") == {"A100"}
    assert found("?R") == {"A200"}
    assert found(["D?", "MR"]) == {"A200", "A300"}
    with warnings.catch_warnings():  # "ct" não é um CS válido; o pydicom avisa
        warnings.simplefilter("ignore", UserWarning)
        assert found("ct") == {"A100"}  # sem diferenciar maiúsculas, como o Horos ([cd])


def test_uid_list_and_series_level(engine):
    studies = list(engine.find(q("STUDY", StudyInstanceUID="", AccessionNumber="")))
    uids = [r.StudyInstanceUID for r in studies]
    series = list(engine.find(q("SERIES", StudyInstanceUID=uids, Modality="", SeriesInstanceUID="", NumberOfSeriesRelatedInstances="")))
    assert sorted(r.Modality for r in series) == ["CT", "DX", "MR"]
    ct = next(r for r in series if r.Modality == "CT")
    assert int(ct.NumberOfSeriesRelatedInstances) == 3
    images = list(engine.find(q("IMAGE", SeriesInstanceUID=ct.SeriesInstanceUID, SOPInstanceUID="", InstanceNumber="")))
    assert [int(r.InstanceNumber) for r in images] == [1, 2, 3]


def test_lower_level_keys_do_not_filter_and_come_back_empty(engine):
    results = list(engine.find(q("STUDY", Modality="CT", AccessionNumber="")))
    assert len(results) == 3
    assert all(r.Modality in ("", None) for r in results)


def test_patient_root_patient_level(engine):
    patients = list(engine.find(q("PATIENT", PatientID="", PatientName="", NumberOfPatientRelatedStudies=""), PATIENT_ROOT))
    by_id = {p.PatientID: p for p in patients}
    assert int(by_id["P1"].NumberOfPatientRelatedStudies) == 2
    with pytest.raises(QueryError):
        list(engine.find(q("PATIENT", PatientID=""), STUDY_ROOT))


def test_non_ascii_name_is_returned_as_utf8(engine):
    (hit,) = engine.find(q("STUDY", PatientID="P2", PatientName=""))
    assert hit.SpecificCharacterSet == "ISO_IR 192"
    assert str(hit.PatientName) == "CONCEIÇÃO^MARIA"


def test_retrieve_requires_unique_key(engine):
    (study,) = engine.find(q("STUDY", AccessionNumber="A100", StudyInstanceUID=""))
    items = engine.retrieve(q("STUDY", StudyInstanceUID=study.StudyInstanceUID))
    assert len(items) == 3 and all(Path(i.path).exists() for i in items)
    with pytest.raises(QueryError):
        engine.retrieve(q("STUDY"))


def test_like_escaping():
    sql, args = match_clause("x", "LO", "50%*")
    assert args == ["50\\%%"]
    assert match_clause("x", "IS", "*") is None
    assert match_clause("x", "LO", "") is None
