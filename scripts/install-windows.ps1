<#
.SYNOPSIS
  Instala o ORION ServiceLog como aplicativo de desktop no Windows.

.DESCRIPTION
  Compila em modo release, copia o programa para a pasta do usuário e cria
  o atalho no menu Iniciar, de modo que ele abra como qualquer outro
  aplicativo, sem terminal.

  Não requer administrador: tudo é gravado dentro do perfil do usuário.

.EXAMPLE
  .\scripts\install-windows.cmd
  Instala ou atualiza.

.EXAMPLE
  .\scripts\install-windows.cmd -Desktop
  Instala e cria também um atalho na área de trabalho.

.EXAMPLE
  .\scripts\install-windows.cmd -NoBuild
  Reinstala o que já foi compilado.

.EXAMPLE
  .\scripts\install-windows.cmd -Uninstall
  Remove o programa, preservando os dados locais.
#>
[CmdletBinding()]
param(
  [switch]$Uninstall,
  [switch]$NoBuild,
  [switch]$Desktop
)

$ErrorActionPreference = 'Stop'

$AppName = 'ORION ServiceLog'
$BinaryName = 'servicelog_ai.exe'
$ProcessName = 'servicelog_ai'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\$AppName"
$StartMenuLink = Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk"
$DesktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk"

# O banco e a sessão ficam fora da pasta do programa: o path_provider usa
# %APPDATA%\<CompanyName>\<ProductName>, lidos de windows\runner\Runner.rc.
# Se esses dois nomes mudarem lá, esta pasta muda junto e os dados antigos
# ficam para trás.
$DataDir = Join-Path $env:APPDATA "ORION\$AppName"

function Info([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Aviso([string]$Text) { Write-Host "/!\ $Text" -ForegroundColor Yellow }
function Falha([string]$Text) {
  Write-Host "xxx $Text" -ForegroundColor Red
  exit 1
}

# Com o programa aberto, o Windows mantém o executável e as DLLs
# bloqueados: a cópia pararia no meio e deixaria a instalação misturada.
function Exigir-ProgramaFechado {
  if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
    Falha "O $AppName está aberto. Feche a janela e rode de novo."
  }
}

function Criar-Atalho([string]$Caminho) {
  $shell = New-Object -ComObject WScript.Shell
  $atalho = $shell.CreateShortcut($Caminho)
  $atalho.TargetPath = Join-Path $InstallDir $BinaryName
  $atalho.WorkingDirectory = $InstallDir
  $atalho.Description = 'Registro de atendimentos de engenharia clínica'
  $atalho.Save()
}

# ---------------------------------------------------------------------------
# Desinstalação
# ---------------------------------------------------------------------------

if ($Uninstall) {
  Exigir-ProgramaFechado
  Info "Removendo $AppName"
  foreach ($alvo in @($InstallDir, $StartMenuLink, $DesktopLink)) {
    if (Test-Path -LiteralPath $alvo) {
      Remove-Item -LiteralPath $alvo -Recurse -Force
    }
  }
  # Remover o aplicativo não pode apagar os atendimentos do usuário, ainda
  # mais havendo fila offline não sincronizada.
  if (Test-Path -LiteralPath $DataDir) {
    Info 'Removido. Os dados locais foram preservados em:'
    Info "  $DataDir"
    Info 'Para apagá-los também, remova essa pasta.'
  } else {
    Info 'Removido.'
  }
  exit 0
}

Set-Location -LiteralPath $ProjectRoot

# ---------------------------------------------------------------------------
# Compilação
# ---------------------------------------------------------------------------

if (-not $NoBuild) {
  if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Falha 'flutter não encontrado no PATH. Consulte docs\60_WINDOWS.md.'
  }

  # As credenciais do Supabase entram por String.fromEnvironment, que é
  # resolvida em tempo de compilação. Sem passá-las aqui, o aplicativo
  # instalado nasce sem backend e cai no modo local.
  $argumentos = @('build', 'windows', '--release')
  if (Test-Path -LiteralPath (Join-Path $ProjectRoot '.env')) {
    Info 'Usando credenciais de .env'
    $argumentos += '--dart-define-from-file=.env'
  } else {
    Aviso 'Arquivo .env ausente: o aplicativo será instalado SEM conexão com o'
    Aviso 'Supabase e funcionará apenas com dados locais. Para conectar, copie'
    Aviso '.env.example para .env, preencha as chaves e rode este script de novo.'
  }

  Info 'Compilando em modo release (pode levar alguns minutos)'
  & flutter @argumentos
  if ($LASTEXITCODE -ne 0) {
    Falha 'A compilação falhou. A mensagem do Flutter está logo acima.'
  }
}

# ---------------------------------------------------------------------------
# Localização do programa compilado
# ---------------------------------------------------------------------------

# A pasta carrega a arquitetura, que difere entre x64 e arm64.
$Bundle = $null
$buildRoot = Join-Path $ProjectRoot 'build\windows'
if (Test-Path -LiteralPath $buildRoot) {
  $Bundle = Get-ChildItem -LiteralPath $buildRoot -Directory |
    ForEach-Object { Join-Path $_.FullName 'runner\Release' } |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ $BinaryName) } |
    Select-Object -First 1
}
if (-not $Bundle) {
  Falha 'Programa compilado não encontrado. Rode sem -NoBuild para compilar primeiro.'
}

# ---------------------------------------------------------------------------
# Instalação
# ---------------------------------------------------------------------------

Exigir-ProgramaFechado

Info "Instalando em $InstallDir"

# Substitui o conteúdo anterior: uma versão antiga pode conter bibliotecas
# que não existem mais na nova, e misturar as duas quebra a execução.
if (Test-Path -LiteralPath $InstallDir) {
  Remove-Item -LiteralPath $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $Bundle '*') -Destination $InstallDir -Recurse -Force

Info 'Criando o atalho no menu Iniciar'
Criar-Atalho $StartMenuLink
if ($Desktop) {
  Info 'Criando o atalho na área de trabalho'
  Criar-Atalho $DesktopLink
}

Info 'Pronto.'
Info "$AppName está no menu Iniciar."
