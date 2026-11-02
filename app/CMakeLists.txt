cmake_minimum_required(VERSION 3.16)
project(r36llm LANGUAGES CXX)
find_package(llama CONFIG REQUIRED)
find_package(Threads REQUIRED)
add_executable(r36llm
    src/main.cpp
    src/fb.cpp
    src/input.cpp
    src/llm.cpp
    src/ui.cpp
    src/config.cpp
    src/device.cpp
)
target_compile_features(r36llm PRIVATE cxx_std_17)
target_compile_options(r36llm PRIVATE -Wall -Wextra)
target_link_libraries(r36llm PRIVATE llama Threads::Threads)
install(TARGETS r36llm DESTINATION bin)
