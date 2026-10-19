"""Implementação Windows.

| Horos (macOS)                                   | Horus (Windows)                          |
|-------------------------------------------------|------------------------------------------|
| DiscRecording: DRTrack + DRBurn                  | IMAPI2: MsftDiscFormat2Data + IMAPI2FS   |
| DRBurnSetupPanel (escolha de gravador/mídia)     | lista de gravadores no diálogo do Horus  |
| `deviceContainsSuitableMedia:` (espaço livre)    | FreeSectorsOnMedia × TotalBlocks         |
| NSWorkspace `mountedRemovableMedia`              | GetLogicalDrives + GetDriveTypeW         |
| `diskutil rename`                                | SetVolumeLabelW                          |
| `unmountAndEjectDeviceAtPath:`                   | FSCTL_LOCK/DISMOUNT + IOCTL_STORAGE_EJECT|
| `hdiutil create` (DMG)                           | ISO (pycdlib) + isoburn.exe              |

O IMAPI2 é COM. Ele é acionado por um script PowerShell (imapi2.ps1)
executado como processo filho: o PowerShell 5.1 vem em todo Windows 10/11
e fala COM sem nenhuma dependência adicional no executável do Horus.
Quando a política da máquina bloqueia scripts, a gravação cai para o
Gravador de Imagem de Disco do próprio Windows, com a ISO gerada aqui.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from importlib import resources
from pathlib import Path
from typing import Callable

from . import BurnError, BurnToolUnavailable, EventFn, Platform, Recorder, Volume

DRIVE_REMOVABLE = 2
FILE_READ_ONLY_VOLUME = 0x00080000
SEM_FAILCRITICALERRORS = 0x0001
SEM_NOOPENFILEERRORBOX = 0x8000
CREATE_NO_WINDOW = 0x08000000

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
FILE_SHARE_READ = 0x1
FILE_SHARE_WRITE = 0x2
OPEN_EXISTING = 3
FSCTL_LOCK_VOLUME = 0x00090018
FSCTL_DISMOUNT_VOLUME = 0x00090020
IOCTL_STORAGE_MEDIA_REMOVAL = 0x002D4804
IOCTL_STORAGE_EJECT_MEDIA = 0x002D4808

PROGRESS_MESSAGES = {
    "building": "Montando o sistema de arquivos do disco",
    "writing": "Gravando o disco",
    "written": "Gravação concluída",
}

ERROR_MESSAGES = {
    "no_recorder": "Nenhum gravador de CD/DVD compatível foi encontrado neste computador.",
    "recorder_unsupported": "O gravador selecionado não grava discos de dados.",
    "media_unsupported": "A unidade está sem mídia ou a mídia não é gravável. Insira um CD-R/DVD-R vazio.",
    "folder_missing": "A pasta preparada para gravação não foi encontrada.",
    "unknown_action": "Chamada inválida ao script de gravação.",
}

# Mensagens que o PowerShell escreve quando a política de execução impede
# o script (inglês e português).
_POLICY_MARKERS = ("execution polic", "running scripts is disabled", "execução de scripts", "politica de execu", "política de execu")


def _script_path() -> Path:
    if getattr(sys, "frozen", False):
        # PyInstaller copia os dados do pacote para dentro do bundle.
        base = Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent))
        return base / "horus" / "platform" / "imapi2.ps1"
    return Path(str(resources.files("horus.platform") / "imapi2.ps1"))


def describe_error(event: dict) -> str:
    code = event.get("code", "")
    if code == "capacity":
        needed = int(event.get("needed_bytes", 0)) / 1e6
        free = int(event.get("free_bytes", 0)) / 1e6
        return (
            f"Os dados ocupam {needed:.0f} MB e a mídia tem {free:.0f} MB livres. "
            "Use um DVD (ou divida a gravação)."
        )
    if code == "exception":
        detail = event.get("detail") or "erro desconhecido"
        hresult = event.get("hresult")
        return f"{detail} ({hresult})" if hresult else detail
    return ERROR_MESSAGES.get(code, event.get("detail") or code or "falha na gravação")


class WindowsPlatform(Platform):
    name = "Windows"
    usb_label_max = 11

    def __init__(self, runner: Callable[..., subprocess.Popen] | None = None):
        # `runner` permite testar o protocolo do script fora do Windows.
        self._runner = runner or subprocess.Popen

    # ------------------------------------------------------- IMAPI2

    def _run_script(self, env: dict[str, str], on_event: Callable[[dict], None] | None = None) -> tuple[int, list[dict], str]:
        command = [
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-STA",  # COM do IMAPI2 exige apartamento single-threaded
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(_script_path()),
        ]
        environment = dict(os.environ)
        environment.update(env)
        try:
            # stderr junto com stdout: com dois canais separados, um volume
            # grande de erros encheria o buffer de stderr e travaria o filho.
            proc = self._runner(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                env=environment,
                creationflags=CREATE_NO_WINDOW,
            )
        except OSError as exc:
            raise BurnToolUnavailable(f"PowerShell indisponível: {exc}") from exc

        events: list[dict] = []
        other: list[str] = []
        assert proc.stdout is not None
        for raw in proc.stdout:
            line = raw.decode("utf-8", "replace").strip().lstrip("\ufeff")
            if not line:
                continue
            try:
                event = json.loads(line) if line.startswith("{") else None
            except json.JSONDecodeError:
                event = None
            if not isinstance(event, dict):
                other.append(line)
                continue
            events.append(event)
            if on_event:
                on_event(event)
        stderr = "\n".join(other)
        code = proc.wait()
        if not events and code != 0:
            lowered = stderr.lower()
            if any(marker in lowered for marker in _POLICY_MARKERS):
                raise BurnToolUnavailable("a política de execução do PowerShell bloqueou o script de gravação")
            raise BurnToolUnavailable(stderr.strip() or f"PowerShell terminou com código {code}")
        return code, events, stderr

    def list_recorders(self) -> list[Recorder]:
        self.recorder_error = ""
        try:
            _code, events, _ = self._run_script({"HORUS_ACTION": "list"})
        except BurnToolUnavailable as exc:
            self.recorder_error = str(exc)
            return []
        for e in events:
            if e.get("event") == "error" and e.get("code") != "no_recorder":
                self.recorder_error = describe_error(e)
        recorders = []
        for e in events:
            if e.get("event") != "recorder":
                continue
            media_type = int(e.get("media_type", -1))
            name = " ".join(p for p in (e.get("vendor", ""), e.get("product", "")) if p) or "Gravador"
            recorders.append(
                Recorder(
                    id=str(e.get("index", 0)),
                    name=name,
                    drive=str(e.get("drive", "")).split(";")[0].rstrip("\\"),
                    media_present=bool(e.get("media_present")),
                    media_writable=bool(e.get("media_writable")),
                    media_label=str(e.get("media_name", "")),
                    free_bytes=int(e.get("free_bytes", 0)),
                    is_cd=media_type in (1, 2, 3),
                )
            )
        return recorders

    def burn_folder(
        self,
        folder: Path,
        label: str,
        recorder: Recorder,
        iso_path: Path | None,
        on_event: EventFn,
        eject: bool = True,
    ) -> None:
        errors: list[dict] = []

        def handle(event: dict) -> None:
            kind = event.get("event")
            if kind == "progress":
                fraction = event.get("fraction")
                on_event(PROGRESS_MESSAGES.get(event.get("code", ""), "Gravando"), None if fraction is None else float(fraction))
            elif kind == "error":
                errors.append(event)

        code, events, stderr = self._run_script(
            {
                "HORUS_ACTION": "burn",
                "HORUS_RECORDER_INDEX": recorder.id,
                "HORUS_FOLDER": str(folder),
                "HORUS_LABEL": label,
                "HORUS_EJECT": "1" if eject else "0",
            },
            handle,
        )
        if errors:
            raise BurnError(describe_error(errors[-1]))
        if code != 0 or not any(e.get("event") == "done" for e in events):
            raise BurnError(stderr.strip() or f"a gravação terminou com código {code}")

    def burn_iso_interactive(self, iso_path: Path, recorder: Recorder | None) -> bool:
        """Entrega a ISO ao Gravador de Imagem de Disco do Windows."""
        system32 = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
        tool = system32 / "isoburn.exe"
        if not tool.exists():
            return False
        args = [str(tool), "/Q"]
        if recorder and recorder.drive:
            args.append(recorder.drive.rstrip("\\"))
        args.append(str(iso_path))
        subprocess.Popen(args)
        return True

    # ------------------------------------------------------- volumes

    @staticmethod
    def _kernel32():
        import ctypes
        from ctypes import wintypes

        k = ctypes.WinDLL("kernel32", use_last_error=True)
        k.CreateFileW.restype = wintypes.HANDLE
        k.CreateFileW.argtypes = [
            wintypes.LPCWSTR,
            wintypes.DWORD,
            wintypes.DWORD,
            wintypes.LPVOID,
            wintypes.DWORD,
            wintypes.DWORD,
            wintypes.HANDLE,
        ]
        k.DeviceIoControl.argtypes = [
            wintypes.HANDLE,
            wintypes.DWORD,
            wintypes.LPVOID,
            wintypes.DWORD,
            wintypes.LPVOID,
            wintypes.DWORD,
            ctypes.POINTER(wintypes.DWORD),
            wintypes.LPVOID,
        ]
        k.CloseHandle.argtypes = [wintypes.HANDLE]
        return k

    def list_removable_volumes(self) -> list[Volume]:
        import ctypes
        from ctypes import wintypes

        k = self._kernel32()
        # Leitor de cartão vazio faria o Windows abrir a caixa "Não há
        # disco na unidade" a cada consulta; o modo de erro da thread evita.
        old_mode = wintypes.DWORD()
        k.SetThreadErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX, ctypes.byref(old_mode))
        volumes: list[Volume] = []
        try:
            mask = k.GetLogicalDrives()
            for i in range(26):
                if not mask & (1 << i):
                    continue
                root = f"{chr(ord('A') + i)}:\\"
                if k.GetDriveTypeW(root) != DRIVE_REMOVABLE:
                    continue
                label = ctypes.create_unicode_buffer(261)
                fs = ctypes.create_unicode_buffer(261)
                flags = wintypes.DWORD()
                if not k.GetVolumeInformationW(root, label, 261, None, None, ctypes.byref(flags), fs, 261):
                    continue  # sem mídia
                if flags.value & FILE_READ_ONLY_VOLUME:
                    continue
                free, total = ctypes.c_ulonglong(), ctypes.c_ulonglong()
                k.GetDiskFreeSpaceExW(root, None, ctypes.byref(total), ctypes.byref(free))
                volumes.append(Volume(root[:2], label.value, fs.value, total.value, free.value))
        finally:
            k.SetThreadErrorMode(old_mode.value, None)
        return volumes

    def set_volume_label(self, volume: Volume, label: str) -> bool:
        k = self._kernel32()
        return bool(k.SetVolumeLabelW(volume.path.rstrip("\\") + "\\", label))

    def eject(self, volume: Volume) -> bool:
        import ctypes
        from ctypes import wintypes

        k = self._kernel32()
        handle = k.CreateFileW(
            f"\\\\.\\{volume.path.rstrip(chr(92))}",
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            None,
            OPEN_EXISTING,
            0,
            None,
        )
        if handle in (None, ctypes.c_void_p(-1).value):
            return False
        returned = wintypes.DWORD()
        try:
            locked = False
            for _ in range(10):
                if k.DeviceIoControl(handle, FSCTL_LOCK_VOLUME, None, 0, None, 0, ctypes.byref(returned), None):
                    locked = True
                    break
                time.sleep(0.5)
            if not locked:
                return False
            k.DeviceIoControl(handle, FSCTL_DISMOUNT_VOLUME, None, 0, None, 0, ctypes.byref(returned), None)
            allow = ctypes.c_ubyte(0)  # PREVENT_MEDIA_REMOVAL.PreventMediaRemoval = FALSE
            k.DeviceIoControl(handle, IOCTL_STORAGE_MEDIA_REMOVAL, ctypes.byref(allow), 1, None, 0, ctypes.byref(returned), None)
            return bool(k.DeviceIoControl(handle, IOCTL_STORAGE_EJECT_MEDIA, None, 0, None, 0, ctypes.byref(returned), None))
        finally:
            k.CloseHandle(handle)

    def open_folder(self, path: Path) -> None:
        os.startfile(str(path))  # type: ignore[attr-defined]  # só existe no Windows
