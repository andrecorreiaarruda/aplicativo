"""Anonimização de cópias de arquivos DICOM.

O Horos (`+[Anonymization anonymizeFiles:dicomImages:toPath:withTags:]`)
copia cada arquivo para uma pasta temporária e substitui os atributos de
uma lista configurável, devolvendo um dicionário arquivo original → cópia.
O gravador usa isso antes de montar o disco, em `/tmp/burnAnonymized`.

Aqui a lista padrão segue um subconjunto do perfil básico de
confidencialidade do PS3.15 (anexo E): identificação do paciente,
profissionais, instituição e equipamento são removidos ou esvaziados, e os
UIDs de estudo, série, instância e referencial são trocados de forma
consistente dentro do lote — a hierarquia do exame continua válida no
disco. Texto gravado nos próprios pixels (comum em US e capturas de tela)
não é tratado, assim como no Horos.
"""

from __future__ import annotations

import hashlib
import secrets
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable

import pydicom
from pydicom.dataset import Dataset
from pydicom.uid import generate_uid

from .dicom.fileio import save_media_file

# Esvaziados (atributos de tipo 2 devem continuar presentes).
BLANK = (
    "AccessionNumber",
    "ReferringPhysicianName",
    "PatientBirthDate",
    "StudyID",
)

REMOVE = (
    "OtherPatientIDs",
    "OtherPatientIDsSequence",
    "OtherPatientNames",
    "PatientBirthName",
    "PatientMotherBirthName",
    "PatientAddress",
    "PatientTelephoneNumbers",
    "PatientInsurancePlanCodeSequence",
    "MilitaryRank",
    "BranchOfService",
    "MedicalRecordLocator",
    "Occupation",
    "AdditionalPatientHistory",
    "PatientComments",
    "PatientBirthTime",
    "IssuerOfPatientID",
    "InstitutionName",
    "InstitutionAddress",
    "InstitutionalDepartmentName",
    "ReferringPhysicianAddress",
    "ReferringPhysicianTelephoneNumbers",
    "PhysiciansOfRecord",
    "PerformingPhysicianName",
    "NameOfPhysiciansReadingStudy",
    "OperatorsName",
    "RequestingPhysician",
    "StationName",
    "DeviceSerialNumber",
    "RequestAttributesSequence",
    "ImageComments",
    "StudyComments",
    "RequestedProcedureDescription",
    "PerformedProcedureStepID",
    "ScheduledProcedureStepID",
)

UID_KEYWORDS = (
    "StudyInstanceUID",
    "SeriesInstanceUID",
    "SOPInstanceUID",
    "FrameOfReferenceUID",
    "ReferencedSOPInstanceUID",
    "ReferencedFrameOfReferenceUID",
    "RelatedFrameOfReferenceUID",
)


@dataclass
class AnonymizationOptions:
    patient_name: str = "ANONIMO"
    # None: deriva um ID estável dentro do lote a partir do original.
    patient_id: str | None = None
    keep_sex_and_age: bool = True
    keep_dates: bool = True
    keep_descriptions: bool = True
    remove_private_tags: bool = True
    replace_uids: bool = True


class Anonymizer:
    """Um lote: mesmo segredo para todos os arquivos.

    UIDs e IDs derivados do original com um segredo do lote ficam
    consistentes entre os arquivos do mesmo exame, mas não podem ser
    revertidos nem correlacionados com outro lote.
    """

    def __init__(self, options: AnonymizationOptions | None = None):
        self.options = options or AnonymizationOptions()
        self._salt = secrets.token_hex(16)

    def _uid(self, original: str) -> str:
        return generate_uid(entropy_srcs=[self._salt, original])

    def _patient_id(self, original: str) -> str:
        if self.options.patient_id is not None:
            return self.options.patient_id
        digest = hashlib.sha256(f"{self._salt}:{original}".encode()).hexdigest()
        return "ANON" + digest[:8].upper()

    def _walk_uids(self, ds: Dataset) -> None:
        for elem in ds:
            if elem.VR == "SQ":
                for item in elem.value:
                    self._walk_uids(item)
            elif elem.keyword in UID_KEYWORDS and elem.value:
                if isinstance(elem.value, (list, pydicom.multival.MultiValue)):
                    elem.value = [self._uid(str(v)) for v in elem.value]
                else:
                    elem.value = self._uid(str(elem.value))

    def _blank_person_names(self, ds: Dataset) -> None:
        for elem in ds:
            if elem.VR == "SQ":
                for item in elem.value:
                    self._blank_person_names(item)
            elif elem.VR == "PN" and elem.keyword != "PatientName":
                elem.value = ""

    def apply(self, ds: Dataset) -> Dataset:
        opts = self.options
        original_id = str(ds.get("PatientID", "")) + "|" + str(ds.get("PatientName", ""))
        ds.PatientName = opts.patient_name
        ds.PatientID = self._patient_id(original_id)
        for kw in BLANK:
            if kw in ds:
                ds[kw].value = ""
        for kw in REMOVE:
            if kw in ds:
                del ds[kw]
        if not opts.keep_sex_and_age:
            for kw in ("PatientSex", "PatientAge", "PatientWeight", "PatientSize"):
                if kw in ds:
                    ds[kw].value = ""
        if not opts.keep_dates:
            for elem in ds:
                if elem.VR in ("DA", "DT", "TM") and elem.keyword not in ("PatientBirthDate",):
                    elem.value = ""
        if not opts.keep_descriptions:
            for kw in ("StudyDescription", "SeriesDescription", "ProtocolName"):
                if kw in ds:
                    ds[kw].value = ""
        self._blank_person_names(ds)
        if opts.remove_private_tags:
            ds.remove_private_tags()
        if opts.replace_uids:
            self._walk_uids(ds)
            meta = getattr(ds, "file_meta", None)
            if meta is not None and "SOPInstanceUID" in ds:
                meta.MediaStorageSOPInstanceUID = ds.SOPInstanceUID
        ds.PatientIdentityRemoved = "YES"
        ds.DeidentificationMethod = "Horus: PS3.15 perfil basico (subconjunto)"
        return ds

    def anonymize_files(
        self,
        files: Iterable[str | Path],
        out_dir: Path,
        progress: Callable[[int, str], None] | None = None,
        cancelled: Callable[[], bool] = lambda: False,
    ) -> dict[str, Path]:
        """Grava cópias anonimizadas; devolve original → cópia."""
        out_dir.mkdir(parents=True, exist_ok=True)
        produced: dict[str, Path] = {}
        for n, src in enumerate(files):
            if cancelled():
                break
            if progress:
                progress(n + 1, str(src))
            ds = pydicom.dcmread(str(src), force=True)
            self.apply(ds)
            target = out_dir / f"{n:06d}.dcm"
            save_media_file(ds, target)
            produced[str(src)] = target
        return produced


def anonymize_to_folder(
    files: Iterable[str | Path],
    out_dir: Path,
    options: AnonymizationOptions | None = None,
    progress: Callable[[int, str], None] | None = None,
    cancelled: Callable[[], bool] = lambda: False,
) -> dict[str, Path]:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    return Anonymizer(options).anonymize_files(files, out_dir, progress, cancelled)
