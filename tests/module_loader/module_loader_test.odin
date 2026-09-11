package module_loader_tests

import "core:c"
import "core:strings"
import "core:testing"

import "../../lua"
import "../../luaL"
import module_loader "../../libraries/module_loader"
import luau_require "../../require"

PROJECT_ROOT :: "tests/module_loader/project"

#assert(size_of(luau_require.Configuration) == 128)
#assert(offset_of(luau_require.Configuration, get_config_status) == 88)
#assert(offset_of(luau_require.Configuration, get_config) == 104)
#assert(offset_of(luau_require.Configuration, load) == 120)

Load_Counts :: struct {
	first:  int,
	helper: int,
	init:   int,
	alias:  int,
}

record_load :: proc "c" (L: ^lua.State) -> c.int {
	counts := cast(^Load_Counts)lua.tolightuserdata(L, c.int(lua.upvalueindex(1)))
	name := luaL.checkstring(L, 1)
	switch name {
	case "first": counts.first += 1
	case "helper": counts.helper += 1
	case "init": counts.init += 1
	case "alias": counts.alias += 1
	}
	return 0
}

open_test_vm :: proc(counts: ^Load_Counts) -> (^lua.State, ^module_loader.Loader, module_loader.Create_Error) {
	state := luaL.newstate()
	if state == nil {
		return nil, nil, .Invalid_State
	}
	luaL.openlibs(state)
	lua.pushlightuserdata(state, counts)
	lua.pushcclosure(state, record_load, "record_load", 1)
	lua.setglobal(state, "record_load")
	loader, err := module_loader.create(state, PROJECT_ROOT)
	if err != .None {
		lua.close(state)
		return nil, nil, err
	}
	luaL.sandbox(state)
	luaL.sandboxthread(state)
	return state, loader, .None
}

close_test_vm :: proc(state: ^lua.State, loader: ^module_loader.Loader) {
	lua.close(state)
	module_loader.destroy(loader)
}

@(test)
relative_alias_init_and_cache :: proc(t: ^testing.T) {
	counts: Load_Counts
	state, loader, err := open_test_vm(&counts)
	if !testing.expect_value(t, err, module_loader.Create_Error.None) {
		return
	}
	defer close_test_vm(state, loader)

	status := module_loader.run_entry(loader, PROJECT_ROOT + "/entry.luau", 1)
	if !testing.expect_value(t, status, lua.Status.OK) {
		testing.fail_now(t, lua.tostring(state, -1))
	}

	lua.getfield(state, -1, "answer")
	testing.expect_value(t, lua.tointeger(state, -1), c.int(43))
	lua.pop(state, 1)
	lua.getfield(state, -1, "sameModule")
	testing.expect(t, lua.toboolean(state, -1) != 0, "equivalent module paths did not share one cached value")
	lua.pop(state, 2)

	testing.expect_value(t, counts.first, 1)
	testing.expect_value(t, counts.helper, 1)
	testing.expect_value(t, counts.init, 1)
	testing.expect_value(t, counts.alias, 1)
}

@(test)
independent_vm_caches :: proc(t: ^testing.T) {
	for _ in 0..<2 {
		counts: Load_Counts
		state, loader, err := open_test_vm(&counts)
		if !testing.expect_value(t, err, module_loader.Create_Error.None) {
			return
		}

		for _ in 0..<2 {
			status := module_loader.run_entry(loader, PROJECT_ROOT + "/entry.luau", 1)
			if !testing.expect_value(t, status, lua.Status.OK) {
				testing.fail_now(t, lua.tostring(state, -1))
			}
			lua.pop(state, 1)
		}
		testing.expect_value(t, counts.first, 1)
		testing.expect_value(t, counts.helper, 1)
		testing.expect_value(t, counts.init, 1)
		testing.expect_value(t, counts.alias, 1)
		close_test_vm(state, loader)
	}
}

check_error :: proc(t: ^testing.T, loader: ^module_loader.Loader, state: ^lua.State, entry, expected: string) {
	status := module_loader.run_entry(loader, entry, 0)
	if !testing.expect(t, status != .OK, "failing entry unexpectedly succeeded") {
		return
	}
	message := lua.tostring(state, -1)
	testing.expectf(t, strings.contains(message, expected), "expected %q in diagnostic: %q", expected, message)
	lua.pop(state, 1)
}

@(test)
useful_module_diagnostics :: proc(t: ^testing.T) {
	counts: Load_Counts
	state, loader, err := open_test_vm(&counts)
	if !testing.expect_value(t, err, module_loader.Create_Error.None) {
		return
	}
	defer close_test_vm(state, loader)

	check_error(t, loader, state, PROJECT_ROOT + "/errors/missing_entry.luau", "does_not_exist")
	check_error(t, loader, state, PROJECT_ROOT + "/errors/syntax_entry.luau", "compile error requiring")
	check_error(t, loader, state, PROJECT_ROOT + "/errors/syntax_entry.luau", "syntax.luau")
	check_error(t, loader, state, PROJECT_ROOT + "/errors/runtime_entry.luau", "runtime error requiring")
	check_error(t, loader, state, PROJECT_ROOT + "/errors/runtime_entry.luau", "module loader boom")
	check_error(t, loader, state, PROJECT_ROOT + "/errors/cycle_entry.luau", "cyclic require")
	check_error(t, loader, state, PROJECT_ROOT + "/errors/nul_entry.luau", "embedded NUL")
	check_error(t, loader, state, PROJECT_ROOT + "/errors/escape_entry.luau", "../../../outside")
}

@(test)
repeated_startup_and_shutdown :: proc(t: ^testing.T) {
	for _ in 0..<50 {
		counts: Load_Counts
		state, loader, err := open_test_vm(&counts)
		if !testing.expect_value(t, err, module_loader.Create_Error.None) {
			return
		}
		status := module_loader.run_entry(loader, PROJECT_ROOT + "/entry.luau", 1)
		if !testing.expect_value(t, status, lua.Status.OK) {
			testing.fail_now(t, lua.tostring(state, -1))
		}
		lua.pop(state, 1)
		close_test_vm(state, loader)
	}
}
