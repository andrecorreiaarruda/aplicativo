"""Locais de dados por sistema operacional.

O Horos guarda tudo em `~/Documents/Horos Data` (`OsirixDataDirName` em
DicomDatabase.mm) e cria a pasta de arquivos como `DATABASE.noindex`: o
sufixo `.noindex` é a convenção do macOS para o Spotlight não indexar o
conteúdo. No Windows a convenção não existe; o equivalente é o atributo
FILE_ATTRIBUTE_NOT_CONTENT_INDEXED, aplicado em `mark_not_indexed`. O nome
da pasta é mantido igual nas três plataformas para que uma base copiada de
um sistema para outro continue sendo reconhecida.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

DATA_DIR_NAME = "Horus Data"
DATABASE_DIR_NAME = "DATABASE.noindex"
INCOMING_DIR_NAME = "INCOMING.noindex"
SQL_FILE_NAME = "Database.sql"

_FILE_ATTRIBUTE_NOT_CONTENT_INDEXED = 0x2000


def default_base_dir() -> Path:
    """Pasta-base da base local; `HORUS_DATA_DIR` tem precedência."""
    override = os.environ.get("HORUS_DATA_DIR")
    if override:
        return Path(override)
    if sys.platform == "win32":
        # Documents pode estar redirecionado ao OneDrive, que sincroniza a
        # pasta inteira — com exames de imagem isso significa gigabytes de
        # dados de paciente enviados para a nuvem sem o usuário perceber.
        # LOCALAPPDATA é por máquina e fica fora do OneDrive.
        root = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        return Path(root) / "Horus" / DATA_DIR_NAME
    if sys.platform == "darwin":
        return Path.home() / "Documents" / DATA_DIR_NAME
    root = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(root) / "horus" / DATA_DIR_NAME


def temp_dir() -> Path:
    """Área de preparo do gravador.

    O Horos monta o disco em `/tmp/<nome do CD>` (folderToBurn em
    BurnerWindowController.m). `/tmp` não existe no Windows; o diretório
    temporário do usuário (`%TEMP%`) cumpre o mesmo papel.
    """
    path = Path(tempfile.gettempdir()) / "Horus"
    path.mkdir(parents=True, exist_ok=True)
    return path


def mark_not_indexed(path: Path) -> None:
    """Pede ao indexador do Windows que ignore a pasta (sem efeito fora dele)."""
    if sys.platform != "win32":
        return
    import ctypes

    kernel32 = ctypes.windll.kernel32
    attrs = kernel32.GetFileAttributesW(str(path))
    if attrs == -1 or attrs == 0xFFFFFFFF:
        return
    kernel32.SetFileAttributesW(str(path), attrs | _FILE_ATTRIBUTE_NOT_CONTENT_INDEXED)
