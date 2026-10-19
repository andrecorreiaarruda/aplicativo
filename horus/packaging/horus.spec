# -*- mode: python ; coding: utf-8 -*-
"""Empacotamento do Horus com PyInstaller (pasta única, sem instalador).

    pyinstaller packaging/horus.spec --noconfirm

Gera `dist/Horus/Horus.exe` no Windows. O PyInstaller não faz compilação
cruzada: o executável do Windows precisa ser gerado no Windows (ver
build_windows.ps1 e o workflow do GitHub Actions).
"""

from pathlib import Path

from PyInstaller.utils.hooks import collect_submodules, copy_metadata

ROOT = Path(SPECPATH).parent
SRC = ROOT / "src"
ICON = ROOT / "packaging" / "build" / "horus.ico"

datas = [
    (str(SRC / "horus" / "platform" / "imapi2.ps1"), "horus/platform"),
    (str(SRC / "horus" / "gui" / "horus.svg"), "horus/gui"),
]
# Os codecs do pylibjpeg são plugins descobertos por "entry points": sem os
# metadados dos pacotes o executável abre, mas não decodifica JPEG/JPEG 2000.
for dist in ("pydicom", "pylibjpeg", "pylibjpeg-libjpeg", "pylibjpeg-openjpeg"):
    datas += copy_metadata(dist)

hiddenimports = (
    collect_submodules("horus")
    + collect_submodules("pydicom.pixels")
    + collect_submodules("pylibjpeg")
    + collect_submodules("libjpeg")
    + collect_submodules("openjpeg")
)
try:
    import pyzipper  # noqa: F401  (opcional: ZIP com AES no gravador)

    hiddenimports += collect_submodules("pyzipper")
except ImportError:
    pass

a = Analysis(
    [str(ROOT / "packaging" / "entry.py")],
    pathex=[str(SRC)],
    datas=datas,
    hiddenimports=hiddenimports,
    excludes=["tkinter", "pytest", "PySide6.QtWebEngineCore", "PySide6.QtQml", "PySide6.QtQuick", "PySide6.QtPdf"],
    noarchive=False,
)

# Bibliotecas do Qt que o Horus não usa. A interface desenha com QPainter
# (sem OpenGL), então o OpenGL em software e o compilador de shaders do
# Direct3D ficam de fora — juntos passam de 20 MB, o que pesa quando o
# visualizador é gravado em CD junto com os exames.
_UNUSED = ("opengl32sw", "d3dcompiler", "qt6quick", "qt6qml", "qt6pdf", "qt6virtualkeyboard", "qt6webengine")
a.binaries = [b for b in a.binaries if not any(tag in Path(b[0]).name.lower() for tag in _UNUSED)]

pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="Horus",
    console=False,
    icon=str(ICON) if ICON.exists() else None,
)
coll = COLLECT(exe, a.binaries, a.datas, name="Horus")
