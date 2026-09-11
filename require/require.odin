// Thin bindings for the pinned Luau Require C API.
package luau_require

import "core:c"
import "../lua"

when ODIN_OS == .Windows {
	foreign import LuauRequire {
		"../lib/windows/Luau.Require.lib",
		"../lib/windows/Luau.Config.lib",
		"../lib/windows/Luau.Compiler.lib",
		"../lib/windows/Luau.VM.lib",
		"../lib/windows/Luau.Ast.lib",
		"../lib/windows/Luau.Bytecode.lib",
		"../lib/windows/Luau.Common.lib",
	}
} else {
	#panic("Unsupported OS (currently). The bundled native libraries target Windows x64.")
}

Navigate_Result :: enum c.int {
	Success,
	Ambiguous,
	Not_Found,
}

Write_Result :: enum c.int {
	Success,
	Buffer_Too_Small,
	Failure,
}

Config_Status :: enum c.int {
	Absent,
	Ambiguous,
	Present_JSON,
	Present_Luau,
}

Is_Require_Allowed_Callback :: #type proc "c" (
	L: ^lua.State,
	ctx: rawptr,
	requirer_chunkname: cstring,
) -> bool
Navigate_From_String_Callback :: #type proc "c" (L: ^lua.State, ctx: rawptr, value: cstring) -> Navigate_Result
Navigate_Callback :: #type proc "c" (L: ^lua.State, ctx: rawptr) -> Navigate_Result
Is_Module_Present_Callback :: #type proc "c" (L: ^lua.State, ctx: rawptr) -> bool
Write_Callback :: #type proc "c" (
	L: ^lua.State,
	ctx: rawptr,
	buffer: [^]u8,
	buffer_size: c.size_t,
	size_out: ^c.size_t,
) -> Write_Result
Config_Status_Callback :: #type proc "c" (L: ^lua.State, ctx: rawptr) -> Config_Status
Get_Alias_Callback :: #type proc "c" (
	L: ^lua.State,
	ctx: rawptr,
	alias: cstring,
	buffer: [^]u8,
	buffer_size: c.size_t,
	size_out: ^c.size_t,
) -> Write_Result
Config_Timeout_Callback :: #type proc "c" (L: ^lua.State, ctx: rawptr) -> c.int
Load_Callback :: #type proc "c" (
	L: ^lua.State,
	ctx: rawptr,
	path: cstring,
	chunkname: cstring,
	loadname: cstring,
) -> c.int

Configuration :: struct {
	is_require_allowed: Is_Require_Allowed_Callback,
	reset: Navigate_From_String_Callback,
	jump_to_alias: Navigate_From_String_Callback,
	to_alias_override: Navigate_From_String_Callback,
	to_alias_fallback: Navigate_From_String_Callback,
	to_parent: Navigate_Callback,
	to_child: Navigate_From_String_Callback,
	is_module_present: Is_Module_Present_Callback,
	get_chunkname: Write_Callback,
	get_loadname: Write_Callback,
	get_cache_key: Write_Callback,
	get_config_status: Config_Status_Callback,
	get_alias: Get_Alias_Callback,
	get_config: Write_Callback,
	get_luau_config_timeout: Config_Timeout_Callback,
	load: Load_Callback,
}

Configuration_Init :: #type proc "c" (config: ^Configuration)

@(link_prefix = "luarequire_")
foreign LuauRequire {
	pushrequire :: proc(L: ^lua.State, config_init: Configuration_Init, ctx: rawptr) ---
	clearcacheentry :: proc(L: ^lua.State) -> c.int ---
	clearcache :: proc(L: ^lua.State) -> c.int ---
}

foreign LuauRequire {
	@(link_name = "luaopen_require")
	open :: proc(L: ^lua.State, config_init: Configuration_Init, ctx: rawptr) ---
}

when ODIN_ARCH == .amd64 {
	#assert(size_of(Configuration) == 128)
	#assert(align_of(Configuration) == 8)
	#assert(offset_of(Configuration, get_config_status) == 88)
	#assert(offset_of(Configuration, get_config) == 104)
	#assert(offset_of(Configuration, load) == 120)
}
