"""Base local de exames — equivalente ao DicomDatabase do Horos.

O Horos usa Core Data sobre SQLite (`NSSQLiteStoreType`, arquivo
`Database.sql`), com as entidades Study → Series → Image, e copia os
arquivos recebidos para `DATABASE.noindex/<lote>/<n>.dcm`, em lotes de
10 000 arquivos (uniquePathForNewDataFileWithExtension). Core Data só
existe nas plataformas Apple; o modelo foi reescrito como tabelas SQLite
comuns, com a mesma hierarquia e a mesma disposição dos arquivos.

O identificador de paciente segue a ideia de `patientUID` do Horos: nome,
ID e data de nascimento normalizados, para agrupar exames do mesmo
paciente mesmo quando vêm de equipamentos diferentes.
"""

from __future__ import annotations

import shutil
import sqlite3
import threading
import unicodedata
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable, Iterable, Iterator

import pydicom

from . import paths
from .importer import MEDIA_STORAGE_DIRECTORY, collect_files

FOLDER_SIZE = 10_000

_SCHEMA = """
CREATE TABLE IF NOT EXISTS study (
    id INTEGER PRIMARY KEY,
    study_instance_uid TEXT NOT NULL UNIQUE,
    patient_uid TEXT NOT NULL,
    patient_name TEXT NOT NULL DEFAULT '',
    patient_id TEXT NOT NULL DEFAULT '',
    patient_birth_date TEXT NOT NULL DEFAULT '',
    patient_sex TEXT NOT NULL DEFAULT '',
    study_date TEXT NOT NULL DEFAULT '',
    study_time TEXT NOT NULL DEFAULT '',
    study_description TEXT NOT NULL DEFAULT '',
    accession_number TEXT NOT NULL DEFAULT '',
    institution_name TEXT NOT NULL DEFAULT '',
    referring_physician TEXT NOT NULL DEFAULT '',
    modalities TEXT NOT NULL DEFAULT '',
    number_of_images INTEGER NOT NULL DEFAULT 0,
    date_added TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS series (
    id INTEGER PRIMARY KEY,
    study_id INTEGER NOT NULL REFERENCES study(id) ON DELETE CASCADE,
    series_instance_uid TEXT NOT NULL UNIQUE,
    series_number INTEGER,
    modality TEXT NOT NULL DEFAULT '',
    series_description TEXT NOT NULL DEFAULT '',
    sop_class_uid TEXT NOT NULL DEFAULT '',
    number_of_images INTEGER NOT NULL DEFAULT 0,
    thumbnail BLOB
);
CREATE TABLE IF NOT EXISTS image (
    id INTEGER PRIMARY KEY,
    series_id INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    sop_instance_uid TEXT NOT NULL UNIQUE,
    sop_class_uid TEXT NOT NULL DEFAULT '',
    instance_number INTEGER,
    number_of_frames INTEGER NOT NULL DEFAULT 1,
    transfer_syntax_uid TEXT NOT NULL DEFAULT '',
    path TEXT NOT NULL,
    stored_in_database INTEGER NOT NULL DEFAULT 0,
    file_size INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS series_study ON series(study_id);
CREATE INDEX IF NOT EXISTS image_series ON image(series_id);
CREATE INDEX IF NOT EXISTS study_patient ON study(patient_uid);
CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT);
"""


def _strip_accents(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))


def patient_uid(name: str, patient_id: str, birth_date: str) -> str:
    norm = _strip_accents(name).upper().replace("^", " ")
    norm = " ".join(norm.split())
    return f"{norm}-{patient_id.strip().upper()}-{birth_date.strip()}"


@dataclass
class StudyRow:
    id: int
    study_instance_uid: str
    patient_uid: str
    patient_name: str
    patient_id: str
    patient_birth_date: str
    patient_sex: str
    study_date: str
    study_time: str
    study_description: str
    accession_number: str
    institution_name: str
    referring_physician: str
    modalities: str
    number_of_images: int
    date_added: str


@dataclass
class SeriesRow:
    id: int
    study_id: int
    series_instance_uid: str
    series_number: int | None
    modality: str
    series_description: str
    sop_class_uid: str
    number_of_images: int


@dataclass
class ImageRow:
    id: int
    series_id: int
    sop_instance_uid: str
    sop_class_uid: str
    instance_number: int | None
    number_of_frames: int
    transfer_syntax_uid: str
    path: str
    stored_in_database: int
    file_size: int


@dataclass
class ImportResult:
    added: int = 0
    duplicates: int = 0
    errors: list[tuple[str, str]] = field(default_factory=list)
    study_ids: set[int] = field(default_factory=set)


def _text(ds: pydicom.Dataset, keyword: str) -> str:
    value = ds.get(keyword)
    if value is None:
        return ""
    return str(value).strip()


def _int(ds: pydicom.Dataset, keyword: str) -> int | None:
    value = ds.get(keyword)
    if value in (None, ""):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


class Database:
    def __init__(self, base_dir: Path | None = None):
        self.base_dir = Path(base_dir) if base_dir else paths.default_base_dir()
        self.base_dir.mkdir(parents=True, exist_ok=True)
        self.sql_path = self.base_dir / paths.SQL_FILE_NAME
        self.data_dir = self.base_dir / paths.DATABASE_DIR_NAME
        self.data_dir.mkdir(exist_ok=True)
        paths.mark_not_indexed(self.data_dir)
        self._index_lock = threading.Lock()
        self._next_index: int | None = None
        with self.connect() as db:
            db.executescript(_SCHEMA)

    # ------------------------------------------------------------ conexão

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        """Uma conexão por uso: a importação roda em outra thread."""
        conn = sqlite3.connect(self.sql_path, timeout=30)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA journal_mode = WAL")
        try:
            yield conn
            conn.commit()
        except BaseException:
            conn.rollback()
            raise
        finally:
            conn.close()

    # ------------------------------------------------------- arquivos

    def _compute_next_index(self) -> int:
        # Os lotes são múltiplos de FOLDER_SIZE, então o maior índice está
        # sempre no lote de maior número; não é preciso varrer a base toda.
        folders = [int(p.name) for p in self.data_dir.iterdir() if p.is_dir() and p.name.isdigit()]
        if not folders:
            return 1
        last = self.data_dir / str(max(folders))
        stems = [int(f.stem) for f in last.iterdir() if f.stem.isdigit()]
        return (max(stems) if stems else max(folders) - FOLDER_SIZE) + 1

    def _unique_data_path(self, ext: str = "dcm") -> Path:
        # Mesma regra do Horos: extensão estranha vira "dcm".
        if not 3 <= len(ext) <= 4:
            ext = "dcm"
        with self._index_lock:
            if self._next_index is None:
                self._next_index = self._compute_next_index()
            while True:
                index = self._next_index
                self._next_index += 1
                folder = self.data_dir / str(FOLDER_SIZE * (index // FOLDER_SIZE + 1))
                folder.mkdir(exist_ok=True)
                candidate = folder / f"{index}.{ext}"
                if not candidate.exists():
                    return candidate

    # ------------------------------------------------------- importação

    def add_files(
        self,
        sources: Iterable[str | Path],
        copy: bool = True,
        progress: Callable[[int, str], None] | None = None,
        cancelled: Callable[[], bool] = lambda: False,
    ) -> ImportResult:
        """Importa arquivos e pastas (addFilesAtPaths no Horos).

        Com `copy=False` a base só referencia os arquivos no local de
        origem — o que o Horos faz ao ler um CD sem copiar.
        """
        result = ImportResult()
        touched_series: set[int] = set()
        now = datetime.now().isoformat(timespec="seconds")
        with self.connect() as db:
            for n, path in enumerate(collect_files(sources, cancelled), start=1):
                if cancelled():
                    break
                if progress:
                    progress(n, str(path))
                try:
                    ds = pydicom.dcmread(str(path), stop_before_pixels=True, force=True)
                except Exception as exc:  # arquivo truncado, cabeçalho inválido
                    result.errors.append((str(path), str(exc)))
                    continue
                meta = getattr(ds, "file_meta", None)
                if meta is not None and str(meta.get("MediaStorageSOPClassUID", "")) == MEDIA_STORAGE_DIRECTORY:
                    continue
                sop_uid = _text(ds, "SOPInstanceUID")
                series_uid = _text(ds, "SeriesInstanceUID")
                study_uid = _text(ds, "StudyInstanceUID")
                if not (sop_uid and series_uid and study_uid):
                    result.errors.append((str(path), "sem SOP/Series/Study Instance UID"))
                    continue
                if db.execute("SELECT 1 FROM image WHERE sop_instance_uid = ?", (sop_uid,)).fetchone():
                    result.duplicates += 1
                    continue

                stored = 0
                target = Path(path)
                if copy:
                    target = self._unique_data_path()
                    shutil.copyfile(path, target)
                    stored = 1

                study_id = self._upsert_study(db, ds, study_uid, now)
                series_id = self._upsert_series(db, ds, study_id, series_uid)
                transfer = ""
                if meta is not None:
                    transfer = str(meta.get("TransferSyntaxUID", ""))
                db.execute(
                    """INSERT INTO image (series_id, sop_instance_uid, sop_class_uid,
                           instance_number, number_of_frames, transfer_syntax_uid,
                           path, stored_in_database, file_size)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        series_id,
                        sop_uid,
                        _text(ds, "SOPClassUID"),
                        _int(ds, "InstanceNumber"),
                        _int(ds, "NumberOfFrames") or 1,
                        transfer,
                        str(target),
                        stored,
                        target.stat().st_size,
                    ),
                )
                touched_series.add(series_id)
                result.study_ids.add(study_id)
                result.added += 1
            self._refresh_counts(db, touched_series, result.study_ids)
        return result

    def _upsert_study(self, db: sqlite3.Connection, ds: pydicom.Dataset, uid: str, now: str) -> int:
        row = db.execute("SELECT id FROM study WHERE study_instance_uid = ?", (uid,)).fetchone()
        if row:
            return int(row["id"])
        name = _text(ds, "PatientName").replace("^", " ").strip()
        pid = _text(ds, "PatientID")
        birth = _text(ds, "PatientBirthDate")
        cur = db.execute(
            """INSERT INTO study (study_instance_uid, patient_uid, patient_name, patient_id,
                   patient_birth_date, patient_sex, study_date, study_time,
                   study_description, accession_number, institution_name,
                   referring_physician, date_added)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                uid,
                patient_uid(name, pid, birth),
                name,
                pid,
                birth,
                _text(ds, "PatientSex"),
                _text(ds, "StudyDate"),
                _text(ds, "StudyTime"),
                _text(ds, "StudyDescription"),
                _text(ds, "AccessionNumber"),
                _text(ds, "InstitutionName"),
                _text(ds, "ReferringPhysicianName").replace("^", " ").strip(),
                now,
            ),
        )
        return int(cur.lastrowid)

    def _upsert_series(self, db: sqlite3.Connection, ds: pydicom.Dataset, study_id: int, uid: str) -> int:
        row = db.execute("SELECT id FROM series WHERE series_instance_uid = ?", (uid,)).fetchone()
        if row:
            return int(row["id"])
        cur = db.execute(
            """INSERT INTO series (study_id, series_instance_uid, series_number, modality,
                   series_description, sop_class_uid)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (
                study_id,
                uid,
                _int(ds, "SeriesNumber"),
                _text(ds, "Modality"),
                _text(ds, "SeriesDescription"),
                _text(ds, "SOPClassUID"),
            ),
        )
        return int(cur.lastrowid)

    def _refresh_counts(self, db: sqlite3.Connection, series_ids: set[int], study_ids: set[int]) -> None:
        for sid in series_ids:
            db.execute(
                """UPDATE series SET number_of_images =
                       (SELECT COALESCE(SUM(number_of_frames), 0) FROM image WHERE series_id = ?),
                       thumbnail = NULL
                   WHERE id = ?""",
                (sid, sid),
            )
        for stid in study_ids:
            mods = [
                r["modality"]
                for r in db.execute(
                    "SELECT DISTINCT modality FROM series WHERE study_id = ? AND modality <> '' ORDER BY modality",
                    (stid,),
                )
            ]
            db.execute(
                """UPDATE study SET modalities = ?, number_of_images =
                       (SELECT COALESCE(SUM(number_of_images), 0) FROM series WHERE study_id = ?)
                   WHERE id = ?""",
                ("\\".join(mods), stid, stid),
            )

    # ----------------------------------------------------------- leitura

    def studies(self, search: str = "") -> list[StudyRow]:
        sql = "SELECT * FROM study"
        args: tuple = ()
        if search.strip():
            like = f"%{search.strip()}%"
            sql += (
                " WHERE patient_name LIKE ? OR patient_id LIKE ? OR study_description LIKE ?"
                " OR accession_number LIKE ? OR modalities LIKE ?"
            )
            args = (like,) * 5
        sql += " ORDER BY patient_name COLLATE NOCASE, study_date DESC, study_time DESC"
        with self.connect() as db:
            return [StudyRow(**dict(r)) for r in db.execute(sql, args)]

    def study(self, study_id: int) -> StudyRow | None:
        with self.connect() as db:
            r = db.execute("SELECT * FROM study WHERE id = ?", (study_id,)).fetchone()
            return StudyRow(**dict(r)) if r else None

    def series_for_study(self, study_id: int) -> list[SeriesRow]:
        with self.connect() as db:
            rows = db.execute(
                """SELECT id, study_id, series_instance_uid, series_number, modality,
                          series_description, sop_class_uid, number_of_images
                   FROM series WHERE study_id = ?
                   ORDER BY series_number IS NULL, series_number, id""",
                (study_id,),
            )
            return [SeriesRow(**dict(r)) for r in rows]

    def series(self, series_id: int) -> SeriesRow | None:
        with self.connect() as db:
            r = db.execute(
                """SELECT id, study_id, series_instance_uid, series_number, modality,
                          series_description, sop_class_uid, number_of_images
                   FROM series WHERE id = ?""",
                (series_id,),
            ).fetchone()
            return SeriesRow(**dict(r)) if r else None

    def images_for_series(self, series_id: int) -> list[ImageRow]:
        with self.connect() as db:
            rows = db.execute(
                "SELECT * FROM image WHERE series_id = ? ORDER BY instance_number IS NULL, instance_number, id",
                (series_id,),
            )
            return [ImageRow(**dict(r)) for r in rows]

    def images_for(self, study_ids: Iterable[int] = (), series_ids: Iterable[int] = ()) -> list[ImageRow]:
        """Imagens de uma seleção mista de exames e séries, sem repetição."""
        study_ids, series_ids = list(study_ids), list(series_ids)
        found: dict[int, ImageRow] = {}
        with self.connect() as db:
            for stid in study_ids:
                for r in db.execute(
                    """SELECT image.* FROM image JOIN series ON series.id = image.series_id
                       WHERE series.study_id = ? ORDER BY series.series_number, image.instance_number""",
                    (stid,),
                ):
                    found.setdefault(r["id"], ImageRow(**dict(r)))
            for sid in series_ids:
                for r in db.execute("SELECT * FROM image WHERE series_id = ? ORDER BY instance_number", (sid,)):
                    found.setdefault(r["id"], ImageRow(**dict(r)))
        return list(found.values())

    def patient_uids_for(self, images: Iterable[ImageRow]) -> set[str]:
        series_ids = {img.series_id for img in images}
        if not series_ids:
            return set()
        marks = ",".join("?" * len(series_ids))
        with self.connect() as db:
            rows = db.execute(
                f"""SELECT DISTINCT study.patient_uid FROM study JOIN series ON series.study_id = study.id
                    WHERE series.id IN ({marks})""",
                tuple(series_ids),
            )
            return {r[0] for r in rows}

    # --------------------------------------------------------- miniaturas

    def thumbnail(self, series_id: int) -> bytes | None:
        with self.connect() as db:
            r = db.execute("SELECT thumbnail FROM series WHERE id = ?", (series_id,)).fetchone()
            return bytes(r[0]) if r and r[0] is not None else None

    def set_thumbnail(self, series_id: int, png: bytes) -> None:
        with self.connect() as db:
            db.execute("UPDATE series SET thumbnail = ? WHERE id = ?", (png, series_id))

    # ---------------------------------------------------------- exclusão

    def delete(self, study_ids: Iterable[int] = (), series_ids: Iterable[int] = ()) -> int:
        """Remove da base e apaga os arquivos que a própria base copiou.

        Arquivos apenas referenciados (importação sem cópia) ficam onde
        estão: não pertencem à base.
        """
        study_ids, series_ids = list(study_ids), list(series_ids)
        images = self.images_for(study_ids, series_ids)
        with self.connect() as db:
            parents: set[int] = set()
            for sid in series_ids:
                row = db.execute("SELECT study_id FROM series WHERE id = ?", (sid,)).fetchone()
                if row:
                    parents.add(int(row[0]))
                db.execute("DELETE FROM series WHERE id = ?", (sid,))
            for stid in study_ids:
                db.execute("DELETE FROM study WHERE id = ?", (stid,))
            parents -= set(study_ids)
            # Exames que ficaram sem séries depois de apagar séries avulsas.
            for stid in list(parents):
                if not db.execute("SELECT 1 FROM series WHERE study_id = ?", (stid,)).fetchone():
                    db.execute("DELETE FROM study WHERE id = ?", (stid,))
                    parents.discard(stid)
            self._refresh_counts(db, set(), parents)
        data_root = self.data_dir.resolve()
        for img in images:
            if not img.stored_in_database:
                continue
            path = Path(img.path)
            try:
                if data_root in path.resolve().parents:
                    path.unlink(missing_ok=True)
            except OSError:
                pass
        return len(images)
