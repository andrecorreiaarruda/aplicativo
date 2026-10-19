"""Diálogo de gravação — equivalente à janela BurnViewer do Horos.

Mesmos elementos do BurnerWindowController: nome do disco (com a sugestão
de `defaultTitle`), tamanho estimado e final, modo de compressão,
anonimização, inclusões (visualizador, HTML, pasta suplementar, ZIP com
senha) e o destino — CD/DVD, pendrive ou imagem de disco. No Windows a
imagem é ISO em vez de DMG, e há um quarto destino, "pasta", para enviar o
conteúdo por rede.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from PySide6.QtWidgets import (
    QButtonGroup,
    QCheckBox,
    QComboBox,
    QDialog,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QRadioButton,
    QVBoxLayout,
    QWidget,
)

from .. import paths
from ..anonymize import AnonymizationOptions
from ..burn.destinations import burn_disc, write_iso, write_usb
from ..burn.iso import sanitize_volume_label
from ..burn.prepare import COMPRESS, DECOMPRESS, KEEP, Cancelled, DiscOptions, default_label, estimate_size, prepare_disc, viewer_bundle
from ..platform import BurnError, Platform, Recorder, Volume
from .anonymize_dialog import AnonymizeDialog
from .tasks import Task, TaskRunner

CD_BYTES = 700 * 1024 * 1024
DVD_BYTES = 4_700_000_000

DEST_DISC, DEST_USB, DEST_ISO, DEST_FOLDER = range(4)

# Aviso da tarefa de que a fase de escrita começou. Daí em diante não há
# cancelamento: interromper o IMAPI2 no meio inutiliza a mídia, e parar a
# cópia no pendrive o deixaria apagado pela metade.
_WRITE_PHASE = "\x00write"


def _zip_available() -> bool:
    try:
        import pyzipper  # noqa: F401
    except ImportError:
        return False
    return True


class BurnDialog(QDialog):
    def __init__(
        self,
        files: list[str],
        patient_names: list[str],
        multiple_patients: bool,
        platform: Platform,
        runner: TaskRunner,
        parent=None,
    ):
        super().__init__(parent)
        self.setWindowTitle("Gravar exames")
        self.setMinimumWidth(560)
        self.files = files
        self.platform = platform
        self.runner = runner
        self.anon_options: AnonymizationOptions | None = None
        self.task: Task | None = None
        self.recorders: list[Recorder] = []
        self.volumes: list[Volume] = []

        self.name = QLineEdit(default_label(patient_names, multiple_patients, False))
        self.name.setMaxLength(15)
        self.name.setToolTip("Até 15 caracteres: letras sem acento, números e _ (limite do Windows/IMAPI2)")
        self.name.editingFinished.connect(lambda: self.name.setText(sanitize_volume_label(self.name.text())))
        self.estimate = QLabel()
        self.final_size = QLabel()

        self.anonymize = QCheckBox("Anonimizar antes de gravar")
        self.anonymize.toggled.connect(self._on_anonymize)
        self.multiple = multiple_patients
        self.patient_names = patient_names

        self.compression = QComboBox()
        self.compression.addItem("Manter como está", KEEP)
        self.compression.addItem("Comprimir (JPEG 2000 sem perdas)", COMPRESS)
        self.compression.addItem("Descomprimir", DECOMPRESS)

        self.include_viewer = QCheckBox("Incluir o visualizador Horus para Windows")
        self.include_viewer.setEnabled(viewer_bundle() is not None)
        self.include_viewer.setChecked(viewer_bundle() is not None)
        if viewer_bundle() is None:
            self.include_viewer.setToolTip("Disponível quando o Horus roda como executável instalado")
        self.include_html = QCheckBox("Incluir página HTML com miniaturas (INDEX.HTM)")
        self.include_html.setChecked(True)
        self.extra = QCheckBox("Incluir pasta suplementar:")
        self.extra_path = QLineEdit()
        extra_btn = QPushButton("…")
        extra_btn.clicked.connect(self._choose_extra)
        self.encrypt = QCheckBox("Criptografar em ZIP com senha (AES-256)")
        self.encrypt.setEnabled(_zip_available())
        self.password = QLineEdit()
        self.password.setEchoMode(QLineEdit.EchoMode.Password)
        self.password.setPlaceholderText("mínimo de 8 caracteres")
        self.password.setEnabled(False)
        self.encrypt.toggled.connect(self.password.setEnabled)
        for w in (self.include_viewer, self.extra, self.anonymize):
            w.toggled.connect(self._update_estimate)

        # destino
        self.dest_group = QButtonGroup(self)
        dest_disc = QRadioButton("CD/DVD")
        dest_usb = QRadioButton("Pendrive")
        dest_iso = QRadioButton("Imagem ISO")
        dest_folder = QRadioButton("Pasta")
        for i, b in enumerate((dest_disc, dest_usb, dest_iso, dest_folder)):
            self.dest_group.addButton(b, i)
        dest_disc.setChecked(True)
        self.dest_group.idToggled.connect(self._on_destination)

        self.recorder_box = QComboBox()
        self.volume_box = QComboBox()
        refresh_rec = QPushButton("Atualizar")
        refresh_rec.clicked.connect(self.refresh_recorders)
        refresh_vol = QPushButton("Atualizar")
        refresh_vol.clicked.connect(self.refresh_volumes)
        self.iso_path = QLineEdit(str(Path.home() / f"{self.name.text()}.iso"))
        iso_btn = QPushButton("…")
        iso_btn.clicked.connect(self._choose_iso)
        self.folder_path = QLineEdit(str(Path.home() / self.name.text()))
        folder_btn = QPushButton("…")
        folder_btn.clicked.connect(self._choose_folder)
        self.eject = QCheckBox("Ejetar ao terminar")
        self.eject.setChecked(True)
        self.dest_hint = QLabel()
        self.dest_hint.setWordWrap(True)
        self.dest_hint.setStyleSheet("color: #e0a040")

        self.progress = QProgressBar()
        self.progress.setVisible(False)
        self.status = QLabel()
        self.status.setWordWrap(True)
        self.burn_btn = QPushButton("Gravar")
        self.burn_btn.setDefault(True)
        self.burn_btn.clicked.connect(self.start)
        self.close_btn = QPushButton("Fechar")
        self.close_btn.clicked.connect(self._close_or_cancel)

        # layout
        content = QFormLayout()
        content.addRow("Nome do disco:", self.name)
        content.addRow("Imagens:", QLabel(f"{len(files)} arquivo(s)"))
        content.addRow("Tamanho estimado:", self.estimate)
        content.addRow("Compressão:", self.compression)
        extras = QVBoxLayout()
        for w in (self.anonymize, self.include_viewer, self.include_html):
            extras.addWidget(w)
        extras.addLayout(self._row(self.extra, self.extra_path, extra_btn))
        extras.addLayout(self._row(self.encrypt, self.password))
        content_box = QGroupBox("Conteúdo")
        inner = QVBoxLayout(content_box)
        inner.addLayout(content)
        inner.addLayout(extras)

        dest_box = QGroupBox("Destino")
        dest = QVBoxLayout(dest_box)
        dest.addLayout(self._row(dest_disc, dest_usb, dest_iso, dest_folder))
        self.disc_row = self._wrap(self._row(QLabel("Gravador:"), self.recorder_box, refresh_rec))
        self.usb_row = self._wrap(self._row(QLabel("Volume:"), self.volume_box, refresh_vol))
        self.iso_row = self._wrap(self._row(QLabel("Arquivo:"), self.iso_path, iso_btn))
        self.folder_row = self._wrap(self._row(QLabel("Pasta:"), self.folder_path, folder_btn))
        for w in (self.disc_row, self.usb_row, self.iso_row, self.folder_row, self.eject, self.dest_hint):
            dest.addWidget(w)

        layout = QVBoxLayout(self)
        layout.addWidget(content_box)
        layout.addWidget(dest_box)
        layout.addWidget(self.final_size)
        layout.addWidget(self.progress)
        layout.addWidget(self.status)
        layout.addLayout(self._row(QWidget(), self.close_btn, self.burn_btn, stretch_first=True))

        self._update_estimate()
        self._on_destination(DEST_DISC, True)
        self.refresh_recorders()

    # ------------------------------------------------------------ apoio

    @staticmethod
    def _row(*widgets, stretch_first: bool = False) -> QHBoxLayout:
        row = QHBoxLayout()
        for i, w in enumerate(widgets):
            if isinstance(w, QHBoxLayout):
                row.addLayout(w)
            else:
                row.addWidget(w, 1 if (stretch_first and i == 0) or isinstance(w, (QLineEdit, QComboBox)) else 0)
        return row

    @staticmethod
    def _wrap(layout) -> QWidget:
        w = QWidget()
        layout.setContentsMargins(0, 0, 0, 0)
        w.setLayout(layout)
        return w

    def _options(self) -> DiscOptions:
        return DiscOptions(
            label=self.name.text(),
            anonymize=self.anon_options if self.anonymize.isChecked() else None,
            compression=self.compression.currentData(),
            include_viewer=self.include_viewer.isChecked() and self.include_viewer.isEnabled(),
            include_html=self.include_html.isChecked(),
            supplementary_dir=Path(self.extra_path.text()) if self.extra.isChecked() and self.extra_path.text() else None,
            zip_password=self.password.text() if self.encrypt.isChecked() else None,
        )

    def _update_estimate(self) -> None:
        size = estimate_size(self.files, self._options())
        media = "cabe em CD" if size <= CD_BYTES else ("requer DVD" if size <= DVD_BYTES else "maior que um DVD")
        self.estimate.setText(f"{size / 1e6:.1f} MB ({media})")

    def _on_anonymize(self, on: bool) -> None:
        if on:
            dialog = AnonymizeDialog(self, self.anon_options)
            if dialog.exec() != QDialog.DialogCode.Accepted:
                self.anonymize.setChecked(False)
                return
            self.anon_options = dialog.options()
        # Regra do Horos: disco anonimizado recebe o rótulo de arquivo.
        self.name.setText(default_label(self.patient_names, self.multiple, on))

    def _on_destination(self, button_id: int, checked: bool) -> None:
        if not checked:
            return
        self.disc_row.setVisible(button_id == DEST_DISC)
        self.usb_row.setVisible(button_id == DEST_USB)
        self.iso_row.setVisible(button_id == DEST_ISO)
        self.folder_row.setVisible(button_id == DEST_FOLDER)
        self.eject.setVisible(button_id in (DEST_DISC, DEST_USB))
        self.dest_hint.setText("")
        if button_id == DEST_USB and not self.volumes:
            self.refresh_volumes()
        if button_id == DEST_DISC and self.platform.recorder_error:
            self.dest_hint.setText(self.platform.recorder_error)

    def _choose_extra(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Pasta suplementar")
        if path:
            self.extra_path.setText(path)
            self.extra.setChecked(True)

    def _choose_iso(self) -> None:
        path, _ = QFileDialog.getSaveFileName(self, "Salvar imagem ISO", self.iso_path.text(), "Imagem de disco (*.iso)")
        if path:
            self.iso_path.setText(path if path.lower().endswith(".iso") else path + ".iso")

    def _choose_folder(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Pasta de destino")
        if path:
            self.folder_path.setText(str(Path(path) / self.name.text()))

    # ------------------------------------------------- dispositivos

    def refresh_recorders(self) -> None:
        self.recorder_box.clear()
        self.recorder_box.addItem("Procurando gravadores…")
        self.recorder_box.setEnabled(False)

        def done(recorders: list[Recorder]) -> None:
            self.recorders = recorders
            self.recorder_box.clear()
            for r in recorders:
                self.recorder_box.addItem(r.describe())
            if not recorders:
                self.recorder_box.addItem("Nenhum gravador encontrado")
            self.recorder_box.setEnabled(bool(recorders))
            if self.dest_group.checkedId() == DEST_DISC:
                self.dest_hint.setText(self.platform.recorder_error)

        self.runner.start(lambda task: self.platform.list_recorders(), on_done=done, on_error=lambda m: done([]))

    def refresh_volumes(self) -> None:
        self.volume_box.clear()
        try:
            self.volumes = self.platform.list_removable_volumes()
        except Exception as exc:
            self.volumes = []
            self.dest_hint.setText(f"Não foi possível listar os volumes: {exc}")
        for v in self.volumes:
            self.volume_box.addItem(v.describe())
        if not self.volumes:
            self.volume_box.addItem("Nenhum pendrive encontrado")
        self.volume_box.setEnabled(bool(self.volumes))

    # ------------------------------------------------------- gravação

    def _close_or_cancel(self) -> None:
        if self.task is not None:
            self.task.cancel_requested = True
            self.status.setText("Cancelando…")
        else:
            self.reject()

    def closeEvent(self, event) -> None:
        if self.task is not None:
            # Como o Horos (validateMenuItem bloqueia o "Sair" durante a
            # gravação): não se fecha a janela no meio de uma gravação.
            event.ignore()
            return
        super().closeEvent(event)

    def start(self) -> None:
        options = self._options()
        dest = self.dest_group.checkedId()
        if options.zip_password is not None and len(options.zip_password) < 8:
            QMessageBox.warning(self, "Gravar", "A senha precisa ter ao menos 8 caracteres.")
            return
        recorder = volume = None
        target: Path | None = None
        if dest == DEST_DISC:
            if not self.recorders:
                QMessageBox.warning(self, "Gravar", "Nenhum gravador de CD/DVD disponível. Grave uma imagem ISO.")
                return
            recorder = self.recorders[self.recorder_box.currentIndex()]
        elif dest == DEST_USB:
            if not self.volumes:
                QMessageBox.warning(self, "Gravar", "Nenhum pendrive selecionado.")
                return
            volume = self.volumes[self.volume_box.currentIndex()]
            answer = QMessageBox.warning(
                self,
                "Gravar no pendrive",
                f"TODO o conteúdo de {volume.describe()} será apagado antes da gravação.\n\nConfirma?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
                QMessageBox.StandardButton.Cancel,
            )
            if answer != QMessageBox.StandardButton.Yes:
                return
        elif dest == DEST_ISO:
            target = Path(self.iso_path.text())
        else:
            target = Path(self.folder_path.text())
            if target.exists() and any(target.iterdir()):
                QMessageBox.warning(self, "Gravar", f"A pasta {target} já existe e não está vazia.")
                return

        eject = self.eject.isChecked()
        staging = paths.temp_dir()
        fallback: list[Path] = []

        def job(task: Task):
            def step(message: str, done: int, total: int) -> None:
                task.report(message, done, total)

            def event(message: str, fraction: float | None) -> None:
                task.report(message, int((fraction or 0) * 1000), 1000 if fraction is not None else 0)

            prepared = prepare_disc(self.files, options, staging, step, task.cancelled)
            task.report(f"Tamanho final: {prepared.size_bytes / 1e6:.1f} MB", 0, 0)
            if task.cancelled():
                shutil.rmtree(prepared.folder, ignore_errors=True)
                raise Cancelled()
            task.report(_WRITE_PHASE, 0, 0)
            warnings = list(prepared.warnings)
            if dest == DEST_DISC:
                burn_disc(prepared, recorder, self.platform, event, staging, eject, on_fallback=fallback.append)
            elif dest == DEST_USB:
                warnings += write_usb(prepared, volume, self.platform, event, eject)
            elif dest == DEST_ISO:
                write_iso(prepared, target, event)
            else:
                task.report("Copiando para a pasta", 0, 0)
                shutil.copytree(prepared.folder, target, dirs_exist_ok=True)
            shutil.rmtree(prepared.folder, ignore_errors=True)
            return prepared, warnings

        self._set_busy(True)
        self.task = self.runner.start(job, on_done=lambda r: self._finished(r, dest, target, fallback), on_error=self._failed, on_progress=self._progress)

    def _set_busy(self, busy: bool) -> None:
        self.burn_btn.setEnabled(not busy)
        self.close_btn.setEnabled(True)
        self.close_btn.setText("Cancelar" if busy else "Fechar")
        self.progress.setVisible(busy)
        for w in self.findChildren(QGroupBox):
            w.setEnabled(not busy)

    def _progress(self, message: str, done: int, total: int) -> None:
        if message == _WRITE_PHASE:
            self.close_btn.setEnabled(False)
            return
        if message.startswith("Tamanho final"):
            self.final_size.setText(message)
            return
        self.status.setText(message)
        if total:
            self.progress.setRange(0, total)
            self.progress.setValue(done)
        else:
            self.progress.setRange(0, 0)  # indeterminado (IMAPI2 gravando)

    def _finished(self, result, dest: int, target: Path | None, fallback: list[Path]) -> None:
        self.task = None
        self._set_busy(False)
        prepared, warnings = result
        if fallback:
            text = (
                "O gravador do Windows não pôde ser acionado diretamente; a imagem\n"
                f"{fallback[0]}\nfoi aberta no Gravador de Imagem de Disco do Windows."
            )
        elif dest == DEST_ISO:
            text = f"Imagem gravada em {target}."
        elif dest == DEST_FOLDER:
            text = f"Conteúdo copiado para {target}."
        else:
            text = "Gravação concluída."
        if warnings:
            text += "\n\nAvisos:\n- " + "\n- ".join(warnings)
        self.status.setText("Concluído.")
        QMessageBox.information(self, "Gravar", text)
        if not warnings:
            self.accept()

    def _failed(self, message: str) -> None:
        cancelled = self.task is not None and self.task.cancel_requested
        self.task = None
        self._set_busy(False)
        if cancelled:
            self.status.setText("Gravação cancelada.")
            return
        self.status.setText("")
        QMessageBox.critical(self, "Falha na gravação", message)


__all__ = ["BurnDialog", "BurnError", "Cancelled"]
