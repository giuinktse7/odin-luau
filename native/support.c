#include <stdlib.h>

// luau_compile returns a buffer allocated with malloc. This shim is built with
// Luau's static CRT configuration so the corresponding runtime releases it.
void odin_luau_free(void* pointer)
{
    free(pointer);
}
