"""Environment detection and activation for the fbb framework.

Resolves the install directory, Python venv, and toolchain paths.
The install directory is found by, in order:

1. ``FBB_INSTALL_DIR`` environment variable
2. Walking up from the ``fbb`` script location looking for ``pyproject.toml``
3. ``~/.fbb_hispark`` as default
"""

from __future__ import annotations

import os
import sys
import shutil
from pathlib import Path


def find_install_dir() -> Path:
    """Return the absolute path to the fbb install directory."""
    env = os.environ.get("FBB_INSTALL_DIR")
    if env:
        p = Path(env).expanduser().resolve()
        if p.exists():
            return p

    marker = "pyproject.toml"
    start = Path(__file__).resolve().parent
    for ancestor in [start, *start.parents]:
        if (ancestor / marker).exists() and (ancestor / "src" / "fbb_cli").exists():
            return ancestor

    return Path.home() / ".fbb_hispark"


def find_sdk_dir(start_dir=None, explicit=None) -> Path | None:
    """Walk up from *start_dir* looking for a directory that contains
    ``src/build.py`` (or ``build.py`` at the root of an fbb_* checkout)."""
    if explicit:
        p = Path(explicit).expanduser().resolve()
        if p.exists():
            return p
        return None

    cwd = Path(start_dir).resolve() if start_dir else Path.cwd()
    for d in [cwd, *cwd.parents]:
        if (d / "src" / "build.py").exists():
            return d
        if d.name.startswith("fbb_") and (d / "build.py").exists():
            return d

    return None


def find_venv_dir(install_dir: Path) -> Path:
    """Return the venv directory inside *install_dir*.

    Checks ``venv/`` first (production layout), then ``.venv/`` (dev layout).
    """
    for name in ("venv", ".venv"):
        p = install_dir / name
        if p.is_dir():
            return p
    return install_dir / "venv"  # return default even if missing (doctor reports it)


def find_python(venv_dir: Path) -> Path | None:
    """Return the python executable inside the venv."""
    if sys.platform == "win32":
        py = venv_dir / "Scripts" / "python.exe"
    else:
        py = venv_dir / "bin" / "python"
    return py if py.exists() and os.access(py, os.X_OK) else None


def find_toolchain_dirs(install_dir: Path) -> list[Path]:
    """Collect every ``bin/`` directory under the toolchain tree."""
    tc = install_dir / "toolchain"
    if not tc.is_dir():
        return []
    bins: list[Path] = []
    for root, dirs, _files in os.walk(str(tc)):
        for d in dirs:
            if d == "bin":
                bins.append(Path(root) / d)
    bins.sort()
    return bins


def build_env(install_dir: Path) -> dict[str, str]:
    """Return a copy of ``os.environ`` with fbb paths prepended to PATH,
    and ``VIRTUAL_ENV`` set. Does NOT modify the current process env."""
    env = os.environ.copy()
    venv_dir = find_venv_dir(install_dir)
    python = find_python(venv_dir)

    additions: list[str] = []
    if python:
        env["VIRTUAL_ENV"] = str(venv_dir)
        venv_bin = str(venv_dir / "bin") if sys.platform != "win32" else str(venv_dir / "Scripts")
        additions.append(venv_bin)

    for d in find_toolchain_dirs(install_dir):
        additions.append(str(d))

    if additions:
        sep = ";" if sys.platform == "win32" else ":"
        env["PATH"] = sep.join([*additions, env.get("PATH", "")])

    return env


def check_venv(install_dir: Path) -> list[str]:
    """Return a list of problems with the venv (empty = OK)."""
    problems: list[str] = []

    venv_dir = find_venv_dir(install_dir)
    if not venv_dir.is_dir():
        problems.append(f"venv directory not found: {venv_dir}")
        return problems

    python = find_python(venv_dir)
    if not python:
        problems.append(f"python executable not found in venv: {venv_dir}")
        return problems

    try:
        import subprocess
        result = subprocess.run(
            [str(python), "-c", "import numpy, kconfiglib, PIL; print('ok')"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            problems.append("key modules (numpy, kconfiglib, PIL) not importable")
    except Exception as e:
        problems.append(f"failed to check python modules: {e}")

    return problems


def check_toolchain(install_dir: Path) -> list[str]:
    """Return a list of problems with the toolchain (empty = OK)."""
    problems: list[str] = []
    bins = find_toolchain_dirs(install_dir)

    if not bins:
        problems.append("toolchain not found (expected toolchain/ dir with bin/ subdirs)")
        return problems

    for b in bins:
        ninja = b / ("ninja.exe" if sys.platform == "win32" else "ninja")
        if ninja.exists():
            break
    else:
        problems.append("ninja not found in toolchain bin dirs")

    git_found = shutil.which("git")
    if not git_found:
        problems.append("git not found on PATH")

    return problems
