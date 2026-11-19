cmake_minimum_required(VERSION 3.19)
project(NativeVesselBuilder1 LANGUAGES CXX)

set(ORBITER_NATIVE_SOURCE_DIR "" CACHE PATH "Matching native Orbiter source checkout")
set(ORBITER_NATIVE_BUILD_DIR "" CACHE PATH "Matching native Orbiter build")
if(NOT EXISTS "${ORBITER_NATIVE_SOURCE_DIR}/Orbitersdk/include/NativeVesselAPI.h" OR
   NOT EXISTS "${ORBITER_NATIVE_BUILD_DIR}/native-sdk/OrbiterNativeBuild.h")
    message(FATAL_ERROR "Set ORBITER_NATIVE_SOURCE_DIR and ORBITER_NATIVE_BUILD_DIR")
endif()

add_library(VesselBuilder1 MODULE
    VesselBuilder1.cpp ConfigurationManager.cpp EventManager.cpp AnimationManager.cpp
    MeshManager.cpp DockManager.cpp AttachmentManager.cpp PropellantManager.cpp ThrusterManager.cpp
    ParticleManager.cpp TouchdownPointsManager.cpp AirfoilsManager.cpp ControlSurfacesManager.cpp
    CameraManager.cpp ExTexManager.cpp VCManager.cpp LightsManager.cpp VariableDragManager.cpp
    LaserManager.cpp MET.cpp SoftDock.cpp Log.cpp GeneralSettingsManager.cpp
)
target_compile_features(VesselBuilder1 PRIVATE cxx_std_17)
target_compile_definitions(VesselBuilder1 PRIVATE ORBITER_NATIVE_BUILD_CONFIGURATION="$<CONFIG>")
target_include_directories(VesselBuilder1 SYSTEM PRIVATE
    "${ORBITER_NATIVE_SOURCE_DIR}/Orbitersdk/include"
    "${ORBITER_NATIVE_SOURCE_DIR}/Src/Orbiter"
    "${ORBITER_NATIVE_BUILD_DIR}/native-sdk"
)
target_link_libraries(VesselBuilder1 PRIVATE
    "${ORBITER_NATIVE_BUILD_DIR}/liborbiter_production_boundary.so"
    "${ORBITER_NATIVE_BUILD_DIR}/liborbiter_production_vessels.so"
)
target_link_options(VesselBuilder1 PRIVATE -Wl,--no-undefined)
set_target_properties(VesselBuilder1 PROPERTIES PREFIX "" CXX_VISIBILITY_PRESET hidden)
