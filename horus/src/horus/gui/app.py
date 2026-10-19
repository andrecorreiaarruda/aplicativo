"""Inicialização da interface.

Dois modos, como o par Horos / visualizador gravado no disco:

* normal — base local em `paths.default_base_dir()`, com importação,
  gravação e anonimização;
* disco (`--disc`) — o executável roda de dentro de um CD/pendrive gravado
  pelo próprio Horus; os exames são lidos pelo DICOMDIR da mídia, sem
  copiar nada para o computador. É o papel do Horos Lite / Weasis que o
  Horos gravava junto com as imagens.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from PySide6.QtCore import QLibraryInfo, QLocale, QTranslator
from PySide6.QtGui import QColor, QIcon, QPalette
from PySide6.QtWidgets import QApplication, QMessageBox

from .. import APP_NAME, __version__, paths
from ..database import Database
from ..importer import find_dicomdir
from ..platform import current

ICON = Path(__file__).with_name("horus.svg")


def _dark_palette() -> QPalette:
    p = QPalette()
    base, window, text = QColor("#1b1f24"), QColor("#24292f"), QColor("#e6e6e6")
    for role, color in (
        (QPalette.ColorRole.Window, window),
        (QPalette.ColorRole.WindowText, text),
        (QPalette.ColorRole.Base, base),
        (QPalette.ColorRole.AlternateBase, QColor("#22272e")),
        (QPalette.ColorRole.ToolTipBase, window),
        (QPalette.ColorRole.ToolTipText, text),
        (QPalette.ColorRole.Text, text),
        (QPalette.ColorRole.Button, window),
        (QPalette.ColorRole.ButtonText, text),
        (QPalette.ColorRole.Highlight, QColor("#3a7bd5")),
        (QPalette.ColorRole.HighlightedText, QColor("white")),
        (QPalette.ColorRole.PlaceholderText, QColor("#8b949e")),
    ):
        p.setColor(role, color)
    for role in (QPalette.ColorRole.Text, QPalette.ColorRole.ButtonText, QPalette.ColorRole.WindowText):
        p.setColor(QPalette.ColorGroup.Disabled, role, QColor("#6e7681"))
    return p


def disc_root(start: Path) -> Path | None:
    """Raiz da mídia: a pasta acima do executável que tem DICOMDIR."""
    for folder in (start, *start.parents):
        if find_dicomdir(folder) is not None:
            return folder
    return None


def _windows_app_id() -> None:
    # Sem um AppUserModelID explícito, o Windows agrupa a janela sob o
    # python.exe/pythonw.exe na barra de tarefas e mostra o ícone errado.
    if sys.platform == "win32":
        try:
            import ctypes

            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("Horus.DICOMViewer")
        except Exception:
            pass


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="horus", description=f"{APP_NAME} — visualizador e gravador DICOM")
    parser.add_argument("paths", nargs="*", help="arquivos, pastas ou DICOMDIR para importar")
    parser.add_argument("--disc", action="store_true", help="ler a mídia de onde o executável está rodando, sem copiar")
    parser.add_argument("--data-dir", help="pasta da base local (padrão: %(default)s)", default=None)
    parser.add_argument("--version", action="version", version=f"{APP_NAME} {__version__}")
    parser.add_argument("--self-test", metavar="RELATORIO", help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.self_test:
        from ..selftest import run

        return run(Path(args.self_test))
    _windows_app_id()
    QApplication.setApplicationName(APP_NAME)
    QApplication.setApplicationVersion(__version__)
    QApplication.setOrganizationName(APP_NAME)
    app = QApplication.instance() or QApplication(sys.argv[:1])
    app.setStyle("Fusion")
    app.setPalette(_dark_palette())
    # Textos padrão do Qt (Salvar, Cancelar, Sim, Não...) em português.
    translator = QTranslator(app)
    if translator.load(QLocale("pt_BR"), "qt", "_", QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath)):
        app.installTranslator(translator)
    if ICON.exists():
        app.setWindowIcon(QIcon(str(ICON)))

    from .browser import BrowserWindow
    from .network import NetworkService

    platform = current()
    disc_mode = args.disc
    sources = list(args.paths)
    if disc_mode:
        here = Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path.cwd()
        root = disc_root(here) or (disc_root(Path(sources[0]).resolve()) if sources else None)
        if root is None:
            QMessageBox.critical(None, APP_NAME, "Nenhum DICOMDIR encontrado na mídia.")
            return 1
        # Base descartável, só com referências aos arquivos da mídia.
        db = Database(paths.temp_dir() / f"disc-{os.getpid()}")
        sources = [str(root)]
    else:
        db = Database(Path(args.data_dir) if args.data_dir else None)

    network = None
    if not disc_mode:
        network = NetworkService(db, platform)
        network.start()
    window = BrowserWindow(db, platform, disc_mode=disc_mode, network=network)
    window.show()
    if network is not None and network.config_error:
        QMessageBox.warning(window, APP_NAME, "Configuração de rede ignorada: " + network.config_error)
    if sources:
        window.import_paths(sources, copy=not disc_mode)
    code = app.exec()
    if network is not None:
        network.stop()
    window.runner.wait(5000)
    if disc_mode:
        # A base do modo disco só tinha referências à mídia; não sobra nada.
        import shutil

        shutil.rmtree(db.base_dir, ignore_errors=True)
    return code


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
