cmake_minimum_required(VERSION 3.19)
project(NativeStage2010 LANGUAGES CXX)

set(ORBITER_NATIVE_SOURCE_DIR "" CACHE PATH "Matching native Orbiter source checkout")
set(ORBITER_NATIVE_BUILD_DIR "" CACHE PATH "Matching native Orbiter build")
if(NOT EXISTS "${ORBITER_NATIVE_SOURCE_DIR}/Orbitersdk/include/NativeVesselAPI.h" OR
   NOT EXISTS "${ORBITER_NATIVE_BUILD_DIR}/native-sdk/OrbiterNativeBuild.h")
    message(FATAL_ERROR "Set ORBITER_NATIVE_SOURCE_DIR and ORBITER_NATIVE_BUILD_DIR")
endif()
add_library(stage MODULE stage.cpp)
target_compile_features(stage PRIVATE cxx_std_17)
target_compile_definitions(stage PRIVATE ORBITER_NATIVE_BUILD_CONFIGURATION="$<CONFIG>")
target_include_directories(stage SYSTEM PRIVATE
    "${ORBITER_NATIVE_SOURCE_DIR}/Orbitersdk/include"
    "${ORBITER_NATIVE_SOURCE_DIR}/Src/Orbiter"
    "${ORBITER_NATIVE_BUILD_DIR}/native-sdk"
)
target_link_libraries(stage PRIVATE
    "${ORBITER_NATIVE_BUILD_DIR}/liborbiter_production_boundary.so"
    "${ORBITER_NATIVE_BUILD_DIR}/liborbiter_production_vessels.so"
)
target_link_options(stage PRIVATE -Wl,--no-undefined)
set_target_properties(stage PROPERTIES PREFIX "" CXX_VISIBILITY_PRESET hidden)
