"""Objetos DICOM sintéticos para os testes.

Nenhum dado de paciente real entra no repositório: os exames são gerados
na hora, com pixels conhecidos, para que as asserções possam conferir
valores exatos (rescale, janela, medidas).
"""

from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import pydicom
import pytest
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.uid import (
    CTImageStorage,
    ExplicitVRLittleEndian,
    SecondaryCaptureImageStorage,
    generate_uid,
)

# Testes de interface rodam sem servidor gráfico.
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

DX_STORAGE = "1.2.840.10008.5.1.4.1.1.1.1"


def make_dataset(
    *,
    patient_name: str = "SILVA^JOAO",
    patient_id: str = "PAC001",
    study_uid: str | None = None,
    series_uid: str | None = None,
    series_number: int | None = 1,
    instance_number: int | None = 1,
    modality: str = "CT",
    pixels: np.ndarray | None = None,
    photometric: str = "MONOCHROME2",
    sop_class: str = CTImageStorage,
    slope: float = 1.0,
    intercept: float = -1024.0,
    window: tuple[float, float] | None = (40.0, 400.0),
    spacing: tuple[float, float] | None = (0.5, 0.5),
    position_z: float | None = None,
    charset: str | None = None,
) -> Dataset:
    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = sop_class
    meta.MediaStorageSOPInstanceUID = generate_uid()
    meta.TransferSyntaxUID = ExplicitVRLittleEndian

    ds = Dataset()
    ds.file_meta = meta
    if charset:
        ds.SpecificCharacterSet = charset
    ds.SOPClassUID = sop_class
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.PatientName = patient_name
    ds.PatientID = patient_id
    ds.PatientBirthDate = "19700101"
    ds.PatientSex = "M"
    ds.StudyInstanceUID = study_uid or generate_uid()
    ds.SeriesInstanceUID = series_uid or generate_uid()
    ds.StudyDate = "20240115"
    ds.StudyTime = "101500"
    ds.StudyID = "1"
    ds.AccessionNumber = "ACC123"
    ds.StudyDescription = "TORAX"
    ds.SeriesDescription = "AXIAL"
    ds.InstitutionName = "HOSPITAL TESTE"
    ds.ReferringPhysicianName = "DR^HOUSE"
    ds.Modality = modality
    if series_number is not None:
        ds.SeriesNumber = series_number
    if instance_number is not None:
        ds.InstanceNumber = instance_number
    if position_z is not None:
        ds.ImagePositionPatient = [0.0, 0.0, position_z]
        ds.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]

    if pixels is None:
        pixels = (np.arange(64 * 64, dtype=np.uint16).reshape(64, 64) % 2000)
    if pixels.ndim == 3 and pixels.shape[-1] == 3:
        ds.SamplesPerPixel = 3
        ds.PlanarConfiguration = 0
        rows, cols = pixels.shape[:2]
    elif pixels.ndim == 3:
        ds.SamplesPerPixel = 1
        ds.NumberOfFrames = pixels.shape[0]
        rows, cols = pixels.shape[1:]
    else:
        ds.SamplesPerPixel = 1
        rows, cols = pixels.shape
    ds.PhotometricInterpretation = photometric
    ds.Rows, ds.Columns = rows, cols
    bits = 8 if pixels.dtype == np.uint8 else 16
    ds.BitsAllocated = bits
    ds.BitsStored = bits if bits == 8 else 12
    ds.HighBit = ds.BitsStored - 1
    ds.PixelRepresentation = 1 if pixels.dtype == np.int16 else 0
    if ds.SamplesPerPixel == 1 and bits == 16:
        ds.RescaleSlope = slope
        ds.RescaleIntercept = intercept
    if window:
        ds.WindowCenter, ds.WindowWidth = window
    if spacing:
        ds.PixelSpacing = list(spacing)
    ds.PixelData = pixels.tobytes()
    return ds


def write(ds: Dataset, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    ds.save_as(path, enforce_file_format=True)
    return path


@pytest.fixture
def ct_series(tmp_path: Path) -> list[Path]:
    """Série de 5 cortes gravados fora de ordem no disco."""
    study, series = generate_uid(), generate_uid()
    paths = []
    for order, inst in enumerate([3, 1, 5, 2, 4]):
        px = np.full((32, 32), 1000 + inst * 10, dtype=np.uint16)
        ds = make_dataset(study_uid=study, series_uid=series, instance_number=inst, pixels=px, position_z=inst * 2.5)
        paths.append(write(ds, tmp_path / "src" / f"img_{order}.dcm"))
    return paths


@pytest.fixture
def mixed_folder(tmp_path: Path) -> Path:
    """Pasta com dois pacientes, CT, DX MONOCHROME1, RGB e multiquadro."""
    root = tmp_path / "mixed"
    study, series = generate_uid(), generate_uid()
    for i in range(3):
        write(make_dataset(study_uid=study, series_uid=series, instance_number=i + 1), root / "ct" / f"ct{i}.dcm")
    dx = make_dataset(
        patient_name="SOUZA^MARIA",
        patient_id="PAC002",
        modality="DX",
        sop_class=DX_STORAGE,
        photometric="MONOCHROME1",
        intercept=0.0,
        window=None,
    )
    write(dx, root / "dx" / "dx.dcm")
    rgb = np.zeros((16, 16, 3), dtype=np.uint8)
    rgb[..., 0] = 255
    sc = make_dataset(
        patient_name="SOUZA^MARIA",
        patient_id="PAC002",
        modality="OT",
        sop_class=SecondaryCaptureImageStorage,
        pixels=rgb,
        photometric="RGB",
        window=None,
        spacing=None,
    )
    write(sc, root / "sc" / "rgb.dcm")
    multi = np.stack([np.full((8, 8), v, dtype=np.uint16) for v in (100, 200, 300)])
    write(make_dataset(patient_id="PAC001", pixels=multi, modality="CT"), root / "mf" / "multi.dcm")
    (root / "notes.txt").write_text("não é DICOM")
    return root


def read(path: Path) -> Dataset:
    return pydicom.dcmread(str(path))
