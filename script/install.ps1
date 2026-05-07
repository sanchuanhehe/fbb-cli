# ============================================================
#  fbb CLI installer — Windows (PowerShell)
#
#  One-liner:
#    irm https://raw.gitcode.com/nearlink-vip/fbb-env-install/raw/main/script/install.ps1 | iex
#
#  Or locally:
#    .\script\install.ps1
#    .\script\install.ps1 -InstallDir C:\hispark\fbb
#    .\script\install.ps1 -SkipTools -Force
# ============================================================
param(
    [string]$InstallDir = "$env:USERPROFILE\.fbb_hispark",
    [switch]$SkipTools,
    [switch]$Force,
    [string]$UvVersion = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ---- defaults ------------------------------------------------------------
$PythonVersion = "3.11.4"
$PipIndex       = if ($env:FBB_PIP_INDEX)       { $env:FBB_PIP_INDEX }       else { "https://pypi.tuna.tsinghua.edu.cn/simple" }
$UvPyMirror     = if ($env:UV_PYTHON_INSTALL_MIRROR) { $env:UV_PYTHON_INSTALL_MIRROR } else { "https://mirror.nju.edu.cn/github-release/indygreg/python-build-standalone/Latest" }
$ObsBase        = if ($env:FBB_OBS_BASE)         { $env:FBB_OBS_BASE }         else { "https://hispark-obs.obs.cn-east-3.myhuaweicloud.com" }

$env:UV_INDEX_URL = $PipIndex
$env:UV_PYTHON_INSTALL_MIRROR = $UvPyMirror

# ---- helpers -------------------------------------------------------------
function Write-Cyan   { Write-Host $args -ForegroundColor Cyan }
function Write-Green  { Write-Host $args -ForegroundColor Green }
function Write-Yellow { Write-Host $args -ForegroundColor Yellow }
function Write-Red    { Write-Host $args -ForegroundColor Red }

# ---- force reset ---------------------------------------------------------
if ($Force) {
    Write-Yellow "[FORCE] removing $InstallDir ..."
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$StateFile = Join-Path $InstallDir ".install-state.json"
$State = @{}
if (Test-Path $StateFile) {
    try { $State = Get-Content $StateFile | ConvertFrom-Json -AsHashtable } catch { $State = @{} }
}
function Test-Done { param([string]$step) return $State.ContainsKey($step) }
function Mark-Done  { param([string]$step) $State[$step] = $true; $State | ConvertTo-Json | Set-Content $StateFile }

# ---- banner --------------------------------------------------------------
Write-Cyan "============================================"
Write-Cyan "  fbb CLI installer (Windows)"
Write-Cyan "============================================"
Write-Host "Install dir       : $InstallDir"
Write-Host "PyPI index        : $PipIndex"
Write-Host "Python version    : $PythonVersion"
if ($env:HTTPS_PROXY -or $env:HTTP_PROXY) { Write-Host "Proxy             : $($env:HTTPS_PROXY)$($env:HTTP_PROXY)" }
Write-Host ""

# ============================================================
# 1. Get uv
# ============================================================
$uvBin = $null
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if ($uvCmd) {
    $uvBin = $uvCmd.Source
    Write-Yellow "[SKIP] uv already in PATH: $uvBin"
} else {
    Write-Host "[1/6] installing uv ..."
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

# ============================================================
# 2. Install Python
# ============================================================
Write-Host "[2/6] preparing Python $PythonVersion ..."
& $uvBin python install $PythonVersion 2>$null
$pyFound = & $uvBin python find $PythonVersion 2>$null | Select-Object -First 1
if (-not $pyFound -or -not (Test-Path $pyFound.Trim())) {
    Write-Red "[ERROR] uv could not find Python $PythonVersion"
    exit 1
}
Write-Green "[OK] Python: $($pyFound.Trim())"

# ============================================================
# 3. Create venv
# ============================================================
$venvDir = Join-Path $InstallDir "venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

if ((Test-Done "venv") -and (Test-Path $venvPython)) {
    Write-Yellow "[SKIP] venv already exists"
} else {
    Remove-Item -Recurse -Force $venvDir -ErrorAction SilentlyContinue
    Write-Host "[3/6] creating venv ..."
    & $uvBin venv $venvDir --python $pyFound.Trim()
    @"
[global]
index-url = $PipIndex

[install]
disable-pip-version-check = true
"@ | Out-File -Encoding ascii (Join-Path $venvDir "pip.ini")
    Mark-Done "venv"
    Write-Green "[OK] venv: $venvDir"
}

# ============================================================
# 4. Install fbb-cli package
# ============================================================
Write-Host "[4/6] installing fbb-cli ..."

$pkgSrc = $null
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
if ((Test-Path (Join-Path $repoRoot "pyproject.toml")) -and (Test-Path (Join-Path $repoRoot "src\fbb_cli"))) {
    $pkgSrc = $repoRoot
    Write-Yellow "  using local source: $pkgSrc"
} else {
    $tmpDir = Join-Path $env:TEMP "fbb-cli-$([Guid]::NewGuid())"
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    $tmpZip = Join-Path $tmpDir "fbb-cli.zip"
    Write-Yellow "  downloading fbb-cli source ..."
    try {
        Invoke-WebRequest -Uri "https://raw.gitcode.com/nearlink-vip/fbb-env-install/repository/archive.zip?ref=main" -OutFile $tmpZip
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
        $found = Get-ChildItem -Path $tmpDir -Recurse -Filter "pyproject.toml" -Depth 3 | Select-Object -First 1
        if ($found) { $pkgSrc = $found.Directory.FullName }
    } catch {
        Write-Yellow "  download failed, trying alternate URL..."
    }
}

if (-not $pkgSrc -or -not (Test-Path (Join-Path $pkgSrc "pyproject.toml"))) {
    Write-Red "[ERROR] cannot find fbb-cli package source"
    exit 1
}

& $uvBin pip install $pkgSrc --python $venvPython --index-url $PipIndex
Write-Green "[OK] fbb-cli installed"

# ---- verify --------------------------------------------------------------
$checkResult = & $venvPython -m fbb_cli --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Red "[ERROR] fbb-cli install verification failed"
    exit 1
}

# ============================================================
# 5. Create launcher wrapper
# ============================================================
$binDir = Join-Path $InstallDir "bin"
Remove-Item -Recurse -Force $binDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

# PowerShell launcher
@"
# fbb launcher — PowerShell
# Add ~\.fbb_hispark\bin to your PATH, or symlink this file into a
# directory already on PATH.
param([string[]]`$args)

`$fbbHome = if (`$env:FBB_HOME) { `$env:FBB_HOME } else { "`$env:USERPROFILE\.fbb_hispark" }
`$venvDir = Join-Path `$fbbHome "venv"
`$python = Join-Path `$venvDir "Scripts\python.exe"

if (-not (Test-Path `$python)) {
    Write-Host "[fbb] Python not found at `$python" -ForegroundColor Red
    Write-Host "[fbb] Run: irm https://raw.gitcode.com/nearlink-vip/fbb-env-install/raw/main/script/install.ps1 | iex" -ForegroundColor Red
    exit 1
}

# collect toolchain bin dirs
`$tcDir = Join-Path `$fbbHome "toolchain"
if (Test-Path `$tcDir) {
    Get-ChildItem -Path `$tcDir -Directory -Recurse -Filter "bin" | ForEach-Object {
        `$env:PATH = "`$(`$_.FullName);`$env:PATH"
    }
}

`$env:VIRTUAL_ENV = `$venvDir
`$env:PATH = "`$(Join-Path `$venvDir 'Scripts');`$env:PATH"

& `$python -m fbb_cli @args
exit `$LASTEXITCODE
"@ | Out-File -Encoding utf8 (Join-Path $binDir "fbb.ps1")

# CMD launcher
@"
@echo off
setlocal

if not defined FBB_HOME set "FBB_HOME=%USERPROFILE%\.fbb_hispark"
set "VENV_DIR=%FBB_HOME%\venv"
set "PYTHON=%VENV_DIR%\Scripts\python.exe"

if not exist "%PYTHON%" (
    echo [fbb] Python not found at %PYTHON%
    echo [fbb] Run: irm https://raw.gitcode.com/nearlink-vip/fbb-env-install/raw/main/script/install.ps1 ^| iex
    exit /b 1
)

set "TC_DIR=%FBB_HOME%\toolchain"
if exist "%TC_DIR%" (
    for /d %%i in ("%TC_DIR%\*") do (
        if exist "%%i\bin" set "PATH=%%i\bin;%PATH%"
    )
)

set "VIRTUAL_ENV=%VENV_DIR%"
set "PATH=%VENV_DIR%\Scripts;%PATH%"

"%PYTHON%" -m fbb_cli %*
endlocal & exit /b %ERRORLEVEL%
"@ | Out-File -Encoding ascii (Join-Path $binDir "fbb.bat")

Write-Green "[OK] launcher: $binDir\fbb.ps1, fbb.bat"

# ============================================================
# 6. Toolchain (optional)
# ============================================================
$toolchainDir = Join-Path $InstallDir "toolchain"
if (-not $SkipTools) {
    $tcName = "HiSparkStudioToolchain-windows-x86_64.tar.gz"
    if ((Test-Done "toolchain") -and (Test-Path (Join-Path $toolchainDir "HiSparkStudioToolchain"))) {
        Write-Yellow "[SKIP] toolchain already installed"
    } else {
        Write-Host "[6/6] downloading toolchain ($tcName) ..."
        $tcTgz = Join-Path $env:TEMP "fbb-toolchain.tar.gz"
        try {
            Invoke-WebRequest -Uri "$ObsBase/$tcName" -OutFile $tcTgz
            Remove-Item -Recurse -Force $toolchainDir -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path $toolchainDir | Out-Null
            tar -xzf $tcTgz -C $toolchainDir
            Mark-Done "toolchain"
            Write-Green "[OK] toolchain: $toolchainDir"
        } catch {
            Write-Yellow "[WARN] toolchain not available at $ObsBase/$tcName"
            Write-Yellow "       use -SkipTools to suppress this, or drop a toolchain into $toolchainDir manually"
        }
        Remove-Item $tcTgz -ErrorAction SilentlyContinue
    }
} else {
    Write-Yellow "[SKIP] toolchain (-SkipTools)"
}

# ---- git check ------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Yellow "[WARN] git not found — install from https://git-scm.com/download/win"
} else {
    Write-Yellow "[SKIP] git: $(git --version)"
}

# ============================================================
# Done
# ============================================================
Write-Host ""
Write-Green "============================================"
Write-Green "  fbb CLI installed successfully"
Write-Green "============================================"
Write-Host ""
Write-Host "Layout:"
Write-Host "  install   : $InstallDir"
Write-Host "  venv      : $venvDir"
Write-Host "  launcher  : $binDir\fbb.ps1"
if (-not $SkipTools) { Write-Host "  toolchain : $toolchainDir" }
Write-Host ""

Write-Yellow "Add to your PATH to use fbb from anywhere:"
Write-Host ""
Write-Host "  [Environment]::SetEnvironmentVariable('PATH', '$binDir;' + [Environment]::GetEnvironmentVariable('PATH', 'User'), 'User')"
Write-Host ""
Write-Host "Open a NEW PowerShell / CMD window after setting PATH."

Write-Cyan "Then try:"
Write-Host "  fbb doctor"
Write-Host "  fbb build -c <target>"
