cmake_minimum_required(VERSION 3.15)

cmake_policy(SET CMP0091 NEW)
project(OdinLuauNative LANGUAGES C CXX)

if(NOT LUAU_SOURCE_DIR)
    message(FATAL_ERROR "LUAU_SOURCE_DIR must point to the pinned Luau checkout")
endif()

set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(LUAU_EXTERN_C ON CACHE BOOL "" FORCE)
set(LUAU_STATIC_CRT ON CACHE BOOL "" FORCE)

set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/bin")

add_subdirectory("${LUAU_SOURCE_DIR}" luau)

add_library(Odin.Luau.Support STATIC support.c)

add_executable(Odin.Luau.AbiProbe abi_probe.cpp)
target_link_libraries(Odin.Luau.AbiProbe PRIVATE Luau.Compiler Luau.VM Luau.Require)

add_executable(Odin.Luau.NativeSmoke native_smoke.cpp)
target_link_libraries(Odin.Luau.NativeSmoke PRIVATE Luau.Compiler Luau.VM)
