"""Auto-roteamento: o Horus encaminha imagens novas a outro nó por regra.

Um Horus ("ROTEADOR") recebe de uma "modalidade" e reenvia ao "PACS",
outro Horus, conforme as regras — tudo de verdade em 127.0.0.1.
"""

from __future__ import annotations

import time

import pytest
from pydicom.uid import generate_uid

from conftest import make_dataset, write
from horus.database import ORIGIN_IMPORTED, ORIGIN_RECEIVED, Database
from horus.net import routing, scu
from horus.net.config import ConfigError, NetworkConfig, RoutingRule
from horus.net.routing import Router, rule_matches
from netutil import free_port, local, node, running_listener


def _files(tmp_path, name: str, modality: str, n: int = 2, **kw):
    study, series = generate_uid(), generate_uid()
    return [
        write(make_dataset(study_uid=study, series_uid=series, instance_number=i + 1, modality=modality, **kw), tmp_path / name / f"{i}.dcm")
        for i in range(n)
    ]


def _wait(cond, timeout: float = 15.0) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.1)
    return cond()


def _image_count(db: Database) -> int:
    return len(db.images_for(study_ids=[s.id for s in db.studies()]))


def test_rule_routes_received_ct_only(tmp_path):
    with running_listener(tmp_path / "pacs", ae="PACS") as pacs:
        dest = node("PACS", pacs.config.local.port)
        rule = RoutingRule(name="TC para o PACS", destination=dest.id, modalities=["CT"], calling_ae="MODALIDADE", origin=ORIGIN_RECEIVED)
        config = NetworkConfig(local("ROTEADOR"), [dest], True, [rule]).validate()
        with running_listener(tmp_path / "rot", ae="ROTEADOR") as rot:
            router = Router(rot.db, lambda: config)
            router.start()
            try:
                target = node("ROTEADOR", rot.config.local.port)
                assert scu.send(local("MODALIDADE"), target, _files(tmp_path, "ct", "CT")).ok
                assert scu.send(local("MODALIDADE"), target, _files(tmp_path, "mr", "MR")).ok
                assert scu.send(local("OUTRO"), target, _files(tmp_path, "ct2", "CT")).ok
                assert rot.wait_idle()
                # Só a TC vinda de MODALIDADE passa na regra.
                assert _wait(lambda: _image_count(pacs.db) == 2)
                assert pacs.wait_idle()
                time.sleep(0.5)
                assert _image_count(pacs.db) == 2
                assert {s.modalities for s in pacs.db.studies()} == {"CT"}
                assert router.counts() == {"pending": 0, "failed": 0}
                # A origem da imagem ficou guardada na base.
                (img, *_) = rot.db.images_for(study_ids=[s.id for s in rot.db.studies()])
                assert img.source_ae in ("MODALIDADE", "OUTRO")
            finally:
                router.stop()


def test_failures_are_retried_and_survive_restart(tmp_path, monkeypatch):
    port = free_port()
    dest = node("PACS", port)
    rule = RoutingRule(name="tudo", destination=dest.id, retries=5)
    config = NetworkConfig(local("ROTEADOR"), [dest], True, [rule]).validate()
    db = Database(tmp_path / "rot")
    router = Router(db, lambda: config)
    db.added_hooks.append(router.on_added)
    db.add_files(_files(tmp_path, "ct", "CT", n=3))
    assert router.counts()["pending"] == 3

    # Destino fora do ar: as imagens continuam na fila, com uma tentativa a menos.
    assert router.process_due() == 0
    with db.connect() as conn:
        rows = conn.execute("SELECT retries_left, next_attempt, last_error FROM routing_queue").fetchall()
    assert all(r["retries_left"] == 4 and r["next_attempt"] > time.time() + 20 for r in rows)
    assert "sem resposta" in rows[0]["last_error"]
    assert router.process_due() == 0  # ainda não venceu o intervalo de 30 s

    # Um Router novo (o programa reaberto) encontra a mesma fila.
    monkeypatch.setattr(routing, "RETRY_DELAY", 0)
    with db.connect() as conn:
        conn.execute("UPDATE routing_queue SET next_attempt = 0")
    again = Router(db, lambda: config)
    with running_listener(tmp_path / "pacs", ae="PACS", port=port) as pacs:
        assert again.process_due() == 3
        assert pacs.wait_idle()
        assert _image_count(pacs.db) == 3
    assert again.counts() == {"pending": 0, "failed": 0}


def test_exhausted_retries_become_failures(tmp_path):
    dest = node("PACS", free_port())
    rule = RoutingRule(name="sem repetir", destination=dest.id, retries=0)
    config = NetworkConfig(local("ROTEADOR"), [dest], True, [rule]).validate()
    db = Database(tmp_path / "rot")
    router = Router(db, lambda: config)
    db.added_hooks.append(router.on_added)
    db.add_files(_files(tmp_path, "ct", "CT"))
    router.process_due()
    assert router.counts() == {"pending": 0, "failed": 2}
    assert router.retry_failed() == 2 and router.counts()["pending"] == 2
    router.process_due()
    assert router.discard_failed() == 2 and router.counts() == {"pending": 0, "failed": 0}


def test_routing_off_and_manual_apply(tmp_path):
    dest = node("PACS", free_port())
    rule = RoutingRule(name="mr", destination=dest.id, modalities=["MR"], origin=ORIGIN_RECEIVED)
    config = NetworkConfig(local("ROTEADOR"), [dest], False, [rule]).validate()
    db = Database(tmp_path / "rot")
    router = Router(db, lambda: config)
    db.added_hooks.append(router.on_added)
    result = db.add_files(_files(tmp_path, "mr", "MR"))
    assert result.origin == ORIGIN_IMPORTED and len(result.image_ids) == 2
    assert router.counts()["pending"] == 0  # roteamento desligado
    # Manual: vale com o roteamento desligado e ignora a origem.
    assert router.enqueue(result.image_ids) == 2
    assert router.enqueue(result.image_ids) == 0  # já está na fila
    rule.enabled = False
    assert router.enqueue(result.image_ids) == 0


def test_rule_filters():
    row = {"modality": "ct", "source_ae": "TOMO1 ", "study_description": "TÓRAX COM CONTRASTE"}
    assert rule_matches(RoutingRule(modalities=["CT"], calling_ae="tomo1", description="torax"), row, ORIGIN_RECEIVED)
    assert not rule_matches(RoutingRule(modalities=["MR"]), row, ORIGIN_RECEIVED)
    assert not rule_matches(RoutingRule(description="abdome"), row, ORIGIN_RECEIVED)
    assert not rule_matches(RoutingRule(origin="imported"), row, ORIGIN_RECEIVED)
    assert rule_matches(RoutingRule(origin="imported"), row, None)  # aplicação manual


def test_rules_roundtrip_and_validation(tmp_path):
    dest = node("PACS", 104)
    rule = RoutingRule(name="r", destination=dest.id, modalities=[" ct ", ""])
    NetworkConfig(local("EU"), [dest], True, [rule]).save(tmp_path)
    back = NetworkConfig.load(tmp_path)
    assert back.routing_enabled and back.rules[0].modalities == ["CT"] and back.rules[0].id == rule.id
    with pytest.raises(ConfigError, match="não existe"):
        NetworkConfig(local("EU"), [], True, [rule]).validate()
