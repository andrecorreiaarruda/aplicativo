"""Autoteste do executável empacotado (`Horus.exe --self-test arquivo`).

Um executável PyInstaller pode abrir normalmente e só falhar ao decodificar
um exame comprimido, porque os codecs (pylibjpeg) são plugins descobertos
por metadados de pacote que o empacotador precisa copiar explicitamente.
Este teste exercita, dentro do próprio executável, o caminho completo:
JPEG 2000 sem perdas, DICOMDIR, ISO e o script de gravação do Windows.
"""

from __future__ import annotations

import sys
import tempfile
import traceback
from pathlib import Path


def _dataset():
    import numpy as np
    from pydicom.dataset import Dataset, FileMetaDataset
    from pydicom.uid import CTImageStorage, ExplicitVRLittleEndian, generate_uid

    meta = FileMetaDataset()
    meta.MediaStorageSOPClassUID = CTImageStorage
    meta.MediaStorageSOPInstanceUID = generate_uid()
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    ds = Dataset()
    ds.file_meta = meta
    ds.SOPClassUID = CTImageStorage
    ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
    ds.PatientName, ds.PatientID = "TESTE^AUTO", "SELFTEST"
    ds.StudyInstanceUID, ds.SeriesInstanceUID = generate_uid(), generate_uid()
    ds.StudyDate, ds.StudyTime, ds.StudyID = "20240101", "120000", "1"
    ds.Modality, ds.SeriesNumber, ds.InstanceNumber = "CT", 1, 1
    px = (np.arange(64 * 64, dtype=np.uint16).reshape(64, 64) * 13) % 4096
    ds.Rows, ds.Columns = px.shape
    ds.SamplesPerPixel, ds.PhotometricInterpretation = 1, "MONOCHROME2"
    ds.BitsAllocated, ds.BitsStored, ds.HighBit, ds.PixelRepresentation = 16, 12, 11, 0
    ds.PixelData = px.tobytes()
    return ds, px


def run(report: Path | None = None) -> int:
    lines: list[str] = []
    ok = True

    def check(name, fn):
        nonlocal ok
        try:
            detail = fn()
            lines.append(f"OK    {name}{': ' + detail if detail else ''}")
        except Exception:
            ok = False
            lines.append(f"FALHA {name}\n{traceback.format_exc()}")

    # ignore_cleanup_errors: no Windows, um arquivo ainda aberto (log, base)
    # não pode ser apagado, e isso não deve derrubar o relatório.
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        work = Path(tmp)

        def codecs():
            import numpy as np
            import pydicom
            from pydicom.uid import JPEG2000Lossless

            ds, px = _dataset()
            ds.compress(JPEG2000Lossless, generate_instance_uid=False)
            path = work / "j2k.dcm"
            ds.save_as(path, enforce_file_format=True)
            back = pydicom.dcmread(path)
            assert np.array_equal(back.pixel_array, px), "pixels divergentes após JPEG 2000"
            return "JPEG 2000 sem perdas codifica e decodifica"

        def disc():
            import pycdlib

            from .burn.iso import build_iso
            from .burn.prepare import DiscOptions, prepare_disc

            ds, _ = _dataset()
            src = work / "src.dcm"
            ds.save_as(src, enforce_file_format=True)
            prepared = prepare_disc([src], DiscOptions(label="SELFTEST"), work / "stage")
            iso = build_iso(prepared.folder, work / "t.iso", prepared.label)
            reader = pycdlib.PyCdlib()
            reader.open(str(iso))
            names = [c.file_identifier().decode() for c in reader.list_children(iso_path="/")]
            reader.close()
            assert "DICOMDIR.;1" in names, names
            return f"DICOMDIR e ISO ({iso.stat().st_size // 1024} KiB)"

        def platform_layer():
            from .platform import current

            p = current()
            if sys.platform == "win32":
                from .platform.windows import _script_path

                assert _script_path().exists(), f"script IMAPI2 ausente: {_script_path()}"
                recorders = p.list_recorders()
                volumes = p.list_removable_volumes()
                return f"{p.name}: {len(recorders)} gravador(es), {len(volumes)} volume(s) removível(is) {p.recorder_error}".strip()
            return p.name

        def network():
            import socket

            from .database import Database
            from .net import scu
            from .net.config import LocalSettings, NetworkConfig, Node
            from .net.scp import DicomListener

            with socket.socket() as s:
                s.bind(("127.0.0.1", 0))
                port = s.getsockname()[1]
            local = LocalSettings(ae_title="SELFTEST", port=port, bind_address="127.0.0.1")
            listener = DicomListener(Database(work / "rede"), NetworkConfig(local))
            listener.start()
            try:
                res = scu.echo(LocalSettings(ae_title="CLIENTE"), Node("eu", "SELFTEST", "127.0.0.1", port))
                assert res.ok, res.message
            finally:
                listener.stop()
            return "listener e C-ECHO em 127.0.0.1"

        def translations():
            from PySide6.QtCore import QLibraryInfo

            folder = Path(QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath))
            assert (folder / "qt_pt_BR.qm").exists() or (folder / "qtbase_pt_BR.qm").exists(), folder
            return "traduções do Qt em português"

        check("codecs", codecs)
        check("gravação", disc)
        check("rede", network)
        check("tradução", translations)
        check("plataforma", platform_layer)

    text = "\n".join(lines) + f"\n{'SUCESSO' if ok else 'FALHOU'}\n"
    if report:
        report.write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0 if ok else 1
