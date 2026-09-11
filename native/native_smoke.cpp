#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "lua.h"
#include "lualib.h"
#include "luacode.h"

int main()
{
    const char* source = "return 20 + 22";
    size_t bytecodeSize = 0;
    char* bytecode = luau_compile(source, std::strlen(source), nullptr, &bytecodeSize);
    if (!bytecode)
    {
        std::fprintf(stderr, "luau_compile returned null\n");
        return 1;
    }

    lua_State* state = luaL_newstate();
    if (!state)
    {
        std::free(bytecode);
        std::fprintf(stderr, "luaL_newstate returned null\n");
        return 1;
    }

    const int loadStatus = luau_load(state, "=native-smoke", bytecode, bytecodeSize, 0);
    std::free(bytecode);
    if (loadStatus != LUA_OK)
    {
        std::fprintf(stderr, "load failed: %s\n", lua_tostring(state, -1));
        lua_close(state);
        return 1;
    }

    const int callStatus = lua_pcall(state, 0, 1, 0);
    if (callStatus != LUA_OK)
    {
        std::fprintf(stderr, "execution failed: %s\n", lua_tostring(state, -1));
        lua_close(state);
        return 1;
    }

    int isNumber = 0;
    const int result = lua_tointegerx(state, -1, &isNumber);
    lua_close(state);
    if (!isNumber || result != 42)
    {
        std::fprintf(stderr, "unexpected result\n");
        return 1;
    }

    std::puts("native smoke test passed");
}
