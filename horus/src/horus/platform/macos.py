"""Implementação macOS — as mesmas ferramentas que o Horos usa.

O Horos grava pelo DiscRecording (framework Objective-C); fora de um
aplicativo Cocoa, o equivalente em linha de comando é o `drutil`, que usa
o mesmo framework. Pendrives seguem o Horos ao pé da letra:
`diskutil rename` e ejeção do volume.
"""

from __future__ import annotations

import plistlib
import re
import subprocess
from pathlib import Path

from . import BurnError, EventFn, Platform, Recorder, Volume


class MacPlatform(Platform):
    name = "macOS"
    usb_label_max = 11

    def list_recorders(self) -> list[Recorder]:
        try:
            out = subprocess.run(["drutil", "status"], capture_output=True, text=True, timeout=30).stdout
        except (OSError, subprocess.TimeoutExpired):
            return []
        if "Vendor" not in out:
            return []
        vendor = re.search(r"Vendor\s+Product\s+Rev\s*\n\s*(.+)", out)
        media_type = re.search(r"Type:\s*(.+?)\s{2,}", out)
        free = re.search(r"Space Free:\s*\S+\s+blocks:\s*(\d+)", out)
        writability = re.search(r"Writability:\s*(.+)", out)
        writable = bool(writability) and any(w in writability.group(1) for w in ("blank", "appendable"))
        return [
            Recorder(
                id="1",
                name=vendor.group(1).strip() if vendor else "Gravador",
                media_present=bool(media_type) and "No Media" not in out,
                media_writable=bool(writable),
                media_label=media_type.group(1).strip() if media_type else "",
                free_bytes=int(free.group(1)) * 2048 if free else 0,
                is_cd=bool(media_type and "CD" in media_type.group(1)),
            )
        ]

    def burn_folder(
        self,
        folder: Path,
        label: str,
        recorder: Recorder,
        iso_path: Path | None,
        on_event: EventFn,
        eject: bool = True,
    ) -> None:
        on_event("Gravando o disco", None)
        args = ["drutil", "burn", "-noverify"]
        if eject:
            args.append("-eject")
        args.append(str(folder))
        proc = subprocess.run(args, capture_output=True, text=True)
        if proc.returncode != 0:
            raise BurnError(proc.stderr.strip() or proc.stdout.strip() or "falha no drutil")
        on_event("Gravação concluída", 1.0)

    def list_removable_volumes(self) -> list[Volume]:
        volumes = []
        for path in sorted(Path("/Volumes").iterdir()) if Path("/Volumes").exists() else []:
            try:
                raw = subprocess.run(["diskutil", "info", "-plist", str(path)], capture_output=True, timeout=30).stdout
                info = plistlib.loads(raw)
            except Exception:
                continue
            # Mesmo critério do Horos: removível, gravável e desmontável.
            removable = info.get("Removable") or info.get("RemovableMedia") or info.get("Ejectable")
            if not (removable and info.get("WritableVolume") and info.get("Ejectable", True)):
                continue
            volumes.append(
                Volume(
                    str(path),
                    info.get("VolumeName", path.name),
                    info.get("FilesystemName", ""),
                    int(info.get("TotalSize", 0)),
                    int(info.get("FreeSpace", info.get("APFSContainerFree", 0)) or 0),
                )
            )
        return volumes

    def set_volume_label(self, volume: Volume, label: str) -> bool:
        proc = subprocess.run(["diskutil", "rename", volume.path, label], capture_output=True)
        if proc.returncode == 0:
            volume.path = str(Path(volume.path).parent / label)
        return proc.returncode == 0

    def eject(self, volume: Volume) -> bool:
        return subprocess.run(["diskutil", "eject", volume.path], capture_output=True).returncode == 0

    def open_folder(self, path: Path) -> None:
        subprocess.Popen(["open", str(path)])
