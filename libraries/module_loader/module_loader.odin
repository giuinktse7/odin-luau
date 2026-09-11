// A small filesystem-backed adapter for Luau's upstream require-by-string API.
// It intentionally supports only Windows paths and .luau source files below
// one trusted project root.
package luau_module_loader

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import luau "../.."
import lua "../../lua"
import luaL "../../luaL"
import luau_require "../../require"

Create_Error :: enum {
	None,
	Invalid_State,
	Invalid_Root,
}

Loader :: struct {
	state:           ^lua.State,
	root:            string,
	navigation_path: string,
	module_file:     string,
	compile_options: luau.CompileOptions,
	loading:         map[string]bool,
	allocator:       runtime.Allocator,
	saved_context:   runtime.Context,
}

Node :: struct {
	path:        string,
	module_file: string,
}

// create installs a checked upstream require() function in state. The loader
// must outlive every script execution in the VM. Call destroy only after the
// VM has been closed. Pointer fields inside compile_options are borrowed for
// the same lifetime.
create :: proc {
	create_default,
	create_with_options,
}

create_default :: proc(
	state: ^lua.State,
	root: string,
	allocator := context.allocator,
) -> (^Loader, Create_Error) {
	return create_with_options(state, root, luau.default_compile_options(), allocator)
}

create_with_options :: proc(
	state: ^lua.State,
	root: string,
	compile_options: luau.CompileOptions,
	allocator := context.allocator,
) -> (^Loader, Create_Error) {
	if state == nil || strings.contains_rune(root, '\x00') {
		if state == nil do return nil, .Invalid_State
		return nil, .Invalid_Root
	}

	absolute_root, ok := canonical_directory(root, allocator)
	if !ok {
		return nil, .Invalid_Root
	}

	loader := new(Loader, allocator)
	loader^ = {
		state           = state,
		root            = absolute_root,
		compile_options = compile_options,
		loading         = make(map[string]bool, allocator),
		allocator       = allocator,
		saved_context   = context,
	}
	install(loader)
	return loader, .None
}

destroy :: proc(loader: ^Loader) {
	if loader == nil {
		return
	}
	allocator := loader.allocator
	delete(loader.root, allocator)
	delete(loader.navigation_path, allocator)
	delete(loader.module_file, allocator)
	delete(loader.loading)
	free(loader, allocator)
}

// install replaces the global require with a NUL-checking wrapper around the
// upstream implementation. It is already called by create and is exposed only
// for hosts that deliberately replace globals during setup.
install :: proc(loader: ^Loader) {
	luau_require.pushrequire(loader.state, configure_require, loader)
	lua.pushcclosure(loader.state, checked_require, "require", 1)
	lua.setglobal(loader.state, "require")
}

// run_entry compiles and executes a .luau file below the loader root. It leaves
// exactly result_count values on success, or one diagnostic string on failure.
// The caller retains control over library opening and optional sandboxing.
run_entry :: proc(loader: ^Loader, path: string, result_count: c.int = 0) -> lua.Status {
	if loader == nil || loader.state == nil {
		return .ERRRUN
	}
	context = loader.saved_context

	if strings.contains_rune(path, '\x00') {
		push_message(loader.state, "entry path contains an embedded NUL")
		return .ERRRUN
	}

	entry_file, ok := canonical_file(path, loader.allocator)
	if !ok || !within_root(loader, entry_file) || !strings.equal_fold(filepath.ext(entry_file), ".luau") {
		delete(entry_file, loader.allocator)
		message := fmt.aprintf("entry %q is not a .luau file below root %q", path, loader.root, allocator=loader.allocator)
		push_owned_message(loader.state, message, loader.allocator)
		return .ERRRUN
	}

	source, read_error := os.read_entire_file(entry_file, loader.allocator)
	if read_error != nil {
		message := fmt.aprintf("could not read entry %q resolved to %q: %v", path, entry_file, read_error, allocator=loader.allocator)
		delete(entry_file, loader.allocator)
		push_owned_message(loader.state, message, loader.allocator)
		return .ERRRUN
	}

	chunk_name := fmt.aprint("@", entry_file, sep="", allocator=loader.allocator)
	chunk_name_c := strings.clone_to_cstring(chunk_name, loader.allocator)
	bytecode_size: c.size_t
	bytecode := luau.compile(cast(cstring)raw_data(source), c.size_t(len(source)), &loader.compile_options, &bytecode_size)
	delete(source, loader.allocator)

	if bytecode == nil {
		delete((cast([^]u8)chunk_name_c)[:len(chunk_name)+1], loader.allocator)
		delete(chunk_name, loader.allocator)
		delete(entry_file, loader.allocator)
		push_message(loader.state, "Luau compilation allocation failed")
		return .ERRMEM
	}

	status := lua.load(loader.state, chunk_name_c, bytecode, bytecode_size, 0)
	luau.release_bytecode(bytecode)
	delete((cast([^]u8)chunk_name_c)[:len(chunk_name)+1], loader.allocator)
	delete(chunk_name, loader.allocator)
	delete(entry_file, loader.allocator)
	if status != .OK {
		return status
	}

	return lua.pcall(loader.state, 0, result_count, 0)
}

configure_require :: proc "c" (config: ^luau_require.Configuration) {
	config^ = {
		is_require_allowed = is_require_allowed,
		reset              = reset,
		jump_to_alias      = jump_to_alias,
		to_parent          = to_parent,
		to_child           = to_child,
		is_module_present  = is_module_present,
		get_chunkname      = get_chunkname,
		get_loadname       = get_loadname,
		get_cache_key      = get_cache_key,
		get_config_status  = get_config_status,
		get_config         = get_config,
		load               = load_module,
	}
}

checked_require :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	length: c.size_t
	path := lua.tolstring(L, 1, &length)
	if path != nil {
		bytes := (cast([^]u8)path)[:int(length)]
		for byte in bytes {
			if byte == 0 {
				push_message(L, "require path contains an embedded NUL")
				lua.error(L)
			}
		}
	}

	lua.settop(L, 1)
	lua.pushvalue(L, c.int(lua.upvalueindex(1)))
	lua.insert(L, 1)
	lua.call(L, 1, 1)
	return 1
}

is_require_allowed :: proc "c" (L: ^lua.State, ctx: rawptr, chunkname: cstring) -> bool {
	context = runtime.default_context()
	loader := cast(^Loader)ctx
	if loader == nil || chunkname == nil {
		return false
	}
	name := string(chunkname)
	return len(name) > 1 && name[0] == '@' && !strings.contains_rune(name, '\x00')
}

reset :: proc "c" (L: ^lua.State, ctx: rawptr, chunkname: cstring) -> luau_require.Navigate_Result {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil || chunkname == nil {
		return .Not_Found
	}
	name := string(chunkname)
	if len(name) < 2 || name[0] != '@' {
		return .Not_Found
	}

	file, ok := canonical_file(name[1:], loader.allocator)
	if !ok || !within_root(loader, file) || !strings.equal_fold(filepath.ext(file), ".luau") {
		delete(file, loader.allocator)
		return .Not_Found
	}
	logical := module_path_from_file(file, loader.allocator)
	delete(file, loader.allocator)
	if len(logical) == 0 {
		return .Not_Found
	}
	node, result := resolve_node(loader, logical)
	delete(logical, loader.allocator)
	if result == .Success {
		set_node(loader, node)
	}
	return result
}

jump_to_alias :: proc "c" (L: ^lua.State, ctx: rawptr, path: cstring) -> luau_require.Navigate_Result {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil || path == nil {
		return .Not_Found
	}
	value := string(path)
	if strings.contains_rune(value, '\x00') || !filepath.is_abs(value) {
		return .Not_Found
	}

	absolute, ok := normalize_absolute(value, loader.allocator)
	if !ok || !within_root(loader, absolute) {
		delete(absolute, loader.allocator)
		return .Not_Found
	}
	logical := absolute
	if strings.equal_fold(filepath.ext(absolute), ".luau") {
		logical = module_path_from_file(absolute, loader.allocator)
		delete(absolute, loader.allocator)
	}
	node, result := resolve_node(loader, logical)
	delete(logical, loader.allocator)
	if result == .Success {
		set_node(loader, node)
	}
	return result
}

to_parent :: proc "c" (L: ^lua.State, ctx: rawptr) -> luau_require.Navigate_Result {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil || len(loader.navigation_path) == 0 || strings.equal_fold(loader.navigation_path, loader.root) {
		return .Not_Found
	}
	parent := filepath.dir(loader.navigation_path)
	if len(parent) == 0 || !within_root(loader, parent) {
		return .Not_Found
	}
	node, result := resolve_node(loader, parent)
	if result == .Ambiguous {
		// Navigation to a parent is unambiguous as a hierarchy operation.
		set_navigation_directory(loader, parent)
		return .Success
	}
	if result == .Success {
		set_node(loader, node)
	}
	return result
}

to_child :: proc "c" (L: ^lua.State, ctx: rawptr, name: cstring) -> luau_require.Navigate_Result {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil || name == nil {
		return .Not_Found
	}
	component := string(name)
	if len(component) == 0 || component == "." || component == ".." || component == ".config" ||
	   strings.contains_rune(component, '/') || strings.contains_rune(component, '\\') || strings.contains_rune(component, '\x00') {
		return .Not_Found
	}

	child, _ := filepath.join([]string{loader.navigation_path, component}, loader.allocator)
	if !within_root(loader, child) {
		delete(child, loader.allocator)
		return .Not_Found
	}
	node, result := resolve_node(loader, child)
	delete(child, loader.allocator)
	if result == .Success {
		set_node(loader, node)
	}
	return result
}

is_module_present :: proc "c" (L: ^lua.State, ctx: rawptr) -> bool {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	return loader != nil && len(loader.module_file) > 0
}

get_chunkname :: proc "c" (L: ^lua.State, ctx: rawptr, buffer: [^]u8, buffer_size: c.size_t, size_out: ^c.size_t) -> luau_require.Write_Result {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil || len(loader.module_file) == 0 {
		return .Failure
	}
	value := fmt.aprint("@", loader.module_file, sep="", allocator=loader.allocator)
	result := write_value(value, buffer, buffer_size, size_out)
	delete(value, loader.allocator)
	return result
}

get_loadname :: proc "c" (L: ^lua.State, ctx: rawptr, buffer: [^]u8, buffer_size: c.size_t, size_out: ^c.size_t) -> luau_require.Write_Result {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil {
		return .Failure
	}
	return write_value(loader.module_file, buffer, buffer_size, size_out)
}

get_cache_key :: proc "c" (L: ^lua.State, ctx: rawptr, buffer: [^]u8, buffer_size: c.size_t, size_out: ^c.size_t) -> luau_require.Write_Result {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil {
		return .Failure
	}
	value := strings.to_lower(loader.module_file, loader.allocator)
	result := write_value(value, buffer, buffer_size, size_out)
	delete(value, loader.allocator)
	return result
}

get_config_status :: proc "c" (L: ^lua.State, ctx: rawptr) -> luau_require.Config_Status {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil {
		return .Absent
	}
	json_path, luau_path := config_paths(loader)
	json_exists := os.is_file(json_path)
	luau_exists := os.is_file(luau_path)
	delete(json_path, loader.allocator)
	delete(luau_path, loader.allocator)
	if json_exists && luau_exists do return .Ambiguous
	if json_exists do return .Present_JSON
	if luau_exists do return .Present_Luau
	return .Absent
}

get_config :: proc "c" (L: ^lua.State, ctx: rawptr, buffer: [^]u8, buffer_size: c.size_t, size_out: ^c.size_t) -> luau_require.Write_Result {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil {
		return .Failure
	}
	json_path, luau_path := config_paths(loader)
	path := json_path if os.is_file(json_path) else luau_path
	contents, err := os.read_entire_file(path, loader.allocator)
	delete(json_path, loader.allocator)
	delete(luau_path, loader.allocator)
	if err != nil {
		delete(contents, loader.allocator)
		return .Failure
	}
	result := write_value(string(contents), buffer, buffer_size, size_out)
	delete(contents, loader.allocator)
	return result
}

load_module :: proc "c" (L: ^lua.State, ctx: rawptr, path, chunkname, loadname: cstring) -> c.int {
	context = runtime.default_context()
	loader := begin_callback(ctx)
	if loader == nil || path == nil || chunkname == nil || loadname == nil {
		push_message(L, "invalid filesystem loader state")
		lua.error(L)
	}

	requested := string(path)
	resolved := string(loadname)
	if loader.loading[resolved] {
		message := fmt.aprintf("cyclic require of %q resolved to %q", requested, resolved, allocator=loader.allocator)
		push_owned_message(L, message, loader.allocator)
		lua.error(L)
	}
	loader.loading[resolved] = true

	source, read_error := os.read_entire_file(resolved, loader.allocator)
	if read_error != nil {
		delete_key(&loader.loading, resolved)
		message := fmt.aprintf("could not read required module %q resolved to %q: %v", requested, resolved, read_error, allocator=loader.allocator)
		push_owned_message(L, message, loader.allocator)
		lua.error(L)
	}

	main_state := lua.mainthread(L)
	module_state := lua.newthread(main_state)
	lua.xmove(main_state, L, 1)
	luaL.sandboxthread(module_state)

	bytecode_size: c.size_t
	bytecode := luau.compile(cast(cstring)raw_data(source), c.size_t(len(source)), &loader.compile_options, &bytecode_size)
	delete(source, loader.allocator)
	if bytecode == nil {
		lua.remove(L, -1)
		delete_key(&loader.loading, resolved)
		message := fmt.aprintf("compilation allocation failed for module %q resolved to %q", requested, resolved, allocator=loader.allocator)
		push_owned_message(L, message, loader.allocator)
		lua.error(L)
	}

	load_status := lua.load(module_state, chunkname, bytecode, bytecode_size, 0)
	luau.release_bytecode(bytecode)
	if load_status != .OK {
		detail := lua.tostring(module_state, -1)
		message := fmt.aprintf("compile error requiring %q resolved to %q: %s", requested, resolved, detail, allocator=loader.allocator)
		lua.remove(L, -1)
		delete_key(&loader.loading, resolved)
		push_owned_message(L, message, loader.allocator)
		lua.error(L)
	}

	resume_status := lua.resume(module_state, L, 0)
	if resume_status != c.int(lua.Status.OK) {
		detail := "module yielded" if resume_status == c.int(lua.Status.YIELD) else lua.tostring(module_state, -1)
		message := fmt.aprintf("runtime error requiring %q resolved to %q: %s", requested, resolved, detail, allocator=loader.allocator)
		lua.remove(L, -1)
		delete_key(&loader.loading, resolved)
		push_owned_message(L, message, loader.allocator)
		lua.error(L)
	}
	if lua.gettop(module_state) != 1 {
		message := fmt.aprintf("module %q resolved to %q must return exactly one value", requested, resolved, allocator=loader.allocator)
		lua.remove(L, -1)
		delete_key(&loader.loading, resolved)
		push_owned_message(L, message, loader.allocator)
		lua.error(L)
	}

	lua.xmove(module_state, L, 1)
	lua.remove(L, -2)
	delete_key(&loader.loading, resolved)
	return 1
}

begin_callback :: proc(ctx: rawptr) -> ^Loader {
	loader := cast(^Loader)ctx
	if loader != nil {
		context = loader.saved_context
	}
	return loader
}

write_value :: proc(value: string, buffer: [^]u8, buffer_size: c.size_t, size_out: ^c.size_t) -> luau_require.Write_Result {
	if size_out == nil {
		return .Failure
	}
	required := c.size_t(len(value) + 1)
	size_out^ = required
	if buffer == nil || buffer_size < required {
		return .Buffer_Too_Small
	}
	copy(buffer[:len(value)], transmute([]u8)value)
	buffer[len(value)] = 0
	return .Success
}

push_message :: proc(L: ^lua.State, message: string) {
	lua.pushlstring(L, cast(cstring)raw_data(message), c.size_t(len(message)))
}

push_owned_message :: proc(L: ^lua.State, message: string, allocator: runtime.Allocator) {
	push_message(L, message)
	delete(message, allocator)
}

normalize_absolute :: proc(path: string, allocator: runtime.Allocator) -> (string, bool) {
	absolute, err := os.get_absolute_path(path, allocator)
	if err != nil {
		return "", false
	}
	cleaned, clean_error := filepath.clean(absolute, allocator)
	delete(absolute, allocator)
	if clean_error != nil {
		return "", false
	}
	return cleaned, true
}

canonical_file :: proc(path: string, allocator: runtime.Allocator) -> (string, bool) {
	absolute, ok := normalize_absolute(path, allocator)
	if !ok {
		return "", false
	}
	info, err := os.stat(absolute, allocator)
	delete(absolute, allocator)
	if err != nil || info.type != .Regular {
		if err == nil do os.file_info_delete(info, allocator)
		return "", false
	}
	cleaned, _ := filepath.clean(info.fullpath, allocator)
	os.file_info_delete(info, allocator)
	return cleaned, true
}

canonical_directory :: proc(path: string, allocator: runtime.Allocator) -> (string, bool) {
	absolute, ok := normalize_absolute(path, allocator)
	if !ok {
		return "", false
	}
	info, err := os.stat(absolute, allocator)
	delete(absolute, allocator)
	if err != nil || info.type != .Directory {
		if err == nil do os.file_info_delete(info, allocator)
		return "", false
	}
	cleaned, _ := filepath.clean(info.fullpath, allocator)
	os.file_info_delete(info, allocator)
	return cleaned, true
}

within_root :: proc(loader: ^Loader, path: string) -> bool {
	root := loader.root
	if strings.equal_fold(path, root) {
		return true
	}
	return len(path) > len(root) && strings.equal_fold(path[:len(root)], root) &&
	       (filepath.is_separator(root[len(root)-1]) || filepath.is_separator(path[len(root)]))
}

module_path_from_file :: proc(path: string, allocator: runtime.Allocator) -> string {
	if strings.equal_fold(filepath.base(path), "init.luau") {
		return strings.clone(filepath.dir(path), allocator)
	}
	if strings.equal_fold(filepath.ext(path), ".luau") {
		return strings.clone(path[:len(path)-len(filepath.ext(path))], allocator)
	}
	return ""
}

resolve_node :: proc(loader: ^Loader, path: string) -> (Node, luau_require.Navigate_Result) {
	cleaned, _ := filepath.clean(path, loader.allocator)
	if !within_root(loader, cleaned) {
		delete(cleaned, loader.allocator)
		return {}, .Not_Found
	}

	file_candidate := fmt.aprint(cleaned, ".luau", sep="", allocator=loader.allocator)
	file_exists := within_root(loader, file_candidate) &&
	               !strings.equal_fold(filepath.base(cleaned), "init") &&
	               os.is_file(file_candidate)
	directory_exists := os.is_directory(cleaned)
	if file_exists && directory_exists {
		delete(file_candidate, loader.allocator)
		delete(cleaned, loader.allocator)
		return {}, .Ambiguous
	}

	if file_exists {
		module_file, ok := canonical_file(file_candidate, loader.allocator)
		delete(file_candidate, loader.allocator)
		if !ok || !within_root(loader, module_file) {
			delete(module_file, loader.allocator)
			delete(cleaned, loader.allocator)
			return {}, .Not_Found
		}
		return {path = cleaned, module_file = module_file}, .Success
	}
	delete(file_candidate, loader.allocator)

	if !directory_exists {
		delete(cleaned, loader.allocator)
		return {}, .Not_Found
	}
	canonical_dir, ok := canonical_directory(cleaned, loader.allocator)
	if !ok || !within_root(loader, canonical_dir) {
		delete(canonical_dir, loader.allocator)
		delete(cleaned, loader.allocator)
		return {}, .Not_Found
	}
	delete(canonical_dir, loader.allocator)

	init_candidate, _ := filepath.join([]string{cleaned, "init.luau"}, loader.allocator)
	if os.is_file(init_candidate) {
		module_file, module_ok := canonical_file(init_candidate, loader.allocator)
		delete(init_candidate, loader.allocator)
		if !module_ok || !within_root(loader, module_file) {
			delete(module_file, loader.allocator)
			delete(cleaned, loader.allocator)
			return {}, .Not_Found
		}
		return {path = cleaned, module_file = module_file}, .Success
	}
	delete(init_candidate, loader.allocator)
	return {path = cleaned}, .Success
}

set_node :: proc(loader: ^Loader, node: Node) {
	delete(loader.navigation_path, loader.allocator)
	delete(loader.module_file, loader.allocator)
	loader.navigation_path = node.path
	loader.module_file = node.module_file
}

set_navigation_directory :: proc(loader: ^Loader, path: string) {
	owned_path := strings.clone(path, loader.allocator)
	delete(loader.navigation_path, loader.allocator)
	delete(loader.module_file, loader.allocator)
	loader.navigation_path = owned_path
	loader.module_file = ""
}

config_paths :: proc(loader: ^Loader) -> (string, string) {
	json_path, _ := filepath.join([]string{loader.navigation_path, ".luaurc"}, loader.allocator)
	luau_path, _ := filepath.join([]string{loader.navigation_path, ".config.luau"}, loader.allocator)
	return json_path, luau_path
}
