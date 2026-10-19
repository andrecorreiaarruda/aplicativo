"""Interface da rede DICOM.

Corresponde, no Horos, aos painéis de preferências "Listener" e
"Locations", à janela Query/Retrieve (QueryController) e ao envio
(SendController).
"""

from __future__ import annotations

import shutil
import socket
import sys
import time
import uuid
from collections.abc import Callable
from datetime import date, timedelta

from pydicom.dataset import Dataset
import shiboken6
from PySide6.QtCore import QDate, QObject, Qt, Signal
from PySide6.QtGui import QAction, QColor, QKeySequence
from PySide6.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QComboBox,
    QDateEdit,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QTabWidget,
    QToolBar,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .. import paths
from ..database import ORIGIN_RECEIVED, Database
from ..net import scu
from ..net.config import (
    RETRIEVE_GET,
    RETRIEVE_MOVE,
    SEND_EXPLICIT,
    SEND_IMPLICIT,
    SEND_J2K,
    SEND_KEEP,
    SEND_RLE,
    ROUTE_ALL,
    ROUTE_RETRIES,
    ConfigError,
    LocalSettings,
    NetworkConfig,
    Node,
    RoutingRule,
)
from ..net.horos_nodes import load_horos_nodes, save_horos_nodes
from ..net.routing import Router
from ..net.scp import DicomListener, ListenerError
from ..platform import Platform
from .tasks import Task, TaskRunner

SYNTAX_LABELS = {
    SEND_KEEP: "Como está na base",
    SEND_EXPLICIT: "Sem compressão (Explicit VR)",
    SEND_IMPLICIT: "Sem compressão (Implicit VR, equipamentos antigos)",
    SEND_J2K: "JPEG 2000 sem perdas",
    SEND_RLE: "RLE sem perdas",
}
RETRIEVE_LABELS = {RETRIEVE_MOVE: "C-MOVE", RETRIEVE_GET: "C-GET"}
ORIGIN_LABELS = {
    ROUTE_ALL: "Todas as imagens novas",
    "received": "Recebidas pela rede",
    "imported": "Importadas de arquivos ou discos",
    "generated": "Geradas pelo Horus (anonimizadas)",
}
# As caixas de modalidade da janela Query do Horos (Query.xib).
MODALITIES = ("CR", "CT", "MG", "XA", "RF", "NM", "DX", "ES", "PT", "SR", "SC", "MR", "AU", "OT", "RG", "DR", "XC", "VL", "US")


def local_addresses() -> list[str]:
    """Endereços IPv4 deste computador, para cadastrar o Horus no PACS.

    O painel Listener do Horos mostra os mesmos endereços.
    """
    found: list[str] = []
    try:
        # Descobre a interface da rota padrão sem enviar nada.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            found.append(s.getsockname()[0])
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addr = info[4][0]
            if addr not in found:
                found.append(addr)
    except OSError:
        pass
    return [a for a in found if not a.startswith("127.")] or ["127.0.0.1"]


# --------------------------------------------------------------- serviço


class NetworkService(QObject):
    """Configuração, listener e auto-roteamento, com eventos levados à
    thread da interface."""

    log = Signal(str)
    imported = Signal(dict)
    state = Signal(bool)

    def __init__(self, database: Database, platform: Platform):
        super().__init__()
        self.db = database
        self.platform = platform
        try:
            self.config = NetworkConfig.load(database.base_dir)
            self.config_error = ""
        except ConfigError as exc:
            self.config = NetworkConfig()
            self.config_error = str(exc)
        self.listener: DicomListener | None = None
        self.listener_error = ""
        self.router = Router(database, lambda: self.config, self._on_event)

    def _on_event(self, kind: str, data: dict) -> None:
        # Chamado nas threads do pynetdicom; os sinais Qt atravessam para a
        # thread da interface por conexão enfileirada.
        if kind == "log":
            self.log.emit(data.get("text", ""))
        elif kind == "imported":
            self.imported.emit(data)
        elif kind == "state":
            self.state.emit(bool(data.get("running")))

    def start(self) -> None:
        self.listener_error = ""
        # O roteamento independe do listener: imagens importadas de disco
        # também passam pelas regras.
        self.router.start()
        if not self.config.local.listener_enabled:
            self.state.emit(False)
            return
        if self.listener is None:
            self.listener = DicomListener(self.db, self.config, self._on_event)
        else:
            self.listener.config = self.config
        try:
            self.listener.start()
        except (ListenerError, ConfigError, OSError, ValueError) as exc:
            self.listener_error = str(exc)
            self.state.emit(False)

    def stop(self) -> None:
        # Primeiro o listener: ao parar ele importa o que ainda está na
        # fila, e essas imagens precisam passar pelas regras de roteamento
        # (o gancho sai junto com o roteador).
        if self.listener is not None:
            self.listener.stop()
        self.router.stop()

    @property
    def running(self) -> bool:
        return self.listener is not None and self.listener.running

    def apply(self, config: NetworkConfig) -> None:
        """Grava e reinicia o listener com a configuração nova.

        No Horos a maior parte das mudanças só vale depois de reabrir o
        programa ("Restart Horos to apply these changes"); aqui o listener é
        reiniciado na hora. O roteamento não para: ele lê a configuração a
        cada ciclo, e pará-lo prendia a interface enquanto um envio a um
        destino lento terminava.
        """
        config.save(self.db.base_dir)
        self.config = config
        if self.listener is not None:
            self.listener.stop()
        self.start()

    def status_text(self) -> str:
        local = self.config.local
        if self.running:
            return f"● Recebendo como {local.ae_title} na porta {local.port}"
        if self.listener_error:
            return "● Listener parado: " + self.listener_error
        return "● Listener desligado"


# ------------------------------------------------------- configurações


class NodeDialog(QDialog):
    def __init__(self, node: Node | None = None, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Nó DICOM")
        n = node or Node(name="", ae_title="", host="")
        self._id = n.id
        self.name = QLineEdit(n.name)
        self.ae = QLineEdit(n.ae_title)
        self.ae.setMaxLength(16)
        self.host = QLineEdit(n.host)
        self.port = QSpinBox()
        self.port.setRange(1, 65535)
        self.port.setValue(int(n.port))
        self.query = QCheckBox("Consultar e recuperar deste nó")
        self.query.setChecked(n.query)
        self.send = QCheckBox("Enviar para este nó")
        self.send.setChecked(n.send)
        self.retrieve = QComboBox()
        for key, label in RETRIEVE_LABELS.items():
            self.retrieve.addItem(label, key)
        self.retrieve.setCurrentIndex(max(0, self.retrieve.findData(n.retrieve)))
        self.syntax = QComboBox()
        for key, label in SYNTAX_LABELS.items():
            self.syntax.addItem(label, key)
        self.syntax.setCurrentIndex(max(0, self.syntax.findData(n.send_syntax)))
        self.assocs = QComboBox()
        for k in (1, 2, 4):
            self.assocs.addItem(str(k), k)
        self.assocs.setCurrentIndex(max(0, self.assocs.findData(n.send_associations)))
        self.tls = QCheckBox("Conexão segura (TLS)")
        self.tls.setChecked(n.tls)
        self.tls_verify = QCheckBox("Verificar o certificado do nó")
        self.tls_verify.setChecked(n.tls_verify)
        self.ca = QLineEdit(n.tls_ca_file)
        self.ca.setPlaceholderText("vazio = certificados confiáveis do Windows")

        form = QFormLayout()
        form.addRow("Descrição:", self.name)
        form.addRow("AE title:", self.ae)
        form.addRow("Endereço (IP ou nome):", self.host)
        form.addRow("Porta:", self.port)
        form.addRow("Recuperação:", self.retrieve)
        form.addRow("Sintaxe de envio:", self.syntax)
        form.addRow("Associações no envio:", self.assocs)
        form.addRow(self.query)
        form.addRow(self.send)
        form.addRow(self.tls)
        form.addRow(self.tls_verify)
        form.addRow("Autoridade certificadora:", self.ca)
        hint = QLabel(
            "C-MOVE: o nó envia as imagens ao listener do Horus, que precisa estar "
            "cadastrado nele (AE title, IP e porta). C-GET: as imagens voltam pela "
            "mesma conexão — não exige cadastro, mas nem todo PACS oferece."
        )
        hint.setWordWrap(True)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(self._accept)
        buttons.rejected.connect(self.reject)
        layout = QVBoxLayout(self)
        layout.addLayout(form)
        layout.addWidget(hint)
        layout.addWidget(buttons)
        self.result_node: Node | None = None

    def _accept(self) -> None:
        node = Node(
            name=self.name.text(),
            ae_title=self.ae.text(),
            host=self.host.text(),
            port=self.port.value(),
            query=self.query.isChecked(),
            send=self.send.isChecked(),
            retrieve=self.retrieve.currentData(),
            send_syntax=self.syntax.currentData(),
            send_associations=int(self.assocs.currentData()),
            tls=self.tls.isChecked(),
            tls_verify=self.tls_verify.isChecked(),
            tls_ca_file=self.ca.text().strip(),
            id=self._id,
        )
        try:
            self.result_node = node.validate()
        except ConfigError as exc:
            QMessageBox.warning(self, "Nó DICOM", str(exc))
            return
        self.accept()


class RuleDialog(QDialog):
    """Uma regra de auto-roteamento (a folha "Routing rule" do Horos)."""

    def __init__(self, nodes: list[Node], rule: RoutingRule | None = None, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Regra de auto-roteamento")
        self.setMinimumWidth(460)
        r = rule or RoutingRule()
        self._id = r.id
        self.name = QLineEdit(r.name)
        self.enabled = QCheckBox("Regra ativa")
        self.enabled.setChecked(r.enabled)
        self.destination = QComboBox()
        for n in nodes:
            if n.send or n.id == r.destination:
                self.destination.addItem(n.describe(), n.id)
        self.destination.setCurrentIndex(max(0, self.destination.findData(r.destination)))
        self.origin = QComboBox()
        for key, label in ORIGIN_LABELS.items():
            self.origin.addItem(label, key)
        self.origin.setCurrentIndex(max(0, self.origin.findData(r.origin)))
        self.modalities = QLineEdit(", ".join(r.modalities))
        self.modalities.setPlaceholderText("ex.: CT, MR — vazio = todas")
        self.calling_ae = QLineEdit(r.calling_ae)
        self.calling_ae.setMaxLength(16)
        self.calling_ae.setPlaceholderText("AE title de quem enviou — vazio = qualquer um")
        self.description = QLineEdit(r.description)
        self.description.setPlaceholderText("trecho da descrição do exame — vazio = qualquer uma")
        self.retries = QComboBox()
        for n in ROUTE_RETRIES:
            self.retries.addItem("nenhuma" if n == 0 else f"{n} tentativas", n)
        self.retries.setCurrentIndex(max(0, self.retries.findData(r.retries)))

        form = QFormLayout()
        form.addRow("Nome:", self.name)
        form.addRow(self.enabled)
        form.addRow("Enviar para:", self.destination)
        form.addRow("Imagens:", self.origin)
        form.addRow("Modalidades:", self.modalities)
        form.addRow("Vindas do AE:", self.calling_ae)
        form.addRow("Descrição contém:", self.description)
        form.addRow("Se falhar, repetir:", self.retries)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(self._accept)
        buttons.rejected.connect(self.reject)
        layout = QVBoxLayout(self)
        layout.addLayout(form)
        layout.addWidget(buttons)
        self._nodes = nodes
        self.result_rule: RoutingRule | None = None

    def _accept(self) -> None:
        rule = RoutingRule(
            name=self.name.text(),
            destination=self.destination.currentData() or "",
            enabled=self.enabled.isChecked(),
            origin=self.origin.currentData(),
            modalities=[m for m in self.modalities.text().replace(";", ",").replace(" ", ",").split(",") if m],
            calling_ae=self.calling_ae.text(),
            description=self.description.text(),
            retries=int(self.retries.currentData()),
            id=self._id,
        )
        try:
            self.result_rule = rule.validate(self._nodes)
        except ConfigError as exc:
            QMessageBox.warning(self, "Regra de auto-roteamento", str(exc))
            return
        self.accept()


class NetworkSettingsDialog(QDialog):
    def __init__(self, service: NetworkService, runner: TaskRunner, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Configurações de rede DICOM")
        self.setMinimumWidth(760)
        self.service = service
        self.runner = runner
        cfg = NetworkConfig.from_dict(service.config.to_dict())  # cópia editável
        self.nodes: list[Node] = cfg.nodes
        loc = cfg.local
        self._local = loc

        # --- este computador
        self.ae = QLineEdit(loc.ae_title)
        self.ae.setMaxLength(16)
        self.port = QSpinBox()
        self.port.setRange(1, 65535)
        self.port.setValue(loc.port)
        self.enabled = QCheckBox("Receber imagens (listener ativo)")
        self.enabled.setChecked(loc.listener_enabled)
        self.only_known = QCheckBox("Aceitar conexões só de nós cadastrados")
        self.only_known.setChecked(not loc.accept_unknown_callers)
        self.qr = QCheckBox("Atender consultas e recuperações (C-FIND, C-MOVE, C-GET)")
        self.qr.setChecked(loc.qr_server_enabled)
        self.tls = QCheckBox("Listener com TLS")
        self.tls.setChecked(loc.tls_enabled)
        self.cert = QLineEdit(loc.tls_cert_file)
        self.key = QLineEdit(loc.tls_key_file)
        self.ca = QLineEdit(loc.tls_ca_file)
        self.client_cert = QCheckBox("Exigir certificado dos clientes")
        self.client_cert.setChecked(loc.tls_require_client_cert)
        addresses = QLabel(", ".join(local_addresses()))
        addresses.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)

        local_form = QFormLayout()
        local_form.addRow("AE title:", self.ae)
        local_form.addRow("Porta:", self.port)
        local_form.addRow("Endereço(s) deste computador:", addresses)
        local_form.addRow(self.enabled)
        local_form.addRow(self.only_known)
        local_form.addRow(self.qr)
        tls_box = QGroupBox("TLS")
        tls_form = QFormLayout(tls_box)
        tls_form.addRow(self.tls)
        for label, edit in (("Certificado (PEM):", self.cert), ("Chave privada (PEM):", self.key), ("CA dos clientes:", self.ca)):
            row = QHBoxLayout()
            row.addWidget(edit, 1)
            browse = QPushButton("…")
            browse.clicked.connect(lambda _=False, e=edit: self._browse(e))
            row.addWidget(browse)
            tls_form.addRow(label, row)
        tls_form.addRow(self.client_cert)
        hint = QLabel(
            "Para receber de outros equipamentos, cadastre neles o AE title, um dos "
            "endereços acima e a porta. No Windows, o Firewall do Windows Defender "
            "precisa liberar a porta."
        )
        hint.setWordWrap(True)
        local_tab = QWidget()
        local_layout = QVBoxLayout(local_tab)
        local_layout.addLayout(local_form)
        local_layout.addWidget(tls_box)
        local_layout.addWidget(hint)
        if sys.platform == "win32":
            firewall = QPushButton("Liberar a porta no Firewall do Windows…")
            firewall.clicked.connect(self._firewall)
            local_layout.addWidget(firewall)
        local_layout.addStretch(1)

        # --- nós
        self.table = QTableWidget(0, 7)
        self.table.setHorizontalHeaderLabels(["Descrição", "AE title", "Endereço", "Porta", "Recuperação", "Envio", "TLS"])
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.doubleClicked.connect(lambda *_: self._edit())
        buttons_row = QHBoxLayout()
        for text, slot in (("Adicionar…", self._add), ("Editar…", self._edit), ("Remover", self._remove), ("Testar conexão (C-ECHO)", self._echo)):
            b = QPushButton(text)
            b.clicked.connect(slot)
            buttons_row.addWidget(b)
        buttons_row.addStretch(1)
        for text, slot in (("Importar do Horos…", self._import_horos), ("Exportar para o Horos…", self._export_horos)):
            b = QPushButton(text)
            b.clicked.connect(slot)
            buttons_row.addWidget(b)
        self.echo_status = QLabel()
        self.echo_status.setWordWrap(True)
        nodes_tab = QWidget()
        nodes_layout = QVBoxLayout(nodes_tab)
        nodes_layout.addWidget(self.table)
        nodes_layout.addLayout(buttons_row)
        nodes_layout.addWidget(self.echo_status)

        # --- auto-roteamento
        self.rules: list[RoutingRule] = cfg.rules
        self.routing = QCheckBox("Rotear automaticamente as imagens novas")
        self.routing.setChecked(cfg.routing_enabled)
        self.rules_table = QTableWidget(0, 4)
        self.rules_table.setHorizontalHeaderLabels(["Ativa", "Regra", "Destino", "Filtro"])
        rh = self.rules_table.horizontalHeader()
        rh.setSectionResizeMode(QHeaderView.ResizeMode.ResizeToContents)
        rh.setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        self.rules_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.rules_table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.rules_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.rules_table.doubleClicked.connect(lambda *_: self._edit_rule())
        rules_row = QHBoxLayout()
        for text, slot in (("Adicionar…", self._add_rule), ("Editar…", self._edit_rule), ("Remover", self._remove_rule)):
            b = QPushButton(text)
            b.clicked.connect(slot)
            rules_row.addWidget(b)
        rules_row.addStretch(1)
        rules_hint = QLabel(
            "Cada imagem nova que passar no filtro de uma regra ativa é enviada ao nó "
            "da regra, um paciente por associação. Falhas voltam à fila e são tentadas "
            "de novo a cada 30 s; a fila fica na base e sobrevive ao fechar o programa."
        )
        rules_hint.setWordWrap(True)
        routing_tab = QWidget()
        routing_layout = QVBoxLayout(routing_tab)
        routing_layout.addWidget(self.routing)
        routing_layout.addWidget(self.rules_table)
        routing_layout.addLayout(rules_row)
        routing_layout.addWidget(rules_hint)

        tabs = QTabWidget()
        tabs.addTab(local_tab, "Este computador")
        tabs.addTab(nodes_tab, "Nós remotos")
        tabs.addTab(routing_tab, "Auto-roteamento")
        box = QDialogButtonBox(QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel)
        box.accepted.connect(self._save)
        box.rejected.connect(self.reject)
        layout = QVBoxLayout(self)
        layout.addWidget(tabs)
        layout.addWidget(box)
        self._fill()

    def _browse(self, edit: QLineEdit) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Arquivo", edit.text(), "PEM (*.pem *.crt *.key);;Todos (*)")
        if path:
            edit.setText(path)

    def _fill_rules(self) -> None:
        self.rules_table.setRowCount(len(self.rules))
        for row, r in enumerate(self.rules):
            target = next((n for n in self.nodes if n.id == r.destination), None)
            values = ["sim" if r.enabled else "não", r.name, target.name if target else "(nó removido)", r.describe_filter()]
            for col, value in enumerate(values):
                self.rules_table.setItem(row, col, QTableWidgetItem(value))

    def _add_rule(self) -> None:
        if not any(n.send for n in self.nodes):
            QMessageBox.information(self, "Auto-roteamento", "Cadastre antes um nó com envio habilitado.")
            return
        dialog = RuleDialog(self.nodes, parent=self)
        if dialog.exec() == QDialog.DialogCode.Accepted and dialog.result_rule:
            self.rules.append(dialog.result_rule)
            self._fill_rules()

    def _edit_rule(self) -> None:
        rows = self.rules_table.selectionModel().selectedRows()
        if not rows:
            return
        index = rows[0].row()
        dialog = RuleDialog(self.nodes, self.rules[index], self)
        if dialog.exec() == QDialog.DialogCode.Accepted and dialog.result_rule:
            self.rules[index] = dialog.result_rule
            self._fill_rules()

    def _remove_rule(self) -> None:
        rows = self.rules_table.selectionModel().selectedRows()
        if rows:
            del self.rules[rows[0].row()]
            self._fill_rules()

    def _fill(self) -> None:
        self._fill_rules()
        self.table.setRowCount(len(self.nodes))
        for row, n in enumerate(self.nodes):
            values = [n.name, n.ae_title, n.host, str(n.port), RETRIEVE_LABELS.get(n.retrieve, n.retrieve), SYNTAX_LABELS.get(n.send_syntax, n.send_syntax), "sim" if n.tls else ""]
            for col, value in enumerate(values):
                self.table.setItem(row, col, QTableWidgetItem(value))

    def _selected(self) -> int:
        rows = self.table.selectionModel().selectedRows()
        return rows[0].row() if rows else -1

    def _add(self) -> None:
        dialog = NodeDialog(parent=self)
        if dialog.exec() == QDialog.DialogCode.Accepted and dialog.result_node:
            self.nodes.append(dialog.result_node)
            self._fill()

    def _edit(self) -> None:
        row = self._selected()
        if row < 0:
            return
        dialog = NodeDialog(self.nodes[row], self)
        if dialog.exec() == QDialog.DialogCode.Accepted and dialog.result_node:
            self.nodes[row] = dialog.result_node
            self._fill()

    def _remove(self) -> None:
        row = self._selected()
        if row >= 0:
            del self.nodes[row]
            self._fill()

    def _import_horos(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Lista de nós do Horos", "", "Lista de nós do Horos (*.plist);;Todos (*)")
        if not path:
            return
        try:
            imported, notes = load_horos_nodes(path)
        except ConfigError as exc:
            QMessageBox.warning(self, "Importar do Horos", str(exc))
            return
        taken = {n.ae_title for n in self.nodes}
        added = 0
        for n in imported:
            if n.ae_title in taken:
                notes.append(f"{n.name}: o AE title {n.ae_title} já está cadastrado; mantido o atual")
                continue
            taken.add(n.ae_title)
            self.nodes.append(n)
            added += 1
        self._fill()
        text = f"{added} nó(s) importado(s). Confira e clique em Salvar."
        if notes:
            text += "\n\n" + "\n".join(f"- {line}" for line in notes)
        QMessageBox.information(self, "Importar do Horos", text)

    def _export_horos(self) -> None:
        path, _ = QFileDialog.getSaveFileName(self, "Exportar para o Horos", "DICOMNodes.plist", "Lista de nós do Horos (*.plist)")
        if not path:
            return
        try:
            save_horos_nodes(self.nodes, path)
        except OSError as exc:
            QMessageBox.warning(self, "Exportar para o Horos", f"Não foi possível gravar {path}: {exc}")
            return
        QMessageBox.information(self, "Exportar para o Horos", f"{len(self.nodes)} nó(s) gravado(s) em {path}.")

    def _local_settings(self) -> LocalSettings:
        loc = LocalSettings(**self._local.__dict__)
        loc.ae_title = self.ae.text()
        loc.port = self.port.value()
        loc.listener_enabled = self.enabled.isChecked()
        loc.accept_unknown_callers = not self.only_known.isChecked()
        loc.qr_server_enabled = self.qr.isChecked()
        loc.tls_enabled = self.tls.isChecked()
        loc.tls_cert_file = self.cert.text().strip()
        loc.tls_key_file = self.key.text().strip()
        loc.tls_ca_file = self.ca.text().strip()
        loc.tls_require_client_cert = self.client_cert.isChecked()
        return loc

    def _echo(self) -> None:
        row = self._selected()
        if row < 0:
            self.echo_status.setText("Selecione um nó.")
            return
        target = self.nodes[row]
        self.echo_status.setText(f"Testando {target.describe()}…")
        local = self._local_settings()
        self.runner.start(
            lambda task: scu.echo(local, target),
            on_done=lambda res: self.echo_status.setText(("✔ " if res.ok else "✘ ") + res.message),
            on_error=lambda msg: self.echo_status.setText("✘ " + msg),
        )

    def _firewall(self) -> None:
        program = sys.executable
        if self.service.platform.allow_inbound_port(self.port.value(), program):
            QMessageBox.information(
                self, "Firewall",
                f"Porta TCP {self.port.value()} liberada para o Horus no Firewall do Windows Defender. "
                "Regras antigas do Horus, inclusive as de bloqueio, foram substituídas.",
            )
        else:
            QMessageBox.warning(self, "Firewall", "Não foi possível criar a regra (confirmação de administrador recusada ou netsh com erro).")

    def _save(self) -> None:
        config = NetworkConfig(self._local_settings(), list(self.nodes), self.routing.isChecked(), list(self.rules))
        try:
            config.validate()
        except ConfigError as exc:
            QMessageBox.warning(self, "Configurações de rede", str(exc))
            return
        self.result_config = config
        self.accept()


# ------------------------------------------------------------- envio


class SendDialog(QDialog):
    """Envio de imagens a um nó (SendController no Horos)."""

    def __init__(self, files: list[str], service: NetworkService, runner: TaskRunner, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Enviar para nó DICOM")
        self.setMinimumWidth(480)
        self.files = files
        self.service = service
        self.runner = runner
        self.task: Task | None = None
        self.nodes = [n for n in service.config.nodes if n.send]
        self.combo = QComboBox()
        for n in self.nodes:
            self.combo.addItem(n.describe())
        # Associações simultâneas, como o envio do Horos (1, 2 ou 4); o
        # padrão vem do nó e a escolha vale só para este envio.
        self.assocs = QComboBox()
        for k in (1, 2, 4):
            self.assocs.addItem(str(k), k)
        self.combo.currentIndexChanged.connect(self._node_changed)
        self._node_changed(0)
        self.progress = QProgressBar()
        self.progress.setRange(0, max(1, len(files)))
        self.progress.setValue(0)
        self.status = QLabel(f"{len(files)} imagem(ns) selecionada(s).")
        self.status.setWordWrap(True)
        self.send_btn = QPushButton("Enviar")
        self.send_btn.setDefault(True)
        self.send_btn.clicked.connect(self.start)
        self.close_btn = QPushButton("Fechar")
        self.close_btn.clicked.connect(self._close_or_cancel)
        if not self.nodes:
            self.send_btn.setEnabled(False)
            self.status.setText("Nenhum nó com envio habilitado. Cadastre um em Rede → Configurações de rede.")
        row = QHBoxLayout()
        row.addStretch(1)
        row.addWidget(self.close_btn)
        row.addWidget(self.send_btn)
        layout = QVBoxLayout(self)
        form = QFormLayout()
        form.addRow("Destino:", self.combo)
        form.addRow("Associações simultâneas:", self.assocs)
        layout.addLayout(form)
        layout.addWidget(self.progress)
        layout.addWidget(self.status)
        layout.addLayout(row)

    def reject(self) -> None:
        """Esc e o X da janela passam por aqui: com envio em andamento,
        cancelam e fecham quando ele terminar, em vez de esconder a janela
        e deixar o envio rodando sem como cancelar."""
        if self.task is not None:
            self.task.cancel_requested = True
            self._close_when_done = True
            self.status.setText("Cancelando…")
            return
        super().reject()

    def _node_changed(self, index: int) -> None:
        if 0 <= index < len(self.nodes):
            wanted = self.nodes[index].send_associations
            self.assocs.setCurrentIndex(max(0, self.assocs.findData(wanted)))

    def _close_or_cancel(self) -> None:
        if self.task is not None:
            self.task.cancel_requested = True
            self.status.setText("Cancelando…")
        else:
            self.reject()

    def start(self) -> None:
        target = self.nodes[self.combo.currentIndex()]
        local = self.service.config.local
        associations = int(self.assocs.currentData())
        self.send_btn.setEnabled(False)
        self.close_btn.setText("Cancelar")
        self.status.setText(f"Enviando para {target.describe()}…")

        def job(task: Task):
            return scu.send(local, target, self.files, progress=lambda d, t, p: task.report(p, d, t), cancelled=task.cancelled, associations=associations)

        self.task = self.runner.start(job, on_done=self._done, on_error=self._failed, on_progress=self._progress)

    def _progress(self, _path: str, done: int, total: int) -> None:
        self.progress.setRange(0, max(1, total))
        self.progress.setValue(done)

    def _done(self, result: scu.SendResult) -> None:
        self.task = None
        self.close_btn.setText("Fechar")
        self.send_btn.setEnabled(True)
        text = f"{result.sent} de {result.total} imagem(ns) enviada(s)"
        if result.warnings:
            text += f", {result.warnings} com aviso"
        if result.cancelled:
            text += " — envio cancelado"
        if result.failed:
            reasons = {}
            for _p, reason in result.failed:
                reasons[reason] = reasons.get(reason, 0) + 1
            text += ".\n\nFalhas:\n" + "\n".join(f"- {n}× {r}" for r, n in reasons.items())
        self.status.setText(text)
        self.service.log.emit(f"envio para {self.nodes[self.combo.currentIndex()].ae_title}: {text.splitlines()[0]}")
        if getattr(self, "_close_when_done", False):
            super().reject()

    def _failed(self, message: str) -> None:
        self.task = None
        self.close_btn.setText("Fechar")
        self.send_btn.setEnabled(True)
        self.status.setText("Falha no envio: " + message)
        if getattr(self, "_close_when_done", False):
            super().reject()


# --------------------------------------------------------- consulta


def _da(d: date) -> str:
    return d.strftime("%Y%m%d")


def _fmt_date(value: str) -> str:
    value = str(value or "")
    return f"{value[6:8]}/{value[4:6]}/{value[:4]}" if len(value) == 8 and value.isdigit() else value


def _starts_with(text: str) -> str:
    """Busca por início, como o Horos: ele acrescenta `*` ao nome e à
    descrição. Sem isso, a maioria dos PACS faz correspondência exata e
    "SILVA" não encontra "SILVA^JOAO"."""
    text = text.strip()
    return text if not text or "*" in text or "?" in text else text + "*"


def study_query(name: str = "", patient_id: str = "", accession: str = "", description: str = "", date_range: str = "", modalities: list[str] | None = None) -> Dataset:
    """Identificador de C-FIND de estudo (DCMTKRootQueryNode no Horos).

    ID do paciente e número de acesso vão exatamente como digitados.
    """
    ds = Dataset()
    ds.QueryRetrieveLevel = "STUDY"
    ds.PatientName = _starts_with(name)
    ds.PatientID = patient_id.strip()
    ds.PatientBirthDate = ""
    ds.PatientSex = ""
    ds.StudyDate = date_range
    ds.StudyTime = ""
    ds.StudyDescription = _starts_with(description)
    ds.AccessionNumber = accession.strip()
    ds.StudyID = ""
    ds.StudyInstanceUID = ""
    ds.ModalitiesInStudy = modalities or ""
    ds.NumberOfStudyRelatedInstances = ""
    ds.NumberOfStudyRelatedSeries = ""
    ds.ReferringPhysicianName = ""
    if any(not str(v).isascii() for v in (name, patient_id, accession, description)):
        ds.SpecificCharacterSet = "ISO_IR 192"
    return ds


def series_query(study_uid: str) -> Dataset:
    """Identificador de C-FIND de série (DCMTKStudyQueryNode no Horos)."""
    ds = Dataset()
    ds.QueryRetrieveLevel = "SERIES"
    ds.StudyInstanceUID = study_uid
    ds.SeriesInstanceUID = ""
    ds.SeriesNumber = ""
    ds.SeriesDate = ""
    ds.SeriesTime = ""
    ds.Modality = ""
    ds.SeriesDescription = ""
    ds.NumberOfSeriesRelatedInstances = ""
    return ds


# Presets de data do Horos (getDateAndTimeQueryFilterWithTag). Os "últimos
# N" contam N dias para trás a partir de agora e ficam abertos no fim
# ("AAAAMMDD-"), como no Horos com DICOMQueryAllowFutureQuery ligado: um
# exame com data adiantada pelo relógio do equipamento continua aparecendo.
_LAST_DAYS = {"Últimos 2 dias": 2, "Últimos 7 dias": 7, "Último mês": 31, "Últimos 3 meses": 93}
DATE_PRESETS = ("Qualquer data", "Hoje", "Ontem", "Anteontem", *_LAST_DAYS, "Em", "Entre")


def date_range_for(preset: str, today: date, start: date | None = None, end: date | None = None) -> str:
    if preset == "Hoje":
        return _da(today)
    if preset == "Ontem":
        return _da(today - timedelta(days=1))
    if preset == "Anteontem":
        return _da(today - timedelta(days=2))
    if preset in _LAST_DAYS:
        return f"{_da(today - timedelta(days=_LAST_DAYS[preset]))}-"
    if preset == "Em" and start:
        return _da(start)
    if preset == "Entre" and start and end:
        return f"{_da(min(start, end))}-{_da(max(start, end))}"
    return ""


def merge_studies(results: list[tuple[Node, Dataset]]) -> list[tuple[Node, Dataset]]:
    """Um exame por StudyInstanceUID, mesmo vindo de vários nós.

    Como no Horos (QueryController), fica a resposta com mais imagens — e
    a recuperação vai ao nó que a deu.
    """
    def count(ds: Dataset) -> int:
        try:
            return int(ds.get("NumberOfStudyRelatedInstances", 0) or 0)
        except (TypeError, ValueError):
            return 0

    best: dict[str, tuple[Node, Dataset]] = {}
    order: list[str] = []
    for i, (n, ds) in enumerate(results):
        uid = str(ds.get("StudyInstanceUID", "")) or f"sem-uid-{i}"
        if uid not in best:
            order.append(uid)
            best[uid] = (n, ds)
        elif count(ds) > count(best[uid][1]):
            best[uid] = (n, ds)
    return [best[u] for u in order]


def _get_into_base(db: Database, local, target: Node, level: str, uid: str, parent: str, incoming, progress, cancelled) -> str:
    """C-GET de um exame ou série para a base.

    O que chegou é importado mesmo que a recuperação falhe no meio (o PACS
    caiu, status final de falha): o Horos grava cada sub-operação direto em
    INCOMING, qualquer que seja o status final. A pasta temporária só é
    apagada depois de importar; se a importação falhar, ela fica em
    INCOMING/GET e o listener a retoma depois.
    """
    folder = incoming / uuid.uuid4().hex
    failure: Exception | None = None
    try:
        res = scu.get(local, target, level, [uid], folder, study_uid=parent, progress=progress, cancelled=cancelled)
    except scu.NetworkError as exc:
        failure, res = exc, None
    received = sorted(str(p) for p in folder.glob("*.dcm"))
    imported = db.add_files(received, move=True, origin=ORIGIN_RECEIVED) if received else None
    added = imported.added if imported else 0
    if imported is None or not imported.transient:
        # Duplicados e recusados ficam para trás; a pasta é só desta recuperação.
        shutil.rmtree(folder, ignore_errors=True)
    if failure is not None:
        raise scu.NetworkError(f"{failure} ({added} imagem(ns) importada(s) antes da falha)") from failure
    note = f" ({res.message})" if res is not None and res.message and res.message != "recuperação concluída" else ""
    return f"{target.name}: {added} imagem(ns) importada(s) por C-GET{note}"


ROLE_NODE = Qt.ItemDataRole.UserRole
ROLE_UID = Qt.ItemDataRole.UserRole + 1
ROLE_LEVEL = Qt.ItemDataRole.UserRole + 2
ROLE_STUDY = Qt.ItemDataRole.UserRole + 3
ROLE_LOADING = Qt.ItemDataRole.UserRole + 4


class QueryWindow(QMainWindow):
    """Consulta e recuperação (QueryController no Horos)."""

    def __init__(self, service: NetworkService, runner: TaskRunner, on_imported: Callable[[], None], parent=None):
        super().__init__(parent)
        self.setWindowTitle("Consultar e recuperar")
        self.resize(1150, 680)
        self.service = service
        self.runner = runner
        self.on_imported = on_imported
        self.task: Task | None = None

        self.node_box = QComboBox()
        self.name = QLineEdit()
        self.name.setPlaceholderText("Nome do paciente")
        self.pid = QLineEdit()
        self.pid.setPlaceholderText("ID")
        self.accession = QLineEdit()
        self.accession.setPlaceholderText("Nº de acesso")
        self.description = QLineEdit()
        self.description.setPlaceholderText("Descrição do exame")
        self.preset = QComboBox()
        self.preset.addItems(DATE_PRESETS)
        self.preset.setCurrentText("Hoje")
        self.start_date = QDateEdit(QDate.currentDate())
        self.end_date = QDateEdit(QDate.currentDate())
        for d in (self.start_date, self.end_date):
            d.setCalendarPopup(True)
            d.setDisplayFormat("dd/MM/yyyy")
            d.setEnabled(False)
        self.preset.currentTextChanged.connect(self._preset_changed)
        self.mod_boxes = {m: QCheckBox(m) for m in MODALITIES}
        for edit in (self.name, self.pid, self.accession, self.description):
            edit.returnPressed.connect(self.search)

        bar = QToolBar("Consulta")
        bar.setMovable(False)
        self.addToolBar(bar)
        search = QAction("Consultar", self)
        search.setShortcut(QKeySequence("Ctrl+F"))
        search.triggered.connect(self.search)
        self.retrieve_act = QAction("Recuperar selecionados", self)
        self.retrieve_act.setShortcut(QKeySequence("Ctrl+R"))
        self.retrieve_act.triggered.connect(self.retrieve)
        cancel = QAction("Cancelar", self)
        cancel.triggered.connect(self._cancel)
        for act in (search, self.retrieve_act, cancel):
            bar.addAction(act)

        filters = QWidget()
        grid = QVBoxLayout(filters)
        row1 = QHBoxLayout()
        row1.addWidget(QLabel("Nó:"))
        row1.addWidget(self.node_box, 1)
        for w in (self.name, self.pid, self.accession, self.description):
            row1.addWidget(w, 1)
        row2 = QHBoxLayout()
        row2.addWidget(QLabel("Data:"))
        row2.addWidget(self.preset)
        row2.addWidget(self.start_date)
        row2.addWidget(QLabel("a"))
        row2.addWidget(self.end_date)
        row2.addStretch(1)
        row3 = QHBoxLayout()
        row3.addWidget(QLabel("Modalidades:"))
        for box in self.mod_boxes.values():
            row3.addWidget(box)
        row3.addStretch(1)
        grid.addLayout(row1)
        grid.addLayout(row2)
        grid.addLayout(row3)

        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["Paciente", "ID", "Nascimento", "Data", "Descrição", "Modalidades", "Imagens", "Nº de acesso", "Nó"])
        self.tree.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.tree.setAlternatingRowColors(True)
        self.tree.header().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.tree.itemExpanded.connect(self._expand)
        self.tree.itemDoubleClicked.connect(lambda *_: self.retrieve())

        self.progress = QProgressBar()
        self.progress.setVisible(False)
        self.status = QLabel()
        central = QWidget()
        layout = QVBoxLayout(central)
        layout.addWidget(filters)
        layout.addWidget(self.tree, 1)
        layout.addWidget(self.progress)
        layout.addWidget(self.status)
        self.setCentralWidget(central)
        self.refresh_nodes()

    def _preset_changed(self, text: str) -> None:
        self.start_date.setEnabled(text in ("Em", "Entre"))
        self.end_date.setEnabled(text == "Entre")

    def refresh_nodes(self) -> None:
        self.node_box.clear()
        nodes = [n for n in self.service.config.nodes if n.query]
        if len(nodes) > 1:
            self.node_box.addItem("Todos os nós", "*")
        for n in nodes:
            self.node_box.addItem(n.describe(), n.id)
        if not nodes:
            self.status.setText("Nenhum nó de consulta cadastrado (Rede → Configurações de rede).")

    def _targets(self) -> list[Node]:
        key = self.node_box.currentData()
        nodes = [n for n in self.service.config.nodes if n.query]
        return nodes if key == "*" else [n for n in nodes if n.id == key]

    def _busy(self, on: bool, text: str = "") -> None:
        self.progress.setVisible(on)
        if on:
            self.progress.setRange(0, 0)
        self.status.setText(text)

    def _cancel(self) -> None:
        if self.task is not None:
            self.task.cancel_requested = True
            self.status.setText("Cancelando…")

    # -------------------------------------------------------- consulta

    def search(self) -> None:
        targets = self._targets()
        if not targets or self.task is not None:
            return
        today = date.today()
        rng = date_range_for(
            self.preset.currentText(), today, self.start_date.date().toPython(), self.end_date.date().toPython()
        )
        mods = [m for m, b in self.mod_boxes.items() if b.isChecked()]
        ident = study_query(self.name.text(), self.pid.text(), self.accession.text(), self.description.text(), rng, mods)
        local = self.service.config.local

        def job(task: Task):
            results, errors = [], []
            for n in targets:
                if task.cancelled():
                    break
                task.report(f"Consultando {n.describe()}…")
                try:
                    found = scu.find(local, n, ident, cancelled=task.cancelled, limit=local.max_find_results)
                    results.extend((n, ds) for ds in found.matches)
                    if found.warning:
                        errors.append(f"{n.name}: {found.warning}")
                except Exception as exc:  # um nó com problema não apaga o resultado dos outros
                    errors.append(f"{n.name}: {exc}")
            return results, errors

        self.tree.clear()
        self._busy(True, "Consultando…")
        self.task = self.runner.start(job, on_done=self._show, on_error=self._failed, on_progress=lambda m, *_: self.status.setText(m))

    def _local_uids(self) -> set[str]:
        with self.service.db.connect() as conn:
            return {r[0] for r in conn.execute("SELECT study_instance_uid FROM study")}

    def _show(self, payload) -> None:
        self.task = None
        self._busy(False)
        results, errors = payload
        results = merge_studies(results)
        local = self._local_uids()
        for n, ds in results:
            uid = str(ds.get("StudyInstanceUID", ""))
            mods = ds.get("ModalitiesInStudy", "")
            mods = str(mods) if isinstance(mods, str) else "/".join(str(m) for m in mods)
            item = QTreeWidgetItem([
                str(ds.get("PatientName", "")).replace("^", " "),
                str(ds.get("PatientID", "")),
                _fmt_date(ds.get("PatientBirthDate", "")),
                _fmt_date(ds.get("StudyDate", "")),
                str(ds.get("StudyDescription", "")),
                mods,
                str(ds.get("NumberOfStudyRelatedInstances", "")),
                str(ds.get("AccessionNumber", "")),
                n.name,
            ])
            item.setData(0, ROLE_NODE, n.id)
            item.setData(0, ROLE_UID, uid)
            item.setData(0, ROLE_LEVEL, "STUDY")
            item.setData(0, ROLE_STUDY, uid)
            item.setChildIndicatorPolicy(QTreeWidgetItem.ChildIndicatorPolicy.ShowIndicator)
            if uid in local:
                # Exame já presente na base local, como o Horos sinaliza.
                for col in range(self.tree.columnCount()):
                    item.setForeground(col, QColor("#7ee787"))
                item.setToolTip(0, "Já está na base local")
            self.tree.addTopLevelItem(item)
        for col in range(1, self.tree.columnCount()):
            self.tree.resizeColumnToContents(col)
        text = f"{len(results)} exame(s) encontrado(s)"
        if errors:
            text += " — falhas: " + "; ".join(errors)
        self.status.setText(text)

    def _failed(self, message: str) -> None:
        self.task = None
        self._busy(False, "Falha: " + message)

    def _expand(self, item: QTreeWidgetItem) -> None:
        if item.data(0, ROLE_LEVEL) != "STUDY" or item.childCount() or item.data(0, ROLE_LOADING):
            return
        target = self.service.config.node_by_id(item.data(0, ROLE_NODE))
        if target is None:
            return
        uid = item.data(0, ROLE_UID)
        local = self.service.config.local
        # Recolher e expandir de novo antes da resposta não dispara outra
        # consulta (as séries apareciam em dobro).
        item.setData(0, ROLE_LOADING, True)

        def alive() -> bool:
            # Uma consulta nova limpa a árvore; o item pode não existir mais.
            return shiboken6.isValid(item)

        def failed(message: str) -> None:
            if alive():
                item.setData(0, ROLE_LOADING, False)
            self.status.setText("Falha ao listar séries: " + message)

        def done(found) -> None:
            if not alive():
                return
            item.setData(0, ROLE_LOADING, False)
            if item.childCount():
                return
            for ds in sorted(found.matches, key=lambda d: int(d.get("SeriesNumber", 0) or 0)):
                child = QTreeWidgetItem([
                    f"Série {ds.get('SeriesNumber', '')} — {ds.get('SeriesDescription', '')}", "", "", "", "",
                    str(ds.get("Modality", "")), str(ds.get("NumberOfSeriesRelatedInstances", "")), "", target.name,
                ])
                child.setData(0, ROLE_NODE, target.id)
                child.setData(0, ROLE_UID, str(ds.get("SeriesInstanceUID", "")))
                child.setData(0, ROLE_LEVEL, "SERIES")
                child.setData(0, ROLE_STUDY, uid)
                item.addChild(child)

        self.runner.start(lambda task: scu.find(local, target, series_query(uid)), on_done=done, on_error=failed)

    # ---------------------------------------------------- recuperação

    def retrieve(self) -> None:
        items = self.tree.selectedItems()
        if not items or self.task is not None:
            return
        jobs: dict[tuple[str, str], list[tuple[str, str]]] = {}
        for it in items:
            jobs.setdefault((it.data(0, ROLE_NODE), it.data(0, ROLE_LEVEL)), []).append((it.data(0, ROLE_UID), it.data(0, ROLE_STUDY)))
        local = self.service.config.local
        needs_listener = any(
            (n := self.service.config.node_by_id(node_id)) is not None and n.retrieve == RETRIEVE_MOVE for node_id, _ in jobs
        )
        if needs_listener and not self.service.running:
            QMessageBox.warning(
                self,
                "Recuperar",
                "A recuperação por C-MOVE precisa do listener ativo: o PACS envia as imagens "
                f"para o AE title {local.ae_title} na porta {local.port}.\n\n"
                + (self.service.listener_error or "Ligue o listener em Rede → Configurações de rede."),
            )
            return
        db = self.service.db
        incoming = db.base_dir / paths.INCOMING_DIR_NAME / "GET"

        def job(task: Task):
            summary, errors = [], []
            for (node_id, level), entries in jobs.items():
                target = self.service.config.node_by_id(node_id)
                if target is None:
                    continue
                for uid, study_uid in entries:
                    if task.cancelled():
                        return summary, errors
                    task.report(f"Recuperando de {target.describe()}…")
                    progress = lambda done, total, _p, name=target.name: task.report(f"Recuperando de {name}: {done}/{total}", done, total)  # noqa: E731
                    parent = study_uid if level != "STUDY" else ""
                    try:
                        if target.retrieve == RETRIEVE_GET:
                            summary.append(_get_into_base(db, local, target, level, uid, parent, incoming, progress, task.cancelled))
                        else:
                            res = scu.move(local, target, level, [uid], study_uid=parent, progress=progress, cancelled=task.cancelled)
                            summary.append(f"{target.name}: {res.completed} imagem(ns) enviada(s) por C-MOVE ({res.message})")
                    except Exception as exc:  # um exame com problema não impede os outros
                        errors.append(f"{target.name}: {exc}")
            return summary, errors

        self._busy(True, "Recuperando…")
        self.task = self.runner.start(job, on_done=self._retrieved, on_error=self._failed, on_progress=self._progress)

    def _progress(self, message: str, done: int, total: int) -> None:
        self.status.setText(message)
        if total:
            self.progress.setRange(0, total)
            self.progress.setValue(done)

    def _retrieved(self, payload) -> None:
        self.task = None
        summary, errors = payload
        text = "; ".join(summary) or "Nada recuperado."
        if errors:
            text += " — falhas: " + "; ".join(errors)
        self._busy(False, text)
        self.on_imported()


# ---------------------------------------------------------- atividade


class ActivityDialog(QDialog):
    """Registro de atividade de rede (os "Network logs" do Horos)."""

    def __init__(self, service: NetworkService, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Atividade de rede")
        self.resize(760, 420)
        self.service = service
        self.text = QPlainTextEdit()
        self.text.setReadOnly(True)
        if service.listener is not None:
            for stamp, line in list(service.listener.activity):
                self.text.appendPlainText(f"{time.strftime('%d/%m %H:%M:%S', time.localtime(stamp))}  {line}")
        service.log.connect(self._append)
        log_dir = service.db.base_dir / "logs"
        self.queue_label = QLabel()
        retry = QPushButton("Tentar as falhas de novo")
        retry.clicked.connect(lambda: (service.router.retry_failed(), self._refresh_queue()))
        discard = QPushButton("Descartar as falhas")
        discard.clicked.connect(lambda: (service.router.discard_failed(), self._refresh_queue()))
        queue_row = QHBoxLayout()
        queue_row.addWidget(self.queue_label, 1)
        queue_row.addWidget(retry)
        queue_row.addWidget(discard)
        open_logs = QPushButton("Abrir pasta de registros")
        open_logs.clicked.connect(lambda: service.platform.open_folder(log_dir))
        close = QPushButton("Fechar")
        close.clicked.connect(self.accept)
        row = QHBoxLayout()
        row.addWidget(open_logs)
        row.addStretch(1)
        row.addWidget(close)
        layout = QVBoxLayout(self)
        layout.addWidget(self.text)
        layout.addLayout(queue_row)
        layout.addLayout(row)
        self._refresh_queue()

    def _refresh_queue(self) -> None:
        c = self.service.router.counts()
        state = "ligado" if self.service.config.routing_enabled else "desligado"
        self.queue_label.setText(f"Auto-roteamento {state}: {c['pending']} imagem(ns) na fila, {c['failed']} com falha")

    def _append(self, line: str) -> None:
        self.text.appendPlainText(f"{time.strftime('%d/%m %H:%M:%S')}  {line}")
        if line.startswith("roteamento:"):
            self._refresh_queue()

    def done(self, result: int) -> None:
        try:
            self.service.log.disconnect(self._append)
        except (RuntimeError, TypeError):
            pass
        super().done(result)


__all__ = [
    "ActivityDialog",
    "NetworkService",
    "NetworkSettingsDialog",
    "NodeDialog",
    "QueryWindow",
    "RuleDialog",
    "SendDialog",
    "date_range_for",
    "local_addresses",
    "series_query",
    "study_query",
]
