cmake_minimum_required(VERSION 3.22.1)

project(silent_llama_bridge LANGUAGES CXX)

add_library(
    silent_llama_bridge
    SHARED
    silent_llama_bridge.cpp
)

target_compile_features(silent_llama_bridge PRIVATE cxx_std_17)

find_library(dl_library dl)

target_link_libraries(
    silent_llama_bridge
    PRIVATE
    ${dl_library}
)
