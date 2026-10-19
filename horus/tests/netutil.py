"""Apoio aos testes de rede: portas livres e listeners descartáveis."""

from __future__ import annotations

import socket
from contextlib import contextmanager
from pathlib import Path

from horus.database import Database
from horus.net.config import LocalSettings, NetworkConfig, Node
from horus.net.scp import DicomListener


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def local(ae: str, port: int | None = None, **kw) -> LocalSettings:
    return LocalSettings(ae_title=ae, port=port or free_port(), bind_address="127.0.0.1", **kw)


def node(ae: str, port: int, **kw) -> Node:
    return Node(name=ae, ae_title=ae, host="127.0.0.1", port=port, **kw)


@contextmanager
def running_listener(base: Path, ae: str = "HORUS", nodes: list[Node] | None = None, **kw):
    db = Database(base)
    config = NetworkConfig(local(ae, **kw), list(nodes or []))
    listener = DicomListener(db, config)
    listener.start()
    try:
        yield listener
    finally:
        listener.stop()
