"""Interface em modo offscreen: janelas abrem, desenham e gravam."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

pytest.importorskip("PySide6.QtWidgets")

from PySide6.QtCore import QPoint, QPointF, Qt  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402
from PySide6.QtWidgets import QApplication, QMessageBox  # noqa: E402

from conftest import make_dataset, write  # noqa: E402
from horus.database import Database  # noqa: E402
from horus.dicom.series import SeriesStack, refs_from_files  # noqa: E402
from horus.gui.browser import BrowserWindow  # noqa: E402
from horus.gui.burner import DEST_ISO, BurnDialog  # noqa: E402
from horus.gui.imageview import ImageView  # noqa: E402
from horus.gui.viewer import SeriesEntry, ViewerWindow  # noqa: E402
from horus.platform import Platform  # noqa: E402


@pytest.fixture(scope="module")
def app():
    return QApplication.instance() or QApplication([])


@pytest.fixture(autouse=True)
def no_modal(monkeypatch):
    # Caixas modais travariam o teste; as mensagens ficam registradas.
    seen: list[str] = []
    for name in ("information", "warning", "critical"):
        monkeypatch.setattr(QMessageBox, name, staticmethod(lambda *a, **k: seen.append(a[2] if len(a) > 2 else "") or QMessageBox.StandardButton.Ok))
    monkeypatch.setattr(QMessageBox, "question", staticmethod(lambda *a, **k: QMessageBox.StandardButton.Yes))
    return seen


def _wait(runner, app, ms: int = 15000):
    runner.wait(ms)
    for _ in range(20):
        app.processEvents()


def _gradient_series(tmp_path: Path) -> list[Path]:
    from pydicom.uid import generate_uid

    study, series = generate_uid(), generate_uid()
    out = []
    for i in range(4):
        px = (np.add.outer(np.arange(128), np.arange(128)) * 8 + i * 100).astype(np.uint16)
        ds = make_dataset(study_uid=study, series_uid=series, instance_number=i + 1, pixels=px, intercept=0.0, window=(1000.0, 2000.0), spacing=(0.5, 0.5))
        out.append(write(ds, tmp_path / "g" / f"{i}.dcm"))
    return out


def test_imageview_renders_and_tools_work(app, tmp_path: Path):
    stack = SeriesStack(refs_from_files(_gradient_series(tmp_path)))
    view = ImageView()
    view.resize(400, 400)
    view.set_stack(stack)
    view.show()
    app.processEvents()
    image = view.grab().toImage()
    center = image.pixelColor(200, 200)
    assert center.lightness() > 0, "a imagem deveria ter sido desenhada"

    # Janela: arrastar para a direita aumenta a largura (como no Horos).
    wl, ww = view.wl, view.ww
    QTest.mousePress(view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(200, 200))
    QTest.mouseMove(view, QPoint(240, 200))
    QTest.mouseRelease(view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(240, 200))
    assert view.ww == pytest.approx(ww + 40 * ww / 80)
    assert view.wl == pytest.approx(wl)

    # Roda do mouse: próxima imagem.
    view.show_index(0)
    view.wheelEvent(_Wheel(-120))
    assert view.index == 1

    # Régua: 100 px de tela numa imagem de 128 px ajustada a 400 px.
    view.tool = "length"
    view.reset_view()
    QTest.mousePress(view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(100, 200))
    QTest.mouseMove(view, QPoint(300, 200))
    QTest.mouseRelease(view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(300, 200))
    (measure,) = view.measures[view.index]
    # 200 px de tela = 64 px de imagem (fator 400/128) × 0,5 mm.
    assert measure.text == "32.00 mm"

    view.tool = "roi"
    QTest.mousePress(view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(150, 150))
    QTest.mouseMove(view, QPoint(250, 250))
    QTest.mouseRelease(view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(250, 250))
    assert "Média" in view.measures[view.index][-1].text

    view.rotate(90)
    view.flip_h = True
    p = view.to_image(QPointF(200, 200))
    assert abs(p.x() - 64) < 1 and abs(p.y() - 64) < 1
    assert not view.rendered_image().isNull()


class _Wheel:
    def __init__(self, dy):
        self._dy = dy

    def angleDelta(self):
        return QPoint(0, self._dy)

    def modifiers(self):
        return Qt.KeyboardModifier.NoModifier


def test_viewer_window_switches_series(app, tmp_path: Path, mixed_folder: Path):
    entries = [
        SeriesEntry("CT", [str(p) for p in sorted((mixed_folder / "ct").iterdir())]),
        SeriesEntry("MF", [str(mixed_folder / "mf" / "multi.dcm")]),
    ]
    win = ViewerWindow(entries)
    win.show()
    app.processEvents()
    assert len(win.view.stack) == 3
    win.series_list.setCurrentRow(1)
    assert len(win.view.stack) == 3  # 3 quadros do multiquadro
    win.preset_box.setCurrentIndex(2)
    win._apply_preset(2)
    assert (win.view.wl, win.view.ww) == (40.0, 350.0)  # TC - Abdome
    win.close()


def test_browser_lists_and_makes_thumbnails(app, tmp_path: Path, mixed_folder: Path):
    db = Database(tmp_path / "base")
    db.add_files([mixed_folder])
    win = BrowserWindow(db, Platform())
    win.show()
    # CT, DX, captura RGB e multiquadro: quatro estudos.
    assert win.tree.topLevelItemCount() == 4
    win.tree.setCurrentItem(win.tree.topLevelItem(0))
    win.tree.topLevelItem(0).setSelected(True)
    _wait(win.runner, app)
    assert win.thumbs.count() >= 1
    sid = win.thumbs.item(0).data(Qt.ItemDataRole.UserRole + 1)
    assert db.thumbnail(sid) is not None
    win.search.setText("SOUZA")
    win.refresh()
    assert win.tree.topLevelItemCount() == 2
    win.close()


def test_burn_dialog_writes_iso(app, tmp_path: Path, ct_series, monkeypatch):
    monkeypatch.setenv("TMP", str(tmp_path / "tmp"))
    monkeypatch.setenv("TMPDIR", str(tmp_path / "tmp"))
    import tempfile

    monkeypatch.setattr(tempfile, "tempdir", str(tmp_path / "tmp"))
    (tmp_path / "tmp").mkdir()
    from horus.gui.tasks import TaskRunner

    runner = TaskRunner()
    dialog = BurnDialog([str(p) for p in ct_series], ["SILVA JOAO"], False, Platform(), runner)
    assert dialog.name.text() == "SILVA_JOAO"
    dialog.dest_group.button(DEST_ISO).setChecked(True)
    target = tmp_path / "saida" / "exame.iso"
    dialog.iso_path.setText(str(target))
    dialog.start()
    _wait(runner, app, 30000)
    assert target.exists() and target.stat().st_size > 0
    assert dialog.task is None
