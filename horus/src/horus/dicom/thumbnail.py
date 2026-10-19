"""Miniaturas em PNG sem depender da interface gráfica.

Usadas na base (miniatura de cada série, como `Series.thumbnail` no
Horos) e nas páginas HTML gravadas no disco. O PNG é montado com zlib da
biblioteca padrão; não há necessidade de Pillow só para isso.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

import numpy as np

from .pixels import Frame, render_8bit
from .series import SeriesStack, refs_from_files


def downsample(img: np.ndarray, size: int) -> np.ndarray:
    """Reduz por média de blocos até caber em size×size."""
    h, w = img.shape[:2]
    step = max(1, int(np.ceil(max(h, w) / size)))
    if step == 1:
        return img
    h2, w2 = (h // step) * step, (w // step) * step
    if h2 == 0 or w2 == 0:
        return img[::step, ::step]
    trimmed = img[:h2, :w2].astype(np.float32)
    if img.ndim == 3:
        blocks = trimmed.reshape(h2 // step, step, w2 // step, step, img.shape[2]).mean(axis=(1, 3))
    else:
        blocks = trimmed.reshape(h2 // step, step, w2 // step, step).mean(axis=(1, 3))
    return np.clip(blocks + 0.5, 0, 255).astype(np.uint8)


def frame_thumbnail(frame: Frame, size: int = 128) -> np.ndarray:
    wl, ww = frame.default_window()
    return downsample(render_8bit(frame, wl, ww), size)


def encode_png(img: np.ndarray) -> bytes:
    img = np.ascontiguousarray(img, dtype=np.uint8)
    if img.ndim == 2:
        color_type = 0
    elif img.ndim == 3 and img.shape[2] == 3:
        color_type = 2
    else:
        raise ValueError("PNG: esperado cinza (HxW) ou RGB (HxWx3)")
    h, w = img.shape[:2]
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")


def series_thumbnail_png(paths: list[str | Path], size: int = 128) -> bytes:
    """Miniatura da imagem do meio da série."""
    stack = SeriesStack(refs_from_files(paths), cache_size=1)
    frame = stack.frame(len(stack) // 2)
    return encode_png(frame_thumbnail(frame, size))
