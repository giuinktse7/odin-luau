package compiler_vm_tests

import "core:c"
import "core:strings"
import "core:testing"

import luau "../.."
import "../../lua"
import "../../luaL"

#assert(size_of(luau.CompileOptions) == 96)
#assert(offset_of(luau.CompileOptions, vector_precision) == 40)
#assert(offset_of(luau.CompileOptions, mutable_globals) == 48)
#assert(offset_of(luau.CompileOptions, disabled_builtins) == 88)

#assert(size_of(lua.Debug) == 320)
#assert(offset_of(lua.Debug, protoid) == 40)
#assert(offset_of(lua.Debug, userdata) == 56)
#assert(offset_of(lua.Debug, ssbuf) == 64)

#assert(size_of(lua.Callbacks) == 104)
#assert(offset_of(lua.Callbacks, useratom) == 32)
#assert(offset_of(lua.Callbacks, onallocate) == 72)
#assert(offset_of(lua.Callbacks, onfree) == 96)

#assert(int(lua.Type.INTEGER) == 4)
#assert(int(lua.Type.VECTOR) == 5)
#assert(int(lua.Type.CLASS) == 12)
#assert(int(lua.Type.OBJECT) == 13)
#assert(int(lua.Type.DEADKEY) == 14)
#assert(int(lua.Type.COUNT) == 14)
#assert(lua.USE_LONGJMP == 1)
#assert(lua.VECTOR_SIZE == 3)

host_add :: proc "c" (L: ^lua.State) -> c.int {
    left := lua.tointeger(L, 1)
    right := lua.tointeger(L, 2)
    lua.pushinteger(L, left + right)
    return 1
}

read_integer :: proc "c" (L: ^lua.State, index: c.int) -> c.int {
    return lua.tointeger(L, index)
}

load_source :: proc(L: ^lua.State, source, chunk_name: string) -> lua.Status {
    options := luau.default_compile_options()
    bytecode_size: c.size_t
    bytecode := luau.compile(
        cast(cstring)raw_data(source),
        c.size_t(len(source)),
        &options,
        &bytecode_size,
    )
    if bytecode == nil {
        return .ERRMEM
    }

    status := lua.load(L, cast(cstring)raw_data(chunk_name), bytecode, bytecode_size, 0)
    luau.release_bytecode(bytecode)
    return status
}

@(test)
compile_execute_and_callback :: proc(t: ^testing.T) {
    state := luaL.newstate()
    if !testing.expect(t, state != nil, "luaL_newstate returned nil") {
        return
    }
    defer lua.close(state)

    luaL.openlibs(state)
    lua.pushcfunction(state, host_add, "host_add")
    lua.setglobal(state, "host_add")

	status := load_source(state, `return host_add(20, 22), "a\0b"`, "=compiler-vm-success\x00")
    if !testing.expect_value(t, status, lua.Status.OK) {
        testing.fail_now(t, lua.tostring(state, -1))
    }

    status = lua.pcall(state, 0, 2, 0)
    if !testing.expect_value(t, status, lua.Status.OK) {
        testing.fail_now(t, lua.tostring(state, -1))
    }

    testing.expect_value(t, lua.tointeger(state, -2), c.int(42))
    testing.expect_value(t, lua.tostring(state, -1), "a\x00b")
}

@(test)
protected_errors_are_reported :: proc(t: ^testing.T) {
    state := luaL.newstate()
    if !testing.expect(t, state != nil, "luaL_newstate returned nil") {
        return
    }
    defer lua.close(state)
    luaL.openlibs(state)

	syntax_status := load_source(state, "local =", "=compiler-vm-syntax\x00")
    testing.expect(t, syntax_status != .OK, "invalid syntax unexpectedly loaded")
    testing.expect(t, len(lua.tostring(state, -1)) > 0, "syntax error had no diagnostic")
    lua.pop(state, 1)

	load_status := load_source(state, `error("compiler VM boom")`, "=compiler-vm-runtime\x00")
    if !testing.expect_value(t, load_status, lua.Status.OK) {
        testing.fail_now(t, lua.tostring(state, -1))
    }

    call_status := lua.pcall(state, 0, 0, 0)
    testing.expect_value(t, call_status, lua.Status.ERRRUN)
    error_message := lua.tostring(state, -1)
    testing.expectf(
        t,
		strings.contains(error_message, "compiler VM boom"),
        "runtime error did not contain the original message: %q",
        error_message,
    )
}

@(test)
repeated_lifecycle :: proc(t: ^testing.T) {
    for _ in 0..<100 {
        state := luaL.newstate()
        if !testing.expect(t, state != nil, "luaL_newstate returned nil") {
            return
        }

		load_status := load_source(state, "return 42", "=compiler-vm-lifecycle\x00")
        if !testing.expect_value(t, load_status, lua.Status.OK) {
            testing.fail_now(t, lua.tostring(state, -1))
        }

        call_status := lua.pcall(state, 0, 1, 0)
        if !testing.expect_value(t, call_status, lua.Status.OK) {
            testing.fail_now(t, lua.tostring(state, -1))
        }
        testing.expect_value(t, lua.tointeger(state, -1), c.int(42))
        lua.close(state)
    }
}

@(test)
corrected_helpers_and_symbols :: proc(t: ^testing.T) {
    state := luaL.newstate()
    if !testing.expect(t, state != nil, "luaL_newstate returned nil") {
        return
    }
    defer lua.close(state)

    callbacks := lua.callbacks(state)
    if !testing.expect(t, callbacks != nil, "lua.callbacks returned nil") {
        return
    }
    testing.expect(t, callbacks.useratom == nil, "default useratom callback was not nil")
    testing.expect(t, callbacks.onallocate == nil, "default allocation callback was not nil")

    lua.pushinteger(state, 73)
    reference := lua.ref(state, -1)
    lua.pop(state, 1)
    testing.expect(t, reference > 0, "lua.ref did not return a registry reference")
    testing.expect_value(t, lua.getref(state, reference), c.int(lua.Type.NUMBER))
    testing.expect_value(t, lua.tointeger(state, -1), c.int(73))
    lua.pop(state, 1)
    testing.expect_value(t, lua.unref(state, reference), c.int(lua.NOREF))

    testing.expect_value(t, luaL.opt(state, read_integer, 99, 17), c.int(17))
    lua.pushinteger(state, 29)
    testing.expect_value(t, luaL.opt(state, read_integer, -1, 17), c.int(29))
    lua.pop(state, 1)

    lua.pushvector(state, 1, 2, 3)
    vector := luaL.checkvector(state, -1)
    testing.expect_value(t, vector[0], c.float(1))
    testing.expect_value(t, vector[1], c.float(2))
    testing.expect_value(t, vector[2], c.float(3))
    lua.pop(state, 1)

    default_vector := [3]c.float{4, 5, 6}
    vector = luaL.optvector(state, 99, raw_data(default_vector[:]))
    testing.expect_value(t, vector[0], c.float(4))
    testing.expect_value(t, vector[1], c.float(5))
    testing.expect_value(t, vector[2], c.float(6))

    luaL.where_(state, 0)
    testing.expect_value(t, lua.tostring(state, -1), "")
    lua.pop(state, 1)

    coroutine := lua.newthread(state)
	load_status := load_source(coroutine, "return 91", "=compiler-vm-coroutine\x00")
    if !testing.expect_value(t, load_status, lua.Status.OK) {
        testing.fail_now(t, lua.tostring(coroutine, -1))
    }
    testing.expect_value(t, lua.resume(coroutine, state, 0), c.int(lua.Status.OK))
    testing.expect_value(t, lua.status(coroutine), c.int(lua.Status.OK))
    testing.expect_value(t, lua.tointeger(coroutine, -1), c.int(91))
}
