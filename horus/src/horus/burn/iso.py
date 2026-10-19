"""Imagem de disco ISO 9660 + Joliet — substitui o DMG do Horos.

O Horos grava a pasta preparada como imagem com
`hdiutil create <arquivo>.dmg -srcfolder <pasta>` (createDMG em
BurnerWindowController.m). DMG é um formato do macOS: o Windows não monta
nem grava. A imagem ISO cumpre o mesmo papel e é aberta nativamente pelo
Windows (duplo clique monta a unidade; "Gravar imagem de disco" usa o
isoburn.exe do sistema).

A imagem é gerada em Python puro (pycdlib), igual em qualquer sistema:

* ISO 9660 nível 1 — nomes 8.3 em maiúsculas, o que o PS3.12 exige para
  mídias DICOM em CD. Os nomes dos objetos DICOM já nascem nesse formato
  (`DICOM/00000`); os demais (visualizador, extras) são abreviados;
* Joliet com os nomes originais, que é o que o Windows exibe.
"""

from __future__ import annotations

import os
import re
import unicodedata
from pathlib import Path
from typing import Callable

import pycdlib

_D_CHARS = re.compile(r"[^A-Z0-9_]")
JOLIET_MAX = 64
SECTOR = 2048


def _ascii_upper(text: str) -> str:
    text = unicodedata.normalize("NFKD", text)
    return "".join(c for c in text if not unicodedata.combining(c)).upper()


def sanitize_volume_label(label: str, max_len: int = 15) -> str:
    """Rótulo válido para ISO 9660/Joliet/FAT: A–Z, 0–9 e "_".

    O Horos só passa o nome para maiúsculas e remove caracteres inválidos
    em nome de arquivo (`[[title uppercaseString] filenameString]`). No
    Windows o IMAPI2 recusa rótulos com mais de 15 caracteres ou fora de
    A–Z, 0–9 e "_" em ISO 9660 (IMAPI_E_INVALID_VOLUME_NAME); o FAT dos
    pendrives aceita 11.
    """
    clean = _D_CHARS.sub("_", _ascii_upper(label.strip()))
    clean = re.sub(r"_+", "_", clean).strip("_")
    return (clean or "DICOM")[:max_len].rstrip("_") or "DICOM"


class _Namer:
    """Nomes ISO 9660 nível 1 únicos por diretório."""

    def __init__(self) -> None:
        self._used: dict[str, set[str]] = {}

    def _unique(self, parent: str, base: str, tail: str) -> str:
        used = self._used.setdefault(parent, set())
        name = base + tail
        n = 1
        while name in used:
            suffix = f"~{n}"
            name = base[: 8 - len(suffix)] + suffix + tail
            n += 1
        used.add(name)
        return name

    def directory(self, parent: str, name: str) -> str:
        base = _D_CHARS.sub("_", _ascii_upper(name))[:8] or "DIR"
        return self._unique(parent, base, "")

    def file(self, parent: str, name: str) -> str:
        """Nome de arquivo; o ponto é obrigatório mesmo sem extensão.

        O ECMA-119 exige o separador "." no identificador de arquivo, então
        o DICOMDIR fica gravado como "DICOMDIR.;1" — que é o que leitores
        de mídia DICOM procuram.
        """
        stem, dot, ext = name.rpartition(".")
        if not dot:
            stem, ext = name, ""
        base = _D_CHARS.sub("_", _ascii_upper(stem))[:8] or "FILE"
        ext = _D_CHARS.sub("_", _ascii_upper(ext))[:3]
        return self._unique(parent, base, "." + ext)


def folder_size(folder: Path) -> int:
    total = 0
    for root, _dirs, files in os.walk(folder):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def disc_size(folder: Path) -> int:
    """Tamanho ocupado em mídia: cada arquivo arredondado ao setor."""
    total = 0
    for root, dirs, files in os.walk(folder):
        total += SECTOR * (1 + len(dirs))
        for f in files:
            size = os.path.getsize(os.path.join(root, f))
            total += -(-size // SECTOR) * SECTOR
    return total


def build_iso(
    folder: Path,
    out_path: Path,
    label: str,
    progress: Callable[[int, int], None] | None = None,
) -> Path:
    folder = Path(folder)
    out_path = Path(out_path)
    vol = sanitize_volume_label(label)
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=1, joliet=3, vol_ident=vol, app_ident_str="HORUS DICOM")
    namer = _Namer()
    iso_dirs = {folder: "/"}
    joliet_dirs = {folder: "/"}
    try:
        for root, dirs, files in os.walk(folder):
            root_path = Path(root)
            dirs.sort()
            parent_iso = iso_dirs[root_path]
            parent_joliet = joliet_dirs[root_path]
            for d in dirs:
                sub = root_path / d
                iso_name = namer.directory(parent_iso, d)
                iso_path = parent_iso.rstrip("/") + "/" + iso_name
                joliet_path = parent_joliet.rstrip("/") + "/" + d[:JOLIET_MAX]
                iso.add_directory(iso_path, joliet_path=joliet_path)
                iso_dirs[sub] = iso_path
                joliet_dirs[sub] = joliet_path
            for f in sorted(files):
                iso_name = namer.file(parent_iso, f)
                iso.add_file(
                    str(root_path / f),
                    iso_path=parent_iso.rstrip("/") + "/" + iso_name + ";1",
                    joliet_path=parent_joliet.rstrip("/") + "/" + f[:JOLIET_MAX],
                )
        out_path.parent.mkdir(parents=True, exist_ok=True)
        if progress:
            iso.write(str(out_path), progress_cb=lambda done, total, _opaque=None: progress(done, total))
        else:
            iso.write(str(out_path))
    finally:
        iso.close()
    return out_path
