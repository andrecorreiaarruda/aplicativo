"""Consulta da base local para o C-FIND e seleção de arquivos para C-MOVE/C-GET.

Quando outro equipamento consulta o Horos, o `dcmqrdbq.mm` modificado traduz
o identificador DICOM para uma busca na base Core Data. Aqui a tradução é
para SQL sobre a mesma base SQLite do navegador, seguindo as regras de
correspondência do PS3.4 (anexo C.2.2.2):

* valor vazio: correspondência universal (o atributo só é devolvido);
* valor único: igualdade exata — nomes de pessoa (PN) sem distinção de
  maiúsculas, como a maioria dos PACS faz;
* `*` e `?`: curingas, só nos tipos de texto (AE, CS, LO, PN, SH...);
* `inicio-fim` em datas e horas (DA, TM, DT), com qualquer lado aberto;
* lista de UIDs separada por `\\`: qualquer um deles.

Chaves de níveis abaixo do nível consultado (por exemplo `Modality` numa
consulta de estudo) não filtram: são devolvidas vazias. Muitos clientes as
enviam por hábito, e recusar a consulta inteira por isso só atrapalharia.
"""

from __future__ import annotations

import re
from collections.abc import Iterator
from dataclasses import dataclass

from pydicom.datadict import dictionary_VR
from pydicom.dataset import Dataset
from pydicom.multival import MultiValue

from ..database import Database, fold_text

LEVELS = ("PATIENT", "STUDY", "SERIES", "IMAGE")

# Modelos de informação de Q/R.
PATIENT_ROOT = "PATIENT"
STUDY_ROOT = "STUDY"

_TEXT_VRS = {"AE", "CS", "LO", "LT", "PN", "SH", "ST", "UC", "UR", "UT"}
_RANGE_VRS = {"DA", "TM", "DT"}

# atributo → (nível, expressão SQL, VR). As expressões usam os apelidos
# st (study), se (series) e im (image).
_NAME = "COALESCE(NULLIF(st.patient_name_raw, ''), st.patient_name)"
_REFERRING = "COALESCE(NULLIF(st.referring_physician_raw, ''), st.referring_physician)"
ATTRIBUTES: dict[str, tuple[str, str, str]] = {
    "PatientName": ("PATIENT", _NAME, "PN"),
    "PatientID": ("PATIENT", "st.patient_id", "LO"),
    "PatientBirthDate": ("PATIENT", "st.patient_birth_date", "DA"),
    "PatientSex": ("PATIENT", "st.patient_sex", "CS"),
    "StudyInstanceUID": ("STUDY", "st.study_instance_uid", "UI"),
    "StudyDate": ("STUDY", "st.study_date", "DA"),
    "StudyTime": ("STUDY", "st.study_time", "TM"),
    "AccessionNumber": ("STUDY", "st.accession_number", "SH"),
    "StudyID": ("STUDY", "st.dicom_study_id", "SH"),
    "StudyDescription": ("STUDY", "st.study_description", "LO"),
    "ReferringPhysicianName": ("STUDY", _REFERRING, "PN"),
    "InstitutionName": ("STUDY", "st.institution_name", "LO"),
    "SeriesInstanceUID": ("SERIES", "se.series_instance_uid", "UI"),
    "Modality": ("SERIES", "se.modality", "CS"),
    "SeriesNumber": ("SERIES", "se.series_number", "IS"),
    "SeriesDescription": ("SERIES", "se.series_description", "LO"),
    "SeriesDate": ("SERIES", "se.series_date", "DA"),
    "SeriesTime": ("SERIES", "se.series_time", "TM"),
    "BodyPartExamined": ("SERIES", "se.body_part", "CS"),
    "SOPInstanceUID": ("IMAGE", "im.sop_instance_uid", "UI"),
    "SOPClassUID": ("IMAGE", "im.sop_class_uid", "UI"),
    "InstanceNumber": ("IMAGE", "im.instance_number", "IS"),
    "NumberOfFrames": ("IMAGE", "im.number_of_frames", "IS"),
}

# Contagens que o SCP calcula (PS3.4 C.3); não servem para filtrar.
_COUNTS = {
    "NumberOfPatientRelatedStudies": ("PATIENT", "COUNT(DISTINCT st.id)"),
    "NumberOfPatientRelatedSeries": ("PATIENT", "(SELECT COUNT(*) FROM series s2 JOIN study t2 ON s2.study_id = t2.id WHERE t2.patient_id = st.patient_id)"),
    "NumberOfPatientRelatedInstances": ("PATIENT", "(SELECT COUNT(*) FROM image i2 JOIN series s2 ON i2.series_id = s2.id JOIN study t2 ON s2.study_id = t2.id WHERE t2.patient_id = st.patient_id)"),
    "NumberOfStudyRelatedSeries": ("STUDY", "(SELECT COUNT(*) FROM series s2 WHERE s2.study_id = st.id)"),
    "NumberOfStudyRelatedInstances": ("STUDY", "(SELECT COUNT(*) FROM image i2 JOIN series s2 ON i2.series_id = s2.id WHERE s2.study_id = st.id)"),
    "NumberOfSeriesRelatedInstances": ("SERIES", "(SELECT COUNT(*) FROM image i2 WHERE i2.series_id = se.id)"),
}

_FROM = {
    "PATIENT": "FROM study st",
    "STUDY": "FROM study st",
    "SERIES": "FROM series se JOIN study st ON se.study_id = st.id",
    "IMAGE": "FROM image im JOIN series se ON im.series_id = se.id JOIN study st ON se.study_id = st.id",
}


class QueryError(ValueError):
    """Identificador inválido; vira status de falha no C-FIND/C-MOVE/C-GET."""


@dataclass(frozen=True)
class RetrieveItem:
    path: str
    sop_class_uid: str
    sop_instance_uid: str
    transfer_syntax_uid: str


def _values(value) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple, MultiValue)):
        return [str(v) for v in value if str(v) != ""]
    text = str(value)
    return [text] if text != "" else []


def _like(pattern: str) -> str:
    """Curinga DICOM → padrão LIKE, escapando os curingas do SQL."""
    out = []
    for ch in pattern:
        if ch == "*":
            out.append("%")
        elif ch == "?":
            out.append("_")
        elif ch in "%_\\":
            out.append("\\" + ch)
        else:
            out.append(ch)
    return "".join(out)


def _folded_like(pattern: str) -> str:
    return _like(fold_text(pattern))


def _name_clause(expr: str, text: str) -> tuple[str, list] | None:
    """Nome de pessoa como o Horos busca (patientsnamePredicate).

    Sem curinga interno, o valor é quebrado em palavras (por `^`, vírgula
    ou espaço): a primeira tem de abrir o nome e as demais aparecer em
    qualquer ponto, sem acentos nem maiúsculas — "silva" encontra
    "SILVA^JOAO" e "silva maria" encontra "SILVA^ANA MARIA". Um `*` no
    começo libera também a primeira palavra. Com `?` ou `*` no meio do
    valor, vale o curinga DICOM sobre o nome inteiro.
    """
    inner = text.strip("*")
    if "?" in text or "*" in inner:
        return f"horus_fold({expr}) LIKE ? ESCAPE '\\'", [_folded_like(text)]
    words = [w for w in re.split(r"[\^,\s]+", inner) if w]
    if not words:
        return None
    conds, args = [], []
    for i, word in enumerate(words):
        prefix = "" if (i == 0 and not text.startswith("*")) else "%"
        conds.append(f"horus_fold(REPLACE({expr}, '^', ' ')) LIKE ? ESCAPE '\\'")
        args.append(prefix + _like(fold_text(word)) + "%")
    return "(" + " AND ".join(conds) + ")", args


def match_clause(expr: str, vr: str, value) -> tuple[str, list] | None:
    """Condição SQL para uma chave de busca; None = correspondência universal."""
    values = _values(value)
    if not values or (len(values) == 1 and set(values[0]) == {"*"}):
        return None
    if vr == "UI":
        marks = ",".join("?" * len(values))
        return f"{expr} IN ({marks})", values
    if len(values) > 1:
        # Valor múltiplo fora de UID (ex.: "CT\\MR" num CS): qualquer um.
        parts, args = [], []
        for v in values:
            clause = match_clause(expr, vr, v)
            if clause:
                parts.append(clause[0])
                args.extend(clause[1])
        return "(" + " OR ".join(parts) + ")", args
    text = values[0]
    if vr in _RANGE_VRS and "-" in text:
        low, _, high = text.partition("-")
        conds, args = [], []
        if low:
            conds.append(f"{expr} >= ?")
            args.append(low)
        if high:
            # Hora "1100" como limite superior inclui 11:00:59.999 — o
            # prefixo vale como o minuto inteiro (PS3.4 C.2.2.2.5).
            conds.append(f"SUBSTR({expr}, 1, ?) <= ?")
            args.extend([len(high), high])
        # Valor vazio na base não está dentro de nenhuma faixa.
        conds.append(f"{expr} <> ''")
        return "(" + " AND ".join(conds) + ")", args
    if vr == "IS":
        try:
            return f"{expr} = ?", [int(text)]
        except ValueError as exc:
            raise QueryError(f"valor inteiro inválido: {text!r}") from exc
    if vr == "PN":
        return _name_clause(expr, text)
    if vr in _TEXT_VRS:
        # Texto: sem acentos nem maiúsculas, como no Horos; curingas DICOM.
        if "*" in text or "?" in text:
            return f"horus_fold({expr}) LIKE ? ESCAPE '\\'", [_folded_like(text)]
        return f"horus_fold({expr}) = ?", [fold_text(text)]
    if vr in ("TM", "DT"):
        # Hora (ou data e hora) exata casa pelo prefixo: "1015" é o minuto
        # inteiro, e "101500" também casa com "101500.250". (No Horos a
        # comparação exata de hora não funciona — compara um número com
        # outro em escala diferente.)
        return f"SUBSTR({expr}, 1, ?) = ?", [len(text), text]
    return f"{expr} = ?", [text]


def _modalities_clause(value) -> tuple[str, list] | None:
    """ModalitiesInStudy: o estudo tem alguma série de uma das modalidades.

    Valores múltiplos ("CT\\MR") valem como OU. Um `*` sozinho é a
    correspondência universal, e `*`/`?` funcionam como curinga numa
    modalidade (CS aceita curinga, PS3.4 C.2.2.2.4) — alguns RIS mandam
    ModalitiesInStudy="*" para dizer "qualquer uma".
    """
    values = _values(value)
    if not values or any(set(v) == {"*"} for v in values):
        return None
    parts, args = [], []
    for v in values:
        if "*" in v or "?" in v:
            parts.append(
                "EXISTS (SELECT 1 FROM series s2 WHERE s2.study_id = st.id AND horus_fold(s2.modality) LIKE ? ESCAPE '\\')"
            )
            args.append(_folded_like(v))
        else:
            parts.append("('\\' || st.modalities || '\\') LIKE ? ESCAPE '|'")
            args.append(f"%\\{v.replace('|', '||').replace('%', '|%').replace('_', '|_')}\\%")
    return "(" + " OR ".join(parts) + ")", args


def _needs_utf8(ds: Dataset) -> bool:
    for elem in ds:
        if isinstance(elem.value, str) and not elem.value.isascii():
            return True
        if elem.VR == "PN" and elem.value is not None and not str(elem.value).isascii():
            return True
    return False


class QueryEngine:
    def __init__(self, database: Database, max_results: int = 10000, max_image_results: int = 200000):
        self.db = database
        self.max_results = max_results
        self.max_image_results = max_image_results

    def find(self, identifier: Dataset, model: str = STUDY_ROOT, retrieve_ae: str = "") -> Iterator[Dataset]:
        """Respostas do C-FIND, uma por correspondência.

        `retrieve_ae` vai em Retrieve AE Title (0008,0054) de cada resposta,
        como o Horos faz: diz ao cliente a quem pedir o C-MOVE/C-GET.
        """
        level = str(identifier.get("QueryRetrieveLevel", "")).upper().strip()
        if level not in LEVELS:
            raise QueryError(f"QueryRetrieveLevel inválido: {level!r}")
        if model == STUDY_ROOT and level == "PATIENT":
            raise QueryError("o modelo Study Root não tem o nível PATIENT")
        allowed = LEVELS[: LEVELS.index(level) + 1]

        conds: list[str] = []
        args: list = []
        requested: list[str] = []
        for elem in identifier:
            kw = elem.keyword
            if not kw or kw in ("QueryRetrieveLevel", "SpecificCharacterSet"):
                continue
            requested.append(kw)
            if kw == "ModalitiesInStudy" and level in ("STUDY", "PATIENT") and "STUDY" in allowed:
                clause = _modalities_clause(elem.value)
            elif kw in ATTRIBUTES and ATTRIBUTES[kw][0] in allowed:
                _lvl, expr, vr = ATTRIBUTES[kw]
                clause = match_clause(expr, vr, elem.value)
            else:
                clause = None
            if clause:
                conds.append(clause[0])
                args.extend(clause[1])

        select = self._select(level, requested)
        sql = f"SELECT {select} {_FROM[level]}"
        if conds:
            sql += " WHERE " + " AND ".join(conds)
        if level == "PATIENT":
            sql += " GROUP BY st.patient_id"
        order = {
            "PATIENT": "MAX(" + _NAME + ")",
            "STUDY": "st.study_date DESC, st.study_time DESC",
            "SERIES": "se.series_number",
            "IMAGE": "im.instance_number",
        }[level]
        limit = self.max_image_results if level == "IMAGE" else self.max_results
        sql += f" ORDER BY {order} LIMIT {int(limit)}"

        with self.db.connect() as conn:
            rows = conn.execute(sql, args).fetchall()
        for row in rows:
            ds = self._response(level, requested, row)
            if retrieve_ae:
                ds.RetrieveAETitle = retrieve_ae
            yield ds

    @staticmethod
    def _select(level: str, requested: list[str]) -> str:
        allowed = LEVELS[: LEVELS.index(level) + 1]
        cols = []
        for kw, (lvl, expr, _vr) in ATTRIBUTES.items():
            if lvl in allowed:
                # No nível de paciente as colunas vêm agregadas por PatientID.
                cols.append(f"MAX({expr}) AS {kw}" if level == "PATIENT" else f"{expr} AS {kw}")
        if "STUDY" in allowed:
            cols.append("st.modalities AS ModalitiesInStudy")
        for kw, (lvl, expr) in _COUNTS.items():
            if lvl == level and kw in requested:
                cols.append(f"{expr} AS {kw}")
        return ", ".join(cols)

    @staticmethod
    def _response(level: str, requested: list[str], row) -> Dataset:
        ds = Dataset()
        ds.QueryRetrieveLevel = level
        keys = row.keys()
        for kw in requested:
            value = row[kw] if kw in keys else None
            if kw == "ModalitiesInStudy" and value:
                value = [m for m in str(value).split("\\") if m]
            elif isinstance(value, int) and kw not in _COUNTS and ATTRIBUTES.get(kw, ("", "", ""))[2] == "IS":
                value = str(value)
            elif value == "" or value is None:
                # Chave pedida sem valor conhecido: volta vazia (PS3.4 C.2.2.1).
                value = [] if dictionary_VR(kw) == "SQ" else None
            setattr(ds, kw, value)
        if _needs_utf8(ds):
            ds.SpecificCharacterSet = "ISO_IR 192"
        return ds

    # -------------------------------------------------- C-MOVE / C-GET

    def retrieve(self, identifier: Dataset) -> list[RetrieveItem]:
        """Arquivos pedidos num C-MOVE/C-GET, pelo UID do nível."""
        level = str(identifier.get("QueryRetrieveLevel", "")).upper().strip()
        keys = {
            "PATIENT": ("PatientID", "st.patient_id"),
            "STUDY": ("StudyInstanceUID", "st.study_instance_uid"),
            "SERIES": ("SeriesInstanceUID", "se.series_instance_uid"),
            "IMAGE": ("SOPInstanceUID", "im.sop_instance_uid"),
        }
        if level not in keys:
            raise QueryError(f"QueryRetrieveLevel inválido: {level!r}")
        keyword, expr = keys[level]
        values = _values(identifier.get(keyword))
        if not values:
            # Sem a chave única do nível não há o que recuperar; recuperar
            # "tudo" por engano seria grave num PACS.
            raise QueryError(f"{keyword} ausente para recuperação no nível {level}")
        marks = ",".join("?" * len(values))
        sql = (
            "SELECT im.path, im.sop_class_uid, im.sop_instance_uid, im.transfer_syntax_uid "
            f"{_FROM['IMAGE']} WHERE {expr} IN ({marks}) "
            "ORDER BY st.id, se.series_number, im.instance_number, im.id"
        )
        with self.db.connect() as conn:
            rows = conn.execute(sql, values).fetchall()
        return [RetrieveItem(r[0], r[1], r[2], r[3]) for r in rows]
