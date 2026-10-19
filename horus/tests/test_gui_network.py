"""Interface da rede, de ponta a ponta, em modo offscreen.

Um Horus faz o papel de PACS (listener com imagens); o outro usa as
janelas de consulta, recuperação e envio contra ele.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

import pytest

pytest.importorskip("PySide6.QtWidgets")

from conftest import make_dataset, write
from netutil import free_port, local, node, running_listener
from pydicom.uid import generate_uid
from PySide6.QtWidgets import QApplication, QMessageBox

from horus.database import Database
from horus.gui.browser import BrowserWindow
from horus.gui.network import (
    NetworkService,
    NetworkSettingsDialog,
    QueryWindow,
    SendDialog,
    date_range_for,
    merge_studies,
    study_query,
)
from horus.net.config import RETRIEVE_GET, NetworkConfig
from horus.platform import Platform


@pytest.fixture(scope="module")
def app():
    return QApplication.instance() or QApplication([])


@pytest.fixture(autouse=True)
def no_modal(monkeypatch):
    for name in ("information", "warning", "critical"):
        monkeypatch.setattr(QMessageBox, name, staticmethod(lambda *a, **k: QMessageBox.StandardButton.Ok))


def _settle(runner, app, ms: int = 30000) -> None:
    runner.wait(ms)
    for _ in range(30):
        app.processEvents()


def _pacs_with_study(tmp_path: Path, nodes=None):
    study, series = generate_uid(), generate_uid()
    files = [
        write(make_dataset(patient_name="LIMA^RITA", patient_id="Q1", study_uid=study, series_uid=series, instance_number=i + 1), tmp_path / "src" / f"{i}.dcm")
        for i in range(2)
    ]
    ctx = running_listener(tmp_path / "pacs", ae="PACS", nodes=nodes)
    lst = ctx.__enter__()
    lst.db.add_files(files)
    return ctx, lst, study


def _service(tmp_path: Path, ae: str, nodes, port: int | None = None, enabled: bool = True) -> NetworkService:
    db = Database(tmp_path / f"base-{ae}")
    NetworkConfig(local(ae, port=port, listener_enabled=enabled), nodes).save(db.base_dir)
    service = NetworkService(db, Platform())
    service.start()
    return service


def test_date_presets():
    today = date(2024, 3, 15)
    assert date_range_for("Hoje", today) == "20240315"
    assert date_range_for("Ontem", today) == "20240314"
    assert date_range_for("Anteontem", today) == "20240313"
    # Como no Horos: N dias para trás e faixa aberta no fim.
    assert date_range_for("Últimos 7 dias", today) == "20240308-"
    assert date_range_for("Último mês", today) == "20240213-"
    assert date_range_for("Em", today, date(2024, 1, 2)) == "20240102"
    assert date_range_for("Entre", today, date(2024, 3, 20), date(2024, 3, 1)) == "20240301-20240320"
    assert date_range_for("Qualquer data", today) == ""


def test_study_identifier_like_horos():
    q = study_query(name="silva", patient_id=" 123 ", description="TORAX", accession="A1")
    # Nome e descrição buscam pelo início; ID e acesso vão exatos.
    assert q.PatientName == "silva*" and q.StudyDescription == "TORAX*"
    assert q.PatientID == "123" and q.AccessionNumber == "A1"
    assert study_query(name="SI?VA").PatientName == "SI?VA"
    assert study_query().PatientName == ""
    assert "SpecificCharacterSet" not in q
    assert study_query(name="João").SpecificCharacterSet == "ISO_IR 192"


def test_merge_keeps_the_answer_with_more_images():
    from pydicom.dataset import Dataset

    def ds(uid, n):
        d = Dataset()
        d.StudyInstanceUID, d.NumberOfStudyRelatedInstances = uid, n
        return d

    a, b = node("A", 1), node("B", 2)
    merged = merge_studies([(a, ds("1.1", 3)), (a, ds("1.2", 5)), (b, ds("1.1", 10)), (b, ds("1.3", ""))])
    assert [(n.ae_title, str(d.StudyInstanceUID)) for n, d in merged] == [("B", "1.1"), ("A", "1.2"), ("B", "1.3")]


def test_query_and_retrieve_with_get(app, tmp_path):
    ctx, pacs, study = _pacs_with_study(tmp_path)
    try:
        service = _service(tmp_path, "CLIENTE", [node("PACS", pacs.config.local.port, retrieve=RETRIEVE_GET)])
        try:
            win = QueryWindow(service, BrowserWindow(service.db, Platform(), network=service).runner, lambda: None)
            win.preset.setCurrentText("Qualquer data")
            win.name.setText("lima")
            win.search()
            _settle(win.runner, app)
            assert win.tree.topLevelItemCount() == 1
            item = win.tree.topLevelItem(0)
            assert item.text(0) == "LIMA RITA" and item.text(6) == "2"

            item.setExpanded(True)
            _settle(win.runner, app)
            assert item.childCount() == 1  # a série, por C-FIND de série

            item.setSelected(True)
            win.retrieve()
            _settle(win.runner, app)
            assert sum(s.number_of_images for s in service.db.studies()) == 2
            assert "C-GET" in win.status.text()
        finally:
            service.stop()
    finally:
        ctx.__exit__(None, None, None)


def test_retrieve_with_move_needs_and_uses_listener(app, tmp_path):
    client_port = free_port()
    ctx, pacs, study = _pacs_with_study(tmp_path, nodes=[node("CLIENTE", client_port)])
    try:
        service = _service(tmp_path, "CLIENTE", [node("PACS", pacs.config.local.port)], port=client_port)
        try:
            assert service.running
            browser = BrowserWindow(service.db, Platform(), network=service)
            assert "Recebendo como CLIENTE" in browser.listener_label.text()
            browser.open_query()
            win = browser.query_window
            win.preset.setCurrentText("Qualquer data")
            win.search()
            _settle(win.runner, app)
            win.tree.topLevelItem(0).setSelected(True)
            win.retrieve()
            _settle(win.runner, app)
            assert service.listener.wait_idle()
            assert sum(s.number_of_images for s in service.db.studies()) == 2
            # A lista principal se atualiza com o que chegou pela rede.
            _settle(browser.runner, app, 3000)
            browser.refresh()
            assert browser.tree.topLevelItemCount() == 1
            browser.close()
        finally:
            service.stop()
    finally:
        ctx.__exit__(None, None, None)


def test_send_dialog(app, tmp_path):
    files = [write(make_dataset(instance_number=i + 1), tmp_path / "src" / f"{i}.dcm") for i in range(2)]
    with running_listener(tmp_path / "pacs", ae="PACS") as pacs:
        service = _service(tmp_path, "CLIENTE", [node("PACS", pacs.config.local.port)], enabled=False)
        dialog = SendDialog([str(f) for f in files], service, BrowserWindow(service.db, Platform(), network=service).runner)
        dialog.start()
        _settle(dialog.runner, app)
        assert dialog.status.text().startswith("2 de 2 imagem(ns) enviada(s)")
        assert pacs.wait_idle()
        assert len(pacs.db.studies()) == 2


def test_settings_dialog_validates_and_applies(app, tmp_path):
    service = _service(tmp_path, "CLIENTE", [], enabled=False)
    dialog = NetworkSettingsDialog(service, BrowserWindow(service.db, Platform(), network=service).runner)
    dialog.ae.setText("NOME MUITO LONGO DEMAIS")  # 23 caracteres: corta em 16 no campo
    assert len(dialog.ae.text()) == 16
    dialog.ae.setText("ESTACAO1")
    dialog.port.setValue(free_port())
    dialog.enabled.setChecked(True)
    dialog.nodes.append(node("PACS", 104))
    dialog._save()
    assert dialog.result()  # aceito
    service.apply(dialog.result_config)
    try:
        assert service.running
        reloaded = NetworkConfig.load(service.db.base_dir)
        assert reloaded.local.ae_title == "ESTACAO1" and [n.ae_title for n in reloaded.nodes] == ["PACS"]
    finally:
        service.stop()

    dup = NetworkSettingsDialog(service, BrowserWindow(service.db, Platform(), network=service).runner)
    dup.nodes.append(node("PACS", 105))  # AE title repetido
    dup._save()
    assert not dup.result()


def test_port_conflict_is_reported(app, tmp_path):
    with running_listener(tmp_path / "pacs", ae="PACS") as pacs:
        service = _service(tmp_path, "CLIENTE", [], port=pacs.config.local.port)
        assert not service.running
        assert "porta" in service.listener_error
        assert "parado" in service.status_text()
