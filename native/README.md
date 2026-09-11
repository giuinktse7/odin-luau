# Native build support

This directory builds and verifies the Windows x64 static libraries used by the Odin bindings. It is invoked by
`just build-native`; applications using the already-built libraries do not compile these files.

- `CMakeLists.txt` configures the pinned Luau checkout and builds Luau, the support library, and the verification tools.
- `support.c` provides `odin_luau_free`, used by `luau.release_bytecode` to free compiler output with the correct C runtime.
- `native_smoke.cpp` verifies that the new libraries can compile and execute a small Luau program.
- `abi_probe.cpp` records the C layouts and constants that must match the Odin declarations.

Successful builds are staged in `lib/windows` by `tools/build_native.py`.

Projects vendoring these bindings only need the Odin packages and `lib/windows`; they do not need this directory unless
they intend to rebuild the native libraries.
