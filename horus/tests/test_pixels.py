from __future__ import annotations

import numpy as np
import pytest
from pydicom.dataset import Dataset
from pydicom.sequence import Sequence

from conftest import make_dataset
from horus.dicom.pixels import distance_mm, frame_from_dataset, region_stats, render_8bit
from horus.dicom.series import SeriesStack, refs_from_files


def test_rescale_to_modality_values():
    px = np.array([[0, 1024], [1064, 2048]], dtype=np.uint16)
    frame = frame_from_dataset(make_dataset(pixels=px, slope=1.0, intercept=-1024.0))
    assert frame.data.dtype == np.float32
    assert frame.data.tolist() == [[-1024.0, 0.0], [40.0, 1024.0]]


def test_zero_slope_is_treated_as_one():
    px = np.full((4, 4), 10, dtype=np.uint16)
    frame = frame_from_dataset(make_dataset(pixels=px, slope=0.0, intercept=5.0))
    assert frame.slope == 1.0
    assert float(frame.data[0, 0]) == 15.0


def test_window_from_header_and_full_range():
    px = np.array([[0, 100], [200, 300]], dtype=np.uint16)
    with_header = frame_from_dataset(make_dataset(pixels=px, intercept=0.0, window=(40.0, 400.0)))
    assert with_header.default_window() == (40.0, 400.0)
    without = frame_from_dataset(make_dataset(pixels=px, intercept=0.0, window=None))
    assert without.default_window() == (150.0, 300.0)


def test_linear_window_matches_horos_formula():
    # min = wl - ww/2 → 0; max = wl + ww/2 → 255; fora disso, saturado.
    px = np.array([[0, 50, 100, 150, 200]], dtype=np.uint16)
    frame = frame_from_dataset(make_dataset(pixels=px, intercept=0.0))
    out = render_8bit(frame, wl=100.0, ww=100.0)
    assert out.tolist() == [[0, 0, 127, 255, 255]]


def test_monochrome1_is_displayed_inverted_but_values_kept():
    px = np.array([[0, 1000]], dtype=np.uint16)
    frame = frame_from_dataset(make_dataset(pixels=px, photometric="MONOCHROME1", intercept=0.0, window=None))
    assert frame.data.tolist() == [[0.0, 1000.0]]
    out = render_8bit(frame, *frame.default_window())
    assert out[0, 0] == 255 and out[0, 1] == 0
    # O botão "inverter" desfaz a inversão.
    again = render_8bit(frame, *frame.default_window(), invert=True)
    assert again[0, 0] == 0 and again[0, 1] == 255


def test_rgb_frame():
    rgb = np.zeros((2, 2, 3), dtype=np.uint8)
    rgb[0, 0] = (255, 0, 0)
    frame = frame_from_dataset(make_dataset(pixels=rgb, photometric="RGB", window=None))
    assert frame.is_rgb
    out = render_8bit(frame, *frame.default_window())
    assert out.shape == (2, 2, 3)
    assert tuple(out[0, 0]) == (255, 0, 0)


def test_multiframe_selects_frame():
    multi = np.stack([np.full((4, 4), v, dtype=np.uint16) for v in (10, 20, 30)])
    ds = make_dataset(pixels=multi, intercept=0.0)
    assert float(frame_from_dataset(ds, 2).data[0, 0]) == 30.0
    with pytest.raises(IndexError):
        frame_from_dataset(ds, 3)


def test_enhanced_functional_groups():
    px = np.full((4, 4), 100, dtype=np.uint16)
    ds = make_dataset(pixels=px, window=None, spacing=None)
    del ds.RescaleSlope
    del ds.RescaleIntercept
    transform = Dataset()
    transform.RescaleSlope = 2
    transform.RescaleIntercept = -50
    measures = Dataset()
    measures.PixelSpacing = [0.7, 0.8]
    shared = Dataset()
    shared.PixelValueTransformationSequence = Sequence([transform])
    shared.PixelMeasuresSequence = Sequence([measures])
    ds.SharedFunctionalGroupsSequence = Sequence([shared])
    frame = frame_from_dataset(ds)
    assert float(frame.data[0, 0]) == 150.0
    assert frame.pixel_spacing == (0.7, 0.8)


def test_distance_uses_row_and_column_spacing():
    frame = frame_from_dataset(make_dataset(spacing=(2.0, 0.5)))
    # 10 colunas × 0,5 mm e 0 linhas.
    assert distance_mm(frame, (0, 0), (10, 0)) == (5.0, "mm")
    # 0 colunas e 3 linhas × 2 mm.
    assert distance_mm(frame, (0, 0), (0, 3)) == (6.0, "mm")
    uncalibrated = frame_from_dataset(make_dataset(spacing=None))
    assert distance_mm(uncalibrated, (0, 0), (3, 4)) == (5.0, "px")


def test_region_stats():
    px = np.zeros((10, 10), dtype=np.uint16)
    px[2:4, 2:4] = [[10, 20], [30, 40]]
    frame = frame_from_dataset(make_dataset(pixels=px, intercept=0.0, spacing=(0.5, 0.5)))
    stats = region_stats(frame, (2, 2), (4, 4))
    assert stats.mean == 25.0
    assert stats.minimum == 10.0 and stats.maximum == 40.0
    assert stats.count == 4
    assert stats.area == pytest.approx(1.0) and stats.area_unit == "mm²"


def test_series_sorted_by_instance_number(ct_series):
    refs = refs_from_files(ct_series)
    assert [r.instance_number for r in refs] == [1, 2, 3, 4, 5]
    stack = SeriesStack(refs, cache_size=2)
    # Pixels = 1000 + inst*10, intercept -1024.
    assert [float(stack.frame(i).data[0, 0]) for i in range(5)] == [-14.0, -4.0, 6.0, 16.0, 26.0]
    assert len(stack._cache) == 2


def test_multiframe_file_expands_in_stack(mixed_folder):
    refs = refs_from_files([mixed_folder / "mf" / "multi.dcm"])
    assert [r.frame_index for r in refs] == [0, 1, 2]


def test_palette_color_becomes_rgb():
    px = np.array([[0, 1], [2, 1]], dtype=np.uint8)
    ds = make_dataset(pixels=px, photometric="PALETTE COLOR", window=None, spacing=None)
    # Paleta de 16 bits por entrada: 0 = preto, 1 = vermelho, 2 = branco.
    red = np.array([0, 65535, 65535], dtype=np.uint16)
    green = np.array([0, 0, 65535], dtype=np.uint16)
    blue = np.array([0, 0, 65535], dtype=np.uint16)
    for color, lut in (("Red", red), ("Green", green), ("Blue", blue)):
        setattr(ds, f"{color}PaletteColorLookupTableDescriptor", [3, 0, 16])
        setattr(ds, f"{color}PaletteColorLookupTableData", lut.tobytes())
    frame = frame_from_dataset(ds)
    assert frame.is_rgb and frame.data.dtype == np.uint8
    assert tuple(frame.data[0, 1]) == (255, 0, 0)
    assert tuple(frame.data[1, 0]) == (255, 255, 255)
