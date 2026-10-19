"""Testes que só fazem sentido num Windows de verdade (rodam no CI).

Exercitam o COM do IMAPI2 pelo script real e as chamadas Win32 de volume.
Em servidores de CI não há gravador, então o esperado é uma lista vazia
sem erro — o que já prova que o PowerShell, a política de execução, o
BOM do script e o protocolo JSON funcionam no sistema real.
"""

from __future__ import annotations

import sys

import pytest

pytestmark = pytest.mark.skipif(sys.platform != "win32", reason="só no Windows")


def test_imapi2_list_runs_on_real_powershell():
    from horus.platform.windows import WindowsPlatform

    platform = WindowsPlatform()
    recorders = platform.list_recorders()
    assert isinstance(recorders, list)
    # "no_recorder" não é erro; qualquer outra mensagem indicaria problema
    # no script ou no PowerShell.
    assert platform.recorder_error == "", platform.recorder_error


def test_removable_volume_listing_does_not_raise():
    from horus.platform.windows import WindowsPlatform

    volumes = WindowsPlatform().list_removable_volumes()
    assert all(len(v.path) == 2 and v.path[1] == ":" for v in volumes)


def test_not_indexed_attribute(tmp_path):
    import ctypes

    from horus import paths

    paths.mark_not_indexed(tmp_path)
    attrs = ctypes.windll.kernel32.GetFileAttributesW(str(tmp_path))
    assert attrs & 0x2000
