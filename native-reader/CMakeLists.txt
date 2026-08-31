cmake_minimum_required(VERSION 3.22)

project(paper_pro_reader_native VERSION 0.1.0 LANGUAGES CXX)

option(PPR_BUILD_APP "Build the Paper Pro benchmark executable" ON)
option(PPR_BUILD_TESTS "Build host tests" ON)
option(PPR_ENABLE_SANITIZERS "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(Threads REQUIRED)

add_library(paperpro_native_core STATIC
    core/coordinate_transform.cpp
    core/ink_model.cpp
    core/interaction_controller.cpp
    core/latency_recorder.cpp
    core/refresh_scheduler.cpp
    core/systemd_watchdog.cpp
    ui/scene/raster_surface.cpp
    ui/scene/benchmark_renderer.cpp
    platform/paperpro/display/quill_display_backend.cpp
    platform/paperpro/display/qtfb_display_backend.cpp
    platform/paperpro/input/evdev_input_backend.cpp
    benchmark/benchmark_app.cpp
)
target_include_directories(paperpro_native_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(paperpro_native_core PUBLIC Threads::Threads ${CMAKE_DL_LIBS})
target_compile_options(paperpro_native_core PRIVATE
    $<$<CXX_COMPILER_ID:AppleClang,Clang,GNU>:-Wall;-Wextra;-Wpedantic;-Wshadow;-Wconversion>
)

if(PPR_ENABLE_SANITIZERS)
    if(CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang|GNU")
        target_compile_options(paperpro_native_core PUBLIC -fsanitize=address,undefined -fno-omit-frame-pointer)
        target_link_options(paperpro_native_core PUBLIC -fsanitize=address,undefined)
    else()
        message(FATAL_ERROR "PPR_ENABLE_SANITIZERS is unsupported by this compiler")
    endif()
endif()

if(PPR_BUILD_APP)
    add_executable(paper-pro-reader-benchmark app/main.cpp)
    target_link_libraries(paper-pro-reader-benchmark PRIVATE paperpro_native_core)
    install(TARGETS paper-pro-reader-benchmark RUNTIME DESTINATION bin)
endif()

include(CTest)
if(PPR_BUILD_TESTS)
    add_executable(native-reader-tests tests/test_main.cpp)
    target_link_libraries(native-reader-tests PRIVATE paperpro_native_core)
    add_test(NAME native-reader-tests COMMAND native-reader-tests)
endif()
