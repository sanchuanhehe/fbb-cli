"""fbb CLI entry point — argparse-based, following clig.dev conventions.

Usage:
    fbb setup                     # provision build environment (one-time)
    fbb build -c <target> [--sdk-dir <dir>]
    fbb run -- <cmd> [args...]
    fbb doctor [--sdk-dir <dir>]
    fbb shell
    fbb env --print {sh|ps1|bat|json}
    fbb help
    fbb version
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from fbb_cli import __version__
from fbb_cli.env_manager import (
    build_env,
    check_toolchain,
    check_venv,
    find_install_dir,
    find_python,
    find_sdk_dir,
    find_toolchain_dirs,
    find_venv_dir,
)

_GREEN = "\033[32m"
_RED = "\033[31m"
_YELLOW = "\033[33m"
_CYAN = "\033[36m"
_RESET = "\033[0m"


def _green(s: str) -> str:
    return f"{_GREEN}{s}{_RESET}"


def _red(s: str) -> str:
    return f"{_RED}{s}{_RESET}"


def _yellow(s: str) -> str:
    return f"{_YELLOW}{s}{_RESET}"


def _cyan(s: str) -> str:
    return f"{_CYAN}{s}{_RESET}"


def _add_install_dir_flag(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--install-dir",
        default=None,
        help="Path to the fbb install directory (default: $FBB_INSTALL_DIR or ~/.fbb_hispark)",
    )


def _add_sdk_dir_flag(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--sdk-dir",
        default=None,
        help="Path to the SDK checkout (default: auto-detected from CWD or $FBB_SDK_DIR)",
    )


# ---- build ----------------------------------------------------------------


def _cmd_build(args: argparse.Namespace) -> int:
    install_dir = _resolve_install_dir(args)
    sdk_dir = find_sdk_dir(explicit=args.sdk_dir or os.environ.get("FBB_SDK_DIR"))

    if sdk_dir is None:
        print(_red("error:") + " cannot find SDK directory", file=sys.stderr)
        print("  Set --sdk-dir, $FBB_SDK_DIR, or run from inside an fbb_* checkout.", file=sys.stderr)
        return 1

    build_py = (sdk_dir / "src" / "build.py") if (sdk_dir / "src" / "build.py").exists() else (sdk_dir / "build.py")
    if not build_py.exists():
        print(_red("error:") + f" build.py not found in {sdk_dir}", file=sys.stderr)
        return 1

    env = build_env(install_dir)
    python = find_python(find_venv_dir(install_dir))
    if python is None:
        print(_red("error:") + " python not found in venv — run the installer first", file=sys.stderr)
        return 1

    cmd = [str(python), str(build_py)]
    if getattr(args, "target", None):
        cmd.extend(["-c", args.target])

    return _exec(cmd, env=env, cwd=str(sdk_dir / "src"))


# ---- run ------------------------------------------------------------------


def _cmd_run(args: argparse.Namespace) -> int:
    install_dir = _resolve_install_dir(args)
    env = build_env(install_dir)

    cmd = args.cmd
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]

    if not cmd:
        print(_red("error:") + " nothing to run — use `fbb run -- <command> [args...]`", file=sys.stderr)
        return 2

    return _exec(cmd, env=env)


# ---- doctor ---------------------------------------------------------------


def _cmd_doctor(args: argparse.Namespace) -> int:
    install_dir = _resolve_install_dir(args)
    sdk_dir = find_sdk_dir(explicit=args.sdk_dir or os.environ.get("FBB_SDK_DIR"))

    print(_cyan("fbb doctor"))
    print(f"  install dir : {install_dir}")
    if sdk_dir:
        print(f"  sdk dir     : {sdk_dir}")
    else:
        print(_yellow("  sdk dir     :") + " not detected (ok if only checking env)")
    print()

    exit_code = 0

    # Check venv
    print(_cyan("[venv]"))
    problems = check_venv(install_dir)
    if problems:
        for p in problems:
            print(f"  {_red('✗')} {p}")
        exit_code = 1
    else:
        print(f"  {_green('✓')} venv ok")

    # Check toolchain
    print(_cyan("[toolchain]"))
    problems = check_toolchain(install_dir)
    if problems:
        for p in problems:
            print(f"  {_yellow('⚠')} {p}")
    else:
        print(f"  {_green('✓')} toolchain ok")

    # Check SDK patches if sdk_dir found
    if sdk_dir:
        print(_cyan("[sdk patches]"))
        shorten = sdk_dir / "src" / "build" / "script" / "fbb_inc_shorten.py"
        if shorten.exists():
            print(f"  {_green('✓')} path shortener: {shorten}")
        else:
            print(f"  {_yellow('⚠')} path shortener missing: {shorten}")
            exit_code = 1

        for cmake_file in (sdk_dir / "src" / "build" / "toolchains").glob("riscv32_musl_105*.cmake"):
            content = cmake_file.read_text()
            if "CMAKE_NINJA_FORCE_RESPONSE_FILE" in content:
                print(f"  {_green('✓')} response-file patch: {cmake_file.name}")
            else:
                print(f"  {_yellow('⚠')} response-file patch missing in: {cmake_file.name}")
                exit_code = 1

    # Print fix instructions
    if exit_code != 0:
        print()
        print(_cyan("[fix]"))
        print("  Run 'fbb setup' to repair the build environment:")
        print("    fbb setup --force")
        print()
        print("  If the CLI itself is broken, reinstall it:")
        print("    uv tool install --force git+https://github.com/sanchuanhehe/fbb-cli.git")

    return exit_code


# ---- shell ----------------------------------------------------------------


def _cmd_shell(args: argparse.Namespace) -> int:
    install_dir = _resolve_install_dir(args)
    env = build_env(install_dir)

    shell = os.environ.get("SHELL", "/bin/sh" if sys.platform != "win32" else "cmd.exe")
    print(_cyan("fbb shell") + f" — spawning {shell} with fbb environment activated")
    print("  Run 'exit' to leave.")
    return _exec([shell], env=env)


# ---- env ------------------------------------------------------------------


_TEMPLATES = {
    "sh": """# fbb activation — source this file or eval with: eval "$(fbb env --print sh)"
export VIRTUAL_ENV="{venv_dir}"
export PATH="{venv_bin}:{toolchain_bins}:$PATH"
""",
    "ps1": """# fbb activation — dot-source or: fbb env --print ps1 | Out-String | Invoke-Expression
$env:VIRTUAL_ENV = "{venv_dir}"
$env:PATH = "{venv_bin};{toolchain_bins};" + $env:PATH
""",
    "bat": """@echo off
REM fbb activation — call this file or: fbb env --print bat > %%TEMP%%\\_fbb_env.bat && call %%TEMP%%\\_fbb_env.bat
set VIRTUAL_ENV={venv_dir}
set PATH={venv_bin};{toolchain_bins};%PATH%
""",
}


def _cmd_env(args: argparse.Namespace) -> int:
    install_dir = _resolve_install_dir(args)
    venv_dir = find_venv_dir(install_dir)
    venv_bin = str(venv_dir / "bin") if sys.platform != "win32" else str(venv_dir / "Scripts")
    toolchain_bins = ":".join(str(d) for d in find_toolchain_dirs(install_dir))

    fmt = getattr(args, "print", "sh")
    if fmt == "json":
        import json

        print(json.dumps({
            "install_dir": str(install_dir),
            "venv_dir": str(venv_dir),
            "venv_bin": venv_bin,
            "toolchain_bins": toolchain_bins.split(":") if toolchain_bins else [],
        }, indent=2))
        return 0

    template = _TEMPLATES.get(fmt)
    if template is None:
        print(_red("error:") + f" unknown format '{fmt}' — use sh, ps1, bat, or json", file=sys.stderr)
        return 2

    sys.stdout.write(template.format(
        venv_dir=str(venv_dir),
        venv_bin=venv_bin,
        toolchain_bins=toolchain_bins,
    ))
    return 0


# ---- setup ----------------------------------------------------------------

_CORE_REQUIREMENTS = [
    "virtualenv>=20.26,<21",
    "wheel>=0.45,<1",
    "setuptools>=80,<82",
    "cmake>=3.20,<4",
    "kconfiglib>=14.1,<15",
    "pycparser>=2.21,<3",
    "Pillow>=10.4,<12",
    "numpy>=2.0,<3",
    "opencv-python>=4.10,<5",
    "ffmpeg-python>=0.2,<1",
]

_OBS_BASE = "https://hispark-obs.obs.cn-east-3.myhuaweicloud.com"
_PYTHON_VERSION = "3.11.4"


def _cmd_setup(args: argparse.Namespace) -> int:
    install_dir = _resolve_install_dir(args)
    if install_dir == Path(__file__).resolve().parent.parent.parent:
        install_dir = Path.home() / ".fbb_hispark"

    uv = _find_uv()
    if uv is None:
        print(_red("error:") + " uv not found — install it first:", file=sys.stderr)
        print("  curl -LsSf https://astral.sh/uv/install.sh | sh", file=sys.stderr)
        return 1

    print(_cyan("fbb setup"))
    print(f"  install dir : {install_dir}")
    print()

    install_dir.mkdir(parents=True, exist_ok=True)
    venv_dir = install_dir / "venv"

    # 1. Python
    step = 1
    total = 4 if not getattr(args, "skip_tools", False) else 3
    need_python = not args.skip_python
    if need_python:
        print(f"[{step}/{total}] installing Python {_PYTHON_VERSION} ...")
        _run([uv, "python", "install", _PYTHON_VERSION], "python install failed")
        py_found = _uv_python_find(uv, _PYTHON_VERSION)
        if py_found is None:
            print(_red("error:") + f" could not find Python {_PYTHON_VERSION}", file=sys.stderr)
            return 1
        print(_green(f"  Python: {py_found}"))
        step += 1
    else:
        py_found = _uv_python_find(uv, _PYTHON_VERSION)
        if py_found is None:
            print(_yellow(f"  Python {_PYTHON_VERSION} not found, will install"))
            _run([uv, "python", "install", _PYTHON_VERSION], "python install failed")
            py_found = _uv_python_find(uv, _PYTHON_VERSION)
        print(_green(f"  Using Python: {py_found}"))

    # 2. Create venv
    print(f"[{step}/{total}] creating venv ...")
    if venv_dir.exists():
        if args.force:
            shutil.rmtree(venv_dir)
        else:
            print(_yellow(f"  venv already exists, use --force to recreate"))
            step += 1
            # fall through to install deps
    if not venv_dir.exists():
        _run([uv, "venv", str(venv_dir), "--python", _PYTHON_VERSION], "venv creation failed")
        venv_python = find_python(venv_dir)
        if venv_python is None:
            print(_red("error:") + " venv created but python not found", file=sys.stderr)
            return 1
        # write pip.conf
        pip_index = os.environ.get("FBB_PIP_INDEX", "https://pypi.tuna.tsinghua.edu.cn/simple")
        pip_conf = venv_dir / ("pip.ini" if sys.platform == "win32" else "pip.conf")
        pip_conf.write_text(f"[global]\nindex-url = {pip_index}\n\n[install]\ndisable-pip-version-check = true\n")
        print(_green(f"  venv: {venv_dir}"))
    step += 1

    venv_python = find_python(venv_dir)
    if venv_python is None:
        print(_red("error:") + " venv python not found", file=sys.stderr)
        return 1

    # 3. Install build dependencies
    print(f"[{step}/{total}] installing build dependencies ...")
    pip_index = os.environ.get("FBB_PIP_INDEX", "https://pypi.tuna.tsinghua.edu.cn/simple")
    _run([uv, "pip", "install", "--python", str(venv_python), "--index-url", pip_index, *_CORE_REQUIREMENTS],
         "dependency install failed")
    print(_green("  build dependencies installed"))
    step += 1

    # 4. Toolchain (optional)
    if not getattr(args, "skip_tools", False):
        print(f"[{step}/{total}] downloading toolchain ...")
        os_name = "darwin" if sys.platform == "darwin" else "linux"
        arch = {"x86_64": "x86_64", "amd64": "x86_64", "arm64": "aarch64", "aarch64": "aarch64"}.get(
            os.uname().machine if sys.platform != "win32" else "x86_64", "x86_64"
        )
        tc_name = f"HiSparkStudioToolchain-{os_name}-{arch}.tar.gz"
        tc_dir = install_dir / "toolchain"
        obs_base = os.environ.get("FBB_OBS_BASE", _OBS_BASE)

        with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as f:
            tc_tgz = f.name
        try:
            result = subprocess.run(
                ["curl", "-fsSL", "--retry", "3", "-o", tc_tgz, f"{obs_base}/{tc_name}"],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                if tc_dir.exists():
                    shutil.rmtree(tc_dir)
                tc_dir.mkdir(parents=True, exist_ok=True)
                _run(["tar", "-xzf", tc_tgz, "-C", str(tc_dir)], "toolchain extraction failed")
                print(_green(f"  toolchain: {tc_dir}"))
            else:
                print(_yellow(f"  toolchain not available at {obs_base}/{tc_name}"))
                print(_yellow(f"  toolchain not available at {obs_base}/{tc_name}"))
                print(_yellow("  skip for now — download it manually into {tc_dir} if needed"))
        finally:
            Path(tc_tgz).unlink(missing_ok=True)

    print()
    print(_green("Setup complete."))
    print()
    print(_cyan("Try:"))
    print("  fbb doctor")
    print("  fbb build -c <target>")
    return 0


def _find_uv() -> str | None:
    uv = shutil.which("uv")
    if uv:
        return uv
    for p in [Path.home() / ".local" / "bin" / "uv", Path.home() / ".cargo" / "bin" / "uv"]:
        if p.exists():
            return str(p)
    return None


def _uv_python_find(uv: str, version: str) -> str | None:
    result = subprocess.run([uv, "python", "find", version], capture_output=True, text=True)
    if result.returncode == 0:
        path = result.stdout.strip().split("\n")[0].strip()
        if path and Path(path).exists():
            return path
    return None


def _run(cmd: list[str], err_msg: str) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(_red(f"error:") + f" {err_msg}", file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        sys.exit(1)


# ---- helpers --------------------------------------------------------------


def _resolve_install_dir(args: argparse.Namespace) -> Path:
    if getattr(args, "install_dir", None):
        return Path(args.install_dir).expanduser().resolve()
    return find_install_dir()


def _exec(cmd: list[str], env: dict[str, str] | None = None, cwd: str | None = None) -> int:
    """Execute *cmd* replacing the current process (Unix) or via subprocess (Windows)."""
    if sys.platform == "win32":
        return subprocess.run(cmd, env=env, cwd=cwd).returncode

    if cwd:
        os.chdir(cwd)

    try:
        os.execvpe(cmd[0], cmd, env or os.environ)
    except FileNotFoundError:
        print(_red("error:") + f" command not found: {cmd[0]}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(_red("error:") + f" exec failed: {exc}", file=sys.stderr)
        return 1
    return 0


# ---- parser setup ---------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="fbb",
        description="HiSpark fbb framework build environment CLI.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-V", "--version",
        action="version",
        version=f"fbb {__version__}",
    )

    sub = parser.add_subparsers(dest="command", metavar="<command>")

    # build
    p_build = sub.add_parser("build", help="Build a named target")
    p_build.add_argument("-c", "--target", required=True, help="Build target name (e.g. ws63-liteos-app)")
    _add_install_dir_flag(p_build)
    _add_sdk_dir_flag(p_build)
    p_build.set_defaults(func=_cmd_build)

    # run
    p_run = sub.add_parser("run", help="Run any command inside the activated environment")
    p_run.add_argument("cmd", nargs=argparse.REMAINDER, help="Command and its arguments (use -- to delimit)")
    _add_install_dir_flag(p_run)
    p_run.set_defaults(func=_cmd_run)

    # doctor
    p_doctor = sub.add_parser("doctor", help="Check environment health and print fix commands")
    _add_install_dir_flag(p_doctor)
    _add_sdk_dir_flag(p_doctor)
    p_doctor.set_defaults(func=_cmd_doctor)

    # shell
    p_shell = sub.add_parser("shell", help="Spawn a subshell with the environment activated")
    _add_install_dir_flag(p_shell)
    p_shell.set_defaults(func=_cmd_shell)

    # setup
    p_setup = sub.add_parser("setup", help="Provision build environment (Python, venv, toolchain)")
    _add_install_dir_flag(p_setup)
    p_setup.add_argument("--skip-python", action="store_true", help="Skip Python installation")
    p_setup.add_argument("--skip-tools", action="store_true", help="Skip toolchain download")
    p_setup.add_argument("--force", action="store_true", help="Recreate venv even if it exists")
    p_setup.set_defaults(func=_cmd_setup)

    # env
    p_env = sub.add_parser("env", help="Print activation snippet for shell integration")
    p_env.add_argument("--print", dest="print", choices=["sh", "ps1", "bat", "json"], default="sh",
                       help="Output format (default: sh)")
    _add_install_dir_flag(p_env)
    p_env.set_defaults(func=_cmd_env)

    # help (explicit)
    sub.add_parser("help", help="Show this help message")

    return parser


def main() -> None:
    parser = _build_parser()

    if len(sys.argv) == 1 or (len(sys.argv) == 2 and sys.argv[1] in ("help", "--help", "-h")):
        parser.print_help()
        sys.exit(0)

    if len(sys.argv) >= 2 and sys.argv[1] == "help":
        # `fbb help <cmd>` → delegate to argparse
        if len(sys.argv) >= 3:
            # re-construct help request
            parser.parse_args([sys.argv[2], "--help"])
            sys.exit(0)
        parser.print_help()
        sys.exit(0)

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(0)

    sys.exit(args.func(args))
