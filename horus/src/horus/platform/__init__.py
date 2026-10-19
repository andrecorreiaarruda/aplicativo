"""Serviços que dependem do sistema operacional.

No Horos esses serviços vêm de frameworks exclusivos do macOS:

* DiscRecording / DiscRecordingUI — gravação de CD/DVD (DRBurnSetupPanel,
  DRBurnProgressPanel, DRTrack);
* NSWorkspace + DiskArbitration — lista de volumes removíveis graváveis
  (`mountedRemovableMedia`), ejeção (`unmountAndEjectDeviceAtPath:`);
* `/usr/sbin/diskutil rename` — rótulo do pendrive;
* `hdiutil` — imagem de disco.

Cada sistema tem aqui uma implementação da mesma interface. A do Windows
usa IMAPI2 (a API de gravação do próprio Windows) e a Win32 para volumes;
as de macOS e Linux mantêm o comportamento equivalente com as ferramentas
de linha de comando de cada sistema.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


@dataclass
class Recorder:
    """Gravador de CD/DVD e a mídia que está nele."""

    id: str
    name: str
    drive: str = ""
    media_present: bool = False
    media_writable: bool = False
    media_label: str = ""
    free_bytes: int = 0
    is_cd: bool = False

    def describe(self) -> str:
        where = f" ({self.drive})" if self.drive else ""
        if not self.media_present:
            media = "sem mídia"
        elif not self.media_writable:
            media = f"mídia não gravável{f' — {self.media_label}' if self.media_label else ''}"
        else:
            media = f"{self.media_label or 'mídia gravável'}, {self.free_bytes / 1e6:.0f} MB livres"
        return f"{self.name}{where} — {media}"


@dataclass
class Volume:
    """Volume removível gravável (pendrive, cartão)."""

    path: str
    label: str
    filesystem: str = ""
    total_bytes: int = 0
    free_bytes: int = 0

    def describe(self) -> str:
        size = f"{self.total_bytes / 1e9:.1f} GB" if self.total_bytes else "?"
        return f"{self.path} {self.label or 'SEM RÓTULO'} ({self.filesystem or '?'}, {size})"


class BurnError(RuntimeError):
    pass


EventFn = Callable[[str, float | None], None]
"""Callback de progresso: (mensagem, fração 0..1 ou None se indeterminado)."""


class BurnToolUnavailable(BurnError):
    """O gravador nativo não pôde ser acionado; resta a imagem ISO."""


class Platform:
    name = "genérico"
    # Rótulo máximo de volume no sistema de arquivos dos pendrives (FAT).
    usb_label_max = 11
    # Motivo de a lista de gravadores ter vindo vazia, quando há um.
    recorder_error = ""
    # A ferramenta de gravação do sistema só aceita imagem, não pasta.
    needs_iso_for_burn = False

    def list_recorders(self) -> list[Recorder]:
        return []

    def burn_folder(
        self,
        folder: Path,
        label: str,
        recorder: Recorder,
        iso_path: Path | None,
        on_event: EventFn,
        eject: bool = True,
    ) -> None:
        raise BurnToolUnavailable("gravação de CD/DVD não suportada neste sistema")

    def burn_iso_interactive(self, iso_path: Path, recorder: Recorder | None) -> bool:
        """Abre a ferramenta de gravação de imagem do sistema, se houver."""
        return False

    def list_removable_volumes(self) -> list[Volume]:
        return []

    def set_volume_label(self, volume: Volume, label: str) -> bool:
        return False

    def eject(self, volume: Volume) -> bool:
        return False

    def open_folder(self, path: Path) -> None:
        pass

    def allow_inbound_port(self, port: int, program: str) -> bool:
        """Libera a porta do listener no firewall do sistema, se fizer sentido."""
        return False


def current() -> Platform:
    if sys.platform == "win32":
        from .windows import WindowsPlatform

        return WindowsPlatform()
    if sys.platform == "darwin":
        from .macos import MacPlatform

        return MacPlatform()
    from .linux import LinuxPlatform

    return LinuxPlatform()
