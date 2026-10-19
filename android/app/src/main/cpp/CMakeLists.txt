# libtyped_llm.so: llama.cpp (CPU only, statically linked) plus a one-call C
# wrapper for the voice-memo shaper. The model itself is never bundled; it
# is an optional download.
cmake_minimum_required(VERSION 3.22)
project(typed_llm LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)
# Pinned release; the GGUF model is converted with the same version.
FetchContent_Declare(
  llama
  URL https://github.com/ggml-org/llama.cpp/archive/refs/tags/b11716.tar.gz
  URL_HASH SHA256=a411ee5e422528bb4c4396a3796948cda73f20edb1f5d4949248175b633335df
)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
if(ANDROID_ABI STREQUAL "arm64-v8a")
  # Dot-product + fp16 arithmetic (ARMv8.2-A): every big-core phone since
  # ~2018 has them and llama.cpp is several times faster with them. The app
  # checks /proc/cpuinfo for asimddp before loading this library, so older
  # cores never execute these instructions.
  set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
endif()
FetchContent_MakeAvailable(llama)

add_library(typed_llm SHARED typed_llm.cpp)
target_link_libraries(typed_llm PRIVATE llama ggml)
# Keep only the two exported functions; strip the rest.
set_target_properties(typed_llm PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)
target_link_options(typed_llm PRIVATE -Wl,--gc-sections -Wl,-s)
