# ============================================================
#  fbb CLI installer — Windows (PowerShell)
#
#  One-liner:
#    irm https://raw.githubusercontent.com/sanchuanhehe/fbb-cli/main/script/install.ps1 | iex
#
#  Locally:
#    .\script\install.ps1
#    .\script\install.ps1 -InstallDir C:\hispark\fbb -SkipTools -Force
#    .\script\install.ps1 -Yes
# ============================================================
param(
    [string]$InstallDir = "$env:USERPROFILE\.fbb_hispark",
    [switch]$SkipTools,
    [switch]$Force,
    [switch]$Yes,
    [string]$UvVersion = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ---- defaults ------------------------------------------------------------
$PythonVersion = "3.11.4"
$PipIndex   = if ($env:FBB_PIP_INDEX)             { $env:FBB_PIP_INDEX }             else { "https://pypi.tuna.tsinghua.edu.cn/simple" }
$UvPyMirror = if ($env:UV_PYTHON_INSTALL_MIRROR)  { $env:UV_PYTHON_INSTALL_MIRROR }  else { "https://mirror.nju.edu.cn/github-release/indygreg/python-build-standalone/Latest" }
$ObsBase    = if ($env:FBB_OBS_BASE)               { $env:FBB_OBS_BASE }               else { "https://hispark-obs.obs.cn-east-3.myhuaweicloud.com" }
$RepoUrl    = "git+https://github.com/sanchuanhehe/fbb-cli.git"

$env:UV_INDEX_URL = $PipIndex
$env:UV_PYTHON_INSTALL_MIRROR = $UvPyMirror

# ---- helpers -------------------------------------------------------------
function Write-Cyan   { Write-Host $args -ForegroundColor Cyan }
function Write-Green  { Write-Host $args -ForegroundColor Green }
function Write-Yellow { Write-Host $args -ForegroundColor Yellow }
function Write-Red    { Write-Host $args -ForegroundColor Red }

# ---- banner --------------------------------------------------------------
Write-Cyan "============================================"
Write-Cyan "  fbb CLI installer (Windows)"
Write-Cyan "============================================"
Write-Host "Build env dir     : $InstallDir"
Write-Host "PyPI index        : $PipIndex"
Write-Host "Python version    : $PythonVersion"
if ($env:HTTPS_PROXY -or $env:HTTP_PROXY) { Write-Host "Proxy             : $($env:HTTPS_PROXY)$($env:HTTP_PROXY)" }
Write-Host ""
Write-Host "The installer will:"
Write-Host "  1. Install uv (Python package manager)"
Write-Host "  2. Install fbb CLI via uv tool (auto-adds to PATH)"
Write-Host "  3. Run 'fbb setup' to provision build environment"
if (-not $SkipTools) { Write-Host "     (includes HiSpark RISC-V toolchain)" }
Write-Host ""

# ---- confirmation ---------------------------------------------------------
if (-not $Yes -and $env:FBB_YES -ne "1") {
    $reply = Read-Host "Proceed with installation? [y/N]"
    if ($reply -notmatch '^[Yy]') {
        Write-Red "Installation cancelled."
        exit 0
    }
    Write-Host ""
}

# ---- force reset ---------------------------------------------------------
if ($Force) {
    Write-Yellow "[FORCE] removing $InstallDir ..."
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# ============================================================
# 1. Install uv
# ============================================================
$uvBin = $null
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if ($uvCmd) {
    $uvBin = $uvCmd.Source
    Write-Yellow "[1/3] uv already in PATH: $uvBin"
} else {
    Write-Host "[1/3] installing uv ..."
    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        $bootDir = Join-Path $InstallDir "uv-bootstrap"
        Remove-Item -Recurse -Force $bootDir -ErrorAction SilentlyContinue
        & python3 -m venv $bootDir
        & "$bootDir\Scripts\pip.exe" install --index-url $PipIndex --upgrade pip
        if ($UvVersion) {
            & "$bootDir\Scripts\pip.exe" install --index-url $PipIndex "uv==$UvVersion"
        } else {
            & "$bootDir\Scripts\pip.exe" install --index-url $PipIndex uv
        }
        $uvBin = "$bootDir\Scripts\uv.exe"
    } else {
        Write-Host "  no python3 found, running astral.sh installer..."
        irm https://astral.sh/uv/install.ps1 | iex
        $uvBin = "$env:USERPROFILE\.local\bin\uv.exe"
    }
    if (-not (Test-Path $uvBin)) { Write-Red "[ERROR] uv install failed"; exit 1 }
    Write-Green "[OK] uv: $uvBin"
}

# Ensure uv is on PATH for the rest of this script
$uvDir = Split-Path -Parent $uvBin
if ($env:PATH -notlike "*$uvDir*") {
    $env:PATH = "$uvDir;$env:PATH"
}

# ============================================================
# 2. Install fbb CLI via uv tool
# ============================================================
Write-Host "[2/3] installing fbb CLI ..."
$toolList = & $uvBin tool list 2>$null
if ($toolList -match "fbb-cli") {
    if ($Force) {
        Write-Yellow "  reinstalling fbb-cli ..."
        & $uvBin tool install --force --reinstall $RepoUrl
    } else {
        Write-Yellow "  fbb-cli already installed — use -Force to reinstall"
    }
} else {
    & $uvBin tool install $RepoUrl
}
Write-Green "[OK] fbb CLI installed"

# Verify fbb is accessible
$fbbCmd = Get-Command fbb -ErrorAction SilentlyContinue
if ($fbbCmd) {
    Write-Green "       fbb: $($fbbCmd.Source)"
} else {
    $localFbb = "$env:USERPROFILE\.local\bin\fbb.exe"
    if (Test-Path $localFbb) {
        $env:PATH = "$(Split-Path -Parent $localFbb);$env:PATH"
        Write-Green "       fbb: $localFbb"
    } else {
        Write-Yellow "       fbb installed but may need a new shell to be available"
    }
}

# ============================================================
# 3. Run fbb setup
# ============================================================
Write-Host "[3/3] provisioning build environment ..."
$setupArgs = @("setup", "--install-dir", $InstallDir)
if ($Force)     { $setupArgs += "--force" }
if ($SkipTools) { $setupArgs += "--skip-tools" }

& fbb $setupArgs
if ($LASTEXITCODE -ne 0) {
    Write-Red "[ERROR] fbb setup failed"
    exit 1
}
Write-Green "[OK] build environment ready"

# ============================================================
# Done
# ============================================================
Write-Host ""
Write-Green "============================================"
Write-Green "  fbb CLI installed successfully"
Write-Green "============================================"
Write-Host ""
Write-Host "Layout:"
Write-Host "  fbb CLI      : $(Get-Command fbb -ErrorAction SilentlyContinue | % Source)"
Write-Host "  build env    : $InstallDir"
Write-Host "  venv         : $InstallDir\venv"
if (-not $SkipTools) { Write-Host "  toolchain    : $InstallDir\toolchain" }
Write-Host ""

if (-not (Get-Command fbb -ErrorAction SilentlyContinue)) {
    Write-Yellow "Open a new terminal for fbb to be available."
    Write-Host ""
}

Write-Cyan "Try:"
Write-Host "  fbb doctor"
Write-Host "  fbb build -c <target>"
