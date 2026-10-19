"""Implementação Linux (suporte básico, para desenvolvimento e testes).

Gravação de disco por `xorriso` sobre a ISO gerada pelo Horus; pendrives
pelo `lsblk`. Renomear o volume exige desmontá-lo e privilégios, então o
rótulo fica como está.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

from . import BurnError, BurnToolUnavailable, EventFn, Platform, Recorder, Volume


class LinuxPlatform(Platform):
    name = "Linux"
    needs_iso_for_burn = True

    def list_recorders(self) -> list[Recorder]:
        devices = sorted(Path("/dev").glob("sr[0-9]*"))
        if not devices:
            self.recorder_error = "nenhuma unidade óptica (/dev/sr*) encontrada"
        # Sem consultar a mídia (exigiria abrir o dispositivo com
        # privilégio); a checagem de capacidade fica com o xorriso.
        return [
            Recorder(id=str(dev), name=dev.name, drive=str(dev), media_present=True, media_writable=True)
            for dev in devices
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
        xorriso = shutil.which("xorriso")
        if not xorriso or iso_path is None:
            raise BurnToolUnavailable("instale o xorriso para gravar discos")
        on_event("Gravando o disco", None)
        args = [xorriso, "-as", "cdrecord", "-v", f"dev={recorder.drive}"]
        if eject:
            args.append("-eject")
        args.append(str(iso_path))
        proc = subprocess.run(args, capture_output=True, text=True)
        if proc.returncode != 0:
            raise BurnError(proc.stderr.strip()[-500:] or "falha no xorriso")
        on_event("Gravação concluída", 1.0)

    def list_removable_volumes(self) -> list[Volume]:
        try:
            raw = subprocess.run(
                ["lsblk", "-J", "-b", "-o", "NAME,RM,RO,MOUNTPOINT,LABEL,FSTYPE,SIZE"],
                capture_output=True,
                text=True,
                timeout=30,
            ).stdout
            tree = json.loads(raw)
        except Exception:
            return []
        volumes: list[Volume] = []

        def walk(nodes: list[dict], removable: bool) -> None:
            for node in nodes:
                rm = removable or node.get("rm") in (True, "1", 1)
                mount = node.get("mountpoint")
                if rm and mount and node.get("ro") in (False, "0", 0):
                    usage = shutil.disk_usage(mount)
                    volumes.append(Volume(mount, node.get("label") or "", node.get("fstype") or "", usage.total, usage.free))
                walk(node.get("children", []), rm)

        walk(tree.get("blockdevices", []), False)
        return volumes

    def eject(self, volume: Volume) -> bool:
        tool = shutil.which("udisksctl")
        if not tool:
            return False
        proc = subprocess.run([tool, "unmount", "--no-user-interaction", "-p", volume.path], capture_output=True)
        return proc.returncode == 0

    def open_folder(self, path: Path) -> None:
        if shutil.which("xdg-open"):
            subprocess.Popen(["xdg-open", str(path)])
