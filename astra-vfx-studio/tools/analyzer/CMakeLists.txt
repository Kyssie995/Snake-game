# astra-analyze: Luau-Typechecker fuer Rojo-Projekte gegen die Roblox-API-Definitionen.
# Baut gegen einen externen Luau-Quellbaum (wird NICHT ins Repo kopiert).
#
#   cmake -S tools/analyzer -B build -DLUAU_SOURCE_DIR=/pfad/zu/luau -DCMAKE_BUILD_TYPE=Release
#   cmake --build build --target astra-analyze -j4

cmake_minimum_required(VERSION 3.18)
project(AstraAnalyze LANGUAGES CXX C)

set(LUAU_SOURCE_DIR "" CACHE PATH "Pfad zum Luau-Quellbaum (enthaelt Analysis/, Ast/, CLI/, CMakeLists.txt)")

if(NOT LUAU_SOURCE_DIR OR NOT EXISTS "${LUAU_SOURCE_DIR}/Analysis/include/Luau/Frontend.h")
    message(FATAL_ERROR "LUAU_SOURCE_DIR muss auf einen Luau-Quellbaum zeigen (gefunden: '${LUAU_SOURCE_DIR}')")
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Nur die Bibliotheken von Luau bauen, keine CLI-Tools/Tests.
set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)
add_subdirectory(${LUAU_SOURCE_DIR} luau EXCLUDE_FROM_ALL)

find_package(Threads REQUIRED)

# Namen der TypeError-Varianten aus Error.h der verwendeten Luau-Version erzeugen
# (damit die Fehlercodes in der Ausgabe auch nach einem Luau-Update stimmen).
set(_luau_error_h "${LUAU_SOURCE_DIR}/Analysis/include/Luau/Error.h")
file(READ "${_luau_error_h}" _luau_error_src)
string(REGEX MATCH "using TypeErrorData = Variant<([^;]*)>;" _luau_match "${_luau_error_src}")
if(NOT CMAKE_MATCH_1)
    message(FATAL_ERROR "TypeErrorData-Variante in ${_luau_error_h} nicht gefunden")
endif()
string(REGEX REPLACE "[ \t\r\n]" "" _luau_names "${CMAKE_MATCH_1}")
string(REPLACE "," ";" _luau_names "${_luau_names}")
set(_luau_names_inc "// generiert aus ${_luau_error_h}\n")
foreach(_name IN LISTS _luau_names)
    string(APPEND _luau_names_inc "    \"${_name}\",\n")
endforeach()
file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/generated/TypeErrorNames.inc" CONTENT "${_luau_names_inc}" @ONLY)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_luau_error_h}")

add_executable(astra-analyze
    src/main.cpp
    src/RojoTree.cpp
    src/RobloxMagic.cpp
    src/RobloxMagic.h
    src/RojoTree.h
    src/Json.h
)
target_compile_features(astra-analyze PRIVATE cxx_std_17)
target_include_directories(astra-analyze PRIVATE src "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_link_libraries(astra-analyze PRIVATE Luau.Analysis Luau.Ast Luau.Config Luau.VM Luau.CLI.lib Threads::Threads)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(astra-analyze PRIVATE -Wall -Wno-unused-parameter)
endif()

install(TARGETS astra-analyze RUNTIME DESTINATION bin)
