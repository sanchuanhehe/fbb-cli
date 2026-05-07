# fbb — HiSpark fbb framework build CLI

One-command build environment for any HiSpark **fbb framework** SDK
(`fbb_ws63`, `fbb_bs2x`, and future `fbb_*` chip SDKs). Runs on Windows,
Linux, and macOS.

```
fbb build -c <target>    # e.g. fbb build -c ws63-liteos-app
```

No `source` step. `fbb` self-activates the Python venv and toolchain on
every invocation.

## Quick start

### I already have uv

```bash
uv tool install git+https://github.com/sanchuanhehe/fbb-cli.git
fbb setup
```

That's it. `uv tool install` puts `fbb` on your PATH; `fbb setup` provisions
Python 3.11.4, the build venv, and the RISC-V toolchain into
`~/.fbb_hispark`.

### One-liner (bootstraps uv too)

#### Linux / macOS

```bash
curl -sL https://raw.githubusercontent.com/sanchuanhehe/fbb-cli/main/script/install.sh | bash
```

#### Windows

```powershell
irm https://raw.githubusercontent.com/sanchuanhehe/fbb-cli/main/script/install.ps1 | iex
```

The one-liner installs uv, then runs `uv tool install` + `fbb setup`. Open a
new terminal if `fbb` isn't found immediately (uv's tool bin dir needs to be
on PATH, which already happens if you've used uv before).

### Build

Once installed, build any fbb-framework SDK:

```bash
cd ~/hispark/fbb_ws63/src
fbb build -c ws63-liteos-app
```

## Install options

| Option | Effect |
|---|---|
| `-d <path>` / `--install-dir <path>` | Custom install directory (default: `~/.fbb_hispark`) |
| `--skip-tools` | Python-only setup, skip toolchain download |
| `--force` | Wipe and reinstall everything |
| `--uv-version <ver>` | Pin a specific `uv` release |

### Bash

```bash
curl -sL .../install.sh | bash -s -- -d /opt/fbb --skip-tools
```

### PowerShell

```powershell
$env:FBB_HOME = 'C:\hispark\fbb'
irm .../install.ps1 | iex
```

## Mirror configuration

All defaults are Chinese mirrors. Override via environment variables:

| Variable | Default | Used by |
|---|---|---|
| `FBB_PIP_INDEX` | `https://pypi.tuna.tsinghua.edu.cn/simple` | pip / uv pip |
| `UV_PYTHON_INSTALL_MIRROR` | `https://mirror.nju.edu.cn/.../python-build-standalone/Latest` | uv python install |
| `FBB_OBS_BASE` | `https://hispark-obs.obs.cn-east-3.myhuaweicloud.com` | Toolchain download |

```bash
export FBB_PIP_INDEX='https://mirrors.aliyun.com/pypi/simple/'
curl -sL .../install.sh | bash
```

## Commands

```
fbb setup                  Provision build environment (Python 3.11.4, venv, toolchain)
fbb build -c <target>     Build a named target
fbb run -- <cmd> [args]   Run any command inside the activated environment
fbb doctor                Check environment health
fbb shell                 Spawn a subshell with the environment activated
fbb env --print {sh|ps1|bat|json}
                          Print activation snippet
fbb help                  Show help
```

### SDK auto-detection

`fbb build` and `fbb doctor` resolve the SDK directory:

1. `--sdk-dir <path>` flag
2. `FBB_SDK_DIR` environment variable
3. Walk up from the current directory looking for `src/build.py`

## What gets installed

```
~/.local/bin/
└── fbb                  The CLI (managed by uv tool)

~/.fbb_hispark/
├── venv/                 Python virtual environment (numpy, kconfiglib, ...)
├── toolchain/            HiSpark RISC-V toolchain (gcc, ninja, etc.)
└── install.log           Full install transcript
```

## Troubleshooting

Always start with `fbb doctor` — it checks every component and prints fix
commands:

```
fbb doctor --sdk-dir ~/hispark/fbb_ws63
```

Common issues:

| Symptom | Fix |
|---|---|
| `[fbb] Python not found` | Re-run the installer |
| `ModuleNotFoundError: numpy` | Use `fbb run python` not bare `python` |
| `ninja: fatal: ...` | Toolchain missing; `fbb doctor` to confirm, then reinstall with `--force` |
| Behind a proxy | Set `HTTPS_PROXY` / `HTTP_PROXY` before installing |

To start over:

```bash
rm -rf ~/.fbb_hispark
curl -sL .../install.sh | bash
```

## Development

```bash
git clone https://github.com/sanchuanhehe/fbb-cli.git
cd fbb-cli

# install in editable mode
uv venv
uv pip install -e .

# run locally
python -m fbb_cli doctor
python -m fbb_cli build -c <target>
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
