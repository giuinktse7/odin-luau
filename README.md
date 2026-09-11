# Luau bindings for Odin

Personal-use Windows x64 bindings for embedding [Luau](https://luau.org/) in an Odin application.

The supported workflow can:

- compile Luau source to bytecode;
- load and execute it through a protected VM call;
- exchange values between Luau and Odin;
- expose Odin callbacks to Luau; and
- load a rooted multi-file Luau project through `require()`.

The old `libraries/file` package is not part of the supported workflow and should not be exposed to scripts.

## Integrate into an Odin project

The bindings are ready to use for the supported target: a Windows x64 Odin application using the bundled, pinned Luau
static libraries. Consuming them does not require Python, uv, CMake, a C++ compiler, or a separate Luau installation.
Those tools are only needed to rebuild or verify the native libraries.

### Vendor the bindings

Copy the bindings into the consuming repository and commit them with the project. A minimal vendored copy contains:

```text
my-game/
    src/
        main.odin
    scripts/
        main.luau
    vendor/
        luau/
            luau.odin
            lua/
            luaL/
            require/
            libraries/
                module_loader/
            lib/
                windows/
            LICENSE
```

The source packages and `lib/windows` must retain this relative layout. The bindings refer to one another and to their
static libraries using relative paths. No headers or DLLs need to be copied elsewhere in the game project.

Import the vendored packages by relative path from the consuming Odin package. For example, these imports are correct
from `src/main.odin` in the layout above:

```odin
import luau "../vendor/luau"
import lua "../vendor/luau/lua"
import luaL "../vendor/luau/luaL"
import module_loader "../vendor/luau/libraries/module_loader"
```

An import from a nested package such as `src/scripting` would use `../../vendor/luau` instead. A directory named
`vendor` inside the project is not Odin's built-in `vendor:` collection; no additional collection mapping or build
flag is required. Keep any existing collection mappings for the project's own packages unchanged.

When updating the dependency, replace the vendored source and native libraries together. Keep
`lib/windows/luau-build.json` and `lib/windows/luau-abi.txt` in the vendored copy so the pinned upstream revision and
native configuration remain identifiable.

### Run a single script

This is the minimum complete compile-and-execute path:

```odin
package main

import "core:c"
import "core:fmt"

import luau "../vendor/luau"
import lua "../vendor/luau/lua"
import luaL "../vendor/luau/luaL"

main :: proc() {
    state := luaL.newstate()
    if state == nil {
        fmt.eprintln("Could not create the Luau VM")
        return
    }
    defer lua.close(state)

    luaL.openlibs(state)

    source := `return 6 * 7`
    options := luau.default_compile_options()
    bytecode_size: c.size_t
    bytecode := luau.compile(
        cast(cstring)raw_data(source),
        c.size_t(len(source)),
        &options,
        &bytecode_size,
    )
    if bytecode == nil {
        fmt.eprintln("Luau compilation allocation failed")
        return
    }

    load_status := lua.load(state, "=main", bytecode, bytecode_size, 0)
    luau.release_bytecode(bytecode)
    if load_status != .OK {
        fmt.eprintf("Load error: %s\n", lua.tostring(state, -1))
        return
    }

    call_status := lua.pcall(state, 0, 1, 0)
    if call_status != .OK {
        fmt.eprintf("Runtime error: %s\n", lua.tostring(state, -1))
        return
    }

    fmt.printf("Luau returned %d\n", lua.tointeger(state, -1))
}
```

Odin functions exposed to Luau must use the C calling convention. Register them after opening the libraries and
before sandboxing:

```odin
host_open_door :: proc "c" (state: ^lua.State) -> c.int {
    door_id := luaL.checkinteger(state, 1)
    // Call the game's door system here.
    fmt.printf("Opening door %d\n", door_id)
    return 0
}

// During VM setup:
lua.pushcfunction(state, host_open_door, "host_open_door")
lua.setglobal(state, "host_open_door")
```

### Run a multi-file script project

For scripts that use `require()`, create one loader per VM and keep it alive for all script execution in that VM:

```odin
state := luaL.newstate()
luaL.openlibs(state)

// Register the game's Odin APIs here.

loader, loader_error := module_loader.create(state, "scripts")
if loader_error != .None {
    fmt.eprintln("Could not create the Luau module loader")
    lua.close(state)
    return
}

luaL.sandbox(state)
luaL.sandboxthread(state)

status := module_loader.run_entry(loader, "scripts/main.luau", 0)
if status != .OK {
    fmt.eprintf("Luau error: %s\n", lua.tostring(state, -1))
}

// Close the VM before destroying its loader.
lua.close(state)
module_loader.destroy(loader)
```

Paths passed to `module_loader.create` and `module_loader.run_entry` are resolved from the application's current
working directory. The loader accepts `.luau` files below its configured root and supports relative imports,
`init.luau` directory modules, aliases, and module caching. See [examples/modules](examples/modules) for a runnable
two-script project.

### Integration rules

- Use protected execution with `lua.pcall` or `module_loader.run_entry`; do not use an unprotected `lua.call` for
  project scripts.
- Release every allocation returned by `luau.compile` after `lua.load`, including when loading reports an error.
- Treat strings returned by `lua.tostring`, `luaL.checkstring`, and related helpers as borrowed VM-owned memory.
- Access one VM serially. Separate VMs can be used independently, such as one client VM and one server VM.
- Register host APIs before calling `luaL.sandbox`; sandboxing makes the shared libraries and globals immutable.
- Keep the binding declarations and bundled native libraries together. They target the pinned Luau revision and should
  not be mixed with libraries built from another revision or configuration.

## Pinned native build

The bundled libraries are built from Luau commit `47cda63705c25633d757bacdcb7c9c6190625cad` with:

- Windows x64 and MSVC;
- `RelWithDebInfo`;
- `LUAU_EXTERN_C=ON`;
- `LUAU_STATIC_CRT=ON`;
- `LUA_USE_LONGJMP=1`; and
- three single-precision vector components.

The repository commands use [just](https://github.com/casey/just) and run the Python 3 tooling through [uv](https://docs.astral.sh/uv/). From a native Windows terminal, rebuild Luau with:

```text
just build-native
```

The default checkout is `../../checkouts/luau` relative to this repository. Set `LUAU_SOURCE` or `LUAU_BUILD_DIR` in the environment or a local `.env` file to override the checkout or build directory. The Python script refuses the wrong revision or tracked source changes, builds outside the Luau checkout, runs a native smoke test and ABI probe, and then stages the complete library set and [build manifest](lib/windows/luau-build.json).

To invoke the script without `just`:

```text
uv run --python 3 tools/build_native.py --luau-source C:\path\to\luau
```

## Run the checks

Run everything in ordinary and optimized modes:

```text
just test
```

Use `just test-compiler-vm` or `just test-module-loader` for one suite, and `just --list` to see every saved command. Set `ODIN` when `odin.exe` is not on `PATH`. The underlying command is also directly available as `uv run --python 3 tools/run_checks.py compiler-vm|module-loader|all`.

The compiler/VM suite covers compilation, protected execution, values returned to Odin, an Odin callback called from Luau, binary strings, corrected helpers, coroutine linkage, error diagnostics, and repeated VM teardown. The module-loader suite covers relative and nested modules, caching, aliases, `init.luau`, diagnostics, independent VMs, and repeated teardown.

## Usage

See [examples/basic/main.odin](examples/basic/main.odin) for a complete executable. The essential lifetime is:

1. Create a state with `luaL.newstate`.
2. Open the desired libraries and register host callbacks.
3. Compile source with `luau.compile`.
4. Load the counted bytecode with `lua.load`.
5. Immediately release the compiler allocation with `luau.release_bytecode`.
6. Execute through `lua.pcall` and inspect any error on the VM stack.
7. Close the state with `lua.close`.

`luau.default_compile_options()` returns the upstream defaults used by the pinned compiler. A zero-initialized `CompileOptions` instead requests optimization and debug level zero.

`lua.tostring`, `luaL.checkstring`, and `luaL.optstring` return borrowed views into VM-owned storage. They preserve embedded NUL bytes, but must not outlive the corresponding Luau value or VM.

One VM must be accessed serially. Separate VMs can be used independently.

### Filesystem modules

Run the small module example with:

```text
just example-modules
```

[examples/modules/main.odin](examples/modules/main.odin) runs `main.luau`, which imports the second Luau file with `require("./greeting")`.

The setup order is intentional:

1. Create the VM and call `luaL.openlibs`.
2. Register any Odin APIs that scripts should receive.
3. Create the module loader, which installs `require`.
4. If desired, call `luaL.sandbox` and `luaL.sandboxthread`.
5. Call `module_loader.run_entry` through its protected execution path.
6. Close the VM, then destroy the loader.

The loader accepts only `.luau` files beneath its configured root. It supports relative imports, `init.luau` directory modules, upstream caching, and aliases from Luau configuration files. This is a trusted-project guard against accidental path escapes, not a security boundary for hostile filesystems.

## Scope

These packages intentionally cover the APIs needed by the supported embedding workflow, not every public declaration in Luau. Additional raw bindings can be added when a project has a concrete use for them.
