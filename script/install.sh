#!/usr/bin/env bash
# ============================================================
#  fbb CLI installer — Unix (Linux / macOS)
#
#  One-liner:
#    curl -sL https://raw.gitcode.com/nearlink-vip/fbb-env-install/raw/main/script/install.sh | bash
#
#  Or locally:
#    ./script/install.sh
#    ./script/install.sh --install-dir /opt/fbb-hispark
#    ./script/install.sh --skip-tools --force
# ============================================================
set -Eeuo pipefail

# ---- defaults ------------------------------------------------------------
FBB_HOME="${FBB_HOME:-$HOME/.fbb_hispark}"
SKIP_TOOLS=0
FORCE=0
UV_VERSION=""
PYTHON_VERSION="3.11.4"

# mirrors
PIP_INDEX="${FBB_PIP_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
UV_PY_MIRROR="${UV_PYTHON_INSTALL_MIRROR:-https://mirror.nju.edu.cn/github-release/indygreg/python-build-standalone/Latest}"
OBS_BASE="${FBB_OBS_BASE:-https://hispark-obs.obs.cn-east-3.myhuaweicloud.com}"
REPO_URL="${FBB_REPO_URL:-https://raw.gitcode.com/nearlink-vip/fbb-env-install/raw/main}"

# ---- helpers -------------------------------------------------------------
cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }

# ---- parse args ----------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--install-dir) FBB_HOME="$2"; shift 2;;
    --skip-tools)     SKIP_TOOLS=1; shift;;
    --force)          FORCE=1; shift;;
    --uv-version)     UV_VERSION="$2"; shift 2;;
    -h|--help)
      echo "Usage: install.sh [-d <dir>] [--skip-tools] [--force] [--uv-version <v>]"
      echo ""
      echo "Options:"
      echo "  -d, --install-dir <path>   Install directory (default: ~/.fbb_hispark)"
      echo "  --skip-tools               Skip toolchain download"
      echo "  --force                    Force reinstall (wipe existing)"
      echo "  --uv-version <ver>         Pin a specific uv release"
      exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

# ---- banner --------------------------------------------------------------
OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_NAME="$(uname -m)"
case "$ARCH_NAME" in x86_64|amd64) ARCH_NAME=x86_64;; arm64|aarch64) ARCH_NAME=aarch64;; esac

cyan "============================================"
cyan "  fbb CLI installer"
cyan "============================================"
echo "Install dir       : $FBB_HOME"
echo "PyPI index        : $PIP_INDEX"
echo "Python version    : $PYTHON_VERSION"
echo "OS / arch         : $OS_NAME / $ARCH_NAME"
[[ -n "${HTTPS_PROXY:-}${HTTP_PROXY:-}" ]] && echo "Proxy             : ${HTTPS_PROXY:-}${HTTP_PROXY:-}"
echo

# ---- force reset ---------------------------------------------------------
if [[ $FORCE -eq 1 ]]; then
  yellow "[FORCE] removing $FBB_HOME ..."
  rm -rf "$FBB_HOME"
fi

mkdir -p "$FBB_HOME"
LOG="$FBB_HOME/install.log"
exec > >(tee -a "$LOG") 2>&1

STATE="$FBB_HOME/.install-state"
mark_done() { echo "$1=done" >> "$STATE"; }
is_done()   { [[ -f "$STATE" ]] && grep -qE "^$1=done$" "$STATE"; }

export UV_INDEX_URL="$PIP_INDEX"
export UV_PYTHON_INSTALL_MIRROR="$UV_PY_MIRROR"

# ============================================================
# 1. Get uv
# ============================================================
UV_BIN=""
if command -v uv >/dev/null 2>&1; then
  UV_BIN="$(command -v uv)"
  yellow "[SKIP] uv already in PATH: $UV_BIN"
else
  echo "[1/6] installing uv ..."
  if command -v python3 >/dev/null 2>&1; then
    BOOT_PY="$(command -v python3)"
    BOOT_DIR="$FBB_HOME/uv-bootstrap"
    rm -rf "$BOOT_DIR"
    "$BOOT_PY" -m venv "$BOOT_DIR"
    "$BOOT_DIR/bin/pip" install --index-url "$PIP_INDEX" --upgrade pip >/dev/null
    if [[ -n "$UV_VERSION" ]]; then
      "$BOOT_DIR/bin/pip" install --index-url "$PIP_INDEX" "uv==$UV_VERSION"
    else
      "$BOOT_DIR/bin/pip" install --index-url "$PIP_INDEX" uv
    fi
    UV_BIN="$BOOT_DIR/bin/uv"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL https://astral.sh/uv/install.sh | sh
    UV_BIN="$HOME/.local/bin/uv"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://astral.sh/uv/install.sh | sh
    UV_BIN="$HOME/.local/bin/uv"
  else
    red "[ERROR] no python3 / curl / wget — cannot install uv"; exit 1
  fi
  if [[ ! -x "$UV_BIN" ]]; then red "[ERROR] uv install failed"; exit 1; fi
  green "[OK] uv: $UV_BIN"
fi

# ============================================================
# 2. Install Python
# ============================================================
echo "[2/6] preparing Python $PYTHON_VERSION ..."
"$UV_BIN" python install "$PYTHON_VERSION" || true
PY_FOUND="$("$UV_BIN" python find "$PYTHON_VERSION" 2>/dev/null | head -n1 | tr -d '\r' || true)"
if [[ -z "$PY_FOUND" || ! -x "$PY_FOUND" ]]; then
  red "[ERROR] uv could not find Python $PYTHON_VERSION"
  exit 1
fi
green "[OK] Python: $PY_FOUND"

# ============================================================
# 3. Create venv
# ============================================================
VENV_DIR="$FBB_HOME/venv"

if is_done venv && [[ -x "$VENV_DIR/bin/python" ]]; then
  yellow "[SKIP] venv already exists"
else
  rm -rf "$VENV_DIR"
  echo "[3/6] creating venv ..."
  "$UV_BIN" venv "$VENV_DIR" --python "$PY_FOUND"
  cat > "$VENV_DIR/pip.conf" <<EOF
[global]
index-url = $PIP_INDEX

[install]
disable-pip-version-check = true
EOF
  mark_done venv
  green "[OK] venv: $VENV_DIR"
fi

VENV_PY="$VENV_DIR/bin/python"

# ============================================================
# 4. Install fbb-cli package
# ============================================================
echo "[4/6] installing fbb-cli ..."

PKG_SRC=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0##*/}}")" 2>/dev/null && pwd || true)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || true)"
if [[ -f "$REPO_ROOT/pyproject.toml" && -d "$REPO_ROOT/src/fbb_cli" ]]; then
  PKG_SRC="$REPO_ROOT"
  yellow "  using local source: $PKG_SRC"
else
  TMP_SRC="$(mktemp -d)"
  TMP_TGZ="$TMP_SRC/fbb-cli.tar.gz"
  yellow "  downloading fbb-cli source ..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$TMP_TGZ" \
      "https://raw.gitcode.com/nearlink-vip/fbb-env-install/repository/archive.tar.gz?ref=main" \
      || curl -fsSL --retry 3 -o "$TMP_TGZ" \
      "https://api.gitcode.com/api/v5/repos/nearlink-vip/fbb-env-install/tarball/main"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$TMP_TGZ" \
      "https://raw.gitcode.com/nearlink-vip/fbb-env-install/repository/archive.tar.gz?ref=main"
  fi
  if [[ -s "$TMP_TGZ" ]]; then
    tar -xzf "$TMP_TGZ" -C "$TMP_SRC"
    # find the extracted directory
    EXTRACTED="$(find "$TMP_SRC" -maxdepth 2 -name 'pyproject.toml' -print -quit)"
    if [[ -n "$EXTRACTED" ]]; then
      PKG_SRC="$(dirname "$EXTRACTED")"
    fi
  fi
fi

if [[ -z "$PKG_SRC" || ! -f "$PKG_SRC/pyproject.toml" ]]; then
  red "[ERROR] cannot find fbb-cli package source"
  exit 1
fi

"$UV_BIN" pip install "$PKG_SRC" --python "$VENV_PY" --index-url "$PIP_INDEX"
green "[OK] fbb-cli installed"

# ---- verify fbb command available ----------------------------------------
if ! "$VENV_PY" -m fbb_cli --version >/dev/null 2>&1; then
  red "[ERROR] fbb-cli install verification failed"
  exit 1
fi

# ============================================================
# 5. Create launcher wrapper
# ============================================================
BIN_DIR="$FBB_HOME/bin"
rm -rf "$BIN_DIR"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/fbb" << 'WRAPPER'
#!/usr/bin/env bash
# fbb launcher — self-activates the environment on every invocation.
# Add ~/.fbb_hispark/bin to your PATH, or symlink this file into a
# directory already on PATH.
set -euo pipefail

_fbb_home="${FBB_HOME:-$HOME/.fbb_hispark}"
_venv_dir="$_fbb_home/venv"
_python="$_venv_dir/bin/python"

# auto-heal: if Python is missing, remind the user to re-run the installer
if [[ ! -x "$_python" ]]; then
  echo "[fbb] Python not found at $_python" >&2
  echo "[fbb] Run: curl -sL https://raw.gitcode.com/nearlink-vip/fbb-env-install/raw/main/script/install.sh | bash" >&2
  exit 1
fi

# collect toolchain bin dirs
_tc_path=""
_tc_dir="$_fbb_home/toolchain"
if [[ -d "$_tc_dir" ]]; then
  while IFS= read -r b; do
    _tc_path="$b:$_tc_path"
  done < <(find "$_tc_dir" -type d -name bin 2>/dev/null)
fi

export VIRTUAL_ENV="$_venv_dir"
export PATH="$_venv_dir/bin:$_tc_path$PATH"

exec "$_python" -m fbb_cli "$@"
WRAPPER

chmod +x "$BIN_DIR/fbb"
green "[OK] launcher: $BIN_DIR/fbb"

# ============================================================
# 6. Toolchain (optional)
# ============================================================
TOOLCHAIN_DIR="$FBB_HOME/toolchain"
if [[ $SKIP_TOOLS -eq 0 ]]; then
  TC_NAME="HiSparkStudioToolchain-$OS_NAME-$ARCH_NAME.tar.gz"
  if is_done toolchain && [[ -d "$TOOLCHAIN_DIR/HiSparkStudioToolchain" ]]; then
    yellow "[SKIP] toolchain already installed"
  else
    echo "[6/6] downloading toolchain ($TC_NAME) ..."
    TC_TGZ="$(mktemp -t fbb.XXXXXX.tar.gz)"
    if curl -fsSL --retry 3 -o "$TC_TGZ" "$OBS_BASE/$TC_NAME"; then
      rm -rf "$TOOLCHAIN_DIR"
      mkdir -p "$TOOLCHAIN_DIR"
      tar -xzf "$TC_TGZ" -C "$TOOLCHAIN_DIR"
      mark_done toolchain
      green "[OK] toolchain: $TOOLCHAIN_DIR"
    else
      yellow "[WARN] toolchain not available at $OBS_BASE/$TC_NAME"
      yellow "       skip toolchain-only setup — use --skip-tools to suppress this"
      yellow "       or drop a platform toolchain into $TOOLCHAIN_DIR manually"
    fi
    rm -f "$TC_TGZ"
  fi
else
  yellow "[SKIP] toolchain (--skip-tools)"
fi

# ---- git check ------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  yellow "[WARN] git not found — install via your package manager (apt/yum/brew install git)"
else
  yellow "[SKIP] git: $(git --version)"
fi

# ============================================================
# Done
# ============================================================
echo
green "============================================"
green "  fbb CLI installed successfully"
green "============================================"
echo
echo "Layout:"
echo "  install   : $FBB_HOME"
echo "  venv      : $VENV_DIR"
echo "  launcher  : $BIN_DIR/fbb"
[[ $SKIP_TOOLS -eq 0 ]] && echo "  toolchain : $TOOLCHAIN_DIR"
echo "  log       : $LOG"
echo

# check if the bin dir is on PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  yellow "Add to your PATH to use fbb from anywhere:"
  echo
  SHELL_RC=""
  case "${SHELL##*/}" in
    zsh)  SHELL_RC="$HOME/.zshrc";;
    bash) SHELL_RC="$HOME/.bashrc";;
    *)    SHELL_RC="$HOME/.profile";;
  esac
  printf "  echo 'export PATH=\"%s:\$PATH\"' >> %s\n" "$BIN_DIR" "$SHELL_RC"
  printf "  source %s\n" "$SHELL_RC"
  echo
  cyan "Then try:"
  echo "  fbb doctor"
  echo "  fbb build -c <target>"
else
  cyan "Try:"
  echo "  fbb doctor"
  echo "  fbb build -c <target>"
fi
