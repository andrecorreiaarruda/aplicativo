"""Área de imagem — equivalente ao DCMView do Horos.

O DCMView desenha com OpenGL legado (NSOpenGLView, texturas
GL_TEXTURE_RECTANGLE_EXT, CGL), que só existe no macOS. Aqui a imagem de
8 bits vira um QImage e o QPainter aplica a mesma transformação (zoom,
deslocamento, rotação, espelhamento e proporção do pixel), o que funciona
em qualquer placa de vídeo — inclusive nas máquinas virtuais e áreas de
trabalho remotas comuns em clínicas, onde OpenGL costuma faltar.

Ferramentas e atalhos seguem `-[DCMView getTool:]`:

* botão esquerdo: ferramenta corrente; direito: zoom; do meio: mover;
* Ctrl (⌘ no Mac) + arrastar: mover; Alt + arrastar: janela;
  Shift + arrastar: zoom;
* roda do mouse: imagem anterior/seguinte (scrollWheel).

No arraste de janela, o Horos usa `WWAdapter = startWW / 80` como passo
por pixel (mouseDraggedWindowLevel). O eixo Y do Cocoa cresce para cima e
o do Qt para baixo; o sinal foi invertido para que arrastar para cima
continue aumentando o nível, como no original.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from PySide6.QtCore import QPointF, QRectF, QRunnable, Qt, QThreadPool, QTimer, Signal
from PySide6.QtGui import QColor, QFont, QImage, QMouseEvent, QPainter, QPen, QPolygonF, QTransform, QWheelEvent
from PySide6.QtWidgets import QWidget

from ..dicom.pixels import Frame, distance_mm, region_stats, render_8bit
from ..dicom.series import SeriesStack

TOOLS = {
    "wl": "Janela",
    "pan": "Mover",
    "zoom": "Zoom",
    "browse": "Navegar",
    "length": "Régua",
    "roi": "ROI",
}


@dataclass
class Measure:
    kind: str  # "length" | "roi"
    p0: QPointF
    p1: QPointF
    text: str = ""


def _fmt_date(value: str) -> str:
    return f"{value[6:8]}/{value[4:6]}/{value[:4]}" if len(value) == 8 and value.isdigit() else value


def _fmt_time(value: str) -> str:
    return f"{value[:2]}:{value[2:4]}" if len(value) >= 4 and value[:4].isdigit() else value


def _mm(value: str, label: str) -> str:
    try:
        return f"{label} {float(value):.2f} mm" if value else ""
    except ValueError:
        return ""


class _Prefetch(QRunnable):
    def __init__(self, stack: SeriesStack, indices: list[int]):
        super().__init__()
        self.stack = stack
        self.indices = indices

    def run(self) -> None:
        for i in self.indices:
            try:
                self.stack.frame(i)
            except Exception:
                pass


class ImageView(QWidget):
    indexChanged = Signal(int, int)
    windowChanged = Signal(float, float)
    cursorInfo = Signal(str)

    def __init__(self, parent: QWidget | None = None):
        super().__init__(parent)
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self.setMinimumSize(320, 240)
        self.setAttribute(Qt.WidgetAttribute.WA_OpaquePaintEvent)
        self.stack: SeriesStack | None = None
        self.frame: Frame | None = None
        self.index = 0
        self.wl: float | None = None
        self.ww: float | None = None
        self.invert = False
        self.scale = 1.0
        self.pan = QPointF(0.0, 0.0)
        self.rotation = 0
        self.flip_h = False
        self.flip_v = False
        self.tool = "wl"
        self.annotations = True
        self.measures: dict[int, list[Measure]] = {}
        self.error = ""
        self._image: QImage | None = None
        self._buffer: np.ndarray | None = None
        self._drag: dict | None = None
        self._cine = QTimer(self)
        self._cine.timeout.connect(lambda: self.show_index((self.index + 1) % len(self.stack) if self.stack else 0))

    # --------------------------------------------------------------- dados

    def set_stack(self, stack: SeriesStack, index: int = 0) -> None:
        self.stack = stack
        self.wl = self.ww = None
        self.measures = {}
        self.reset_view()
        self.show_index(index)

    def show_index(self, index: int) -> None:
        if not self.stack:
            return
        index = max(0, min(index, len(self.stack) - 1))
        try:
            frame = self.stack.frame(index)
            self.error = ""
        except Exception as exc:  # pixels em sintaxe sem decodificador, arquivo truncado
            frame = None
            self.error = f"Não foi possível abrir a imagem {index + 1}: {exc}"
        self.index = index
        self.frame = frame
        if frame is not None and (self.wl is None or self.ww is None):
            # A janela vale para a série toda, como no Horos (setWLWW).
            self.wl, self.ww = frame.default_window()
            self.windowChanged.emit(self.wl, self.ww)
        self._refresh_image()
        self.indexChanged.emit(index, len(self.stack))
        neighbours = [i for i in (index + 1, index - 1, index + 2) if 0 <= i < len(self.stack)]
        QThreadPool.globalInstance().start(_Prefetch(self.stack, neighbours))

    def set_window(self, wl: float, ww: float) -> None:
        self.wl, self.ww = wl, max(ww, 1e-3)
        self._refresh_image()
        self.windowChanged.emit(self.wl, self.ww)

    def default_window(self) -> None:
        if self.frame:
            self.set_window(*self.frame.default_window())

    def full_window(self) -> None:
        if self.frame:
            self.set_window(*self.frame.full_window())

    def set_invert(self, on: bool) -> None:
        self.invert = on
        self._refresh_image()

    def reset_view(self) -> None:
        self.scale = 1.0
        self.pan = QPointF(0.0, 0.0)
        self.rotation = 0
        self.flip_h = self.flip_v = False
        self.update()

    def rotate(self, degrees: int) -> None:
        self.rotation = (self.rotation + degrees) % 360
        self.update()

    def toggle_cine(self, fps: int = 10) -> bool:
        if self._cine.isActive():
            self._cine.stop()
            return False
        if self.stack and len(self.stack) > 1:
            self._cine.start(int(1000 / fps))
            return True
        return False

    def clear_measures(self) -> None:
        self.measures.pop(self.index, None)
        self.update()

    def _refresh_image(self) -> None:
        if self.frame is None or self.wl is None or self.ww is None:
            self._image = None
        else:
            buf = render_8bit(self.frame, self.wl, self.ww, self.invert)
            h, w = buf.shape[:2]
            fmt = QImage.Format.Format_RGB888 if buf.ndim == 3 else QImage.Format.Format_Grayscale8
            # O QImage aponta para o buffer do NumPy; a referência é mantida
            # em self._buffer enquanto a imagem existir.
            self._buffer = buf
            self._image = QImage(buf.data, w, h, buf.strides[0], fmt)
        self.update()

    def rendered_image(self) -> QImage:
        """A vista atual, com anotações, para exportar (PNG/JPEG)."""
        img = QImage(self.size(), QImage.Format.Format_RGB32)
        img.fill(QColor("black"))
        painter = QPainter(img)
        self._paint(painter)
        painter.end()
        return img

    # -------------------------------------------------------- geometria

    def _aspect(self) -> float:
        # Pixels não quadrados: altura relativa do pixel (pixelSpacingY/X).
        if self.frame and self.frame.pixel_spacing:
            row, col = self.frame.pixel_spacing
            if row > 0 and col > 0:
                return row / col
        return 1.0

    def _transform(self) -> QTransform:
        t = QTransform()
        if self.frame is None:
            return t
        w, h = self.frame.columns, self.frame.rows
        aspect = self._aspect()
        rotated = self.rotation in (90, 270)
        box_w, box_h = (h * aspect, w) if rotated else (w, h * aspect)
        fit = min(self.width() / box_w, self.height() / box_h) if box_w and box_h else 1.0
        s = fit * self.scale
        t.translate(self.width() / 2 + self.pan.x(), self.height() / 2 + self.pan.y())
        t.rotate(self.rotation)
        t.scale(-s if self.flip_h else s, (-s if self.flip_v else s) * aspect)
        t.translate(-w / 2, -h / 2)
        return t

    def to_image(self, pos: QPointF) -> QPointF:
        inverse, ok = self._transform().inverted()
        return inverse.map(pos) if ok else QPointF()

    # -------------------------------------------------------------- desenho

    def paintEvent(self, _event) -> None:
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor("black"))
        self._paint(painter)
        painter.end()

    def _paint(self, painter: QPainter) -> None:
        if self._image is not None and self.frame is not None:
            t = self._transform()
            painter.save()
            painter.setTransform(t)
            # Suavização só ao reduzir; ampliado, o pixel fica visível como
            # no Horos sem interpolação.
            painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, t.m11() ** 2 + t.m12() ** 2 < 1.0)
            painter.drawImage(QPointF(0, 0), self._image)
            painter.restore()
            self._paint_measures(painter, t)
        if self.error:
            painter.setPen(QColor("#ff8080"))
            painter.drawText(self.rect().adjusted(20, 20, -20, -20), Qt.AlignmentFlag.AlignCenter | Qt.TextFlag.TextWordWrap, self.error)
        if self.annotations and self.frame is not None:
            self._paint_annotations(painter)

    def _paint_measures(self, painter: QPainter, t: QTransform) -> None:
        painter.save()
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        items = list(self.measures.get(self.index, []))
        if self._drag and self._drag.get("measure") is not None:
            items.append(self._drag["measure"])
        for m in items:
            a, b = t.map(m.p0), t.map(m.p1)
            painter.setPen(QPen(QColor("#00e676"), 1.5))
            if m.kind == "length":
                painter.drawLine(a, b)
                for p in (a, b):
                    painter.drawEllipse(p, 3, 3)
            else:
                corners = [m.p0, QPointF(m.p1.x(), m.p0.y()), m.p1, QPointF(m.p0.x(), m.p1.y())]
                painter.drawPolygon(QPolygonF([t.map(c) for c in corners]))
            if m.text:
                self._text_box(painter, b + QPointF(8, 8), m.text, QColor("#00e676"))
        painter.restore()

    def _text_box(self, painter: QPainter, pos: QPointF, text: str, color: QColor) -> None:
        metrics = painter.fontMetrics()
        lines = text.split("\n")
        width = max(metrics.horizontalAdvance(line) for line in lines) + 8
        height = metrics.height() * len(lines) + 4
        box = QRectF(pos, pos + QPointF(width, height))
        painter.fillRect(box, QColor(0, 0, 0, 160))
        painter.setPen(color)
        painter.drawText(box.adjusted(4, 2, -4, -2), Qt.AlignmentFlag.AlignLeft, text)

    def _paint_annotations(self, painter: QPainter) -> None:
        meta = self.frame.meta if self.frame else {}
        painter.setPen(QColor("#e0e0e0"))
        font = QFont(painter.font())
        font.setPointSizeF(max(8.0, min(11.0, self.width() / 90)))
        painter.setFont(font)
        r = self.rect().adjusted(8, 6, -8, -6)
        sex = meta.get("PatientSex", "")
        birth = _fmt_date(meta.get("PatientBirthDate", ""))
        top_left = "\n".join(
            x for x in (meta.get("PatientName", ""), meta.get("PatientID", ""), " ".join(v for v in (birth, sex) if v)) if x
        )
        top_right = "\n".join(
            x
            for x in (
                meta.get("InstitutionName", ""),
                meta.get("StudyDescription", ""),
                " ".join(v for v in (_fmt_date(meta.get("StudyDate", "")), _fmt_time(meta.get("StudyTime", ""))) if v),
            )
            if x
        )
        n, total = self.index + 1, len(self.stack) if self.stack else 0
        frame_note = ""
        if int(meta.get("NumberOfFrames", 1)) > 1:
            frame_note = f" (quadro {int(meta.get('FrameIndex', 0)) + 1}/{meta.get('NumberOfFrames')})"
        location = meta.get("SliceLocation", "")
        thickness = meta.get("SliceThickness", "")
        bottom_left = "\n".join(
            x
            for x in (
                " ".join(v for v in (meta.get("Modality", ""), f"Série {meta.get('SeriesNumber', '')}".strip(), meta.get("SeriesDescription", "")) if v),
                f"Imagem {n}/{total}{frame_note}",
                _mm(location, "Posição"),
                _mm(thickness, "Espessura"),
            )
            if x
        )
        zoom = self._transform().m11() ** 2 + self._transform().m12() ** 2
        bottom_right = "\n".join(
            (
                f"N: {self.wl:.0f}  L: {self.ww:.0f}" if self.wl is not None and self.ww is not None else "",
                f"Zoom: {math.sqrt(zoom) * 100:.0f}%" + (f"  Rot: {self.rotation}°" if self.rotation else ""),
            )
        )
        align_l, align_r = Qt.AlignmentFlag.AlignLeft, Qt.AlignmentFlag.AlignRight
        top, bottom = Qt.AlignmentFlag.AlignTop, Qt.AlignmentFlag.AlignBottom
        painter.drawText(r, align_l | top, top_left)
        painter.drawText(r, align_r | top, top_right)
        painter.drawText(r, align_l | bottom, bottom_left)
        painter.drawText(r, align_r | bottom, bottom_right)

    # -------------------------------------------------------------- eventos

    def _tool_for(self, event: QMouseEvent) -> str:
        mods = event.modifiers()
        button = event.button()
        if button == Qt.MouseButton.RightButton:
            tool = "zoom"
        elif button == Qt.MouseButton.MiddleButton:
            tool = "pan"
        else:
            tool = self.tool
        # No Qt, ControlModifier é o ⌘ no macOS e o Ctrl no Windows — o
        # mesmo papel do NSCommandKeyMask no Horos.
        if mods & Qt.KeyboardModifier.ControlModifier:
            tool = "pan"
        if mods & Qt.KeyboardModifier.AltModifier and not mods & Qt.KeyboardModifier.ShiftModifier:
            tool = "wl"
        if mods & Qt.KeyboardModifier.ShiftModifier and tool not in ("length", "roi"):
            tool = "zoom"
        return tool

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if self.frame is None:
            return
        tool = self._tool_for(event)
        pos = event.position()
        drag = {"tool": tool, "start": pos, "wl": self.wl, "ww": self.ww, "scale": self.scale, "pan": QPointF(self.pan), "index": self.index, "measure": None}
        if tool in ("length", "roi"):
            p = self.to_image(pos)
            drag["measure"] = Measure(tool, p, QPointF(p))
        self._drag = drag

    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        pos = event.position()
        if self._drag is None:
            self._report_cursor(pos)
            return
        d = self._drag
        dx = pos.x() - d["start"].x()
        dy = pos.y() - d["start"].y()
        tool = d["tool"]
        if tool == "wl" and d["wl"] is not None:
            adapter = max(d["ww"] / 80.0, 0.001 * abs(self.frame.slope if self.frame else 1.0))
            self.set_window(d["wl"] - dy * adapter, max(d["ww"] + dx * adapter, 1e-3))
        elif tool == "pan":
            self.pan = d["pan"] + QPointF(dx, dy)
            self.update()
        elif tool == "zoom":
            self.scale = max(0.05, min(40.0, d["scale"] * math.exp(-dy / 200.0)))
            self.update()
        elif tool == "browse" and self.stack:
            self.show_index(d["index"] + int(dy / 6))
        elif tool in ("length", "roi") and d["measure"] is not None:
            d["measure"].p1 = self.to_image(pos)
            d["measure"].text = self._measure_text(d["measure"])
            self.update()

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        d, self._drag = self._drag, None
        if d and d.get("measure") is not None:
            m = d["measure"]
            if (m.p1 - m.p0).manhattanLength() >= 1.0:
                m.text = self._measure_text(m)
                self.measures.setdefault(self.index, []).append(m)
        self.update()

    def mouseDoubleClickEvent(self, event: QMouseEvent) -> None:
        self.reset_view()

    def wheelEvent(self, event: QWheelEvent) -> None:
        steps = event.angleDelta().y() / 120.0
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            self.scale = max(0.05, min(40.0, self.scale * (1.15**steps)))
            self.update()
        elif steps:
            self.show_index(self.index - (1 if steps > 0 else -1))

    def keyPressEvent(self, event) -> None:
        key = event.key()
        if key in (Qt.Key.Key_Up, Qt.Key.Key_PageUp, Qt.Key.Key_Left):
            self.show_index(self.index - (10 if key == Qt.Key.Key_PageUp else 1))
        elif key in (Qt.Key.Key_Down, Qt.Key.Key_PageDown, Qt.Key.Key_Right):
            self.show_index(self.index + (10 if key == Qt.Key.Key_PageDown else 1))
        elif key == Qt.Key.Key_Home:
            self.show_index(0)
        elif key == Qt.Key.Key_End and self.stack:
            self.show_index(len(self.stack) - 1)
        elif key in (Qt.Key.Key_Delete, Qt.Key.Key_Backspace):
            items = self.measures.get(self.index)
            if items:
                items.pop()
                self.update()
        else:
            super().keyPressEvent(event)

    def _measure_text(self, m: Measure) -> str:
        if self.frame is None:
            return ""
        p0, p1 = (m.p0.x(), m.p0.y()), (m.p1.x(), m.p1.y())
        if m.kind == "length":
            value, unit = distance_mm(self.frame, p0, p1)
            return f"{value:.2f} {unit}"
        stats = region_stats(self.frame, p0, p1)
        if stats is None:
            return ""
        unit = " UH" if self.frame.meta.get("Modality") == "CT" else ""
        return (
            f"Média: {stats.mean:.1f}{unit}  DP: {stats.sd:.1f}\n"
            f"Mín: {stats.minimum:.0f}  Máx: {stats.maximum:.0f}\n"
            f"Área: {stats.area:.1f} {stats.area_unit}"
        )

    def _report_cursor(self, pos: QPointF) -> None:
        if self.frame is None:
            return
        p = self.to_image(pos)
        col, row = int(math.floor(p.x())), int(math.floor(p.y()))
        value = self.frame.value_at(row, col)
        if value is None:
            self.cursorInfo.emit("")
            return
        if isinstance(value, tuple):
            shown = "RGB " + ",".join(str(v) for v in value)
        else:
            unit = " UH" if self.frame.meta.get("Modality") == "CT" else ""
            shown = f"{value:.1f}{unit}"
        self.cursorInfo.emit(f"x {col}  y {row}  valor {shown}")
