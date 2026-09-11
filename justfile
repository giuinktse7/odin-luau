set dotenv-load
set windows-shell := ["cmd.exe", "/d", "/c"]

uv := env_var_or_default("UV", "uv")
python := env_var_or_default("PYTHON_VERSION", "3")
odin := env_var_or_default("ODIN", "odin")

# Show the project commands.
default:
    @just --list

# Build, verify, and stage the pinned Windows x64 native libraries.
build-native:
    {{ uv }} run --python {{ python }} tools/build_native.py

# Run every test and example in ordinary and optimized modes.
test:
    {{ uv }} run --python {{ python }} tools/run_checks.py all --odin "{{ odin }}"

# Run the compiler/VM tests and basic example in ordinary and optimized modes.
test-compiler-vm:
    {{ uv }} run --python {{ python }} tools/run_checks.py compiler-vm --odin "{{ odin }}"

# Run the module-loader tests and example in ordinary and optimized modes.
test-module-loader:
    {{ uv }} run --python {{ python }} tools/run_checks.py module-loader --odin "{{ odin }}"

# Run the basic compiler/VM example once.
example-basic:
    {{ odin }} run examples/basic

# Run the two-script require example once.
example-modules:
    {{ odin }} run examples/modules
