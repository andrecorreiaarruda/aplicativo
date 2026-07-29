$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter SDK não encontrado no PATH."
}

$backup = Join-Path ([System.IO.Path]::GetTempPath()) ("servicelog-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $backup | Out-Null
try {
  Copy-Item lib, assets, test, pubspec.yaml, analysis_options.yaml -Destination $backup -Recurse

  flutter create . --project-name servicelog_ai --org br.com.orionmed --platforms android,ios,web,windows,macos,linux

  Remove-Item lib, assets, test -Recurse -Force
  Copy-Item (Join-Path $backup "lib"), (Join-Path $backup "assets"), (Join-Path $backup "test") -Destination . -Recurse
  Copy-Item (Join-Path $backup "pubspec.yaml"), (Join-Path $backup "analysis_options.yaml") -Destination . -Force

  flutter pub get
  dart run sqflite_common_ffi_web:setup --force
  dart format lib test
  flutter analyze
  flutter test
  Write-Host "Projeto Flutter preparado e validado."
}
finally {
  Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
}
