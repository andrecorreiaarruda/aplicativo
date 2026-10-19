<#
.SYNOPSIS
  Gera o Horus para Windows: ambiente virtual, testes, executável e instalador.

.DESCRIPTION
  Rode a partir da pasta "horus" do repositório, no PowerShell:

      powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1

  Resultado:
    dist\Horus\Horus.exe         aplicativo em pasta única (portátil)
    dist\Horus-<versão>-setup.exe instalador, se o Inno Setup 6 estiver instalado

  Requisitos: Python 3.10 ou mais novo (64 bits) no PATH ("py" ou "python").

.PARAMETER SkipTests
  Não roda a suíte de testes antes de empacotar.
#>
param([switch]$SkipTests)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }

if (-not (Test-Path .venv)) {
    Step 'Criando ambiente virtual (.venv)'
    if (Get-Command py -ErrorAction SilentlyContinue) { py -3 -m venv .venv } else { python -m venv .venv }
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível criar o ambiente virtual (Python 3.10+ instalado?).' }
}
$venvPython = Join-Path $root '.venv\Scripts\python.exe'

Step 'Instalando dependências'
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -e '.[zip,dev,build]'

if (-not $SkipTests) {
    Step 'Rodando os testes'
    $env:QT_QPA_PLATFORM = 'offscreen'
    & $venvPython -m pytest -q
    if ($LASTEXITCODE -ne 0) { throw 'Testes falharam; empacotamento interrompido.' }
    Remove-Item Env:\QT_QPA_PLATFORM
}

Step 'Gerando o ícone'
& $venvPython packaging\make_icon.py

Step 'Empacotando com PyInstaller'
& $venvPython -m PyInstaller packaging\horus.spec --noconfirm --clean
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller falhou.' }

Step 'Autoteste do executável'
$report = Join-Path $root 'dist\selftest.txt'
$proc = Start-Process -FilePath 'dist\Horus\Horus.exe' -ArgumentList '--self-test', "`"$report`"" -Wait -PassThru
Get-Content $report
if ($proc.ExitCode -ne 0) { throw 'O autoteste do executável falhou.' }

$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($iscc) {
    Step 'Gerando o instalador (Inno Setup)'
    $version = (& $venvPython -c 'import horus; print(horus.__version__)').Trim()
    & $iscc "/DAppVersion=$version" packaging\horus.iss
} else {
    Write-Host 'Inno Setup 6 não encontrado: só a pasta dist\Horus foi gerada.' -ForegroundColor Yellow
}

Step 'Pronto: dist\Horus\Horus.exe'
