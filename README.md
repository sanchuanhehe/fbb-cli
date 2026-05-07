# fbb — HiSpark fbb framework build CLI

One-command build environment for any HiSpark **fbb framework** SDK
(`fbb_ws63`, `fbb_bs2x`, and future `fbb_*` chip SDKs). Runs on Windows,
Linux, and macOS.

```
fbb build -c <target>    # e.g. fbb build -c ws63-liteos-app
```

No `source` step. `fbb` self-activates the Python venv and toolchain on
every invocation.

## Skip This README

```
Read this and tell me what this project does and how to install it:
https://raw.githubusercontent.com/sanchuanhehe/fbb-cli/main/README.md
```

Paste that into your agent. It reads the README so you don't have to.

## For LLM Agents

Paste this into your AI coding agent (Claude Code, Cursor, etc.):

```
Read and follow the installation instructions at:
https://raw.githubusercontent.com/sanchuanhehe/fbb-cli/main/docs/install.md
```

Or fetch directly:

```bash
curl -s https://raw.githubusercontent.com/sanchuanhehe/fbb-cli/main/docs/install.md
```

## Quick start

### 1. Install uv

Follow the [uv installation guide](
https://docs.astral.sh/uv/getting-started/installation/).

```bash
# Linux / macOS
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
```

### 2. Install fbb

```bash
uv tool install git+https://github.com/sanchuanhehe/fbb-cli.git
fbb setup
```

Done. `uv tool install` puts `fbb` on your PATH; `fbb setup` provisions
Python 3.11.4, the build venv, and the RISC-V toolchain into
`~/.fbb_hispark`.

### 3. Build

```bash
cd ~/hispark/fbb_ws63/src
fbb build -c ws63-liteos-app
```

## Mirror configuration

If you're behind the GFW, set Chinese mirrors before running `fbb setup`:

```bash
export UV_PYTHON_INSTALL_MIRROR=https://mirror.nju.edu.cn/github-release/indygreg/python-build-standalone/Latest
export FBB_PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
export FBB_OBS_BASE=https://hispark-obs.obs.cn-east-3.myhuaweicloud.com

fbb setup
```

| Variable | Default | Used by |
|---|---|---|
| `FBB_PIP_INDEX` | `https://pypi.tuna.tsinghua.edu.cn/simple` | pip / uv pip |
| `UV_PYTHON_INSTALL_MIRROR` | `https://mirror.nju.edu.cn/.../python-build-standalone/Latest` | uv python install |
| `FBB_OBS_BASE` | `https://hispark-obs.obs.cn-east-3.myhuaweicloud.com` | Toolchain download |

## Commands

```
fbb setup                      Provision build environment (one-time)
fbb build -c <target>          Build a named target
fbb run -- <cmd> [args...]     Run any command inside the activated environment
fbb doctor                     Check environment health
fbb shell                      Spawn a subshell with the environment activated
fbb env --print {sh|ps1|bat|json}
                               Print activation snippet
```

### SDK auto-detection

`fbb build` and `fbb doctor` resolve the SDK directory:

1. `--sdk-dir <path>` flag
2. `FBB_SDK_DIR` environment variable
3. Walk up from the current directory looking for `src/build.py`

### Setup options

```
fbb setup --install-dir /opt/fbb    Custom build environment directory
fbb setup --skip-tools              Python-only, skip toolchain download
fbb setup --force                   Recreate venv from scratch
```

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
| `fbb: command not found` | `uv tool list` — if missing, re-run `uv tool install`; ensure `~/.local/bin` is on PATH |
| `[fbb] Python not found` | Run `fbb setup` to provision the build environment |
| `ModuleNotFoundError: numpy` | Use `fbb run python` not bare `python` |
| `ninja: fatal: ...` | Toolchain missing; run `fbb setup --force` |
| Behind a proxy | Set `HTTPS_PROXY` / `HTTP_PROXY` before any network operation |

To start over:

```bash
rm -rf ~/.fbb_hispark
uv tool uninstall fbb-cli
uv tool install git+https://github.com/sanchuanhehe/fbb-cli.git
fbb setup
```

## Development

```bash
git clone https://github.com/sanchuanhehe/fbb-cli.git
cd fbb-cli

uv venv
uv pip install -e .

python -m fbb_cli doctor
python -m fbb_cli build -c <target>
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
