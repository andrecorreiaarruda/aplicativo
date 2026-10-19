"""Gravação de arquivos DICOM no formato de mídia (PS3.10)."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pydicom
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.pixels import pixel_array
from pydicom.uid import (
    ExplicitVRBigEndian,
    ExplicitVRLittleEndian,
    ImplicitVRLittleEndian,
    PYDICOM_IMPLEMENTATION_UID,
)

IMPLEMENTATION_VERSION = "HORUS_010"


def ensure_file_meta(ds: Dataset) -> Dataset:
    """Completa a meta de arquivo de objetos lidos sem ela.

    Discos antigos trazem objetos "crus", sem preâmbulo nem grupo 0002.
    Para ir a uma mídia DICOM eles precisam da meta completa; a sintaxe de
    transferência é a mesma com que o objeto foi lido.
    """
    meta = getattr(ds, "file_meta", None)
    if meta is None:
        meta = FileMetaDataset()
        ds.file_meta = meta
    if "TransferSyntaxUID" not in meta:
        implicit, little = getattr(ds, "original_encoding", (True, True))
        if implicit:
            meta.TransferSyntaxUID = ImplicitVRLittleEndian
        else:
            meta.TransferSyntaxUID = ExplicitVRLittleEndian if little else ExplicitVRBigEndian
    if "SOPClassUID" in ds:
        meta.MediaStorageSOPClassUID = ds.SOPClassUID
    if "SOPInstanceUID" in ds:
        meta.MediaStorageSOPInstanceUID = ds.SOPInstanceUID
    meta.setdefault("ImplementationClassUID", PYDICOM_IMPLEMENTATION_UID)
    meta.ImplementationVersionName = IMPLEMENTATION_VERSION
    return ds


def save_media_file(ds: Dataset, path: Path) -> None:
    ensure_file_meta(ds)
    # dcmwrite, e não save_as: save_as recusa trocar a ordem dos bytes de
    # um objeto lido em big endian, o que to_explicit_little faz de
    # propósito.
    pydicom.dcmwrite(path, ds, enforce_file_format=True)


# Largura das palavras dos VRs binários que mudam com a ordem dos bytes.
_SWAP_WIDTH = {"OW": 2, "OF": 4, "OL": 4, "OD": 8, "OV": 8}


def _swap_binary_values(ds: Dataset) -> None:
    for elem in ds:
        if elem.VR == "SQ":
            for item in elem.value:
                _swap_binary_values(item)
        elif elem.tag != 0x7FE00010 and elem.VR in _SWAP_WIDTH and isinstance(elem.value, bytes):
            width = _SWAP_WIDTH[elem.VR]
            usable = len(elem.value) - len(elem.value) % width
            words = np.frombuffer(elem.value[:usable], dtype=f">u{width}")
            elem.value = words.astype(f"<u{width}").tobytes() + elem.value[usable:]


def to_explicit_little(ds: Dataset) -> Dataset:
    """Converte Explicit VR Big Endian, sintaxe aposentada.

    O gravador do Horos faz a mesma conversão antes de montar o disco
    (`bigEndianFilesToConvert` em prepareCDContent), porque vários
    leitores de mídia não aceitam big endian.
    """
    if ds.file_meta.get("TransferSyntaxUID") != ExplicitVRBigEndian:
        return ds
    # Decodifica todos os elementos enquanto a sintaxe ainda é a original;
    # números (US, UL, FL...) passam a valores Python e são regravados na
    # nova ordem. Os binários (OW, OF...) continuam bytes e são trocados à mão.
    for _ in ds.iterall():
        pass
    if "PixelData" in ds:
        # `raw=True` evita a conversão YBR → RGB, que deixaria os pixels em
        # desacordo com a PhotometricInterpretation declarada.
        arr = pixel_array(ds, raw=True)
        ds.PixelData = arr.astype(arr.dtype.newbyteorder("<")).tobytes()
        ds["PixelData"].VR = "OW" if int(ds.get("BitsAllocated", 8)) > 8 else "OB"
    _swap_binary_values(ds)
    ds.file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
    return ds


def read(path: str | Path) -> Dataset:
    return pydicom.dcmread(str(path), force=True)
