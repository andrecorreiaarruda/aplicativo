"""Envio da pasta preparada ao destino — porte de `performBurn`.

O Horos escolhe pelo `burnDestination`: CDDVD (DiscRecording), USBKey
(`saveOnVolume`) ou DMGFile (`createDMG`). Os três destinos estão aqui,
com a parte dependente de sistema delegada a `horus.platform`.
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Callable

from ..platform import BurnError, BurnToolUnavailable, EventFn, Platform, Recorder, Volume
from .iso import build_iso, disc_size, sanitize_volume_label
from .prepare import PreparedDisc

# Pastas que o próprio Windows mantém na raiz de um volume e que não
# podem (nem devem) ser apagadas ao limpar o pendrive.
SYSTEM_ENTRIES = {"system volume information", "$recycle.bin"}


def _volume_root(volume: Volume) -> Path:
    # No Windows o volume chega como "E:"; sem a barra, "E:" designa o
    # diretório corrente daquela unidade, não a raiz.
    if len(volume.path) == 2 and volume.path[1] == ":":
        return Path(volume.path + "\\")
    return Path(volume.path)


def write_iso(prepared: PreparedDisc, out_path: Path, on_event: EventFn) -> Path:
    on_event("Gerando a imagem ISO", 0.0)
    path = build_iso(
        prepared.folder,
        out_path,
        prepared.label,
        progress=lambda done, total: on_event("Gerando a imagem ISO", done / total if total else None),
    )
    on_event("Imagem ISO pronta", 1.0)
    return path


def _erase_volume(root: Path) -> list[str]:
    problems = []
    for entry in root.iterdir():
        if entry.name.lower() in SYSTEM_ENTRIES:
            continue
        try:
            if entry.is_dir() and not entry.is_symlink():
                shutil.rmtree(entry)
            else:
                entry.unlink()
        except OSError as exc:
            problems.append(f"não foi possível apagar {entry.name}: {exc.strerror or exc}")
    return problems


def _copy_tree(src: Path, dst: Path, on_event: EventFn) -> None:
    files = [Path(r) / f for r, _d, fs in os.walk(src) for f in fs]
    for i, f in enumerate(files, start=1):
        target = dst / f.relative_to(src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(f, target)
        on_event("Copiando para o pendrive", i / len(files))


def write_usb(
    prepared: PreparedDisc,
    volume: Volume,
    platform: Platform,
    on_event: EventFn,
    eject: bool = True,
) -> list[str]:
    """Apaga o volume, copia o conteúdo, renomeia e ejeta (saveOnVolume).

    A confirmação de que todo o conteúdo será apagado é da interface —
    o Horos pergunta antes ("The ENTIRE content of the selected media...").
    """
    root = _volume_root(volume)
    if not root.exists():
        raise BurnError(f"o volume {volume.path} não está mais disponível")
    warnings = _erase_volume(root)
    _copy_tree(prepared.folder, root, on_event)

    # Mesma sequência de tentativas do Horos: o nome completo, o nome
    # truncado (FAT aceita 11 caracteres) e, por fim, "DICOM".
    full = sanitize_volume_label(prepared.label, platform.usb_label_max)
    renamed = False
    for candidate in dict.fromkeys((full, full[:10], "DICOM")):
        if platform.set_volume_label(volume, candidate):
            renamed = True
            break
    if not renamed:
        warnings.append("o rótulo do pendrive não pôde ser alterado")

    if eject:
        on_event("Ejetando o pendrive", None)
        if not platform.eject(volume):
            warnings.append("o pendrive não pôde ser ejetado; use 'Remover hardware com segurança'")
    on_event("Cópia concluída", 1.0)
    return warnings


def check_capacity(prepared: PreparedDisc, recorder: Recorder) -> None:
    """Checagem prévia de espaço (deviceContainsSuitableMedia no Horos)."""
    if not recorder.media_present:
        raise BurnError("Não há mídia na unidade. Insira um CD-R ou DVD-R vazio.")
    if not recorder.media_writable:
        raise BurnError("A mídia na unidade não é gravável (já finalizada, protegida ou não suportada).")
    needed = disc_size(prepared.folder)
    if recorder.free_bytes and needed > recorder.free_bytes:
        raise BurnError(
            f"Os dados ocupam {needed / 1e6:.0f} MB e a mídia tem {recorder.free_bytes / 1e6:.0f} MB livres. "
            "Use um DVD (ou divida a gravação)."
        )


def burn_disc(
    prepared: PreparedDisc,
    recorder: Recorder,
    platform: Platform,
    on_event: EventFn,
    staging_root: Path,
    eject: bool = True,
    on_fallback: Callable[[Path], None] | None = None,
) -> None:
    """Grava em CD/DVD; sem gravador nativo, entrega uma ISO ao sistema."""
    check_capacity(prepared, recorder)
    iso_path: Path | None = None
    if platform.needs_iso_for_burn:
        iso_path = write_iso(prepared, staging_root / f"{prepared.label}.iso", on_event)
    try:
        platform.burn_folder(prepared.folder, prepared.label, recorder, iso_path, on_event, eject)
    except BurnToolUnavailable:
        iso_path = iso_path or write_iso(prepared, staging_root / f"{prepared.label}.iso", on_event)
        if platform.burn_iso_interactive(iso_path, recorder):
            if on_fallback:
                on_fallback(iso_path)
            return
        raise
