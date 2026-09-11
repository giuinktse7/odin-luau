# /// script
# requires-python = ">=3.11"
# ///

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PINNED_REVISION = "47cda63705c25633d757bacdcb7c9c6190625cad"
CONFIGURATION = "RelWithDebInfo"
LIBRARY_NAMES = (
    "Luau.Common.lib",
    "Luau.Ast.lib",
    "Luau.Bytecode.lib",
    "Luau.Compiler.lib",
    "Luau.VM.lib",
    "Luau.Config.lib",
    "Luau.Require.lib",
    "Odin.Luau.Support.lib",
)

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LUAU_SOURCE = REPOSITORY_ROOT.parents[1] / "checkouts" / "luau"
DEFAULT_BUILD_DIRECTORY = REPOSITORY_ROOT / "build" / "luau-windows-x64"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build and stage the pinned Windows x64 Luau libraries.")

    parser.add_argument(
        "--luau-source",
        type=Path,
        default=Path(os.environ.get("LUAU_SOURCE", DEFAULT_LUAU_SOURCE)),
        help="pinned Luau checkout (default: %(default)s or LUAU_SOURCE)",
    )

    parser.add_argument(
        "--build-directory",
        type=Path,
        default=Path(os.environ.get("LUAU_BUILD_DIR", DEFAULT_BUILD_DIRECTORY)),
        help="out-of-tree build directory (default: %(default)s or LUAU_BUILD_DIR)",
    )

    return parser.parse_args()


def run(*arguments: object, capture: bool = False) -> str:
    command = [os.fspath(argument) if isinstance(argument, Path) else str(argument) for argument in arguments]

    result = subprocess.run(
        command,
        cwd=REPOSITORY_ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )

    return result.stdout.strip() if capture else ""


def checkout_is_clean(luau_source: Path) -> bool:
    for arguments in (("diff", "--quiet", "--"), ("diff", "--cached", "--quiet", "--")):
        result = subprocess.run(("git", "-C", luau_source, *arguments), check=False)

        if result.returncode == 1:
            return False

        if result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, result.args)

    return True


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)

    return digest.hexdigest()


def artifact_records(directory: Path, names: tuple[str, ...] | list[str]) -> list[dict[str, str]]:
    return [{"name": name, "sha256": sha256(directory / name)} for name in sorted(names)]


def compiler_version(build_directory: Path) -> str:
    pattern = re.compile(r'set\(CMAKE_CXX_COMPILER_VERSION "([^"]+)"\)')
    for path in (build_directory / "CMakeFiles").rglob("CMakeCXXCompiler.cmake"):
        match = pattern.search(path.read_text(encoding="utf-8"))
        if match:
            return match.group(1)
    return "unknown"


def validate_directory(path: Path, label: str) -> Path:
    resolved = path.expanduser().resolve()
    if not resolved.is_dir():
        raise SystemExit(f"{label} does not exist or is not a directory: {resolved}")

    return resolved


def main() -> int:
    args = parse_args()
    if os.name != "nt":
        raise SystemExit("The native Luau build must run from native Windows (uv.exe/just.exe), not WSL.")

    luau_source = validate_directory(args.luau_source, "Luau checkout")
    build_directory = args.build_directory.expanduser().resolve()
    if build_directory == Path(build_directory.anchor):
        raise SystemExit("The build directory cannot be a filesystem root")

    revision = run("git", "-C", luau_source, "rev-parse", "HEAD", capture=True)
    if revision != PINNED_REVISION:
        raise SystemExit(f"Expected Luau revision {PINNED_REVISION}, found {revision}")

    if not checkout_is_clean(luau_source):
        raise SystemExit("The Luau checkout has tracked changes; build provenance would be ambiguous")

    native_source = REPOSITORY_ROOT / "native"
    artifact_directory = REPOSITORY_ROOT / "lib" / "windows"
    build_directory.mkdir(parents=True, exist_ok=True)

    run(
        "cmake",
        "-S",
        native_source,
        "-B",
        build_directory,
        "-G",
        "Visual Studio 17 2022",
        "-A",
        "x64",
        f"-DLUAU_SOURCE_DIR={luau_source}",
    )

    run(
        "cmake",
        "--build",
        build_directory,
        "--config",
        CONFIGURATION,
        "--target",
        *[name.removesuffix(".lib") for name in LIBRARY_NAMES],
        "Odin.Luau.AbiProbe",
        "Odin.Luau.NativeSmoke",
    )

    binary_directory = build_directory / "bin"
    run(binary_directory / "Odin.Luau.NativeSmoke.exe")
    abi_output = run(binary_directory / "Odin.Luau.AbiProbe.exe", capture=True)

    stage_directory = build_directory / "stage"
    if stage_directory.exists():
        shutil.rmtree(stage_directory)

    stage_directory.mkdir()

    built_library_directory = build_directory / "lib"
    for name in LIBRARY_NAMES:
        source = built_library_directory / name

        if not source.is_file():
            raise SystemExit(f"Expected library was not built: {source}")

        shutil.copy2(source, stage_directory / name)

    existing_manifest_path = artifact_directory / "luau-build.json"
    if existing_manifest_path.is_file():
        existing_manifest = json.loads(existing_manifest_path.read_text(encoding="utf-8-sig"))
        previous_artifacts = existing_manifest.get("previousArtifacts", [])
    elif artifact_directory.is_dir():
        previous_names = [path.name for path in artifact_directory.glob("*.lib")]
        previous_artifacts = artifact_records(artifact_directory, previous_names)
    else:
        previous_artifacts = []

    cmake_version = run("cmake", "--version", capture=True).splitlines()[0]
    manifest = {
        "luauRevision": revision,
        "configuration": CONFIGURATION,
        "generator": "Visual Studio 17 2022",
        "architecture": "x64",
        "cmake": cmake_version,
        "compiler": {"id": "MSVC", "version": compiler_version(build_directory)},
        "definitions": {
            "LUAU_EXTERN_C": "ON",
            "LUAU_STATIC_CRT": "ON",
            "LUA_USE_LONGJMP": 1,
            "LUA_VECTOR_SIZE": 3,
            "LUA_VECTOR_DOUBLE": 0,
        },
        "previousArtifacts": previous_artifacts,
        "artifacts": artifact_records(stage_directory, list(LIBRARY_NAMES)),
    }

    build_json_path: Path = stage_directory / "luau-build.json"
    luau_abi_path: Path = stage_directory / "luau-abi.txt"

    build_json_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    luau_abi_path.write_text(abi_output + "\n", encoding="utf-8", newline="\n")

    artifact_directory.mkdir(parents=True, exist_ok=True)
    for name in (*LIBRARY_NAMES, "luau-build.json", "luau-abi.txt"):
        shutil.copy2(stage_directory / name, artifact_directory / name)

    print(f"Staged pinned Luau libraries in {artifact_directory}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
