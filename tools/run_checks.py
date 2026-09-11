# /// script
# requires-python = ">=3.11"
# ///

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
BUILD_DIRECTORY = REPOSITORY_ROOT / "build"

CHECK_GROUPS = {
    "compiler-vm": {
        "tests": Path("tests/compiler_vm"),
        "example": Path("examples/basic"),
        "test_output": "compiler-vm-tests",
        "example_output": "basic-example",
    },
    "module-loader": {
        "tests": Path("tests/module_loader"),
        "example": Path("examples/modules"),
        "test_output": "module-loader-tests",
        "example_output": "modules-example",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the Odin/Luau Windows checks and examples."
    )
    parser.add_argument(
        "group",
        choices=("compiler-vm", "module-loader", "all"),
        nargs="?",
        default="all",
    )
    parser.add_argument(
        "--odin",
        default=os.environ.get("ODIN", "odin"),
        help="Odin executable (default: odin or ODIN)",
    )
    return parser.parse_args()


def run(*arguments: object) -> None:
    command = [
        os.fspath(argument) if isinstance(argument, Path) else str(argument)
        for argument in arguments
    ]
    subprocess.run(command, cwd=REPOSITORY_ROOT, check=True)


def run_group(odin: str, group: str) -> None:
    settings = CHECK_GROUPS[group]
    for optimized, suffix in ((False, ""), (True, "-speed")):
        optimization = ("-o:speed",) if optimized else ()
        run(
            odin,
            "test",
            settings["tests"],
            *optimization,
            f"-out:{BUILD_DIRECTORY / (settings['test_output'] + suffix + '.exe')}",
        )
    for optimized, suffix in ((False, ""), (True, "-speed")):
        optimization = ("-o:speed",) if optimized else ()
        run(
            odin,
            "run",
            settings["example"],
            *optimization,
            f"-out:{BUILD_DIRECTORY / (settings['example_output'] + suffix + '.exe')}",
        )


def main() -> int:
    args = parse_args()
    if os.name != "nt":
        raise SystemExit(
            "The checked-in Luau libraries target Windows x64; "
            "run checks with native uv.exe/just.exe."
        )

    BUILD_DIRECTORY.mkdir(parents=True, exist_ok=True)
    run(args.odin, "version")
    groups = CHECK_GROUPS if args.group == "all" else (args.group,)
    for group in groups:
        run_group(args.odin, group)
    return 0


if __name__ == "__main__":
    sys.exit(main())
