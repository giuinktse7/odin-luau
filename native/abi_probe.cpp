#include <cstddef>
#include <cstdio>

#include "lua.h"
#include "luacode.h"
#include "Luau/Require.h"

int main()
{
    std::printf("luau.commit.expected=47cda63705c25633d757bacdcb7c9c6190625cad\n");
    std::printf("config.LUA_USE_LONGJMP=%d\n", LUA_USE_LONGJMP);
    std::printf("config.LUA_VECTOR_SIZE=%d\n", LUA_VECTOR_SIZE);
    std::printf("config.LUA_VECTOR_DOUBLE=%d\n", LUA_VECTOR_DOUBLE);

    std::printf("lua_CompileOptions.size=%zu\n", sizeof(lua_CompileOptions));
    std::printf("lua_CompileOptions.align=%zu\n", alignof(lua_CompileOptions));
    std::printf("lua_CompileOptions.vectorPrecision=%zu\n", offsetof(lua_CompileOptions, vectorPrecision));
    std::printf("lua_CompileOptions.mutableGlobals=%zu\n", offsetof(lua_CompileOptions, mutableGlobals));
    std::printf("lua_CompileOptions.disabledBuiltins=%zu\n", offsetof(lua_CompileOptions, disabledBuiltins));

    std::printf("lua_Debug.size=%zu\n", sizeof(lua_Debug));
    std::printf("lua_Debug.align=%zu\n", alignof(lua_Debug));
    std::printf("lua_Debug.protoid=%zu\n", offsetof(lua_Debug, protoid));
    std::printf("lua_Debug.userdata=%zu\n", offsetof(lua_Debug, userdata));
    std::printf("lua_Debug.ssbuf=%zu\n", offsetof(lua_Debug, ssbuf));

    std::printf("lua_Callbacks.size=%zu\n", sizeof(lua_Callbacks));
    std::printf("lua_Callbacks.align=%zu\n", alignof(lua_Callbacks));
    std::printf("lua_Callbacks.useratom=%zu\n", offsetof(lua_Callbacks, useratom));
    std::printf("lua_Callbacks.onallocate=%zu\n", offsetof(lua_Callbacks, onallocate));
    std::printf("lua_Callbacks.onfree=%zu\n", offsetof(lua_Callbacks, onfree));

    std::printf("luarequire_Configuration.size=%zu\n", sizeof(luarequire_Configuration));
    std::printf("luarequire_Configuration.align=%zu\n", alignof(luarequire_Configuration));
    std::printf("luarequire_Configuration.get_config_status=%zu\n", offsetof(luarequire_Configuration, get_config_status));
    std::printf("luarequire_Configuration.get_config=%zu\n", offsetof(luarequire_Configuration, get_config));
    std::printf("luarequire_Configuration.load=%zu\n", offsetof(luarequire_Configuration, load));

    std::printf("luarequire_NavigateResult.SUCCESS=%d\n", NAVIGATE_SUCCESS);
    std::printf("luarequire_NavigateResult.AMBIGUOUS=%d\n", NAVIGATE_AMBIGUOUS);
    std::printf("luarequire_NavigateResult.NOT_FOUND=%d\n", NAVIGATE_NOT_FOUND);
    std::printf("luarequire_WriteResult.BUFFER_TOO_SMALL=%d\n", WRITE_BUFFER_TOO_SMALL);
    std::printf("luarequire_ConfigStatus.PRESENT_JSON=%d\n", CONFIG_PRESENT_JSON);

    std::printf("lua_Type.INTEGER=%d\n", LUA_TINTEGER);
    std::printf("lua_Type.VECTOR=%d\n", LUA_TVECTOR);
    std::printf("lua_Type.CLASS=%d\n", LUA_TCLASS);
    std::printf("lua_Type.OBJECT=%d\n", LUA_TOBJECT);
    std::printf("lua_Type.DEADKEY=%d\n", LUA_TDEADKEY);
    std::printf("lua_Type.COUNT=%d\n", LUA_T_COUNT);
}
