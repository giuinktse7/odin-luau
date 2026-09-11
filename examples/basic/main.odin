package main

import "core:c"
import "core:fmt"

import luau "../.."
import "../../lua"
import "../../luaL"

host_add :: proc "c" (L: ^lua.State) -> c.int {
    left := lua.tointeger(L, 1)
    right := lua.tointeger(L, 2)
    lua.pushinteger(L, left + right)
    return 1
}

main :: proc() {
    state := luaL.newstate()
    if state == nil {
        fmt.eprintln("Could not create the Luau VM")
        return
    }

    luaL.openlibs(state)
    lua.pushcfunction(state, host_add, "host_add")
    lua.setglobal(state, "host_add")

    source := `return host_add(20, 22), "hello from Luau"`
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
        lua.close(state)
        return
    }

    load_status := lua.load(state, "=basic", bytecode, bytecode_size, 0)
    luau.release_bytecode(bytecode)
    if load_status != .OK {
        fmt.eprintf("Load error: %s\n", lua.tostring(state, -1))
        lua.close(state)
        return
    }

    call_status := lua.pcall(state, 0, 2, 0)
    if call_status != .OK {
        fmt.eprintf("Runtime error: %s\n", lua.tostring(state, -1))
        lua.close(state)
        return
    }

    fmt.printf("Luau returned %d and %q\n", lua.tointeger(state, -2), lua.tostring(state, -1))
    lua.close(state)
}
