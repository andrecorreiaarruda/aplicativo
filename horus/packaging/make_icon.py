"""Gera packaging/build/horus.ico a partir do SVG do aplicativo.

O ícone do .exe precisa estar em ICO; o desenho é mantido em SVG no
pacote (src/horus/gui/horus.svg) e convertido no build, com o próprio Qt.
"""

import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import Qt  # noqa: E402
from PySide6.QtGui import QGuiApplication, QImage, QPainter  # noqa: E402
from PySide6.QtSvg import QSvgRenderer  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    app = QGuiApplication(sys.argv[:1])  # noqa: F841  (o Qt exige uma instância)
    renderer = QSvgRenderer(str(ROOT / "src" / "horus" / "gui" / "horus.svg"))
    image = QImage(256, 256, QImage.Format.Format_ARGB32)
    image.fill(Qt.GlobalColor.transparent)
    painter = QPainter(image)
    renderer.render(painter)
    painter.end()
    out = ROOT / "packaging" / "build"
    out.mkdir(parents=True, exist_ok=True)
    ok = image.save(str(out / "horus.ico")) and image.save(str(out / "horus.png"))
    print(out / "horus.ico" if ok else "falha ao gerar o ícone")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
