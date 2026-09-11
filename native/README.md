# Native build support

This directory builds and verifies the Windows x64 static libraries used by the Odin bindings. It is invoked by
`just build-native`; applications using the already-built libraries do not compile these files.

Successful builds are staged in `lib/windows`.

Projects vendoring these bindings only need the Odin packages and `lib/windows`. They do not need this directory.
