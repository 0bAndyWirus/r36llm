cmake_minimum_required(VERSION 3.16)
project(r36llm LANGUAGES CXX)
find_package(llama CONFIG REQUIRED)
find_package(Threads REQUIRED)
option(R36LLM_BUILD_TESTS "Build self-contained application unit tests" OFF)
add_executable(r36llm
    src/main.cpp
    src/fb.cpp
    src/input.cpp
    src/keymap.cpp
    src/chat_text.cpp
    src/llm.cpp
    src/ui.cpp
    src/config.cpp
    src/device.cpp
)
target_compile_features(r36llm PRIVATE cxx_std_17)
target_compile_options(r36llm PRIVATE -Wall -Wextra)
target_link_libraries(r36llm PRIVATE llama Threads::Threads)
install(TARGETS r36llm DESTINATION bin)

if(R36LLM_BUILD_TESTS)
    enable_testing()
    add_executable(r36llm-tests
        tests/main.cpp
        tests/test_config.cpp
        tests/test_chat_text.cpp
        tests/test_keymap.cpp
        src/config.cpp
        src/chat_text.cpp
        src/keymap.cpp
    )
    target_include_directories(r36llm-tests PRIVATE src)
    target_compile_features(r36llm-tests PRIVATE cxx_std_17)
    target_compile_options(r36llm-tests PRIVATE -Wall -Wextra)
    foreach(suite config chat_text keymap)
        add_test(NAME ${suite} COMMAND r36llm-tests ${suite})
    endforeach()
endif()
