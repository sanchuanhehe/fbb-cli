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

### Linux / macOS

```bash
curl -sL https://raw.gitcode.com/nearlink-vip/fbb-env-install/raw/main/script/install.sh | bash
```

Add to PATH (the installer prints the exact command for your shell):

```bash
echo 'export PATH="$HOME/.fbb_hispark/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Then build:

```bash
cd ~/hispark/fbb_ws63/src
fbb build -c ws63-liteos-app
```

### Windows

```powershell
irm https://raw.gitcode.com/nearlink-vip/fbb-env-install/raw/main/script/install.ps1 | iex
```

Add to user PATH (open a new terminal after):

```powershell
[Environment]::SetEnvironmentVariable('PATH', "$env:USERPROFILE\.fbb_hispark\bin;" + [Environment]::GetEnvironmentVariable('PATH', 'User'), 'User')
```

Then build:

```powershell
cd D:\hispark\fbb_ws63\src
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
~/.fbb_hispark/
├── bin/
│   └── fbb              Shell launcher (add this dir to PATH)
├── venv/                 Python virtual environment
├── toolchain/            HiSpark RISC-V toolchain (gcc, ninja, etc.)
├── install.log           Full install transcript
└── .install-state        Resume marker for interrupted runs
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
git clone https://gitcode.com/nearlink-vip/fbb-env-install.git
cd fbb-env-install

# install in editable mode
uv venv
uv pip install -e .

# run locally
python -m fbb_cli doctor
python -m fbb_cli build -c <target>
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
