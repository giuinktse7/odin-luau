package main

import "core:fmt"

import "../../lua"
import "../../luaL"
import module_loader "../../libraries/module_loader"

main :: proc() {
	state := luaL.newstate()
	if state == nil {
		fmt.eprintln("Could not create the Luau VM")
		return
	}

	luaL.openlibs(state)
	loader, loader_error := module_loader.create(state, "examples/modules/scripts")
	if loader_error != .None {
		fmt.eprintln("Could not create the module loader")
		lua.close(state)
		return
	}

	// Register host functions before this point when needed. Sandboxing freezes
	// the shared globals; sandboxthread gives the entry its isolated globals.
	luaL.sandbox(state)
	luaL.sandboxthread(state)

	status := module_loader.run_entry(loader, "examples/modules/scripts/main.luau", 1)
	if status == .OK {
		fmt.println(lua.tostring(state, -1))
	} else {
		fmt.eprintf("Luau error: %s\n", lua.tostring(state, -1))
	}

	lua.close(state)
	module_loader.destroy(loader)
}
