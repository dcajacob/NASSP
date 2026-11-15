cmake_minimum_required(VERSION 3.19)
project(NASSPGuidanceComputerTests LANGUAGES C)

enable_testing()

set(repository_root "${CMAKE_CURRENT_LIST_DIR}/../..")
set(yaagc "${repository_root}/Orbitersdk/samples/ProjectApollo/src_sys/yaAGC")

add_executable(apollo7_agc apollo7_agc.c
    "${yaagc}/agc_engine.c"
    "${yaagc}/agc_engine_init.c"
    "${yaagc}/agc_utilities.c"
    "${yaagc}/Backtrace.c"
    "${yaagc}/random.c"
    "${yaagc}/rfopen.c")
target_compile_features(apollo7_agc PRIVATE c_std_17)
target_include_directories(apollo7_agc PRIVATE "${yaagc}")

add_test(NAME apollo7_colossus237
    COMMAND apollo7_agc "${repository_root}/Config/ProjectApollo/Colossus237.bin")
