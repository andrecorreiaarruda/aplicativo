"""Pilha de imagens de uma série, com ordenação e cache de quadros.

No Horos, o ViewerController recebe a lista de DicomImage da série e cria
um DCMPix por quadro (arquivos multiquadro viram várias entradas). A
pilha é ordenada por número de instância; a posição do corte desempata,
o que cobre séries cujo InstanceNumber está ausente ou repetido.
"""

from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from threading import Lock
from typing import Iterable

import pydicom

from .pixels import Frame, frame_from_dataset, header_meta, number_of_frames


@dataclass(frozen=True)
class ImageRef:
    path: Path
    frame_index: int = 0
    instance_number: int | None = None
    slice_position: float | None = None


def _slice_position(ds: pydicom.Dataset) -> float | None:
    """Projeção de ImagePositionPatient sobre a normal do plano."""
    ipp = ds.get("ImagePositionPatient")
    iop = ds.get("ImageOrientationPatient")
    if ipp is not None and iop is not None and len(ipp) == 3 and len(iop) == 6:
        r = [float(v) for v in iop[:3]]
        c = [float(v) for v in iop[3:]]
        n = (r[1] * c[2] - r[2] * c[1], r[2] * c[0] - r[0] * c[2], r[0] * c[1] - r[1] * c[0])
        return sum(float(p) * k for p, k in zip(ipp, n))
    loc = ds.get("SliceLocation")
    try:
        return float(loc) if loc not in (None, "") else None
    except (TypeError, ValueError):
        return None


def refs_from_files(paths: Iterable[str | Path]) -> list[ImageRef]:
    """Lê só os cabeçalhos e expande arquivos multiquadro."""
    refs: list[ImageRef] = []
    for path in paths:
        ds = pydicom.dcmread(str(path), stop_before_pixels=True, force=True)
        try:
            inst = int(ds.get("InstanceNumber")) if ds.get("InstanceNumber") not in (None, "") else None
        except (TypeError, ValueError):
            inst = None
        pos = _slice_position(ds)
        for i in range(number_of_frames(ds)):
            refs.append(ImageRef(Path(path), i, inst, pos))
    return sort_refs(refs)


def sort_refs(refs: list[ImageRef]) -> list[ImageRef]:
    def key(ref: ImageRef):
        return (
            ref.instance_number is None,
            ref.instance_number if ref.instance_number is not None else 0,
            ref.slice_position if ref.slice_position is not None else 0.0,
            str(ref.path),
            ref.frame_index,
        )

    return sorted(refs, key=key)


class SeriesStack:
    """Acesso aos quadros por índice, decodificando sob demanda.

    O Horos lê a série inteira em uma thread logo que o visualizador abre
    (startLoadImageThread, "Start async reading of all images", em
    ViewerController.m). Para séries grandes isso custa memória; aqui só
    os quadros vistos recentemente ficam carregados.
    """

    def __init__(self, refs: list[ImageRef], cache_size: int = 48):
        if not refs:
            raise ValueError("série sem imagens")
        self.refs = refs
        self._cache: OrderedDict[int, Frame] = OrderedDict()
        self._cache_size = cache_size
        self._lock = Lock()

    def __len__(self) -> int:
        return len(self.refs)

    def frame(self, index: int) -> Frame:
        with self._lock:
            cached = self._cache.get(index)
            if cached is not None:
                self._cache.move_to_end(index)
                return cached
        ref = self.refs[index]
        ds = pydicom.dcmread(str(ref.path), force=True)
        frame = frame_from_dataset(ds, ref.frame_index, header_meta(ds))
        frame.meta["StackIndex"] = index
        frame.meta["StackSize"] = len(self.refs)
        with self._lock:
            self._cache[index] = frame
            while len(self._cache) > self._cache_size:
                self._cache.popitem(last=False)
        return frame
