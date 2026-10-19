"""Equivalente ao DCMPix do Horos: um quadro em valores de modalidade.

O DCMPix lê o objeto, converte os pixels armazenados para float aplicando
RescaleSlope/RescaleIntercept (`vImageConvert_16SToF(..., offset, slope)`,
DCMPix.m) e só no momento de desenhar reduz a imagem a 8 bits com a janela
corrente (`vImageConvert_PlanarFtoPlanar8(src, dst, max, min)` com
`min = wl - ww/2` e `max = wl + ww/2`, em compute8bitRepresentation).

Aqui a mesma separação é mantida: `Frame.data` guarda os valores de
modalidade em float32 e `render_8bit` faz a redução. O que o Accelerate
(vImage/vDSP) fazia no macOS é feito pelo NumPy, que tem o mesmo
comportamento em qualquer sistema.

Uma diferença deliberada: para MONOCHROME1 o Horos multiplica todos os
valores por -1 (`vDSP_vsmul(..., &neg, ...)`) e passa a trabalhar com uma
janela negativa. Isso faz as medidas de ROI saírem com o sinal trocado.
Aqui os valores ficam intactos e a inversão é feita na saída de 8 bits.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import pydicom
from pydicom.dataset import Dataset
from pydicom.pixels import apply_color_lut, pixel_array


@dataclass
class Frame:
    """Um quadro pronto para exibição e medida."""

    data: np.ndarray
    is_rgb: bool
    monochrome1: bool = False
    slope: float = 1.0
    intercept: float = 0.0
    window_center: float | None = None
    window_width: float | None = None
    # (espaçamento entre linhas, espaçamento entre colunas) em mm, na
    # ordem do atributo PixelSpacing. O Horos chama de pixelSpacingY e
    # pixelSpacingX, respectivamente.
    pixel_spacing: tuple[float, float] | None = None
    spacing_source: str = ""
    meta: dict[str, Any] = field(default_factory=dict)
    _range: tuple[float, float] | None = field(default=None, repr=False)

    @property
    def rows(self) -> int:
        return int(self.data.shape[0])

    @property
    def columns(self) -> int:
        return int(self.data.shape[1])

    def value_range(self) -> tuple[float, float]:
        """Mínimo e máximo do quadro (computePixMinPixMax no Horos)."""
        if self._range is None:
            if self.data.size == 0:
                self._range = (0.0, 0.0)
            else:
                self._range = (float(np.min(self.data)), float(np.max(self.data)))
        return self._range

    def full_window(self) -> tuple[float, float]:
        """Janela que cobre toda a faixa de valores (fullwl/fullww)."""
        if self.is_rgb:
            return 127.0, 256.0
        lo, hi = self.value_range()
        ww = max(hi - lo, 1.0)
        return lo + ww / 2.0, ww

    def default_window(self) -> tuple[float, float]:
        """Janela do cabeçalho, ou a faixa completa quando não há."""
        if self.is_rgb:
            return 127.0, 256.0
        if self.window_width and self.window_width > 0 and self.window_center is not None:
            return self.window_center, self.window_width
        return self.full_window()

    def value_at(self, row: int, col: int) -> float | tuple[int, ...] | None:
        if not (0 <= row < self.rows and 0 <= col < self.columns):
            return None
        v = self.data[row, col]
        if self.is_rgb:
            return tuple(int(c) for c in v)
        return float(v)


def clamp_window(wl: float, ww: float, slope: float = 1.0) -> tuple[float, float]:
    """Limites aplicados pelo Horos em changeWLWW."""
    floor = 0.001 * abs(slope or 1.0)
    return wl, max(ww, floor)


def render_8bit(frame: Frame, wl: float, ww: float, invert: bool = False) -> np.ndarray:
    """Reduz o quadro a 8 bits com a janela (wl, ww).

    Usa a função linear do Horos: `min = wl - ww/2`, `max = wl + ww/2`,
    com saturação fora do intervalo. Devolve HxW (cinza) ou HxWx3 (RGB),
    sempre contíguo, para virar QImage sem cópia adicional.
    """
    wl, ww = clamp_window(wl, ww, frame.slope)
    lo = wl - ww / 2.0
    scale = 255.0 / ww
    # MONOCHROME1 é exibido invertido; o botão "inverter" inverte de novo.
    flip = invert != frame.monochrome1

    if frame.is_rgb:
        # O Horos aplica a mesma janela às três componentes com uma tabela
        # de 256 entradas (vImageTableLookUp_ARGB8888).
        lut = np.clip((np.arange(256, dtype=np.float32) - lo) * scale, 0, 255).astype(np.uint8)
        if flip:
            lut = 255 - lut
        return np.ascontiguousarray(lut[frame.data])

    out = np.subtract(frame.data, lo, dtype=np.float32)
    out *= scale
    np.clip(out, 0.0, 255.0, out=out)
    img = out.astype(np.uint8)
    if flip:
        np.subtract(255, img, out=img)
    return np.ascontiguousarray(img)


# ---------------------------------------------------------------- leitura


def _first_float(value: Any) -> float | None:
    values = _floats(value)
    return values[0] if values else None


def _floats(value: Any) -> list[float]:
    if value is None or value == "":
        return []
    try:
        if isinstance(value, (str, bytes)) or not hasattr(value, "__iter__"):
            return [float(value)]
        return [float(v) for v in value]
    except (TypeError, ValueError):
        return []


def _functional_item(ds: Dataset, frame_index: int, sequence: str) -> Dataset | None:
    """Item de uma macro funcional, por quadro ou compartilhado.

    Objetos "enhanced" (CT/MR multiquadro) não trazem RescaleSlope,
    PixelSpacing etc. no nível raiz, e sim dentro de
    Per-frame/Shared Functional Groups. O DCMPix procura nos dois lugares
    (PixelMeasuresSequence e PixelValueTransformationSequence).
    """
    for groups_kw, index in (
        ("PerFrameFunctionalGroupsSequence", frame_index),
        ("SharedFunctionalGroupsSequence", 0),
    ):
        groups = ds.get(groups_kw)
        if not groups or index >= len(groups):
            continue
        inner = groups[index].get(sequence)
        if inner:
            return inner[0]
    return None


def _lookup(ds: Dataset, frame_index: int, keyword: str, sequence: str) -> Any:
    if keyword in ds:
        return ds.get(keyword)
    item = _functional_item(ds, frame_index, sequence)
    if item is not None and keyword in item:
        return item.get(keyword)
    return None


def number_of_frames(ds: Dataset) -> int:
    try:
        return max(int(ds.get("NumberOfFrames", 1) or 1), 1)
    except (TypeError, ValueError):
        return 1


def header_meta(ds: Dataset) -> dict[str, Any]:
    """Campos usados nas anotações do visualizador."""

    def text(kw: str) -> str:
        v = ds.get(kw)
        return "" if v is None else str(v)

    return {
        "PatientName": text("PatientName").replace("^", " ").strip(),
        "PatientID": text("PatientID"),
        "PatientBirthDate": text("PatientBirthDate"),
        "PatientSex": text("PatientSex"),
        "StudyDate": text("StudyDate"),
        "StudyTime": text("StudyTime"),
        "StudyDescription": text("StudyDescription"),
        "SeriesDescription": text("SeriesDescription"),
        "SeriesNumber": text("SeriesNumber"),
        "InstanceNumber": text("InstanceNumber"),
        "InstitutionName": text("InstitutionName"),
        "Modality": text("Modality"),
        "SliceThickness": text("SliceThickness"),
        "SliceLocation": text("SliceLocation"),
        "Manufacturer": text("Manufacturer"),
    }


def frame_from_dataset(ds: Dataset, frame_index: int = 0, meta: dict[str, Any] | None = None) -> Frame:
    """Decodifica um quadro de um Dataset já lido (com pixels)."""
    frames = number_of_frames(ds)
    if not 0 <= frame_index < frames:
        raise IndexError(f"quadro {frame_index} fora do intervalo (0..{frames - 1})")

    photometric = str(ds.get("PhotometricInterpretation", "MONOCHROME2")).upper()
    arr = pixel_array(ds, index=frame_index if frames > 1 else None)
    if frames > 1 and arr.ndim >= 3 and arr.shape[0] == 1 and ds.get("SamplesPerPixel", 1) == 1:
        arr = arr[0]

    if photometric == "PALETTE COLOR":
        arr = apply_color_lut(arr, ds)
        # Entradas de paleta com 16 bits ocupam a faixa 0..65535.
        if arr.dtype != np.uint8:
            arr = (arr.astype(np.uint32) >> 8).astype(np.uint8)
        is_rgb = True
    else:
        is_rgb = arr.ndim == 3 and arr.shape[-1] in (3, 4)

    if is_rgb:
        if arr.shape[-1] == 4:
            arr = arr[..., :3]
        if arr.dtype != np.uint8:
            # RGB com 16 bits alocados e 8 armazenados — o DCMPix trata o
            # mesmo caso (`bitsStored == 8 && bitsAllocated == 16`).
            bits = int(ds.get("BitsStored", 8) or 8)
            arr = np.clip(arr.astype(np.float32) * (255.0 / ((1 << bits) - 1)), 0, 255).astype(np.uint8)
        data = np.ascontiguousarray(arr)
        slope, intercept = 1.0, 0.0
    else:
        slope = _first_float(_lookup(ds, frame_index, "RescaleSlope", "PixelValueTransformationSequence"))
        intercept = _first_float(_lookup(ds, frame_index, "RescaleIntercept", "PixelValueTransformationSequence"))
        # O Horos troca slope 0 por 1 ("if( slope == 0) slope = 1.0").
        slope = 1.0 if not slope else slope
        intercept = intercept or 0.0
        data = arr.astype(np.float32, copy=True)
        if slope != 1.0:
            data *= np.float32(slope)
        if intercept != 0.0:
            data += np.float32(intercept)

    wc = _first_float(_lookup(ds, frame_index, "WindowCenter", "FrameVOILUTSequence"))
    ww = _first_float(_lookup(ds, frame_index, "WindowWidth", "FrameVOILUTSequence"))

    spacing: tuple[float, float] | None = None
    source = ""
    for kw, seq in (("PixelSpacing", "PixelMeasuresSequence"), ("ImagerPixelSpacing", "")):
        values = _floats(_lookup(ds, frame_index, kw, seq) if seq else ds.get(kw))
        if values and all(v > 0 for v in values):
            spacing = (values[0], values[1] if len(values) > 1 else values[0])
            source = kw
            break

    info = dict(meta) if meta else header_meta(ds)
    info["FrameIndex"] = frame_index
    info["NumberOfFrames"] = frames
    return Frame(
        data=data,
        is_rgb=is_rgb,
        monochrome1=photometric == "MONOCHROME1",
        slope=slope,
        intercept=intercept,
        window_center=wc,
        window_width=ww,
        pixel_spacing=spacing,
        spacing_source=source,
        meta=info,
    )


def load_frame(path: str | Path, frame_index: int = 0) -> Frame:
    ds = pydicom.dcmread(str(path), force=True)
    return frame_from_dataset(ds, frame_index)


# ------------------------------------------------------------------ medidas


def distance_mm(frame: Frame, p0: tuple[float, float], p1: tuple[float, float]) -> tuple[float, str]:
    """Distância entre dois pontos (x=coluna, y=linha).

    Sem PixelSpacing devolve a distância em pixels — o mesmo que o Horos
    mostra quando o objeto não traz calibração.
    """
    dx = p1[0] - p0[0]
    dy = p1[1] - p0[1]
    if frame.pixel_spacing:
        row_mm, col_mm = frame.pixel_spacing
        return float(np.hypot(dx * col_mm, dy * row_mm)), "mm"
    return float(np.hypot(dx, dy)), "px"


@dataclass
class RegionStats:
    mean: float
    sd: float
    minimum: float
    maximum: float
    count: int
    area: float
    area_unit: str


def region_stats(frame: Frame, p0: tuple[float, float], p1: tuple[float, float]) -> RegionStats | None:
    """Estatística de uma ROI retangular, nos valores de modalidade."""
    c0, c1 = sorted((int(round(p0[0])), int(round(p1[0]))))
    r0, r1 = sorted((int(round(p0[1])), int(round(p1[1]))))
    c0, r0 = max(c0, 0), max(r0, 0)
    c1, r1 = min(c1, frame.columns), min(r1, frame.rows)
    if c1 <= c0 or r1 <= r0:
        return None
    region = frame.data[r0:r1, c0:c1]
    if frame.is_rgb:
        region = region.astype(np.float32).mean(axis=-1)
    count = int(region.size)
    if frame.pixel_spacing:
        area = count * frame.pixel_spacing[0] * frame.pixel_spacing[1]
        unit = "mm²"
    else:
        area, unit = float(count), "px²"
    return RegionStats(
        mean=float(region.mean()),
        sd=float(region.std()),
        minimum=float(region.min()),
        maximum=float(region.max()),
        count=count,
        area=float(area),
        area_unit=unit,
    )
