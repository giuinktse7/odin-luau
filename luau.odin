package luau
import "core:c"

when ODIN_OS == .Windows {
    foreign import LuauCompiler {
        "./lib/windows/Luau.Compiler.lib",
        "./lib/windows/Luau.Ast.lib",
        "./lib/windows/Luau.Bytecode.lib",
        "./lib/windows/Luau.Common.lib",
        "./lib/windows/Odin.Luau.Support.lib",
    }
} else {
    #panic("Unsupported OS(currently). If you want, make a PR with the compiled binaries for your OS.")
}

Library_Member_Type_Callback :: #type proc "c" (library, member: cstring) -> c.int
Compile_Constant             :: rawptr
Library_Member_Constant_Callback :: #type proc "c" (
    library, member: cstring,
    constant: ^Compile_Constant,
)

CompileOptions :: struct {
    // 0 - no optimization
    // 1 - baseline optimization level that doesn't prevent debuggability
    // 2 - includes optimizations that harm debuggability such as inlining
    optimization_level: i32, // default=1

    // 0 - no debugging support
    // 1 - line info & function names only; sufficient for backtraces
    // 2 - full debug info with local & upvalue names; necessary for debugger
    debug_level: i32, // default=1

    // type information is used to guide native code generation decisions
    // information includes testable types for function arguments, locals, upvalues and some temporaries
    // 0 - generate for native modules
    // 1 - generate for all modules
    type_info_level: i32, // default=0

    // 0 - no code coverage support
    // 1 - statement coverage
    // 2 - statement and expression coverage (verbose)
    coverage_level: i32, // default=0

    // global builtin to construct vectors; disabled by default
    vector_lib: cstring,
    vector_ctor: cstring,

    // vector type name for type tables; disabled by default
    vector_type: cstring,

    // 0 - 32-bit float vector components
    // 1 - 64-bit double vector components
    vector_precision: i32, // default=0

    // null-terminated array of globals that are mutable; disables the import optimization for fields accessed through these
    mutable_globals: [^]cstring,

    // null-terminated array of userdata types that will be included in the type information
    userdata_types: [^]cstring,

    // null-terminated array of globals which act as libraries and have members with known type and/or constant value
    libraries_with_known_members: [^]cstring,
    library_member_type_cb: Library_Member_Type_Callback,
    library_member_constant_cb: Library_Member_Constant_Callback,

    // null-terminated array of functions that should not compile into a builtin fastcall
    disabled_builtins: [^]cstring,
}

// These are the defaults used by luau_compile when its options pointer is nil.
default_compile_options :: proc() -> CompileOptions {
    return {
        optimization_level = 1,
        debug_level = 1,
    }
}

@(link_prefix="luau_")
foreign LuauCompiler {

    // compile source to bytecode; when source compilation fails, the resulting bytecode contains the encoded error. use free() to destroy
    compile :: proc(source: cstring, size: c.size_t, options: ^CompileOptions, out_size: ^c.size_t) -> cstring ---

    @(link_name="odin_luau_free")
    _release_bytecode :: proc(pointer: rawptr) ---
}

// Releases the counted binary allocation returned by compile. The support
// library is built with the same CRT as Luau.
release_bytecode :: proc(pointer: cstring) {
    if pointer != nil {
        _release_bytecode(cast(rawptr)pointer)
    }
}

when ODIN_ARCH == .amd64 {
    #assert(size_of(CompileOptions) == 96)
    #assert(align_of(CompileOptions) == 8)
    #assert(offset_of(CompileOptions, vector_precision) == 40)
    #assert(offset_of(CompileOptions, mutable_globals) == 48)
    #assert(offset_of(CompileOptions, disabled_builtins) == 88)
}
