"""Montagem da pasta do disco — porte de `prepareCDContent`.

Ordem das etapas, a mesma do Horos (BurnerWindowController.m):

1. anonimização opcional das cópias (`/tmp/burnAnonymized` no Horos);
2. cópia para `DICOM/00000`, `DICOM/00001`, ... com conversão de big
   endian e compressão/descompressão opcionais;
3. DICOMDIR (DicomDir.mm);
4. visualizador no disco (o Horos inclui o Weasis e ajusta o rótulo do
   Autorun.inf; aqui vai o próprio Horus para Windows);
5. páginas HTML (BurnHtml);
6. pasta suplementar (SupplementaryBurnPath);
7. ZIP com senha (EncryptCD).

O resultado é uma pasta pronta, independente do destino — CD/DVD,
pendrive ou ISO —, exatamente como a `folderToBurn` do Horos.
"""

from __future__ import annotations

import html
import shutil
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Callable, Iterable

import pydicom
from pydicom.uid import JPEG2000Lossless

from .. import APP_NAME, paths
from ..anonymize import AnonymizationOptions, Anonymizer
from ..dicom.fileio import save_media_file, to_explicit_little
from ..dicom.thumbnail import encode_png, frame_thumbnail
from ..dicom.pixels import frame_from_dataset
from .dicomdir import build_dicomdir
from .iso import folder_size, sanitize_volume_label

KEEP, COMPRESS, DECOMPRESS = "keep", "compress", "decompress"
VIEWER_DIR = "HORUS"


class Cancelled(Exception):
    pass


@dataclass
class DiscOptions:
    """Opções de gravação (DiscBurningOptions no Horos)."""

    label: str = "DICOM"
    anonymize: AnonymizationOptions | None = None
    compression: str = KEEP
    include_viewer: bool = False
    include_html: bool = True
    supplementary_dir: Path | None = None
    zip_password: str | None = None
    viewer_source: Path | None = None


@dataclass
class PreparedDisc:
    folder: Path
    label: str
    file_count: int
    size_bytes: int
    warnings: list[str] = field(default_factory=list)


ProgressFn = Callable[[str, int, int], None]


def default_label(patient_names: Iterable[str], multiple_patients: bool, anonymized: bool) -> str:
    """Rótulo sugerido, com a regra do Horos (setup: em BurnerWindowController).

    Um paciente: o nome dele. Vários pacientes ou anonimização:
    "Archive-AAAAMMDD" no Horos; aqui "EXAMES_AAAAMMDD", que cabe nos 15
    caracteres aceitos pelo IMAPI2.
    """
    if multiple_patients or anonymized:
        return f"EXAMES_{date.today():%Y%m%d}"
    names = [n for n in patient_names if n]
    return sanitize_volume_label(names[0] if names else "UNTITLED")


def viewer_bundle() -> Path | None:
    """Pasta do Horus empacotado, quando rodando como executável."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).parent
    return None


def estimate_size(files: Iterable[str | Path], options: DiscOptions) -> int:
    """Estimativa antes de preparar (estimateFolderSize no Horos)."""
    total = 0
    for f in files:
        try:
            total += Path(f).stat().st_size
        except OSError:
            pass
    if options.include_viewer and (options.viewer_source or viewer_bundle()):
        total += folder_size(options.viewer_source or viewer_bundle())
    if options.supplementary_dir and Path(options.supplementary_dir).is_dir():
        total += folder_size(Path(options.supplementary_dir))
    return total


def _check(cancelled: Callable[[], bool]) -> None:
    if cancelled():
        raise Cancelled()


def _place_dicom(src: Path, dst: Path, mode: str, warnings: list[str]) -> None:
    """Copia um objeto, convertendo só quando necessário.

    Sem conversão a cópia é byte a byte: o arquivo do disco é idêntico ao
    da base. Compressão e descompressão são sem perdas e preservam o
    SOPInstanceUID (o pydicom gera um novo por padrão, o que quebraria a
    identidade da imagem e as referências entre objetos).
    """
    # Primeiro só o cabeçalho: no modo "manter" a maioria dos arquivos é
    # copiada sem conversão, e ler os pixels de cada um seria desperdício.
    head = pydicom.dcmread(str(src), stop_before_pixels=True, force=True)
    meta = getattr(head, "file_meta", None)
    transfer = meta.get("TransferSyntaxUID") if meta is not None else None
    big_endian = transfer == pydicom.uid.ExplicitVRBigEndian
    raw_object = transfer is None
    if mode == KEEP and not (big_endian or raw_object):
        shutil.copyfile(src, dst)
        return

    ds = pydicom.dcmread(str(src), force=True)
    has_pixels = "PixelData" in ds
    compressed = bool(transfer and transfer.is_compressed)

    if mode == COMPRESS and has_pixels and not compressed:
        try:
            to_explicit_little(ds)
            ds.compress(JPEG2000Lossless, generate_instance_uid=False)
            save_media_file(ds, dst)
            return
        except Exception as exc:
            warnings.append(f"{src.name}: mantido sem compressão ({exc})")
            ds = pydicom.dcmread(str(src), force=True)
    elif mode == DECOMPRESS and has_pixels and compressed:
        try:
            ds.decompress(generate_instance_uid=False)
            save_media_file(ds, dst)
            return
        except Exception as exc:
            warnings.append(f"{src.name}: mantido comprimido ({exc})")
            ds = pydicom.dcmread(str(src), force=True)

    if big_endian or raw_object:
        to_explicit_little(ds)
        save_media_file(ds, dst)
    else:
        shutil.copyfile(src, dst)


def _write_autorun(folder: Path, label: str) -> None:
    # O AutoRun de CD foi restringido a partir do Windows 7 (o comando
    # "open" só aparece como opção do AutoPlay), mas rótulo e ícone ainda
    # valem. O Horos faz o mesmo ajuste de rótulo no Autorun.inf do Weasis.
    text = (
        "[autorun]\r\n"
        f"open={VIEWER_DIR}\\Horus.exe --disc\r\n"
        f"icon={VIEWER_DIR}\\Horus.exe,0\r\n"
        f"label={label}\r\n"
        "action=Abrir exames com o Horus\r\n"
    )
    (folder / "AUTORUN.INF").write_bytes(text.encode("ascii", "replace"))


def _write_html(folder: Path, files: list[Path]) -> None:
    """Índice navegável do disco, com uma miniatura por série.

    O Horos gera essas páginas só quando o disco não é anonimizado, porque
    elas saem da base original. Aqui elas saem dos arquivos já gravados no
    disco, então refletem a anonimização quando houver.
    """
    images = folder / "IMAGES"
    images.mkdir(exist_ok=True)
    tree: dict[tuple, dict[tuple, list[tuple]]] = {}
    for f in files:
        ds = pydicom.dcmread(str(f), stop_before_pixels=True, force=True)
        patient = (str(ds.get("PatientName", "")).replace("^", " "), str(ds.get("PatientID", "")))
        study = (str(ds.get("StudyDate", "")), str(ds.get("StudyDescription", "")), str(ds.get("StudyInstanceUID", "")))
        series = tree.setdefault(patient, {}).setdefault(study, [])
        series.append((str(ds.get("SeriesInstanceUID", "")), str(ds.get("SeriesNumber", "")), str(ds.get("Modality", "")), str(ds.get("SeriesDescription", "")), f))

    rows: list[str] = []
    n = 0
    for (pname, pid), studies in sorted(tree.items()):
        rows.append(f"<h2>{html.escape(pname)} <small>{html.escape(pid)}</small></h2>")
        for (sdate, sdesc, _uid), entries in sorted(studies.items()):
            when = f"{sdate[6:8]}/{sdate[4:6]}/{sdate[:4]}" if len(sdate) == 8 else sdate
            rows.append(f"<h3>{html.escape(when)} — {html.escape(sdesc)}</h3><div class='grid'>")
            by_series: dict[str, list[tuple]] = {}
            for entry in entries:
                by_series.setdefault(entry[0], []).append(entry)
            for _suid, group in sorted(by_series.items(), key=lambda kv: kv[1][0][1].zfill(6)):
                middle = group[len(group) // 2][4]
                n += 1
                name = f"S{n:04d}.PNG"
                try:
                    frame = frame_from_dataset(pydicom.dcmread(str(middle), force=True))
                    (images / name).write_bytes(encode_png(frame_thumbnail(frame, 256)))
                    img = f"<img src='IMAGES/{name}' alt=''>"
                except Exception:
                    img = "<div class='noimg'>sem imagem</div>"
                _, number, modality, desc, _ = group[0]
                rows.append(
                    f"<figure>{img}<figcaption>{html.escape(modality)} {html.escape(number)} "
                    f"{html.escape(desc)}<br>{len(group)} imagem(ns)</figcaption></figure>"
                )
            rows.append("</div>")
    page = f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>Exames DICOM</title>
<style>
body{{font-family:Segoe UI,Arial,sans-serif;margin:24px;background:#111;color:#eee}}
small{{color:#aaa}} .grid{{display:flex;flex-wrap:wrap;gap:12px}}
figure{{margin:0;width:256px}} img{{max-width:256px;background:#000}}
figcaption{{font-size:13px;color:#ccc}} .noimg{{width:256px;height:128px;background:#222}}
</style></head><body>
<h1>Exames DICOM</h1>
<p>Para abrir as imagens em resolução completa, use um visualizador DICOM
(o Horus, quando incluído, está na pasta {VIEWER_DIR}) e abra o arquivo DICOMDIR.</p>
{''.join(rows)}
</body></html>"""
    (folder / "INDEX.HTM").write_text(page, encoding="utf-8")


def _encrypt(folder: Path, password: str) -> None:
    try:
        import pyzipper
    except ImportError as exc:  # pragma: no cover - dependência opcional
        raise RuntimeError("criptografia indisponível: instale o pacote pyzipper") from exc
    archive = folder.parent / f"{folder.name}.zip"
    with pyzipper.AESZipFile(archive, "w", compression=pyzipper.ZIP_DEFLATED, encryption=pyzipper.WZ_AES) as zf:
        zf.setpassword(password.encode("utf-8"))
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(folder).as_posix())
    shutil.rmtree(folder)
    folder.mkdir()
    shutil.move(str(archive), folder / "DICOM.ZIP")
    (folder / "LEIAME.TXT").write_text(
        "As imagens estão em um arquivo ZIP protegido por senha (AES-256).\r\n"
        "Extraia DICOM.ZIP com a senha recebida (7-Zip, WinRAR ou o próprio\r\n"
        "Horus) e abra o arquivo DICOMDIR extraído em um visualizador DICOM.\r\n",
        encoding="utf-8",
    )


def prepare_disc(
    files: list[str | Path],
    options: DiscOptions,
    staging_root: Path | None = None,
    progress: ProgressFn | None = None,
    cancelled: Callable[[], bool] = lambda: False,
) -> PreparedDisc:
    if not files:
        raise ValueError("nada para gravar")
    if options.zip_password is not None and len(options.zip_password) < 8:
        # Mesmo mínimo do Horos (`[self.password length] < 8`).
        raise ValueError("a senha precisa ter ao menos 8 caracteres")

    report = progress or (lambda *_: None)
    staging_root = Path(staging_root) if staging_root else paths.temp_dir()
    label = sanitize_volume_label(options.label)
    folder = staging_root / label
    anon_dir = staging_root / f"{label}_anon"
    for stale in (folder, anon_dir):
        if stale.exists():
            shutil.rmtree(stale)
    folder.mkdir(parents=True)
    warnings: list[str] = []
    sources = [Path(f) for f in dict.fromkeys(str(f) for f in files)]

    try:
        if options.anonymize is not None:
            anonymizer = Anonymizer(options.anonymize)
            produced = anonymizer.anonymize_files(
                sources,
                anon_dir,
                progress=lambda i, name: report("Anonimizando", i, len(sources)),
                cancelled=cancelled,
            )
            _check(cancelled)
            sources = [produced[str(s)] for s in sources]

        dicom_dir = folder / "DICOM"
        dicom_dir.mkdir()
        placed: list[Path] = []
        for i, src in enumerate(sources):
            _check(cancelled)
            report("Copiando imagens", i + 1, len(sources))
            dst = dicom_dir / f"{i:05d}"
            _place_dicom(src, dst, options.compression, warnings)
            placed.append(dst)

        _check(cancelled)
        report("Gravando DICOMDIR", 0, 0)
        build_dicomdir(folder, fileset_id=label, files=placed)

        if options.include_viewer:
            bundle = options.viewer_source or viewer_bundle()
            if bundle and Path(bundle).is_dir():
                report("Incluindo o visualizador", 0, 0)
                shutil.copytree(bundle, folder / VIEWER_DIR)
                _write_autorun(folder, label)
            else:
                warnings.append(f"visualizador não incluído: o {APP_NAME} não está rodando como executável empacotado")

        if options.include_html:
            _check(cancelled)
            report("Gerando páginas HTML", 0, 0)
            _write_html(folder, placed)

        if options.supplementary_dir:
            extra = Path(options.supplementary_dir)
            if extra.is_dir():
                report("Copiando pasta suplementar", 0, 0)
                for item in extra.iterdir():
                    target = folder / item.name
                    if item.is_dir():
                        shutil.copytree(item, target, dirs_exist_ok=True)
                    else:
                        shutil.copy2(item, target)
            else:
                warnings.append(f"pasta suplementar não encontrada: {extra}")

        if options.zip_password:
            _check(cancelled)
            report("Criptografando", 0, 0)
            _encrypt(folder, options.zip_password)
    except Cancelled:
        shutil.rmtree(folder, ignore_errors=True)
        raise
    finally:
        shutil.rmtree(anon_dir, ignore_errors=True)

    return PreparedDisc(folder, label, len(placed), folder_size(folder), warnings)
