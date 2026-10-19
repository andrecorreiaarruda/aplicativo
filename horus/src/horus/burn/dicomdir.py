"""Geração do DICOMDIR — porte de `+[DicomDir createDicomDirAtDir:]`.

O Horos usa o DicomDirInterface do DCMTK com estas opções (DicomDir.mm):

* `disableConsistencyCheck` e `disableTransferSyntaxCheck` (`-W`, `-Nxc`):
  aceita arquivos inconsistentes ou em qualquer sintaxe de transferência;
* `enableInventMode` (`+I`): inventa no registro os atributos de tipo 1
  ausentes no arquivo (ID do paciente, número da série etc.), sem alterar
  o arquivo;
* perfil `AP_USBandFlash` (General Purpose), varredura recursiva da pasta
  e gravação com comprimentos explícitos (`EET_ExplicitLength`).

O DCMTK não é necessário aqui: o DICOMDIR é um objeto DICOM comum, com uma
sequência de registros ligados por deslocamentos em bytes. Os registros
são serializados uma vez para medir o tamanho de cada item, os
deslocamentos são calculados e a serialização é refeita — os campos de
deslocamento têm tamanho fixo (UL), então as posições não mudam.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Iterable

import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.filebase import DicomBytesIO
from pydicom.filewriter import write_dataset, write_file_meta_info
from pydicom.uid import ExplicitVRLittleEndian, PYDICOM_IMPLEMENTATION_UID, generate_uid

from ..dicom.fileio import IMPLEMENTATION_VERSION
from ..importer import MEDIA_STORAGE_DIRECTORY, is_dicom_file

DICOMDIR_NAME = "DICOMDIR"
_FILE_ID_COMPONENT = re.compile(r"^[A-Z0-9_]{1,8}$")

# Atributos copiados para cada tipo de registro quando presentes no
# arquivo (PS3.3, anexo F.5). Os de tipo 1 ausentes são inventados.
_PATIENT_KEYS = ("PatientName", "PatientID", "PatientBirthDate", "PatientSex")
_STUDY_KEYS = (
    "StudyDate",
    "StudyTime",
    "StudyDescription",
    "StudyInstanceUID",
    "StudyID",
    "AccessionNumber",
    "ReferringPhysicianName",
)
# InstitutionName e PixelSpacing são os que o DCMTK acrescenta no perfil
# de USB/Flash (dcmmkdir -Pfl), conferido gerando os dois para a mesma pasta.
_SERIES_KEYS = (
    "Modality",
    "SeriesInstanceUID",
    "SeriesNumber",
    "SeriesDescription",
    "SeriesDate",
    "InstitutionName",
)
_LEAF_KEYS = {
    "IMAGE": (
        "InstanceNumber",
        "ImageType",
        "Rows",
        "Columns",
        "NumberOfFrames",
        "PixelSpacing",
        "ImagePositionPatient",
    ),
    "SR DOCUMENT": (
        "InstanceNumber",
        "CompletionFlag",
        "VerificationFlag",
        "ContentDate",
        "ContentTime",
        "VerificationDateTime",
        "ConceptNameCodeSequence",
    ),
    "KEY OBJECT DOC": ("InstanceNumber", "ContentDate", "ContentTime", "ConceptNameCodeSequence"),
    "PRESENTATION": (
        "InstanceNumber",
        "PresentationCreationDate",
        "PresentationCreationTime",
        "ContentLabel",
        "ContentDescription",
        "ContentCreatorName",
        "ReferencedSeriesSequence",
    ),
    "ENCAP DOC": (
        "InstanceNumber",
        "ContentDate",
        "ContentTime",
        "DocumentTitle",
        "MIMETypeOfEncapsulatedDocument",
    ),
}


def leaf_record_type(ds: Dataset) -> str:
    modality = str(ds.get("Modality", "")).upper()
    if "EncapsulatedDocument" in ds:
        return "ENCAP DOC"
    if modality == "SR":
        return "SR DOCUMENT"
    if modality == "KO":
        return "KEY OBJECT DOC"
    if modality == "PR":
        return "PRESENTATION"
    return "IMAGE"


def file_id_for(root: Path, path: Path) -> list[str]:
    """Componentes do ReferencedFileID; recusa nomes fora do PS3.10.

    Mídias DICOM exigem componentes de até 8 caracteres A–Z, 0–9 e "_",
    compatíveis com ISO 9660 nível 1.
    """
    parts = list(path.relative_to(root).parts)
    for part in parts:
        if not _FILE_ID_COMPONENT.match(part):
            raise ValueError(f"nome fora do padrão de mídia DICOM: {part!r} em {path}")
    if len(parts) > 8:
        raise ValueError(f"caminho com mais de 8 níveis: {path}")
    return parts


@dataclass
class _Node:
    record: Dataset
    children: list["_Node"] = field(default_factory=list)
    sort_key: tuple = ()


def _copy_keys(record: Dataset, ds: Dataset, keys: Iterable[str]) -> None:
    for kw in keys:
        if kw in ds and ds[kw].value not in (None, ""):
            record[kw] = ds[kw]


def _needs_utf8(ds: Dataset) -> bool:
    for elem in ds:
        if isinstance(elem.value, str) and not elem.value.isascii():
            return True
        if elem.VR == "PN" and elem.value is not None and not str(elem.value).isascii():
            return True
    return False


def _new_record(kind: str) -> Dataset:
    rec = Dataset()
    rec.OffsetOfTheNextDirectoryRecord = 0
    rec.RecordInUseFlag = 0xFFFF
    rec.OffsetOfReferencedLowerLevelDirectoryEntity = 0
    rec.DirectoryRecordType = kind
    return rec


class _Inventor:
    """Valores inventados para atributos de tipo 1 ausentes (+I do DCMTK)."""

    def __init__(self) -> None:
        self.patients = 0
        self.studies = 0
        self.series_numbers: dict[str, int] = {}
        self.instance_numbers: dict[str, int] = {}

    def patient_id(self) -> str:
        self.patients += 1
        return f"HORUSPAT{self.patients:06d}"

    def study_id(self) -> str:
        self.studies += 1
        return str(self.studies)

    def series_number(self, study_uid: str) -> int:
        n = self.series_numbers.get(study_uid, 0) + 1
        self.series_numbers[study_uid] = n
        return n

    def instance_number(self, series_uid: str) -> int:
        n = self.instance_numbers.get(series_uid, 0) + 1
        self.instance_numbers[series_uid] = n
        return n


def _first_date(ds: Dataset) -> str:
    for kw in ("StudyDate", "SeriesDate", "AcquisitionDate", "ContentDate"):
        v = str(ds.get(kw, "") or "")
        if v:
            return v
    return date.today().strftime("%Y%m%d")


def build_dicomdir(root: Path, fileset_id: str = "HORUS", files: Iterable[Path] | None = None) -> Path:
    """Varre `root` (ou usa `files`) e grava `root/DICOMDIR`."""
    root = Path(root)
    if files is None:
        files = sorted(
            p
            for p in root.rglob("*")
            if p.is_file() and p.name.upper() != DICOMDIR_NAME and is_dicom_file(p)
        )

    inventor = _Inventor()
    patients: dict[str, _Node] = {}
    studies: dict[str, _Node] = {}
    series: dict[str, _Node] = {}
    invented_patient_ids: dict[str, str] = {}

    for path in files:
        ds = pydicom.dcmread(str(path), stop_before_pixels=True, force=True)
        meta = getattr(ds, "file_meta", None)
        if meta is not None and str(meta.get("MediaStorageSOPClassUID", "")) == MEDIA_STORAGE_DIRECTORY:
            continue
        if "SOPInstanceUID" not in ds or "SOPClassUID" not in ds:
            continue  # sem identidade não há como referenciar
        file_id = file_id_for(root, Path(path))
        utf8 = _needs_utf8(ds)

        # --- paciente
        pid = str(ds.get("PatientID", "") or "")
        if not pid:
            name_key = f"{ds.get('PatientName', '')}|{ds.get('PatientBirthDate', '')}"
            pid = invented_patient_ids.setdefault(name_key, inventor.patient_id())
        patient = patients.get(pid)
        if patient is None:
            rec = _new_record("PATIENT")
            _copy_keys(rec, ds, _PATIENT_KEYS)
            rec.PatientID = pid
            rec.setdefault("PatientName", "")
            patient = _Node(rec, sort_key=(str(rec.PatientName), pid))
            patients[pid] = patient

        # --- estudo
        study_uid = str(ds.get("StudyInstanceUID", "") or "") or generate_uid()
        study = studies.get(study_uid)
        if study is None:
            rec = _new_record("STUDY")
            _copy_keys(rec, ds, _STUDY_KEYS)
            rec.StudyInstanceUID = study_uid
            rec.StudyDate = str(rec.get("StudyDate", "") or "") or _first_date(ds)
            rec.StudyTime = str(rec.get("StudyTime", "") or "") or "000000"
            rec.StudyID = str(rec.get("StudyID", "") or "") or inventor.study_id()
            rec.setdefault("StudyDescription", "")
            rec.setdefault("AccessionNumber", "")
            study = _Node(rec, sort_key=(str(rec.StudyDate), str(rec.StudyTime), study_uid))
            studies[study_uid] = study
            patient.children.append(study)

        # --- série
        series_uid = str(ds.get("SeriesInstanceUID", "") or "") or f"{study_uid}.0"
        node = series.get(series_uid)
        if node is None:
            rec = _new_record("SERIES")
            _copy_keys(rec, ds, _SERIES_KEYS)
            rec.SeriesInstanceUID = series_uid
            rec.Modality = str(rec.get("Modality", "") or "") or "OT"
            if "SeriesNumber" not in rec:
                rec.SeriesNumber = inventor.series_number(study_uid)
            node = _Node(rec, sort_key=(int(rec.SeriesNumber), series_uid))
            series[series_uid] = node
            study.children.append(node)

        # --- instância
        kind = leaf_record_type(ds)
        rec = _new_record(kind)
        _copy_keys(rec, ds, _LEAF_KEYS[kind])
        if "InstanceNumber" not in rec:
            rec.InstanceNumber = inventor.instance_number(series_uid)
        rec.ReferencedFileID = file_id if len(file_id) > 1 else file_id[0]
        rec.ReferencedSOPClassUIDInFile = ds.SOPClassUID
        rec.ReferencedSOPInstanceUIDInFile = ds.SOPInstanceUID
        transfer = meta.get("TransferSyntaxUID") if meta is not None else None
        if transfer:
            rec.ReferencedTransferSyntaxUIDInFile = transfer
        node.children.append(_Node(rec, sort_key=(int(rec.InstanceNumber), str(ds.SOPInstanceUID))))

        if utf8:
            for level in (patient, study, node):
                level.record.SpecificCharacterSet = "ISO_IR 192"
            rec.SpecificCharacterSet = "ISO_IR 192"

    roots = sorted(patients.values(), key=lambda n: n.sort_key)
    out = root / DICOMDIR_NAME
    out.write_bytes(_serialize(roots, fileset_id))
    return out


# ---------------------------------------------------------------- escrita


def _flatten(nodes: list[_Node]) -> list[_Node]:
    """Ordem de pré-ordem (paciente, seus estudos, ...), como o DCMTK."""
    ordered: list[_Node] = []

    def visit(level: list[_Node]) -> None:
        for n in sorted(level, key=lambda x: x.sort_key):
            ordered.append(n)
            visit(n.children)

    visit(nodes)
    return ordered


def _encode(ds: Dataset) -> bytes:
    fp = DicomBytesIO()
    fp.is_little_endian = True
    fp.is_implicit_VR = False
    write_dataset(fp, ds)
    return fp.getvalue()


def _link(nodes: list[_Node], offsets: dict[int, int]) -> None:
    ordered = sorted(nodes, key=lambda x: x.sort_key)
    for i, n in enumerate(ordered):
        nxt = ordered[i + 1] if i + 1 < len(ordered) else None
        n.record.OffsetOfTheNextDirectoryRecord = offsets[id(nxt)] if nxt else 0
        if n.children:
            first = min(n.children, key=lambda x: x.sort_key)
            n.record.OffsetOfReferencedLowerLevelDirectoryEntity = offsets[id(first)]
        else:
            n.record.OffsetOfReferencedLowerLevelDirectoryEntity = 0
        _link(n.children, offsets)


def _serialize(roots: list[_Node], fileset_id: str) -> bytes:
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = MEDIA_STORAGE_DIRECTORY
    meta.MediaStorageSOPInstanceUID = generate_uid()
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    meta.ImplementationClassUID = PYDICOM_IMPLEMENTATION_UID
    meta.ImplementationVersionName = IMPLEMENTATION_VERSION

    head = DicomBytesIO()
    head.is_little_endian = True
    head.is_implicit_VR = False
    head.write(b"\x00" * 128 + b"DICM")
    write_file_meta_info(head, meta, enforce_standard=True)
    prefix = head.getvalue()

    header = Dataset()
    header.FileSetID = (fileset_id or "HORUS")[:16]
    header.OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity = 0
    header.OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity = 0
    header.FileSetConsistencyFlag = 0

    ordered = _flatten(roots)
    header_len = len(_encode(header))
    # Tag (4) + VR "SQ" (2) + reservado (2) + comprimento (4).
    sequence_start = len(prefix) + header_len + 12

    def layout() -> tuple[dict[int, int], list[bytes]]:
        offsets: dict[int, int] = {}
        encoded: list[bytes] = []
        pos = sequence_start
        for n in ordered:
            offsets[id(n)] = pos
            body = _encode(n.record)
            encoded.append(body)
            pos += 8 + len(body)
        return offsets, encoded

    offsets, _ = layout()
    _link(roots, offsets)
    offsets_after, items = layout()
    assert offsets_after == offsets, "deslocamentos mudaram entre as passagens"

    if ordered:
        root_sorted = sorted(roots, key=lambda x: x.sort_key)
        header.OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity = offsets[id(root_sorted[0])]
        header.OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity = offsets[id(root_sorted[-1])]

    body = bytearray()
    for item in items:
        body += _ITEM_TAG + len(item).to_bytes(4, "little") + item

    out = bytearray(prefix)
    out += _encode(header)
    out += _SEQUENCE_TAG + b"SQ\x00\x00" + len(body).to_bytes(4, "little")
    out += body
    return bytes(out)


# (FFFE,E000) Item e (0004,1220) Directory Record Sequence, little endian.
_ITEM_TAG = b"\xfe\xff\x00\xe0"
_SEQUENCE_TAG = b"\x04\x00\x20\x12"
