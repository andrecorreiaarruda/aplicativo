"""Predefinições de janela (nível/largura).

Valores de `WLWW3` em DefaultsOsiriX.m (getDefaults), na mesma ordem
(nível, largura). "VR - Endoscopy" ficou de fora: é usado pelo render 3D,
que não faz parte deste visualizador.
"""

from __future__ import annotations

PRESETS: dict[str, tuple[float, float]] = {
    "TC - Abdome": (40.0, 350.0),
    "TC - Cérebro": (50.0, 100.0),
    "TC - Osso": (300.0, 1500.0),
    "TC - Pulmão": (-500.0, 1400.0),
}

DEFAULT = "Padrão (cabeçalho)"
FULL = "Faixa completa"
