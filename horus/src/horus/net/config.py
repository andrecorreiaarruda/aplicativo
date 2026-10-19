"""Configuração de rede: AE local e nós remotos.

No Horos tudo isso mora no NSUserDefaults (preferências do macOS): o AE
title e a porta do listener nas preferências "Listener", e a lista de nós
na chave SERVERS, editada no painel "Locations". O NSUserDefaults não
existe no Windows; aqui a configuração é um arquivo JSON dentro da pasta
da base, gravado de forma atômica — copiar a pasta da base leva junto a
configuração de rede.
"""

from __future__ import annotations

import json
import os
import re
import socket
import tempfile
import uuid
from dataclasses import asdict, dataclass, field, fields
from pathlib import Path

CONFIG_FILE = "network.json"

# Sintaxes de envio oferecidas por nó.
SEND_KEEP = "keep"  # como está na base, com reserva sem compressão
SEND_EXPLICIT = "explicit"  # sempre sem compressão (Explicit VR Little Endian)
SEND_IMPLICIT = "implicit"  # sem compressão, Implicit VR (equipamentos antigos)
SEND_J2K = "j2k"  # JPEG 2000 sem perdas
SEND_RLE = "rle"  # RLE sem perdas
SEND_SYNTAXES = (SEND_KEEP, SEND_EXPLICIT, SEND_IMPLICIT, SEND_J2K, SEND_RLE)

MAX_SEND_ASSOCIATIONS = 4

RETRIEVE_MOVE = "move"
RETRIEVE_GET = "get"


class ConfigError(ValueError):
    pass


def validate_ae_title(value: str) -> str:
    """AE title válido (PS3.5 6.2): até 16 caracteres, sem `\\` nem controle.

    Espaços nas pontas não contam; um AE title só de espaços é inválido.
    """
    text = (value or "").strip()
    if not text:
        raise ConfigError("o AE title não pode ficar vazio")
    if len(text) > 16:
        raise ConfigError(f"o AE title tem {len(text)} caracteres; o máximo é 16")
    if "\\" in text or any(ord(c) < 32 or ord(c) > 126 for c in text):
        raise ConfigError("o AE title aceita só caracteres ASCII visíveis, sem '\\'")
    return text


def default_ae_title() -> str:
    """AE title padrão: o nome curto da máquina, como no Horos.

    O Horos usa o hostname até o primeiro ponto, cortado em 16 caracteres,
    com "HOROS" quando não há nome (setAETitleToHostname em AppController.m).
    Um nome fixo igual em todas as estações quebraria o C-MOVE: o PACS
    devolve as imagens ao AE title, e dois Horus com o mesmo AE na mesma
    rede recebem os exames um do outro.
    """
    try:
        host = socket.gethostname().split(".")[0]
    except OSError:
        host = ""
    host = re.sub(r"[^A-Za-z0-9_-]", "", host).upper()[:16]
    return host or "HORUS"


def validate_port(value: int) -> int:
    try:
        port = int(value)
    except (TypeError, ValueError) as exc:
        raise ConfigError(f"porta inválida: {value!r}") from exc
    if not 1 <= port <= 65535:
        raise ConfigError(f"a porta precisa estar entre 1 e 65535 (recebida: {port})")
    return port


@dataclass
class Node:
    """Um equipamento remoto (PACS, modalidade, outra estação)."""

    name: str
    ae_title: str
    host: str
    port: int = 104
    query: bool = True
    send: bool = True
    retrieve: str = RETRIEVE_MOVE
    send_syntax: str = SEND_KEEP
    # Associações simultâneas no envio (SendControllerConcurrentThreads
    # do Horos: 1, 2 ou 4, no máximo 4).
    send_associations: int = 1
    tls: bool = False
    tls_verify: bool = True
    tls_ca_file: str = ""
    id: str = field(default_factory=lambda: uuid.uuid4().hex)

    def validate(self) -> Node:
        self.ae_title = validate_ae_title(self.ae_title)
        self.port = validate_port(self.port)
        self.host = (self.host or "").strip()
        if not self.host:
            raise ConfigError(f"o nó {self.name or self.ae_title} está sem endereço")
        if self.retrieve not in (RETRIEVE_MOVE, RETRIEVE_GET):
            raise ConfigError(f"modo de recuperação desconhecido: {self.retrieve}")
        if self.send_syntax not in SEND_SYNTAXES:
            raise ConfigError(f"sintaxe de envio desconhecida: {self.send_syntax}")
        if not 1 <= int(self.send_associations) <= MAX_SEND_ASSOCIATIONS:
            raise ConfigError(f"associações simultâneas: de 1 a {MAX_SEND_ASSOCIATIONS}")
        self.name = (self.name or "").strip() or self.ae_title
        return self

    def describe(self) -> str:
        return f"{self.name} ({self.ae_title}@{self.host}:{self.port})"


@dataclass
class LocalSettings:
    """O próprio Horus na rede."""

    ae_title: str = field(default_factory=default_ae_title)
    port: int = 11112
    listener_enabled: bool = True
    bind_address: str = ""  # vazio = todas as interfaces
    # Aceitar associações de AEs que não estão na lista de nós. Desligar
    # restringe recepção e consultas aos nós cadastrados.
    accept_unknown_callers: bool = True
    # Atender C-FIND/C-MOVE/C-GET (servir a base a outros equipamentos).
    qr_server_enabled: bool = True
    # Exigir que o AE chamado seja o nosso (alguns PACS erram e mandam o
    # AE do destino errado; muitos servidores aceitam assim mesmo).
    require_called_ae: bool = False
    # Valores do Horos: até 20 associações simultâneas, DICOMTimeout de
    # 40 s para ACSE/DIMSE e DICOMConnectionTimeout de 10 s para conectar.
    max_associations: int = 20
    acse_timeout: int = 40
    dimse_timeout: int = 40
    network_timeout: int = 60
    connection_timeout: int = 10
    max_pdu: int = 116794
    # Limite de respostas de um C-FIND de estudo/série (maximumNumberOf-
    # CFindObjects no Horos); no nível de imagem o limite é bem maior.
    max_find_results: int = 10000
    tls_enabled: bool = False
    tls_cert_file: str = ""
    tls_key_file: str = ""
    tls_ca_file: str = ""
    tls_require_client_cert: bool = False

    def validate(self) -> LocalSettings:
        self.ae_title = validate_ae_title(self.ae_title)
        self.port = validate_port(self.port)
        for name in ("max_associations", "acse_timeout", "dimse_timeout", "network_timeout", "connection_timeout", "max_find_results"):
            if int(getattr(self, name)) < 1:
                raise ConfigError(f"{name} precisa ser positivo")
        if self.tls_enabled and not (self.tls_cert_file and self.tls_key_file):
            raise ConfigError("TLS ligado exige certificado e chave do listener")
        return self


# Origem das imagens que uma regra de roteamento aceita (filterType do
# Horos: 0 todas, 1 geradas pelo programa, 2 importadas; "recebidas pela
# rede" é acréscimo do Horus, o caso mais comum de encaminhamento).
ROUTE_ALL = "all"
ROUTE_ORIGINS = (ROUTE_ALL, "received", "imported", "generated")
# Tentativas depois de uma falha, as opções do Horos ("Try N times").
ROUTE_RETRIES = (0, 5, 20, 100, 1400)


@dataclass
class RoutingRule:
    """Regra de auto-roteamento (AUTOROUTINGDICTIONARY no Horos).

    O Horos filtra com um NSPredicate livre sobre a imagem; aqui o filtro
    é estruturado: cada campo preenchido precisa bater, e os vazios não
    filtram. O destino é o id do nó, não a descrição — no Horos renomear
    um nó quebra as regras que apontam para ele.
    """

    name: str = "nova regra"
    destination: str = ""
    enabled: bool = True
    origin: str = ROUTE_ALL
    modalities: list[str] = field(default_factory=list)
    calling_ae: str = ""
    description: str = ""
    retries: int = 20
    id: str = field(default_factory=lambda: uuid.uuid4().hex)

    def validate(self, nodes: list[Node]) -> "RoutingRule":
        self.name = (self.name or "").strip() or "regra sem nome"
        if self.origin not in ROUTE_ORIGINS:
            raise ConfigError(f"regra {self.name}: origem desconhecida ({self.origin})")
        if not any(n.id == self.destination for n in nodes):
            raise ConfigError(f"a regra de roteamento '{self.name}' envia para um nó que não existe mais")
        self.modalities = [m.strip().upper() for m in self.modalities if m.strip()]
        self.calling_ae = (self.calling_ae or "").strip()
        self.description = (self.description or "").strip()
        if int(self.retries) < 0:
            raise ConfigError(f"regra {self.name}: tentativas não pode ser negativo")
        return self

    def describe_filter(self) -> str:
        parts = []
        if self.origin != ROUTE_ALL:
            parts.append({"received": "recebidas", "imported": "importadas", "generated": "geradas"}[self.origin])
        if self.modalities:
            parts.append("/".join(self.modalities))
        if self.calling_ae:
            parts.append(f"de {self.calling_ae}")
        if self.description:
            parts.append(f"descrição contém “{self.description}”")
        return ", ".join(parts) or "todas as imagens novas"


def _from_dict(cls, data: dict):
    known = {f.name for f in fields(cls)}
    return cls(**{k: v for k, v in data.items() if k in known})


@dataclass
class NetworkConfig:
    local: LocalSettings = field(default_factory=LocalSettings)
    nodes: list[Node] = field(default_factory=list)
    # AUTOROUTINGACTIVATED no Horos (desligado por padrão).
    routing_enabled: bool = False
    rules: list[RoutingRule] = field(default_factory=list)

    def node_by_ae(self, ae_title: str) -> Node | None:
        wanted = (ae_title or "").strip()
        return next((n for n in self.nodes if n.ae_title == wanted), None)

    def node_by_id(self, node_id: str) -> Node | None:
        return next((n for n in self.nodes if n.id == node_id), None)

    def validate(self) -> NetworkConfig:
        self.local.validate()
        seen: set[str] = set()
        for node in self.nodes:
            node.validate()
            if node.ae_title in seen:
                # O C-MOVE escolhe o destino pelo AE title: dois nós com o
                # mesmo AE deixariam a escolha ambígua.
                raise ConfigError(f"AE title repetido na lista de nós: {node.ae_title}")
            seen.add(node.ae_title)
        for rule in self.rules:
            rule.validate(self.nodes)
        return self

    def to_dict(self) -> dict:
        return {
            "version": 1,
            "local": asdict(self.local),
            "nodes": [asdict(n) for n in self.nodes],
            "routing_enabled": self.routing_enabled,
            "rules": [asdict(r) for r in self.rules],
        }

    @classmethod
    def from_dict(cls, data: dict) -> NetworkConfig:
        local = _from_dict(LocalSettings, data.get("local", {}))
        nodes = [_from_dict(Node, n) for n in data.get("nodes", [])]
        rules = [_from_dict(RoutingRule, r) for r in data.get("rules", [])]
        return cls(local, nodes, bool(data.get("routing_enabled", False)), rules)

    @classmethod
    def load(cls, base_dir: Path) -> NetworkConfig:
        path = Path(base_dir) / CONFIG_FILE
        if not path.exists():
            return cls()
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ConfigError(f"configuração de rede ilegível ({path}): {exc}") from exc
        return cls.from_dict(data)

    def save(self, base_dir: Path) -> Path:
        self.validate()
        path = Path(base_dir) / CONFIG_FILE
        path.parent.mkdir(parents=True, exist_ok=True)
        # Grava em arquivo temporário e substitui: uma queda no meio não
        # deixa o JSON truncado (os.replace é atômico também no Windows).
        fd, tmp = tempfile.mkstemp(prefix=".network-", suffix=".json", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(self.to_dict(), fh, ensure_ascii=False, indent=2)
            os.replace(tmp, path)
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise
        return path
