"""Negociação de sintaxe de transferência e conversão antes do envio.

O DCMTKStoreSCU do Horos propõe, para cada classe SOP, a sintaxe em que o
arquivo está e uma alternativa sem compressão, e converte o arquivo quando
o destino só aceita a alternativa. O pynetdicom converte sozinho apenas
entre sintaxes não comprimidas em little endian (implícita ↔ explícita);
compressão, descompressão e big endian ficam por conta deste módulo.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

import pydicom
from pydicom.dataset import Dataset
from pydicom.uid import (
    JPEG2000,
    UID,
    DeflatedExplicitVRLittleEndian,
    ExplicitVRBigEndian,
    ExplicitVRLittleEndian,
    ImplicitVRLittleEndian,
    JPEG2000Lossless,
    JPEGBaseline8Bit,
    JPEGExtended12Bit,
    JPEGLossless,
    JPEGLosslessSV1,
    JPEGLSLossless,
    JPEGLSNearLossless,
    RLELossless,
)
from pynetdicom.presentation import PresentationContext, build_context

from ..dicom.fileio import ensure_file_meta, to_explicit_little
from .config import SEND_EXPLICIT, SEND_IMPLICIT, SEND_J2K, SEND_KEEP, SEND_RLE

UNCOMPRESSED = [ExplicitVRLittleEndian, ImplicitVRLittleEndian]

# Sintaxes aceitas pelo listener e oferecidas no C-GET. Os arquivos são
# guardados como chegam, sem decodificar, então qualquer uma serve.
ACCEPTED_SYNTAXES = [
    ExplicitVRLittleEndian,
    ImplicitVRLittleEndian,
    DeflatedExplicitVRLittleEndian,
    ExplicitVRBigEndian,
    JPEGBaseline8Bit,
    JPEGExtended12Bit,
    JPEGLossless,
    JPEGLosslessSV1,
    JPEGLSLossless,
    JPEGLSNearLossless,
    JPEG2000Lossless,
    JPEG2000,
    RLELossless,
]

_PREFERRED = {SEND_J2K: JPEG2000Lossless, SEND_RLE: RLELossless}
MAX_CONTEXTS = 128


@dataclass(frozen=True)
class FileInfo:
    path: str
    sop_class_uid: str
    sop_instance_uid: str
    transfer_syntax_uid: str


def file_info(path: str | Path) -> FileInfo:
    ds = pydicom.dcmread(str(path), stop_before_pixels=True, force=True)
    meta = getattr(ds, "file_meta", None)
    sop_class = str(ds.get("SOPClassUID", "") or (meta.get("MediaStorageSOPClassUID", "") if meta is not None else ""))
    sop_inst = str(ds.get("SOPInstanceUID", "") or (meta.get("MediaStorageSOPInstanceUID", "") if meta is not None else ""))
    ts = str(meta.get("TransferSyntaxUID", "")) if meta is not None else ""
    if not ts:
        implicit, little = getattr(ds, "original_encoding", (True, True))
        ts = ImplicitVRLittleEndian if implicit else (ExplicitVRLittleEndian if little else ExplicitVRBigEndian)
    if not sop_class or not sop_inst:
        raise ValueError("arquivo sem SOPClassUID/SOPInstanceUID")
    return FileInfo(str(path), sop_class, sop_inst, str(ts))


def proposed_syntaxes(native: str, mode: str) -> list[list[str]]:
    """Listas de sintaxes a propor (uma por contexto) para uma classe SOP.

    Contextos separados deixam o destino aceitar a sintaxe nativa e também a
    alternativa, que serve para os arquivos que ele recusar comprimidos.
    """
    native_uid = UID(native)
    if mode == SEND_IMPLICIT:
        return [[ImplicitVRLittleEndian]]
    if mode == SEND_EXPLICIT:
        return [list(UNCOMPRESSED)]
    contexts: list[list[str]] = []
    preferred = _PREFERRED.get(mode)
    if preferred:
        contexts.append([preferred])
    if mode == SEND_KEEP and native_uid not in UNCOMPRESSED and native_uid != ExplicitVRBigEndian:
        contexts.append([native_uid])
    contexts.append(list(UNCOMPRESSED))
    return contexts


def build_contexts(infos: Iterable[FileInfo], mode: str) -> list[list[PresentationContext]]:
    """Contextos por associação, respeitando o limite de 128 do protocolo."""
    wanted: dict[str, list[list[str]]] = {}
    for info in infos:
        for syntaxes in proposed_syntaxes(info.transfer_syntax_uid, mode):
            current = wanted.setdefault(info.sop_class_uid, [])
            if syntaxes not in current:
                current.append(syntaxes)
    batches: list[list[PresentationContext]] = [[]]
    for sop_class, groups in wanted.items():
        if len(batches[-1]) + len(groups) > MAX_CONTEXTS:
            batches.append([])
        for syntaxes in groups:
            batches[-1].append(build_context(sop_class, syntaxes))
    return [b for b in batches if b]


def accepted_for(assoc, sop_class: str) -> list[UID]:
    return [UID(cx.transfer_syntax[0]) for cx in assoc.accepted_contexts if cx.abstract_syntax == sop_class]


def prepare_for(ds: Dataset, accepted: list[UID], mode: str) -> Dataset:
    """Converte o objeto para uma sintaxe aceita; ValueError se não houver.

    Ordem de preferência: a sintaxe pedida no nó (JPEG 2000/RLE), a
    sintaxe atual do arquivo e, por fim, sem compressão.
    """
    ensure_file_meta(ds)
    current = UID(ds.file_meta.TransferSyntaxUID)
    if not accepted:
        raise ValueError("o destino não aceitou esta classe SOP")
    preferred = _PREFERRED.get(mode)
    if preferred and preferred in accepted and current != preferred and "PixelData" in ds:
        if current.is_compressed:
            ds.decompress(generate_instance_uid=False)
        elif current == ExplicitVRBigEndian:
            to_explicit_little(ds)
        ds.compress(preferred, generate_instance_uid=False)
        return ds
    if current in accepted and not (mode in (SEND_EXPLICIT, SEND_IMPLICIT) and current.is_compressed):
        return ds
    uncompressed = [ts for ts in accepted if ts in UNCOMPRESSED]
    if not uncompressed:
        raise ValueError(f"o destino só aceitou {', '.join(ts.name for ts in accepted)} e a conversão não é possível")
    if current.is_compressed:
        # Sem perdas a partir do que está gravado: o pydicom decodifica e
        # grava os pixels crus, preservando o SOPInstanceUID.
        ds.decompress(generate_instance_uid=False)
    elif current == ExplicitVRBigEndian:
        to_explicit_little(ds)
    # Implícita ↔ explícita fica com o pynetdicom, na codificação.
    return ds
