# Luau bindings for Odin

Forked from: [MineBill/odin-luau](https://github.com/MineBill/odin-luau)

---

Windows x64 bindings for embedding [Luau](https://luau.org/) in an Odin application. The repository contains the
compiler and VM bindings, and a filesystem-backed `require()` adapter.

The supported workflow can:

- compile Luau source and execute it through protected VM calls
- exchange values and C-calling-convention callbacks with Odin
- load `.luau` entry files and relative modules below one configured root
- resolve `init.luau` directory modules and aliases from `.luaurc` or `.config.luau`
- cache each resolved module once per VM.

The bindings intentionally cover this workflow rather than every public Luau declaration.

## Packages

| Path                      | Package              | Responsibility                                                                   |
| ------------------------- | -------------------- | -------------------------------------------------------------------------------- |
| `luau.odin`               | `luau`               | Compile source and release compiler-owned bytecode.                              |
| `lua`                     | `luau_vm`            | VM state, stack, values, calls, callbacks, coroutines, GC, and debug operations. |
| `luaL`                    | `luau_vm_L`          | State creation, standard libraries, checked arguments, and sandbox helpers.      |
| `require`                 | `luau_require`       | Thin bindings to Luau's upstream require-by-string API.                          |
| `libraries/module_loader` | `luau_module_loader` | Rooted filesystem adapter, entry execution, aliases, caching, and diagnostics.   |

## Vendor into an Odin project

Copy the binding source and native libraries into the consuming repository and commit them with the project. A minimal
vendored copy is:

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

Import the packages by relative path from the consuming package. From `src/main.odin` in the layout above:

```odin
import luau "../vendor/luau"
import lua "../vendor/luau/lua"
import luaL "../vendor/luau/luaL"
import module_loader "../vendor/luau/libraries/module_loader"
```

Update the binding declarations and native libraries together. Retain `lib/windows/luau-build.json` and
`lib/windows/luau-abi.txt`: they identify the upstream revision, native configuration, artifact hashes, and C-side ABI
measurements.

## Runtime invariants

- Access one `lua.State` serially. Independent states may be used independently.
- Execute project scripts with `lua.pcall` or `module_loader.run_entry`, never an unprotected `lua.call`.
- Every non-nil result from `luau.compile` is owned by the caller. Call `luau.release_bytecode` exactly once after
  `lua.load` returns, including when loading fails.
- Values returned by `lua.tostring`, `luaL.checkstring`, `luaL.optstring`, and similar helpers borrow VM-owned storage.
  They must not outlive the value or VM.
- Odin callbacks passed to Luau use `proc "c"` and return the number of results left on the Luau stack.
- Register host APIs before `luaL.sandbox`. Sandboxing makes the shared global table, built-in library tables, and
  built-in metatables read-only.
- A `module_loader.Loader` must outlive all script execution in its VM. Close the VM before destroying the loader.

## Compile and run one script

[examples/basic/main.odin](examples/basic/main.odin) is a complete runnable example.

Register an Odin function by pushing it and assigning it to the intended global or host API table:

```odin
host_open_door :: proc "c" (state: ^lua.State) -> c.int {
    door_id := luaL.checkinteger(state, 1)
    // Call the host's door system.
    fmt.printf("Opening door %d\n", door_id)
    return 0
}

lua.pushcfunction(state, host_open_door, "host_open_door")
lua.setglobal(state, "host_open_door")
```

## Load a module tree

[examples/modules](examples/modules) contains an Odin entry point and two Luau scripts. Run it with
`just example-modules`.

The setup and teardown order is part of the loader contract:

```odin
state := luaL.newstate()
luaL.openlibs(state)

// Register host APIs before freezing the shared environment.

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

lua.close(state)
module_loader.destroy(loader)
```

`module_loader.create` canonicalizes the root and installs `require`. `module_loader.run_entry` accepts only a `.luau`
file below that root and executes it through `lua.pcall`. Both paths are resolved from the process working directory.

## Native libraries

The checked-in libraries target Luau commit `47cda63705c25633d757bacdcb7c9c6190625cad` with:

- Windows x64 and MSVC
- `RelWithDebInfo`
- C linkage
- the static release CRT
- longjmp VM errors
- three single-precision vector components

`luau_compile` returns a `malloc`-allocated buffer. `Odin.Luau.Support.lib` contains `odin_luau_free`, compiled with the
same static CRT configuration as Luau; `luau.release_bytecode` calls that shim. See [native/README.md](native/README.md)
for the native build inputs and verification executables.

Applications consuming `lib/windows` do not need CMake, a C++ compiler, uv, Python, or a separate Luau checkout. Those
tools are required only to rebuild the native artifacts.

From native Windows, rebuild and stage the pinned libraries with:

```text
just build-native
```

The default checkout is `../../checkouts/luau`. `LUAU_SOURCE` and `LUAU_BUILD_DIR` override the source and build
directories.

The script can also be invoked directly:

```text
uv run --python 3 tools/build_native.py --luau-source C:\path\to\luau
```

## Repository commands

```text
just test                  # all checks and examples, ordinary and optimized
just test-compiler-vm      # compiler/VM suite and basic example
just test-module-loader    # module-loader suite and module example
just example-basic         # compile and run one embedded source string
just example-modules       # execute the two-script module example
```

Run these commands from native Windows. The checked-in libraries do not target WSL or Linux. `ODIN` overrides the Odin
executable used by the recipes.
