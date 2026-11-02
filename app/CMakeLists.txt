cmake_minimum_required(VERSION 3.16)
project(r36llm LANGUAGES CXX)
find_package(llama CONFIG REQUIRED)
find_package(Threads REQUIRED)
option(R36LLM_BUILD_TESTS "Build self-contained application unit tests" OFF)
# Archive-based engine builds may report an unknown commit. Include the actual
# library digest so replacing that engine still invalidates persisted states.
file(SHA256 "${llama_LIBRARY}" engine_library_hash)
set(engine_pin "${LLAMA_VERSION}:${LLAMA_BUILD_COMMIT}:${LLAMA_BUILD_NUMBER}:${engine_library_hash}")
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
target_compile_definitions(r36llm PRIVATE R36LLM_ENGINE_VERSION="${engine_pin}")
target_link_libraries(r36llm PRIVATE llama Threads::Threads)
install(TARGETS r36llm DESTINATION bin)

if(R36LLM_BUILD_TESTS)
    enable_testing()
    add_executable(r36llm-tests
        tests/main.cpp
        tests/test_config.cpp
        tests/test_chat_text.cpp
        tests/test_keymap.cpp
        tests/test_prompt_cache.cpp
        src/llm.cpp
        src/config.cpp
        src/chat_text.cpp
        src/keymap.cpp
    )
    target_include_directories(r36llm-tests PRIVATE src)
    target_compile_features(r36llm-tests PRIVATE cxx_std_17)
    target_compile_options(r36llm-tests PRIVATE -Wall -Wextra)
    target_compile_definitions(r36llm-tests PRIVATE R36LLM_ENGINE_VERSION="${engine_pin}")
    target_link_libraries(r36llm-tests PRIVATE llama Threads::Threads)
    foreach(suite config chat_text keymap prompt_cache)
        add_test(NAME ${suite} COMMAND r36llm-tests ${suite})
        set_tests_properties(${suite} PROPERTIES
            ENVIRONMENT "LD_LIBRARY_PATH=${LLAMA_LIB_DIR}:$ENV{LD_LIBRARY_PATH}")
    endforeach()
endif()
