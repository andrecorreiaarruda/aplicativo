"""Descoberta de arquivos DICOM em pastas, discos e DICOMDIR.

O Horos decide se um arquivo é DICOM com o gdcm::Scanner
(`+[DicomFile isDICOMFile:]`), aceitando inclusive objetos sem o
preâmbulo de 128 bytes. Aqui a triagem lê só os primeiros bytes: discos
gravados com visualizador embutido trazem executáveis e bibliotecas de
dezenas de megabytes, e abrir cada um deles com o parser DICOM seria lento
e inútil.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Callable, Iterable, Iterator

MEDIA_STORAGE_DIRECTORY = "1.2.840.10008.1.3.10"

# Grupos com que um conjunto de dados sem preâmbulo costuma começar, em
# little endian: (0002) meta, (0008) identificação.
_RAW_START_GROUPS = (b"\x02\x00", b"\x08\x00")


def is_dicom_file(path: str | Path) -> bool:
    try:
        with open(path, "rb") as fh:
            head = fh.read(132)
    except OSError:
        return False
    if len(head) >= 132 and head[128:132] == b"DICM":
        return True
    # Objeto "cru" (sem preâmbulo nem meta de arquivo), comum em discos
    # antigos: o primeiro elemento é de um grupo baixo, com número < 0x100.
    if len(head) < 8 or head[:2] not in _RAW_START_GROUPS:
        return False
    return int.from_bytes(head[2:4], "little") < 0x100


def dicomdir_files(dicomdir: Path) -> list[Path]:
    """Arquivos referenciados por um DICOMDIR (DicomDirParser no Horos)."""
    import pydicom
    from pydicom.fileset import FileSet

    ds = pydicom.dcmread(str(dicomdir))
    root = dicomdir.parent
    files: list[Path] = []
    for instance in FileSet(ds):
        path = Path(instance.path)
        if not path.exists():
            # Mídias ISO 9660 nível 1 podem aparecer com ";1" ou em
            # minúsculas conforme o sistema que montou o disco.
            alt = _case_insensitive(root, path.relative_to(root))
            if alt is None:
                continue
            path = alt
        files.append(path)
    return files


def _case_insensitive(root: Path, relative: Path) -> Path | None:
    current = root
    for part in relative.parts:
        wanted = part.upper().split(";")[0]
        try:
            match = next(
                (p for p in current.iterdir() if p.name.upper().split(";")[0] == wanted),
                None,
            )
        except OSError:
            return None
        if match is None:
            return None
        current = match
    return current


def find_dicomdir(folder: Path) -> Path | None:
    for name in ("DICOMDIR", "dicomdir", "DICOMDIR.;1"):
        candidate = folder / name
        if candidate.is_file():
            return candidate
    return None


def collect_files(
    sources: Iterable[str | Path],
    cancelled: Callable[[], bool] = lambda: False,
) -> Iterator[Path]:
    """Expande arquivos e pastas em uma sequência de arquivos DICOM.

    Uma pasta com DICOMDIR na raiz é lida pelo índice; sem índice, a
    pasta é percorrida recursivamente.
    """
    for source in sources:
        path = Path(source)
        if path.is_file():
            if path.name.upper().split(";")[0] == "DICOMDIR":
                try:
                    yield from dicomdir_files(path)
                    continue
                except Exception:
                    path = path.parent
            elif is_dicom_file(path):
                yield path
                continue
            else:
                continue
        if not path.is_dir():
            continue
        dicomdir = find_dicomdir(path)
        if dicomdir is not None:
            try:
                yield from dicomdir_files(dicomdir)
                continue
            except Exception:
                # DICOMDIR corrompido: cai para a varredura da pasta.
                pass
        for root, dirs, names in os.walk(path):
            if cancelled():
                return
            dirs.sort()
            for name in sorted(names):
                if name.upper().split(";")[0] == "DICOMDIR" or name.startswith("."):
                    continue
                candidate = Path(root) / name
                if is_dicom_file(candidate):
                    yield candidate
