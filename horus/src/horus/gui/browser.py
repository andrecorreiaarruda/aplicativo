"""Janela principal — equivalente ao BrowserController do Horos.

Lista de exames da base (outline de estudos com as séries como filhas),
miniaturas das séries do exame selecionado (BrowserMatrix) e as ações do
menu do Horos: importar, abrir, gravar (burnDICOM:), anonimizar
(anonymizeDICOM:) e excluir.
"""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QSize, Qt, QTimer
from PySide6.QtGui import QAction, QDragEnterEvent, QDropEvent, QIcon, QKeySequence, QPixmap
from PySide6.QtWidgets import (
    QAbstractItemView,
    QFileDialog,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QProgressBar,
    QSplitter,
    QStyle,
    QToolBar,
    QTreeWidget,
    QTreeWidgetItem,
)

from .. import APP_NAME, __version__, paths
from ..anonymize import Anonymizer
from ..database import Database, SeriesRow, StudyRow
from ..dicom.thumbnail import series_thumbnail_png
from ..platform import Platform
from .anonymize_dialog import AnonymizeDialog
from .burner import BurnDialog
from .tasks import Task, TaskRunner
from .viewer import SeriesEntry, ViewerWindow

ROLE_KIND = Qt.ItemDataRole.UserRole
ROLE_ID = Qt.ItemDataRole.UserRole + 1


def _date(value: str) -> str:
    return f"{value[6:8]}/{value[4:6]}/{value[:4]}" if len(value) == 8 and value.isdigit() else value


def _series_title(s: SeriesRow) -> str:
    number = "" if s.series_number is None else str(s.series_number)
    return f"{s.modality} {number}\n{s.series_description}\n{s.number_of_images} img".strip()


class BrowserWindow(QMainWindow):
    def __init__(self, database: Database, platform: Platform, disc_mode: bool = False):
        super().__init__()
        self.db = database
        self.platform = platform
        self.disc_mode = disc_mode
        self.runner = TaskRunner()
        self.viewers: list[ViewerWindow] = []
        self.setWindowTitle(f"{APP_NAME} {__version__}" + (" — disco" if disc_mode else ""))
        self.resize(1180, 760)
        self.setAcceptDrops(True)

        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["Paciente", "ID", "Nascimento", "Data do exame", "Descrição", "Modalidade", "Imagens"])
        self.tree.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.tree.setAlternatingRowColors(True)
        self.tree.setUniformRowHeights(True)
        self.tree.header().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.tree.itemSelectionChanged.connect(self._on_selection)
        self.tree.itemDoubleClicked.connect(lambda *_: self.open_viewer())
        self.tree.itemExpanded.connect(self._fill_series)

        self.thumbs = QListWidget()
        self.thumbs.setViewMode(QListWidget.ViewMode.IconMode)
        self.thumbs.setIconSize(QSize(128, 128))
        self.thumbs.setResizeMode(QListWidget.ResizeMode.Adjust)
        self.thumbs.setMovement(QListWidget.Movement.Static)
        self.thumbs.setSpacing(8)
        self.thumbs.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.thumbs.itemDoubleClicked.connect(self._open_from_thumb)

        splitter = QSplitter(Qt.Orientation.Vertical)
        splitter.addWidget(self.tree)
        splitter.addWidget(self.thumbs)
        splitter.setSizes([460, 260])
        self.setCentralWidget(splitter)

        self._build_actions()
        self.progress = QProgressBar()
        self.progress.setMaximumWidth(220)
        self.progress.setVisible(False)
        self.summary = QLabel()
        self.statusBar().addPermanentWidget(self.summary)
        self.statusBar().addPermanentWidget(self.progress)
        self._search_timer = QTimer(self, singleShot=True, interval=250)
        self._search_timer.timeout.connect(self.refresh)
        self.refresh()

    # --------------------------------------------------------- ações

    def _build_actions(self) -> None:
        style = self.style()
        bar = QToolBar("Principal")
        bar.setMovable(False)
        bar.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextUnderIcon)
        self.addToolBar(bar)

        def action(text, icon, slot, shortcut=None, tip=None):
            act = QAction(style.standardIcon(icon), text, self)
            act.triggered.connect(slot)
            if shortcut:
                act.setShortcut(QKeySequence(shortcut))
            act.setToolTip(tip or text)
            bar.addAction(act)
            return act

        SP = QStyle.StandardPixmap
        self.act_import = action("Importar", SP.SP_DialogOpenButton, self.import_files, QKeySequence.StandardKey.Open, "Importar arquivos DICOM para a base")
        self.act_folder = action("Importar pasta", SP.SP_DirOpenIcon, self.import_folder, "Ctrl+Shift+O", "Importar uma pasta, CD ou DVD (com ou sem DICOMDIR)")
        self.act_view = action("Visualizar", SP.SP_FileDialogContentsView, self.open_viewer, "Return", "Abrir as séries selecionadas")
        bar.addSeparator()
        self.act_burn = action("Gravar", SP.SP_DriveCDIcon, self.burn, "Ctrl+B", "Gravar em CD/DVD, pendrive ou imagem ISO")
        self.act_anon = action("Anonimizar", SP.SP_FileDialogDetailedView, self.anonymize, None, "Criar cópias anonimizadas na base")
        self.act_delete = action("Excluir", SP.SP_TrashIcon, self.delete, QKeySequence.StandardKey.Delete, "Excluir da base")
        bar.addSeparator()
        self.search = QLineEdit()
        self.search.setPlaceholderText("Pesquisar paciente, ID, descrição, nº de acesso…")
        self.search.setClearButtonEnabled(True)
        self.search.setMaximumWidth(340)
        self.search.textChanged.connect(lambda _t: self._search_timer.start())
        bar.addWidget(self.search)
        if self.disc_mode:
            self.act_delete.setVisible(False)
            self.act_anon.setVisible(False)

        menu = self.menuBar().addMenu("&Arquivo")
        for act in (self.act_import, self.act_folder, self.act_view, self.act_burn, self.act_anon, self.act_delete):
            menu.addAction(act)
        menu.addSeparator()
        open_base = QAction("Abrir pasta da base", self)
        open_base.triggered.connect(lambda: self.platform.open_folder(self.db.base_dir))
        menu.addAction(open_base)
        quit_act = QAction("Sair", self)
        quit_act.setShortcut(QKeySequence.StandardKey.Quit)
        quit_act.triggered.connect(self.close)
        menu.addAction(quit_act)
        help_menu = self.menuBar().addMenu("A&juda")
        about = QAction("Sobre", self)
        about.triggered.connect(self._about)
        help_menu.addAction(about)

    def _about(self) -> None:
        QMessageBox.about(
            self,
            f"Sobre o {APP_NAME}",
            f"<b>{APP_NAME} {__version__}</b><br>Visualizador e gravador DICOM.<br><br>"
            "Inspirado no Horos (horosproject.org), reimplementado em Python/Qt para Windows.<br>"
            f"Base local: {self.db.base_dir}<br><br>"
            "Não é um dispositivo médico certificado; não use para diagnóstico primário.",
        )

    # ------------------------------------------------------ listagem

    def refresh(self) -> None:
        expanded = {
            self.tree.topLevelItem(i).data(0, ROLE_ID)
            for i in range(self.tree.topLevelItemCount())
            if self.tree.topLevelItem(i).isExpanded()
        }
        self.tree.clear()
        studies = self.db.studies(self.search.text())
        for st in studies:
            item = QTreeWidgetItem(
                [st.patient_name or "(sem nome)", st.patient_id, _date(st.patient_birth_date), _date(st.study_date), st.study_description, st.modalities.replace("\\", "/"), str(st.number_of_images)]
            )
            item.setData(0, ROLE_KIND, "study")
            item.setData(0, ROLE_ID, st.id)
            item.setChildIndicatorPolicy(QTreeWidgetItem.ChildIndicatorPolicy.ShowIndicator)
            self.tree.addTopLevelItem(item)
            if st.id in expanded:
                item.setExpanded(True)
        for col in range(1, 7):
            self.tree.resizeColumnToContents(col)
        total = sum(s.number_of_images for s in studies)
        self.summary.setText(f"{len(studies)} exame(s), {total} imagem(ns)")
        self._on_selection()

    def _fill_series(self, item: QTreeWidgetItem) -> None:
        if item.data(0, ROLE_KIND) != "study" or item.childCount():
            return
        for s in self.db.series_for_study(item.data(0, ROLE_ID)):
            number = s.series_number if s.series_number is not None else "?"
            child = QTreeWidgetItem([f"Série {number} — {s.series_description}", "", "", "", "", s.modality, str(s.number_of_images)])
            child.setData(0, ROLE_KIND, "series")
            child.setData(0, ROLE_ID, s.id)
            item.addChild(child)

    def selection(self) -> tuple[list[int], list[int]]:
        """(exames, séries) selecionados na árvore ou nas miniaturas."""
        studies, series = [], []
        for item in self.tree.selectedItems():
            (studies if item.data(0, ROLE_KIND) == "study" else series).append(item.data(0, ROLE_ID))
        for item in self.thumbs.selectedItems():
            series.append(item.data(ROLE_ID))
        return studies, series

    def _current_study(self) -> StudyRow | None:
        item = self.tree.currentItem()
        if item is None:
            return None
        if item.data(0, ROLE_KIND) == "series":
            item = item.parent()
        return self.db.study(item.data(0, ROLE_ID))

    def _on_selection(self) -> None:
        studies, series = self.selection()
        has = bool(studies or series)
        for act in (self.act_view, self.act_burn, self.act_anon, self.act_delete):
            act.setEnabled(has)
        study = self._current_study()
        self.thumbs.clear()
        if study is None:
            return
        pending = []
        for s in self.db.series_for_study(study.id):
            item = QListWidgetItem(_series_title(s))
            item.setData(ROLE_ID, s.id)
            item.setTextAlignment(Qt.AlignmentFlag.AlignHCenter)
            png = self.db.thumbnail(s.id)
            if png:
                item.setIcon(self._icon(png))
            else:
                item.setIcon(self.style().standardIcon(QStyle.StandardPixmap.SP_FileIcon))
                pending.append(s.id)
            self.thumbs.addItem(item)
        if pending:
            self.runner.start(self._make_thumbnails, pending, on_done=self._thumbnails_ready)

    @staticmethod
    def _icon(png: bytes) -> QIcon:
        pix = QPixmap()
        pix.loadFromData(png, "PNG")
        return QIcon(pix)

    def _make_thumbnails(self, task: Task, series_ids: list[int]) -> dict[int, bytes]:
        done = {}
        for sid in series_ids:
            images = self.db.images_for_series(sid)
            if not images:
                continue
            try:
                png = series_thumbnail_png([i.path for i in images])
            except Exception:
                continue
            self.db.set_thumbnail(sid, png)
            done[sid] = png
        return done

    def _thumbnails_ready(self, done: dict[int, bytes]) -> None:
        for row in range(self.thumbs.count()):
            item = self.thumbs.item(row)
            png = done.get(item.data(ROLE_ID))
            if png:
                item.setIcon(self._icon(png))

    # ------------------------------------------------------ importação

    def import_files(self) -> None:
        files, _ = QFileDialog.getOpenFileNames(self, "Importar arquivos DICOM", "", "DICOM (*.dcm *.dicom *.ima DICOMDIR);;Todos os arquivos (*)")
        if files:
            self.import_paths(files)

    def import_folder(self) -> None:
        folder = QFileDialog.getExistingDirectory(self, "Importar pasta, CD ou DVD")
        if folder:
            self.import_paths([folder])

    def import_paths(self, sources: list[str], copy: bool = True) -> None:
        self.progress.setVisible(True)
        self.progress.setRange(0, 0)

        def job(task: Task):
            return self.db.add_files(sources, copy=copy, progress=lambda n, p: task.report(Path(p).name, n, 0), cancelled=task.cancelled)

        def done(result) -> None:
            self.progress.setVisible(False)
            self.refresh()
            msg = f"{result.added} imagem(ns) importada(s)"
            if result.duplicates:
                msg += f", {result.duplicates} já estava(m) na base"
            if result.errors:
                msg += f", {len(result.errors)} arquivo(s) com erro"
            self.statusBar().showMessage(msg, 10000)
            if result.errors and not result.added:
                QMessageBox.warning(self, "Importar", msg + ":\n\n" + "\n".join(f"{Path(p).name}: {e}" for p, e in result.errors[:10]))

        def failed(message: str) -> None:
            self.progress.setVisible(False)
            QMessageBox.critical(self, "Importar", message)

        self.runner.start(job, on_done=done, on_error=failed, on_progress=lambda m, n, _t: self.statusBar().showMessage(f"Importando {n}: {m}"))

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event: QDropEvent) -> None:
        paths_ = [u.toLocalFile() for u in event.mimeData().urls() if u.isLocalFile()]
        if paths_:
            self.import_paths(paths_)

    # --------------------------------------------------- visualização

    def _entries_for(self, study_id: int) -> list[SeriesEntry]:
        entries = []
        for s in self.db.series_for_study(study_id):
            images = self.db.images_for_series(s.id)
            if images:
                entries.append(SeriesEntry(_series_title(s), [i.path for i in images], self.db.thumbnail(s.id)))
        return entries

    def open_viewer(self, series_id: int | None = None) -> None:
        studies, series = self.selection()
        if series_id is not None:
            series = [series_id]
        if series:
            target_series = series[0]
            row = self.db.series(target_series)
            study_id = row.study_id if row else None
        elif studies:
            study_id, target_series = studies[0], None
        else:
            return
        if study_id is None:
            return
        study = self.db.study(study_id)
        entries = self._entries_for(study_id)
        if not entries:
            return
        ids = [s.id for s in self.db.series_for_study(study_id) if self.db.images_for_series(s.id)]
        start = ids.index(target_series) if target_series in ids else 0
        title = f"{study.patient_name} — {study.study_description} ({_date(study.study_date)})" if study else ""
        viewer = ViewerWindow(entries, start, title)
        viewer.destroyed.connect(lambda *_: self.viewers.remove(viewer) if viewer in self.viewers else None)
        self.viewers.append(viewer)
        viewer.show()

    def _open_from_thumb(self, item: QListWidgetItem) -> None:
        self.open_viewer(item.data(ROLE_ID))

    # ------------------------------------------------------ gravação

    def burn(self) -> None:
        studies, series = self.selection()
        images = self.db.images_for(studies, series)
        if not images:
            return
        patients = self.db.patient_uids_for(images)
        names = []
        for sid in studies or [self.db.series(series[0]).study_id]:
            st = self.db.study(sid)
            if st:
                names.append(st.patient_name)
        dialog = BurnDialog([i.path for i in images], names, len(patients) > 1, self.platform, self.runner, self)
        dialog.exec()

    # --------------------------------------------------- anonimização

    def anonymize(self) -> None:
        studies, series = self.selection()
        images = self.db.images_for(studies, series)
        if not images:
            return
        dialog = AnonymizeDialog(self)
        if dialog.exec() != AnonymizeDialog.DialogCode.Accepted:
            return
        options = dialog.options()
        out_dir = paths.temp_dir() / "anonimizados"

        def job(task: Task):
            import shutil

            shutil.rmtree(out_dir, ignore_errors=True)
            produced = Anonymizer(options).anonymize_files(
                [i.path for i in images], out_dir, progress=lambda n, _p: task.report("Anonimizando", n, len(images)), cancelled=task.cancelled
            )
            result = self.db.add_files([str(p) for p in produced.values()], copy=True)
            shutil.rmtree(out_dir, ignore_errors=True)
            return result

        self.progress.setVisible(True)

        def progress(_m, n, total):
            self.progress.setRange(0, total)
            self.progress.setValue(n)

        def done(result):
            self.progress.setVisible(False)
            self.refresh()
            self.statusBar().showMessage(f"{result.added} imagem(ns) anonimizada(s) adicionada(s) à base", 10000)

        def failed(message):
            self.progress.setVisible(False)
            QMessageBox.critical(self, "Anonimizar", message)

        self.runner.start(job, on_done=done, on_error=failed, on_progress=progress)

    # -------------------------------------------------------- exclusão

    def delete(self) -> None:
        studies, series = self.selection()
        if not (studies or series):
            return
        answer = QMessageBox.question(
            self,
            "Excluir",
            f"Excluir {len(studies)} exame(s) e {len(series)} série(s) da base?\n"
            "Os arquivos copiados para a base também serão apagados.",
        )
        if answer == QMessageBox.StandardButton.Yes:
            self.db.delete(studies, series)
            self.refresh()

    def closeEvent(self, event) -> None:
        for viewer in list(self.viewers):
            viewer.close()
        super().closeEvent(event)
