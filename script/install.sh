#!/usr/bin/env bash
# ============================================================
#  fbb CLI installer — Unix (Linux / macOS)
#
#  One-liner:
#    curl -sL https://raw.githubusercontent.com/sanchuanhehe/fbb-cli/main/script/install.sh | bash
#
#  Locally:
#    ./script/install.sh
#    ./script/install.sh -d ~/.fbb_hispark --skip-tools --force
# ============================================================
set -Eeuo pipefail

# ---- defaults ------------------------------------------------------------
FBB_HOME="${FBB_HOME:-$HOME/.fbb_hispark}"
SKIP_TOOLS=0
FORCE=0
YES=0
UV_VERSION=""
PYTHON_VERSION="3.11.4"

# mirrors
PIP_INDEX="${FBB_PIP_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
UV_PY_MIRROR="${UV_PYTHON_INSTALL_MIRROR:-https://mirror.nju.edu.cn/github-release/indygreg/python-build-standalone/Latest}"
OBS_BASE="${FBB_OBS_BASE:-https://hispark-obs.obs.cn-east-3.myhuaweicloud.com}"
REPO_URL="git+https://github.com/sanchuanhehe/fbb-cli.git"

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
    -y|--yes)         YES=1; shift;;
    -h|--help)
      echo "Usage: install.sh [-d <dir>] [--skip-tools] [--force] [-y]"
      echo ""
      echo "Options:"
      echo "  -y, --yes                   Skip confirmation prompt"
      echo "  -d, --install-dir <path>   Build environment directory (default: ~/.fbb_hispark)"
      echo "  --skip-tools               Skip toolchain download"
      echo "  --force                    Force reinstall"
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
echo "Build env dir     : $FBB_HOME"
echo "PyPI index        : $PIP_INDEX"
echo "Python version    : $PYTHON_VERSION"
echo "OS / arch         : $OS_NAME / $ARCH_NAME"
[[ -n "${HTTPS_PROXY:-}${HTTP_PROXY:-}" ]] && echo "Proxy             : ${HTTPS_PROXY:-}${HTTP_PROXY:-}"
echo
echo "The installer will:"
echo "  1. Install uv (Python package manager)"
echo "  2. Install fbb CLI via uv tool (auto-adds to PATH)"
echo "  3. Run 'fbb setup' to provision build environment"
[[ $SKIP_TOOLS -eq 0 ]] && echo "     (includes HiSpark RISC-V toolchain)"
echo

# ---- confirmation ---------------------------------------------------------
if [[ $YES -eq 0 && "${FBB_YES:-0}" == "0" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Proceed with installation? [y/N] " REPLY
  elif [[ -e /dev/tty ]]; then
    read -r -p "Proceed with installation? [y/N] " REPLY < /dev/tty
  else
    red "[ERROR] non-interactive — use -y to proceed unattended"
    exit 1
  fi
  if [[ ! "$REPLY" =~ ^[Yy] ]]; then
    red "Installation cancelled."
    exit 0
  fi
  echo
fi

# ---- force reset ---------------------------------------------------------
if [[ $FORCE -eq 1 ]]; then
  yellow "[FORCE] removing $FBB_HOME ..."
  rm -rf "$FBB_HOME"
fi

mkdir -p "$FBB_HOME"
LOG="$FBB_HOME/install.log"
exec > >(tee -a "$LOG") 2>&1

export UV_INDEX_URL="$PIP_INDEX"
export UV_PYTHON_INSTALL_MIRROR="$UV_PY_MIRROR"

# ============================================================
# 1. Install uv
# ============================================================
UV_BIN=""
if command -v uv >/dev/null 2>&1; then
  UV_BIN="$(command -v uv)"
  yellow "[1/3] uv already in PATH: $UV_BIN"
else
  echo "[1/3] installing uv ..."
  if command -v python3 >/dev/null 2>&1; then
    BOOT_PY="$(command -v python3)"
    BOOT_DIR="$FBB_HOME/uv-bootstrap"
    rm -rf "$BOOT_DIR"
    "$BOOT_PY" -m venv "$BOOT_DIR" 2>/dev/null || {
      yellow "  system python venv failed, trying astral.sh installer ..."
      curl -fsSL https://astral.sh/uv/install.sh | sh
      UV_BIN="$HOME/.local/bin/uv"
    }
    if [[ -z "$UV_BIN" && -x "$BOOT_DIR/bin/pip" ]]; then
      "$BOOT_DIR/bin/pip" install --index-url "$PIP_INDEX" --upgrade pip >/dev/null
      if [[ -n "$UV_VERSION" ]]; then
        "$BOOT_DIR/bin/pip" install --index-url "$PIP_INDEX" "uv==$UV_VERSION"
      else
        "$BOOT_DIR/bin/pip" install --index-url "$PIP_INDEX" uv
      fi
      UV_BIN="$BOOT_DIR/bin/uv"
    fi
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
  green "[OK] uv: $UV_BIN ($($UV_BIN --version 2>&1))"
fi

# Ensure uv is on PATH for the rest of this script
if [[ ":$PATH:" != *":$(dirname "$UV_BIN"):"* ]]; then
  export PATH="$(dirname "$UV_BIN"):$PATH"
fi

# ============================================================
# 2. Install fbb CLI via uv tool
# ============================================================
echo "[2/3] installing fbb CLI ..."
if "$UV_BIN" tool list 2>/dev/null | grep -q "fbb-cli"; then
  if [[ $FORCE -eq 1 ]]; then
    yellow "  reinstalling fbb-cli ..."
    "$UV_BIN" tool install --force --reinstall "$REPO_URL"
  else
    yellow "  fbb-cli already installed — use --force to reinstall"
  fi
else
  "$UV_BIN" tool install "$REPO_URL"
fi
green "[OK] fbb CLI installed"

# Verify fbb is accessible
if command -v fbb >/dev/null 2>&1; then
  green "       fbb: $(command -v fbb)"
elif [[ -x "$HOME/.local/bin/fbb" ]]; then
  export PATH="$HOME/.local/bin:$PATH"
  green "       fbb: $HOME/.local/bin/fbb"
else
  yellow "       fbb installed but may need a new shell or PATH refresh"
fi

# ============================================================
# 3. Run fbb setup
# ============================================================
echo "[3/3] provisioning build environment ..."
SETUP_ARGS=("--install-dir" "$FBB_HOME")
[[ $FORCE -eq 1 ]] && SETUP_ARGS+=("--force")
[[ $SKIP_TOOLS -eq 1 ]] && SETUP_ARGS+=("--skip-tools")

fbb setup "${SETUP_ARGS[@]}"
green "[OK] build environment ready"

# ============================================================
# Done
# ============================================================
echo
green "============================================"
green "  fbb CLI installed successfully"
green "============================================"
echo
echo "Layout:"
echo "  fbb CLI      : $(command -v fbb 2>/dev/null || echo "$HOME/.local/bin/fbb")"
echo "  build env    : $FBB_HOME"
echo "  venv         : $FBB_HOME/venv"
[[ $SKIP_TOOLS -eq 0 ]] && echo "  toolchain    : $FBB_HOME/toolchain"
echo "  log          : $LOG"
echo

if ! command -v fbb >/dev/null 2>&1; then
  yellow "Open a new terminal for fbb to be available, or run:"
  echo "  export PATH=\"$HOME/.local/bin:\$PATH\""
  echo
fi

cyan "Try:"
echo "  fbb doctor"
echo "  fbb build -c <target>"
