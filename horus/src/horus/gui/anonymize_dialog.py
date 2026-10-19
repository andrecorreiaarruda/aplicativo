"""Opções de anonimização (AnonymizationPanelController no Horos)."""

from __future__ import annotations

from PySide6.QtWidgets import QCheckBox, QDialog, QDialogButtonBox, QFormLayout, QLabel, QLineEdit, QVBoxLayout

from ..anonymize import AnonymizationOptions


class AnonymizeDialog(QDialog):
    def __init__(self, parent=None, options: AnonymizationOptions | None = None):
        super().__init__(parent)
        self.setWindowTitle("Anonimização")
        opts = options or AnonymizationOptions()
        self.name = QLineEdit(opts.patient_name)
        self.patient_id = QLineEdit(opts.patient_id or "")
        self.patient_id.setPlaceholderText("gerado automaticamente")
        self.keep_dates = QCheckBox("Manter datas do exame")
        self.keep_dates.setChecked(opts.keep_dates)
        self.keep_sex_age = QCheckBox("Manter sexo, idade, peso e altura")
        self.keep_sex_age.setChecked(opts.keep_sex_and_age)
        self.keep_desc = QCheckBox("Manter descrições de exame e série")
        self.keep_desc.setChecked(opts.keep_descriptions)
        self.remove_private = QCheckBox("Remover atributos privados de fabricante")
        self.remove_private.setChecked(opts.remove_private_tags)

        form = QFormLayout()
        form.addRow("Nome do paciente:", self.name)
        form.addRow("ID do paciente:", self.patient_id)
        note = QLabel(
            "Sempre removidos: data de nascimento, endereço, telefones, nº de acesso, "
            "médicos, operadores, instituição e equipamento. Os UIDs são substituídos.\n"
            "Texto gravado dentro da imagem (comum em ultrassom e capturas de tela) "
            "não é removido."
        )
        note.setWordWrap(True)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout = QVBoxLayout(self)
        layout.addLayout(form)
        for w in (self.keep_dates, self.keep_sex_age, self.keep_desc, self.remove_private, note, buttons):
            layout.addWidget(w)

    def options(self) -> AnonymizationOptions:
        return AnonymizationOptions(
            patient_name=self.name.text().strip() or "ANONIMO",
            patient_id=self.patient_id.text().strip() or None,
            keep_sex_and_age=self.keep_sex_age.isChecked(),
            keep_dates=self.keep_dates.isChecked(),
            keep_descriptions=self.keep_desc.isChecked(),
            remove_private_tags=self.remove_private.isChecked(),
        )
