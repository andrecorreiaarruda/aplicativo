"""Protocolo entre o Horus e o script IMAPI2, testado fora do Windows.

O COM do IMAPI2 só existe no Windows; aqui o processo do PowerShell é
substituído por um falso que devolve as linhas que o script emitiria.
"""

from __future__ import annotations

import io
import json
from pathlib import Path

import pytest

from horus.platform import BurnError, BurnToolUnavailable, Recorder
from horus.platform.windows import WindowsPlatform, _script_path


class FakeProcess:
    def __init__(self, lines: list[str], code: int = 0):
        self.stdout = io.BytesIO("".join(line + "\n" for line in lines).encode("utf-8"))
        self.stderr = None
        self._code = code

    def wait(self):
        return self._code


class Runner:
    def __init__(self, lines: list[str], code: int = 0):
        self.lines = lines
        self.code = code
        self.calls: list[dict] = []

    def __call__(self, command, **kwargs):
        self.calls.append({"command": command, **kwargs})
        return FakeProcess(self.lines, self.code)


def ev(**data) -> str:
    return json.dumps(data)


def test_list_recorders_parses_events():
    runner = Runner(
        [
            "\ufeff" + ev(event="recorder", index=0, vendor="HL-DT-ST", product="DVDRAM GP65NB60", drive="E:\\",
                          media_present=True, media_writable=True, media_type=2, media_name="CD-R", free_bytes=736_000_000),
            ev(event="recorder", index=1, vendor="ASUS", product="SDRW", drive="F:\\", media_present=False,
               media_writable=False, media_type=-1, media_name="", free_bytes=0),
            ev(event="done"),
        ]
    )
    recs = WindowsPlatform(runner).list_recorders()
    assert [r.id for r in recs] == ["0", "1"]
    assert recs[0].name == "HL-DT-ST DVDRAM GP65NB60"
    assert recs[0].drive == "E:" and recs[0].is_cd and recs[0].free_bytes == 736_000_000
    assert not recs[1].media_present
    assert "sem mídia" in recs[1].describe()

    call = runner.calls[0]
    assert call["command"][:2] == ["powershell.exe", "-NoProfile"]
    assert "-STA" in call["command"]
    assert call["env"]["HORUS_ACTION"] == "list"


def test_burn_passes_parameters_by_environment(tmp_path: Path):
    folder = tmp_path / "pasta d'água com espaço"
    folder.mkdir()
    runner = Runner([ev(event="progress", code="building", fraction=None), ev(event="progress", code="writing", fraction=None),
                     ev(event="progress", code="written", fraction=1.0), ev(event="done")])
    seen: list[tuple] = []
    WindowsPlatform(runner).burn_folder(folder, "EXAME", Recorder("1", "R"), None, lambda m, f: seen.append((m, f)))

    call = runner.calls[0]
    # O caminho não aparece na linha de comando, só no ambiente.
    assert str(folder) not in " ".join(call["command"])
    assert call["env"]["HORUS_FOLDER"] == str(folder)
    assert call["env"]["HORUS_LABEL"] == "EXAME"
    assert call["env"]["HORUS_RECORDER_INDEX"] == "1"
    assert call["env"]["HORUS_EJECT"] == "1"
    assert seen == [("Montando o sistema de arquivos do disco", None), ("Gravando o disco", None), ("Gravação concluída", 1.0)]


def test_burn_capacity_error_message(tmp_path: Path):
    runner = Runner([ev(event="error", code="capacity", needed_bytes=900_000_000, free_bytes=700_000_000, hresult="")], code=5)
    with pytest.raises(BurnError, match="900 MB.*700 MB.*DVD"):
        WindowsPlatform(runner).burn_folder(tmp_path, "X", Recorder("0", "R"), None, lambda m, f: None)


def test_burn_system_exception_keeps_hresult(tmp_path: Path):
    runner = Runner([ev(event="error", code="exception", detail="A mídia está protegida contra gravação.", hresult="0xC0AA0206")], code=1)
    with pytest.raises(BurnError) as info:
        WindowsPlatform(runner).burn_folder(tmp_path, "X", Recorder("0", "R"), None, lambda m, f: None)
    assert "protegida" in str(info.value) and "0xC0AA0206" in str(info.value)


def test_execution_policy_block_is_tool_unavailable(tmp_path: Path):
    runner = Runner(
        ["File C:\\horus\\imapi2.ps1 cannot be loaded because running scripts is disabled on this system."],
        code=1,
    )
    with pytest.raises(BurnToolUnavailable):
        WindowsPlatform(runner).burn_folder(tmp_path, "X", Recorder("0", "R"), None, lambda m, f: None)
    platform = WindowsPlatform(runner)
    assert platform.list_recorders() == []
    assert "política" in platform.recorder_error


def test_missing_powershell_is_tool_unavailable(tmp_path: Path):
    def runner(*_a, **_k):
        raise FileNotFoundError("powershell.exe")

    with pytest.raises(BurnToolUnavailable):
        WindowsPlatform(runner).burn_folder(tmp_path, "X", Recorder("0", "R"), None, lambda m, f: None)


def test_script_is_powershell51_safe():
    raw = _script_path().read_bytes()
    # Com BOM o PowerShell 5.1 lê o arquivo como UTF-8; sem ele, ANSI.
    assert raw.startswith(b"\xef\xbb\xbf")
    for number, line in enumerate(raw.decode("utf-8-sig").splitlines(), 1):
        code = line.split("#", 1)[0]
        assert code.isascii(), f"linha {number} com caractere não ASCII fora de comentário"
