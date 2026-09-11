# Implementation Plan: Practical Luau Embedding for Odin

## Outcome

A Windows x64 Odin application can build and link a known Luau revision, compile and execute Luau safely, exchange values and callbacks with Odin, and load a multi-file Luau project through `require()`.

This is a personal-use binding for the current projects, not a promise of exhaustive Luau API coverage or compatibility with arbitrary Luau builds.

## Scope and decisions

- Target Windows x64 only.
- Pin Luau to commit `47cda63705c25633d757bacdcb7c9c6190625cad`.
- Build static libraries with C linkage, the static release CRT, longjmp VM errors, and three single-precision vector components.
- Keep the raw compiler, VM, and auxiliary packages thin. Bind and test the APIs needed by the host and module loader; add more APIs when a project needs them.
- Correct existing declarations that are ABI-unsafe or prevent the supported workflow from working. Basic ABI correctness is required because incorrect layouts and callback signatures can corrupt memory.
- Keep the existing `libraries/file` package untouched and unsupported. Scripts do not receive general-purpose filesystem access.
- Treat each VM as single-threaded. Independent VMs may be used independently.
- Start with loose `.luau` files below a configured root. Packaging scripts into game assets can be added later if needed.

## Phase 1 — Reliable compiler and VM execution

Phase 1 produces the small, trustworthy core needed by every later use of Luau.

### Task 1 — Reproducible native libraries

Add a Windows build script that:

- accepts the path to an existing Luau checkout;
- verifies the pinned commit instead of fetching or changing the checkout;
- builds outside the source tree with `LUAU_EXTERN_C=ON`, `LUAU_STATIC_CRT=ON`, and `RelWithDebInfo`;
- records the Luau revision and relevant build configuration;
- stages the static libraries needed by the compiler, VM, and later Require integration; and
- replaces bundled artifacts only after the new build has succeeded.

Remove the current dependency on `Luau.CLI.lib.lib`; it is a CLI implementation detail rather than an embedding dependency. Link each Odin package to the native libraries it actually needs. Do not use linker suppression flags to hide CRT mismatches.

Before replacing the current uncommitted `.lib` files, record their names and checksums so the starting point remains identifiable.

### Task 2 — Correct the supported compiler/VM surface

Repair the existing declarations and helpers used by compilation and execution. In particular:

- update `CompileOptions`, VM type IDs, `Debug`, and `Callbacks` to the pinned layouts;
- use C-width types and `proc "c"` for foreign callbacks;
- fix the auxiliary vector declarations, coroutine link names, `_where`, registry helpers, counted-string helpers, and `unref`;
- provide deliberate compiler defaults rather than relying on a zero-initialized options struct;
- expose an explicit release helper for memory returned by `luau_compile`; and
- replace the README's unprotected `lua.call` example with protected execution and complete cleanup.

Only shared layouts, enums, callbacks, and symbols exercised by the supported workflow require ABI probes in this phase. Do not build a complete declaration inventory or bind unrelated experimental APIs.

### Phase 1 verification

Run the supported workflow on actual Windows x64:

1. Build the pinned libraries using the documented script.
2. Compare the critical C and Odin sizes, alignments, offsets, enum values, and configuration constants.
3. Compile and execute a simple Luau script.
4. Return values from Luau to Odin.
5. Call an Odin callback from Luau.
6. Report syntax and runtime errors through protected execution without crashing.
7. Repeatedly compile, load, execute, release bytecode, and close the VM.
8. Run the example in ordinary and optimized Odin builds.

Phase 1 is complete when this workflow passes against a fresh native build. An `odin check` or symbol inspection alone is not completion evidence.

## Phase 2 — Practical `require()` support

Phase 2 makes Luau useful for organizing client UI and server gameplay into modules.

### Task 3 — Minimum Require bindings and filesystem adapter

Bind the subset of the pinned `Require.h` interface needed by the adapter. Implement a loader associated with one VM that:

- owns or clearly borrows all retained state for its documented lifetime;
- resolves relative module paths from the calling module;
- reads only `.luau` source modules below a configured root;
- compiles modules with the Phase 1 compiler path;
- uses upstream Require caching and cycle behavior; and
- reports the requested module, resolved source, and compile/runtime error.

Reject embedded NULs and straightforward attempts to escape the configured root. Use normalized, stable paths so ordinary equivalent spellings do not execute a module twice. This is a guard against mistakes in trusted project scripts, not a hostile-filesystem sandbox.

### Task 4 — Entry scripts and module conveniences

Provide an entry-file operation that installs `require`, runs an entry script through protected execution, and cleans up explicitly. Document the order used to open libraries, register Odin APIs, sandbox the environment when desired, and execute the entry script.

After relative modules work, add the conveniences useful to the current projects:

- directory modules using `init.luau`; and
- configured aliases for shared UI/gameplay modules.

Follow the pinned upstream behavior for these supported cases, but do not pursue exhaustive CLI/VFS compatibility.

### Phase 2 verification

Use a small example tree resembling the intended projects and verify:

- nested relative imports;
- one-time module execution and cached results;
- equivalent paths resolving to one module identity;
- an `init.luau` module;
- a configured alias;
- independent caches in two VMs;
- missing-module, syntax-error, runtime-error, and ordinary cycle diagnostics; and
- repeated startup and shutdown without leaking compiler-owned buffers.

Publish one runnable example showing an entry script, a UI-style module, and a small gameplay interaction module.

## Deferred until a real project needs it

- Complete coverage of every declaration in `lua.h`, `lualib.h`, `luacode.h`, or `Require.h`.
- A declaration coverage inventory and an all-export symbol-link suite.
- Other operating systems, architectures, CRT configurations, or Luau revisions.
- Native code generation, analysis/LSP bindings, and C++ APIs.
- Lua-facing `loadfile`, `dofile`, or ordinary file I/O.
- Packaged/virtual asset sources, hot reload, dependency invalidation, and file watching.
- Exhaustive `.luaurc`/CLI compatibility.
- Hostile-code or hostile-filesystem hardening, including adversarial races, hard-link identity, and exhaustive UNC/junction behavior.
- Allocator-failure injection and exhaustive lifecycle/API-family stress testing.
- Concurrent access to one VM or an asynchronous module scheduler.

These items can be added incrementally without blocking the intended UI and server-gameplay use cases.
