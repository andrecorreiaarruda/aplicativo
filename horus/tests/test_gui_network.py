"""Interface da rede, de ponta a ponta, em modo offscreen.

Um Horus faz o papel de PACS (listener com imagens); o outro usa as
janelas de consulta, recuperação e envio contra ele.
"""

from __future__ import annotations

import time
from datetime import date
from pathlib import Path

import pytest

pytest.importorskip("PySide6.QtWidgets")

from conftest import make_dataset, write
from netutil import free_port, local, node, running_listener
from pydicom.uid import generate_uid
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication, QMessageBox

from horus.database import Database
from horus.gui.browser import BrowserWindow
from horus.gui.network import (
    ActivityDialog,
    NetworkService,
    NetworkSettingsDialog,
    QueryWindow,
    RuleDialog,
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


# Serviços e janelas criados por teste. Ficar com eles vivos até o fim do
# processo deixa threads de rede e conexões de sinal para a destruição do
# interpretador, e o Qt pode cair ao encerrar ("shared QObject was deleted
# directly", visto no CI do Linux). Cada teste desmonta tudo ao terminar.
_SERVICES: list[NetworkService] = []
_WINDOWS: list = []


@pytest.fixture(autouse=True)
def teardown_network(app):
    yield
    for service in _SERVICES:
        service.stop()
    for window in _WINDOWS:
        window.close()
        window.deleteLater()
    _SERVICES.clear()
    _WINDOWS.clear()
    for widget in QApplication.topLevelWidgets():
        widget.close()
        widget.deleteLater()
    for _ in range(5):
        app.processEvents()


def _browser(service: NetworkService) -> BrowserWindow:
    window = BrowserWindow(service.db, Platform(), network=service)
    _WINDOWS.append(window)
    return window


def _wait(cond, timeout: float = 10.0) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        QApplication.processEvents()
        if cond():
            return True
        time.sleep(0.02)
    return cond()


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
    _SERVICES.append(service)
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
            win = QueryWindow(service, _browser(service).runner, lambda: None)
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
            browser = _browser(service)
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
        dialog = SendDialog([str(f) for f in files], service, _browser(service).runner)
        dialog.start()
        _settle(dialog.runner, app)
        assert dialog.status.text().startswith("2 de 2 imagem(ns) enviada(s)")
        assert pacs.wait_idle()
        assert len(pacs.db.studies()) == 2


def test_settings_dialog_validates_and_applies(app, tmp_path):
    service = _service(tmp_path, "CLIENTE", [], enabled=False)
    dialog = NetworkSettingsDialog(service, _browser(service).runner)
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

    dup = NetworkSettingsDialog(service, _browser(service).runner)
    dup.nodes.append(node("PACS", 105))  # AE title repetido
    dup._save()
    assert not dup.result()


def test_port_conflict_is_reported(app, tmp_path):
    with running_listener(tmp_path / "pacs", ae="PACS") as pacs:
        service = _service(tmp_path, "CLIENTE", [], port=pacs.config.local.port)
        assert not service.running
        assert "porta" in service.listener_error
        assert "parado" in service.status_text()


def test_routing_rules_in_settings(app, tmp_path):
    pacs = node("PACS", 104)
    service = _service(tmp_path, "CLIENTE", [pacs], enabled=False)
    try:
        dialog = NetworkSettingsDialog(service, _browser(service).runner)
        rule_dialog = RuleDialog(dialog.nodes, parent=dialog)
        rule_dialog.name.setText("TC para o PACS")
        rule_dialog.modalities.setText("ct; mr")
        rule_dialog.calling_ae.setText("TOMO1")
        rule_dialog._accept()
        assert rule_dialog.result() and rule_dialog.result_rule.modalities == ["CT", "MR"]
        dialog.rules.append(rule_dialog.result_rule)
        dialog.routing.setChecked(True)
        dialog._fill()
        assert dialog.rules_table.item(0, 2).text() == "PACS"
        assert "CT/MR" in dialog.rules_table.item(0, 3).text()
        dialog._save()
        assert dialog.result()
        service.apply(dialog.result_config)
        back = NetworkConfig.load(service.db.base_dir)
        assert back.routing_enabled and back.rules[0].destination == back.nodes[0].id

        # Remover o nó deixa a regra órfã: salvar avisa em vez de gravar.
        orphan = NetworkSettingsDialog(service, _browser(service).runner)
        orphan.nodes.clear()
        orphan._fill()
        assert orphan.rules_table.item(0, 2).text() == "(nó removido)"
        orphan._save()
        assert not orphan.result()

        activity = ActivityDialog(service)
        assert "ligado" in activity.queue_label.text() and "0 imagem(ns) na fila" in activity.queue_label.text()
        activity.done(0)
    finally:
        service.stop()


# ------------------------------------------- achados da revisão (interface)


def test_send_dialog_escape_cancels_instead_of_hiding(app, tmp_path, monkeypatch):
    """Achado CL8/GU4: Esc escondia a janela e o envio seguia sem cancelamento."""
    from horus.net import scu as scu_mod

    started = []

    def slow_send(local_, node_, paths_, progress=None, cancelled=lambda: False, **k):
        started.append(True)
        while not cancelled():
            time.sleep(0.02)
        return scu_mod.SendResult(total=len(paths_), cancelled=True)

    monkeypatch.setattr(scu_mod, "send", slow_send)
    service = _service(tmp_path, "CLIENTE", [node("PACS", 104)], enabled=False)
    browser = _browser(service)
    dialog = SendDialog(["a.dcm"], service, browser.runner)
    dialog.show()
    dialog.start()
    assert _wait(lambda: bool(started))
    dialog.reject()  # o que Esc e o X da janela fazem
    assert dialog.task is not None and dialog.task.cancel_requested
    assert dialog.isVisible() and "Cancelando" in dialog.status.text()
    _settle(browser.runner, app)
    assert not dialog.isVisible() and "cancelado" in dialog.status.text()


def test_cget_failure_keeps_what_arrived(app, tmp_path):
    """Achado WI3/GU1: um C-GET que falhava no meio apagava o que já tinha chegado."""
    from pynetdicom import AE, evt
    from pynetdicom.sop_class import CTImageStorage, StudyRootQueryRetrieveInformationModelGet

    from horus.gui.network import _get_into_base
    from horus.net import scu as scu_mod

    study, series = generate_uid(), generate_uid()
    sources = [make_dataset(study_uid=study, series_uid=series, instance_number=i + 1) for i in range(3)]

    def serve(event):
        yield 3
        for ds in sources[:2]:
            yield 0xFF00, ds
        event.assoc.abort()  # o PACS cai antes da terceira imagem

    port = free_port()
    ae = AE(ae_title="PACS")
    ae.add_supported_context(StudyRootQueryRetrieveInformationModelGet)
    ae.add_supported_context(CTImageStorage, scu_role=True, scp_role=True)
    server = ae.start_server(("127.0.0.1", port), block=False, evt_handlers=[(evt.EVT_C_GET, serve)])
    try:
        db = Database(tmp_path / "base")
        incoming = tmp_path / "base" / "INCOMING.noindex" / "GET"
        with pytest.raises(scu_mod.NetworkError, match="2 imagem"):
            _get_into_base(db, local("CLIENTE"), node("PACS", port, retrieve=RETRIEVE_GET), "STUDY", study, "", incoming, None, lambda: False)
        assert sum(s.number_of_images for s in db.studies()) == 2
        assert not list(incoming.rglob("*.dcm"))
    finally:
        server.shutdown()


def test_expanding_twice_does_not_duplicate_series(app, tmp_path, monkeypatch):
    """Achado GU9: recolher e expandir antes da resposta duplicava as séries."""
    from horus.net import scu as scu_mod

    ctx, pacs, study = _pacs_with_study(tmp_path)
    try:
        service = _service(tmp_path, "CLIENTE", [node("PACS", pacs.config.local.port)], enabled=False)
        win = QueryWindow(service, _browser(service).runner, lambda: None)
        win.preset.setCurrentText("Qualquer data")
        win.search()
        _settle(win.runner, app)
        real_find = scu_mod.find

        def slow_find(*a, **k):
            time.sleep(0.5)
            return real_find(*a, **k)

        monkeypatch.setattr(scu_mod, "find", slow_find)
        item = win.tree.topLevelItem(0)
        item.setExpanded(True)
        item.setExpanded(False)
        item.setExpanded(True)
        _settle(win.runner, app)
        assert item.childCount() == 1
        # Uma busca nova enquanto as séries chegam não quebra o retorno.
        item2 = win.tree.topLevelItem(0)
        item2.setExpanded(False)
        item2.takeChildren()
        item2.setExpanded(True)
        win.tree.clear()
        _settle(win.runner, app)
    finally:
        ctx.__exit__(None, None, None)


def test_refresh_keeps_the_users_selection(app, tmp_path):
    """Achado GU7: cada lote recebido pela rede apagava a seleção da lista."""
    service = _service(tmp_path, "CLIENTE", [], enabled=False)
    for pid in ("A1", "B2"):
        service.db.add_files([write(make_dataset(patient_id=pid, patient_name=f"PAC^{pid}"), tmp_path / "src" / f"{pid}.dcm")])
    browser = _browser(service)
    browser.refresh()
    target = browser.tree.topLevelItem(1)
    browser.tree.setCurrentItem(target)
    wanted = target.data(0, Qt.ItemDataRole.UserRole + 1)
    browser.refresh()
    current = browser.tree.currentItem()
    assert current is not None and current.data(0, Qt.ItemDataRole.UserRole + 1) == wanted
    assert [it.data(0, Qt.ItemDataRole.UserRole + 1) for it in browser.tree.selectedItems()] == [wanted]
    assert browser.thumbs.count() == 1


def test_task_runner_cancel_all(app):
    from horus.gui.tasks import TaskRunner

    runner = TaskRunner()

    def forever(task):
        while not task.cancelled():
            time.sleep(0.02)
        return "ok"

    runner.start(forever)
    runner.start(forever)
    assert runner.busy()
    runner.cancel_all()
    assert runner.wait(5000)
    _settle(runner, app, 1000)
    assert not runner.busy()
