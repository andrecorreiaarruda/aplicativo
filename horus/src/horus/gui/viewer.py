"""Janela do visualizador — equivalente ao ViewerController do Horos.

À esquerda, as séries do exame (O2ViewerThumbnailsMatrix); no centro, a
imagem; na barra, as ferramentas (ToolMode de DCMView.h: tWL, tTranslate,
tZoom, tNext, tMesure, tROI), as predefinições de janela (WLWW3) e o cine.
"""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QSize, Qt
from PySide6.QtGui import QAction, QActionGroup, QIcon, QKeySequence, QPixmap
from PySide6.QtWidgets import (
    QComboBox,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QSlider,
    QToolBar,
    QVBoxLayout,
    QWidget,
)

from ..dicom import presets
from ..dicom.series import SeriesStack, refs_from_files
from .imageview import TOOLS, ImageView


class SeriesEntry:
    def __init__(self, title: str, paths: list[str], thumbnail: bytes | None = None):
        self.title = title
        self.paths = paths
        self.thumbnail = thumbnail


class ViewerWindow(QMainWindow):
    def __init__(self, series: list[SeriesEntry], start: int = 0, title: str = "", parent=None):
        super().__init__(parent)
        self.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)
        self.setWindowTitle(title or "Visualizador")
        self.resize(1200, 820)
        self.series = series
        self.view = ImageView()

        self.series_list = QListWidget()
        self.series_list.setViewMode(QListWidget.ViewMode.IconMode)
        self.series_list.setFlow(QListWidget.Flow.TopToBottom)
        self.series_list.setWrapping(False)
        self.series_list.setIconSize(QSize(96, 96))
        self.series_list.setFixedWidth(150)
        self.series_list.setMovement(QListWidget.Movement.Static)
        for entry in series:
            item = QListWidgetItem(entry.title)
            if entry.thumbnail:
                pix = QPixmap()
                pix.loadFromData(entry.thumbnail, "PNG")
                item.setIcon(QIcon(pix))
            item.setTextAlignment(Qt.AlignmentFlag.AlignHCenter)
            self.series_list.addItem(item)
        self.series_list.currentRowChanged.connect(self.open_series)

        # Barra de navegação sob a imagem, como o slider do ViewerController.
        self.slider = QSlider(Qt.Orientation.Horizontal)
        self.slider.valueChanged.connect(lambda v: v != self.view.index and self.view.show_index(v))
        image_area = QVBoxLayout()
        image_area.setContentsMargins(0, 0, 0, 0)
        image_area.setSpacing(2)
        image_area.addWidget(self.view, 1)
        image_area.addWidget(self.slider)
        central = QWidget()
        row = QHBoxLayout(central)
        row.setContentsMargins(0, 0, 0, 0)
        row.addWidget(self.series_list)
        row.addLayout(image_area, 1)
        if len(series) <= 1:
            self.series_list.hide()
        self.setCentralWidget(central)

        self._build_toolbar()
        self.position = QLabel()
        self.cursor = QLabel()
        self.statusBar().addWidget(self.position)
        self.statusBar().addPermanentWidget(self.cursor)
        self.view.indexChanged.connect(self._on_index)
        self.view.cursorInfo.connect(self.cursor.setText)

        self.series_list.setCurrentRow(max(0, min(start, len(series) - 1)))
        self.view.setFocus()

    # ----------------------------------------------------------- barra

    def _build_toolbar(self) -> None:
        bar = QToolBar("Ferramentas")
        bar.setMovable(False)
        self.addToolBar(bar)
        group = QActionGroup(self)
        shortcuts = {"wl": "W", "pan": "M", "zoom": "Z", "browse": "N", "length": "L", "roi": "O"}
        for key, label in TOOLS.items():
            act = QAction(label, self, checkable=True)
            act.setShortcut(QKeySequence(shortcuts[key]))
            act.setToolTip(f"{label} ({shortcuts[key]})")
            act.triggered.connect(lambda _=False, k=key: setattr(self.view, "tool", k))
            group.addAction(act)
            bar.addAction(act)
            if key == "wl":
                act.setChecked(True)
        bar.addSeparator()

        self.preset_box = QComboBox()
        self.preset_box.addItems([presets.DEFAULT, presets.FULL, *presets.PRESETS.keys()])
        self.preset_box.setToolTip("Predefinições de janela (nível/largura)")
        self.preset_box.activated.connect(self._apply_preset)
        bar.addWidget(self.preset_box)

        invert = QAction("Inverter", self, checkable=True)
        invert.setShortcut(QKeySequence("I"))
        invert.toggled.connect(self.view.set_invert)
        bar.addAction(invert)
        for text, deg, key in (("↺ 90°", -90, "["), ("↻ 90°", 90, "]")):
            act = QAction(text, self)
            act.setShortcut(QKeySequence(key))
            act.triggered.connect(lambda _=False, d=deg: self.view.rotate(d))
            bar.addAction(act)
        flip = QAction("Espelhar", self)
        flip.setShortcut(QKeySequence("H"))
        flip.triggered.connect(self._flip)
        bar.addAction(flip)
        reset = QAction("Restaurar", self)
        reset.setShortcut(QKeySequence("R"))
        reset.triggered.connect(self._reset)
        bar.addAction(reset)
        bar.addSeparator()

        self.cine = QAction("▶ Cine", self, checkable=True)
        self.cine.setShortcut(QKeySequence("Space"))
        self.cine.triggered.connect(lambda: self.cine.setChecked(self.view.toggle_cine()))
        bar.addAction(self.cine)
        clear = QAction("Limpar medidas", self)
        clear.triggered.connect(self.view.clear_measures)
        bar.addAction(clear)
        annotations = QAction("Anotações", self, checkable=True, checked=True)
        annotations.setShortcut(QKeySequence("A"))
        annotations.toggled.connect(lambda on: (setattr(self.view, "annotations", on), self.view.update()))
        bar.addAction(annotations)
        export = QAction("Exportar", self)
        export.setShortcut(QKeySequence.StandardKey.Save)
        export.triggered.connect(self._export)
        bar.addAction(export)


    def _apply_preset(self, row: int) -> None:
        name = self.preset_box.itemText(row)
        if name == presets.DEFAULT:
            self.view.default_window()
        elif name == presets.FULL:
            self.view.full_window()
        else:
            self.view.set_window(*presets.PRESETS[name])
        self.view.setFocus()

    def _flip(self) -> None:
        self.view.flip_h = not self.view.flip_h
        self.view.update()

    def _reset(self) -> None:
        self.view.reset_view()
        self.view.default_window()

    def _export(self) -> None:
        path, _ = QFileDialog.getSaveFileName(self, "Exportar imagem", "imagem.png", "PNG (*.png);;JPEG (*.jpg)")
        if path:
            if not self.view.rendered_image().save(path):
                QMessageBox.warning(self, "Exportar", f"Não foi possível gravar {path}.")

    # ----------------------------------------------------------- dados

    def open_series(self, row: int) -> None:
        if not 0 <= row < len(self.series):
            return
        entry = self.series[row]
        try:
            stack = SeriesStack(refs_from_files(entry.paths))
        except Exception as exc:
            QMessageBox.warning(self, "Série", f"Não foi possível abrir a série: {exc}")
            return
        if self.cine.isChecked():
            self.view.toggle_cine()
            self.cine.setChecked(False)
        self.slider.blockSignals(True)
        self.slider.setRange(0, len(stack) - 1)
        self.slider.setValue(0)
        self.slider.blockSignals(False)
        self.slider.setVisible(len(stack) > 1)
        self.view.set_stack(stack, 0)
        self.preset_box.setCurrentIndex(0)

    def _on_index(self, index: int, total: int) -> None:
        self.position.setText(f"Imagem {index + 1} de {total}")
        if self.slider.value() != index:
            self.slider.blockSignals(True)
            self.slider.setValue(index)
            self.slider.blockSignals(False)


def viewer_for_files(paths: list[str | Path], title: str = "") -> ViewerWindow:
    """Abre arquivos soltos agrupados por série (sem passar pela base)."""
    import pydicom

    groups: dict[str, list[str]] = {}
    names: dict[str, str] = {}
    for p in paths:
        ds = pydicom.dcmread(str(p), stop_before_pixels=True, force=True)
        uid = str(ds.get("SeriesInstanceUID", "")) or str(p)
        groups.setdefault(uid, []).append(str(p))
        names.setdefault(uid, f"{ds.get('Modality', '')} {ds.get('SeriesNumber', '')}\n{ds.get('SeriesDescription', '')}".strip())
    return ViewerWindow([SeriesEntry(names[k], v) for k, v in groups.items()], title=title)
