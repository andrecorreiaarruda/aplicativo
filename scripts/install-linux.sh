#!/usr/bin/env bash
#
# Instala o ORION ServiceLog como aplicativo de desktop no Linux.
#
# Compila em modo release, copia o bundle para o diretório do usuário e
# registra um lançador, de modo que o programa passe a aparecer no menu e
# abra como qualquer outro aplicativo, sem terminal.
#
#   ./scripts/install-linux.sh              instala ou atualiza
#   ./scripts/install-linux.sh --uninstall  remove
#   ./scripts/install-linux.sh --no-build   reinstala o bundle já compilado
#
# Não requer root: tudo é gravado sob ~/.local, que é o diretório por usuário
# previsto na XDG Base Directory Specification.

set -euo pipefail

APP_ID="br.com.orionmed.servicelog_ai"
APP_NAME="ORION ServiceLog"
BINARY_NAME="servicelog_ai"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="$DATA_HOME/orion-servicelog"
DESKTOP_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/512x512/apps"
DESKTOP_FILE="$DESKTOP_DIR/$APP_ID.desktop"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m/!\\\033[0m %s\n' "$*" >&2; }
erro()  { printf '\033[1;31mxxx\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Desinstalação
# ---------------------------------------------------------------------------

desinstalar() {
  info "Removendo $APP_NAME"
  rm -rf "$INSTALL_DIR"
  rm -f "$DESKTOP_FILE" "$ICON_DIR/$APP_ID.png"
  atualizar_caches
  # O banco SQLite fica fora de INSTALL_DIR: path_provider o coloca em
  # $XDG_DATA_HOME/<application id>, usando o nome do executável apenas
  # como fallback de instalações antigas. Remover o aplicativo não pode
  # apagar os atendimentos do usuário, ainda mais havendo fila offline
  # não sincronizada.
  info "Removido. Os dados locais foram preservados em:"
  for dados in "$DATA_HOME/$APP_ID" "$DATA_HOME/$BINARY_NAME"; do
    [ -d "$dados" ] && info "  $dados"
  done
  info "Para apagá-los também, remova os diretórios acima."
  exit 0
}

atualizar_caches() {
  # Ambos são otimizações do ambiente gráfico: sem eles o lançador ainda
  # funciona, apenas pode demorar a aparecer no menu.
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$DATA_HOME/icons/hicolor" >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------

COMPILAR=1
for arg in "$@"; do
  case "$arg" in
    --uninstall|--remove) desinstalar ;;
    --no-build) COMPILAR=0 ;;
    -h|--help)
      sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) erro "Opção desconhecida: $arg" ;;
  esac
done

cd "$PROJECT_ROOT"

# ---------------------------------------------------------------------------
# Compilação
# ---------------------------------------------------------------------------

if [ "$COMPILAR" -eq 1 ]; then
  command -v flutter >/dev/null 2>&1 \
    || erro "flutter não encontrado no PATH. Consulte FLUTTER_SETUP.md."

  # As credenciais do Supabase entram por String.fromEnvironment, que é
  # resolvida em tempo de compilação. Sem passá-las aqui, o aplicativo
  # instalado nasce sem backend e cai no modo local — e o sintoma só
  # aparece depois, na tela de login, longe da causa.
  DEFINES=()
  if [ -f "$PROJECT_ROOT/.env" ]; then
    info "Usando credenciais de .env"
    DEFINES+=(--dart-define-from-file="$PROJECT_ROOT/.env")
  else
    warn "Arquivo .env ausente: o aplicativo será instalado SEM conexão com o"
    warn "Supabase e funcionará apenas com dados locais. Para conectar, copie"
    warn ".env.example para .env, preencha as chaves e rode este script de novo."
  fi

  info "Compilando em modo release (pode levar alguns minutos)"
  flutter build linux --release "${DEFINES[@]}"
fi

# ---------------------------------------------------------------------------
# Localização do bundle
# ---------------------------------------------------------------------------

# O diretório carrega a arquitetura, que difere entre x64 e arm64.
BUNDLE=""
for candidato in build/linux/*/release/bundle; do
  [ -d "$candidato" ] && BUNDLE="$candidato"
done

[ -n "$BUNDLE" ] \
  || erro "Bundle não encontrado. Rode sem --no-build para compilar primeiro."
[ -x "$BUNDLE/$BINARY_NAME" ] \
  || erro "Executável $BINARY_NAME ausente em $BUNDLE."

# ---------------------------------------------------------------------------
# Instalação
# ---------------------------------------------------------------------------

info "Instalando em $INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# Substitui o conteúdo anterior: um bundle antigo pode conter bibliotecas
# que não existem mais na versão nova, e misturar as duas quebra a execução.
rm -rf "${INSTALL_DIR:?}"/*
cp -r "$BUNDLE"/. "$INSTALL_DIR/"

if [ -f "$PROJECT_ROOT/assets/branding/orion-icon.png" ]; then
  cp "$PROJECT_ROOT/assets/branding/orion-icon.png" "$ICON_DIR/$APP_ID.png"
  ICONE="$APP_ID"
else
  warn "Ícone não encontrado; o lançador usará o ícone padrão do sistema."
  ICONE="application-x-executable"
fi

info "Registrando o lançador"
cat > "$DESKTOP_FILE" <<DESKTOPEOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$APP_NAME
GenericName=Registro técnico
Comment=Registro de atendimentos, histórico de falhas e assistência por IA
Exec=$INSTALL_DIR/$BINARY_NAME %U
Icon=$ICONE
Terminal=false
Categories=Office;ProjectManagement;
StartupNotify=true
StartupWMClass=$APP_ID
DESKTOPEOF

chmod +x "$DESKTOP_FILE" "$INSTALL_DIR/$BINARY_NAME"
atualizar_caches

info "Pronto."
info "$APP_NAME está no menu de aplicativos. Se não aparecer de imediato,"
info "encerre e reabra a sessão gráfica."
