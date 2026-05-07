# fbb CLI — Agent Installation Guide

This guide is written for AI coding agents. Every tool call runs in a fresh
shell — the steps below ensure `fbb` is available regardless.

## Install

```bash
# 1. Ensure uv is available (installs to ~/.local/bin/)
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"

# 2. Install fbb CLI (also to ~/.local/bin/)
uv tool install git+https://github.com/sanchuanhehe/fbb-cli.git

# 3. Provision build environment (Python 3.11.4 + RISC-V toolchain)
export UV_PYTHON_INSTALL_MIRROR=https://mirror.nju.edu.cn/github-release/indygreg/python-build-standalone/Latest
export FBB_PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
export FBB_OBS_BASE=https://hispark-obs.obs.cn-east-3.myhuaweicloud.com
fbb setup
```

Verify with `fbb doctor`.

## Usage

| Task | Command |
|---|---|
| Build a target | `fbb build -t <target>` |
| Run a command in env | `fbb run -- <cmd> [args...]` |
| Diagnose env issues | `fbb doctor --sdk-dir <sdk-dir>` |
| Spawn activated shell | `fbb shell` |
| Print activation snippet | `fbb env --print sh` |
| Re-provision env | `fbb setup --force` |

## SDK targets

`fbb build` walks up from CWD looking for `src/build.py`. Pass `--sdk-dir` or
set `FBB_SDK_DIR` to specify explicitly.

Examples for `fbb_ws63`:

| Target | What it builds |
|---|---|
| `ws63-flashboot` | Bootloader |
| `ws63-loaderboot` | Loader |
| `ws63-liteos-app` | Main application |
| `ws63-liteos-mfg` | Manufacturing firmware |

## Critical anti-patterns

1. **Do NOT** run bare `python build.py` — use `fbb build -t <target>`.
2. **Do NOT** `source export.sh` — agent shells are stateless. Use `fbb <subcommand>`.
3. **Do NOT** move the SDK to a "shorter path" for cmdline errors — the
   path-shortener at `<sdk>/src/build/script/fbb_inc_shorten.py` handles it.

## Troubleshooting

```
fbb doctor --sdk-dir <sdk-dir>
fbb setup --force
uv tool install --force git+https://github.com/sanchuanhehe/fbb-cli.git
```
