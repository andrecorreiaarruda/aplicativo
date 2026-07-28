#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK não encontrado no PATH." >&2
  exit 1
fi

backup_dir="$(mktemp -d)"
trap 'rm -rf "$backup_dir"' EXIT
cp -R lib assets test pubspec.yaml analysis_options.yaml "$backup_dir"/

flutter create . \
  --project-name servicelog_ai \
  --org br.com.orionmed \
  --platforms android,ios,web,windows,macos,linux

rm -rf lib assets test
cp -R "$backup_dir/lib" "$backup_dir/assets" "$backup_dir/test" .
cp "$backup_dir/pubspec.yaml" "$backup_dir/analysis_options.yaml" .

flutter pub get
dart format lib test
flutter analyze
flutter test

echo "Projeto Flutter preparado e validado."
