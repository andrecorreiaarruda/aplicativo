# Horus — visualizador, gravador e nó DICOM para Windows

Reimplementação do fluxo do [Horos](https://horosproject.org) (visualizador
DICOM livre, exclusivo do macOS) com a parte dependente de sistema isolada,
para rodar no Windows: base local de exames, visualizador 2D, gravação de
exames em CD/DVD, pendrive, imagem ISO ou pasta, com DICOMDIR, e rede DICOM
(recepção, envio, consulta e recuperação, auto-roteamento).

Como o Horos funciona, linha a linha, e o que substitui cada dependência
do macOS: [docs/EVIDENCIAS.md](docs/EVIDENCIAS.md).

> Não é um dispositivo médico certificado. Serve para consulta, entrega de
> exames e ensino, não para diagnóstico primário.

| Base de exames | Visualizador | Gravador |
|---|---|---|
| ![Base de exames](docs/img/navegador.png) | ![Visualizador](docs/img/visualizador.png) | ![Gravador](docs/img/gravador.png) |

As telas usam um exame sintético gerado pelos testes. No visualizador, a
ROI sobre o "tecido mole" mede 39,9 UH (valor gerado: 40 UH com ruído de
desvio 12), e a régua mede 140,80 mm (176 pixels de 0,8 mm).

## Funções

**Base de exames** (BrowserController / DicomDatabase)
- importa arquivos, pastas e mídias (lê o DICOMDIR quando houver), por
  menu ou arrastando para a janela;
- copia para `DATABASE.noindex\<lote>\<n>.dcm`, como o Horos, ou só
  referencia (modo disco);
- pesquisa por paciente, ID, descrição, nº de acesso e modalidade;
- miniaturas por série; exclusão; anonimização em cópias novas.

**Visualizador** (ViewerController / DCMView / DCMPix)
- rescale, janela linear, MONOCHROME1, RGB, paleta, multiquadro e objetos
  "enhanced"; codecs JPEG, JPEG-LS (leitura) e JPEG 2000;
- ferramentas: janela, mover, zoom, navegar, régua (mm) e ROI retangular
  (média, DP, mín., máx. e área); predefinições de TC (abdome, cérebro,
  osso, pulmão); inverter, girar, espelhar, cine e exportação em PNG/JPEG;
- anotações nos quatro cantos e valor do pixel sob o cursor (UH em TC).

| Ação | Mouse / teclado |
|---|---|
| ferramenta corrente | botão esquerdo |
| zoom | botão direito, Shift + arrastar, Ctrl + roda |
| mover | botão do meio, Ctrl + arrastar |
| janela | Alt + arrastar (ferramenta "Janela": arrastar para cima/baixo muda o nível, para os lados a largura) |
| imagem anterior/seguinte | roda, ↑ ↓ ← →, PgUp/PgDn (10), Home/End |
| ferramentas | W janela, M mover, Z zoom, N navegar, L régua, O ROI |
| outros | I inverter, `[` `]` girar, H espelhar, R restaurar, Espaço cine, A anotações, Del apaga a última medida, duplo clique ajusta à janela |

**Gravador** (BurnerWindowController)
- nome do disco sugerido pelo paciente (ou `EXAMES_AAAAMMDD` com vários
  pacientes/anonimização), até 15 caracteres — limite do Windows;
- manter, comprimir (JPEG 2000 sem perdas) ou descomprimir, preservando o
  SOPInstanceUID; conversão de big endian;
- DICOMDIR no perfil de mídia geral (como o DCMTK que o Horos usa);
- extras: o próprio Horus para Windows no disco (com `AUTORUN.INF`),
  página `INDEX.HTM` com miniaturas, pasta suplementar e ZIP com senha
  (AES-256);
- destinos:
  - **CD/DVD** pelo IMAPI2 (a API de gravação do Windows). Mostra a mídia e
    o espaço livre e confere a capacidade antes de gravar. Se a política
    da máquina impedir o script, a ISO é aberta no Gravador de Imagem de
    Disco do Windows;
  - **pendrive**: apaga o conteúdo depois de confirmar, copia, renomeia o
    volume e ejeta;
  - **imagem ISO** (ISO 9660 + Joliet; o Windows monta com duplo clique);
  - **pasta**.

## Rede DICOM

O menu **Rede** reúne consulta (Ctrl+K), envio (Ctrl+E), regras de
roteamento, configurações e o registro de atividade. Por baixo está o
pynetdicom, no lugar do DCMTK que o Horos embute.

**Este computador.** O Horus abre um listener (Storage SCP) assim que
inicia. O AE title padrão é o nome curto da máquina, até 16 caracteres, e a
porta padrão é 11112, como no Horos. Para receber exames de um equipamento
ou PACS, cadastre nele o AE title, um dos endereços mostrados em
*Configurações de rede → Este computador* e a porta. No Windows, a porta
precisa estar liberada no Firewall do Windows Defender. O botão "Liberar a
porta no Firewall do Windows…" cria a regra e pede confirmação de
administrador. O mesmo listener responde a C-FIND, C-MOVE e C-GET, então
outros equipamentos podem consultar a base do Horus. Isso pode ser
desligado, assim como dá para aceitar conexões só de nós cadastrados.

**Nós remotos.** Para cada PACS ou equipamento, informe a descrição, o AE
title, o endereço, a porta, a sintaxe de envio, o número de associações
simultâneas (1, 2 ou 4) e o modo de recuperação. "Testar conexão" faz um
C-ECHO. Quem vem do Horos importa a lista em *Importar do Horos…*; o
arquivo é o `DICOMNodes.plist` que o painel Locations do Horos salva.

**C-MOVE ou C-GET.** No C-MOVE, o PACS abre uma conexão de volta para o
listener do Horus. O Horus precisa estar cadastrado no PACS, com AE
title, IP e porta, e a porta liberada no firewall. É o modo mais
compatível e a causa mais comum de falha ("destino desconhecido",
0xA801). No C-GET, as imagens voltam pela mesma conexão: não exige
cadastro nem porta aberta, o que serve atrás de NAT ou VPN, mas nem todo
PACS oferece.

**Consulta.** Nome e descrição buscam pelo início ("silva" acha "SILVA^JOAO");
ID e número de acesso, exatos. Há presets de data como os do Horos e filtro
por modalidade. Exames que já estão na base aparecem em verde; expandir um
exame lista as séries. A recuperação pode ser cancelada: o Horus manda
C-CANCEL e, se o PACS não atender, encerra a associação.

**Auto-roteamento.** Em *Configurações de rede → Auto-roteamento*, cada
regra manda as imagens novas a um nó. O filtro combina origem (recebidas
pela rede, importadas, geradas pelo Horus ou todas), modalidades, AE de
origem e trecho da descrição. A fila fica na base: falhas são repetidas a
cada 30 s, até o limite da regra, e o que estava na fila continua depois
de reabrir o programa. *Rede → Aplicar regras de roteamento à seleção*
manda exames já existentes pelas regras ativas.

| Consulta e recuperação | Este computador |
|---|---|
| ![Consulta](docs/img/consulta.png) | ![Rede local](docs/img/rede_local.png) |
| **Nós remotos** | **Auto-roteamento** |
| ![Nós](docs/img/rede_nos.png) | ![Auto-roteamento](docs/img/roteamento.png) |

O registro de rede fica em `logs\rede.log`, dentro da pasta da base.

## Rodar a partir do código

Requer Python 3.10 ou mais novo (64 bits).

```powershell
cd horus
py -3 -m venv .venv
.venv\Scripts\python -m pip install -e ".[zip]"
.venv\Scripts\python -m horus
```

No Linux ou macOS, o mesmo vale com `python3 -m venv .venv` e
`.venv/bin/python -m horus`.

Opções de linha de comando:

```text
horus [arquivos/pastas/DICOMDIR ...]   importa ao abrir
horus --disc                           lê a mídia de onde o executável roda, sem copiar
horus --data-dir PASTA                 usa outra base local
```

## Gerar o executável do Windows

No Windows, a partir da pasta `horus`:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1
```

O script cria o ambiente virtual, roda os testes, gera o ícone, empacota
com PyInstaller em `dist\Horus\Horus.exe` e roda o autoteste do
executável. Com o [Inno Setup 6](https://jrsoftware.org/isinfo.php)
instalado, gera também `dist\Horus-<versão>-setup.exe`. O instalador é por
usuário e não pede administrador.

O workflow `.github/workflows/horus-windows.yml` faz o mesmo num runner
Windows do GitHub Actions e publica o executável e o instalador como
artefato.

## Onde ficam os dados

| | Windows | macOS | Linux |
|---|---|---|---|
| base | `%LOCALAPPDATA%\Horus\Horus Data` | `~/Documents/Horus Data` | `~/.local/share/horus/Horus Data` |
| preparo do disco | `%TEMP%\Horus` | `$TMPDIR/Horus` | `/tmp/Horus` |

`HORUS_DATA_DIR` ou `--data-dir` mudam o local da base. No Windows a base
fica em `LOCALAPPDATA`, e não em Documentos, porque Documentos costuma
estar no OneDrive, que enviaria os exames para a nuvem.

## Testes

```bash
cd horus
python -m pip install -e ".[zip,dev]"
QT_QPA_PLATFORM=offscreen python -m pytest -q
```

Os testes geram exames sintéticos; nenhum dado de paciente entra no
repositório. Os de rede abrem associações de verdade em 127.0.0.1. Com o
DCMTK instalado (`apt install dcmtk`), `tests/test_net_dcmtk.py` confere a
interoperabilidade com `echoscu`, `storescu`, `findscu`, `getscu`,
`movescu`, `storescp` e `dcmqrscp`. `tests/test_windows_real.py` só roda no Windows, porque chama
o IMAPI2 e a API Win32 de verdade.

## Estrutura

```text
horus/
  src/horus/
    dicom/        pixels (DCMPix), série, predefinições, miniaturas, gravação de arquivos
    database.py   base local (DicomDatabase)
    importer.py   detecção de DICOM e leitura de DICOMDIR
    anonymize.py  anonimização (Anonymization)
    burn/         preparo do disco, DICOMDIR, ISO e destinos (BurnerWindowController)
    net/          rede DICOM: listener e Q/R SCP, cliente (eco, envio, consulta,
                  recuperação), configuração, auto-roteamento, lista de nós do Horos
    platform/     Windows (IMAPI2, Win32, firewall), macOS (drutil/diskutil) e Linux
    gui/          interface Qt: navegador, visualizador, gravador, rede
    selftest.py   autoteste do executável empacotado
  packaging/      PyInstaller, ícone, build do Windows e instalador
  tests/
  docs/EVIDENCIAS.md
```

## Limitações

- só 2D: sem MPR, 3D, renderização de volume ou fusão PET/CT;
- rede sem WADO, sem Bonjour e sem envio com compressão com perdas; o
  roteamento não tem agendamento por horário (ver a seção 7 de
  [docs/EVIDENCIAS.md](docs/EVIDENCIAS.md));
- ROIs só de régua e retângulo;
- durante a escrita em CD/DVD o progresso é indeterminado, porque o
  IMAPI2 não entrega eventos ao PowerShell durante `Write`;
- texto gravado dentro da imagem (ultrassom, capturas de tela) não é
  removido pela anonimização;
- a gravação física em CD/DVD e pendrive ainda precisa ser homologada num
  Windows com gravador e pendrive. No CI (Windows Server, sem gravador),
  o script IMAPI2 e a listagem de volumes rodam de verdade, mas não há
  mídia para gravar.
