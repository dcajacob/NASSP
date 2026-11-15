cmake_minimum_required(VERSION 3.19)

# Set the project name
project(NASSP VERSION 9.0)

# Set C++ compiler variables
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(NASSP_BUILD_NATIVE_LINUX "Build NASSP components ported to the native Linux Orbiter SDK" OFF)
if(NASSP_BUILD_NATIVE_LINUX)
    set(ORBITER_NATIVE_SOURCE_DIR "" CACHE PATH "Source checkout matching the native Orbiter build")
    set(ORBITER_NATIVE_BUILD_DIR "" CACHE PATH "Configured native Orbiter production engine")
    if(NOT EXISTS "${ORBITER_NATIVE_SOURCE_DIR}/Orbitersdk/include/NativeVesselAPI.h"
        OR NOT EXISTS "${ORBITER_NATIVE_BUILD_DIR}/native-sdk/OrbiterNativeBuild.h")
        message(FATAL_ERROR "Set ORBITER_NATIVE_SOURCE_DIR and ORBITER_NATIVE_BUILD_DIR to the matching native Orbiter source and engine build.")
    endif()

    set(NASSP_SOURCE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")
    add_library(NasspNativeOrbiterSdk INTERFACE)
    target_include_directories(NasspNativeOrbiterSdk SYSTEM INTERFACE
        "${ORBITER_NATIVE_SOURCE_DIR}/Orbitersdk/include"
        "${ORBITER_NATIVE_SOURCE_DIR}/Src/Orbiter"
        "${ORBITER_NATIVE_BUILD_DIR}/native-sdk"
    )
    target_include_directories(NasspNativeOrbiterSdk INTERFACE
        "${NASSP_SOURCE_ROOT}/src_sys"
    )
    target_compile_definitions(NasspNativeOrbiterSdk INTERFACE
        NASSP_NATIVE_LINUX ORBITER_NATIVE_BUILD_CONFIGURATION="$<CONFIG>"
    )
    target_link_libraries(NasspNativeOrbiterSdk INTERFACE
        "${ORBITER_NATIVE_BUILD_DIR}/liborbiter_production_boundary.so"
        "${ORBITER_NATIVE_BUILD_DIR}/liborbiter_production_vessels.so"
    )

    add_subdirectory(Project/PanelSDK)
    add_library(NasspOrbMech STATIC src_rtccmfd/OrbMech.cpp)
    add_library(NasspMission STATIC src_aux/Mission.cpp)
    set_target_properties(NasspOrbMech NasspMission PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_link_libraries(NasspOrbMech PUBLIC NasspNativeOrbiterSdk)
    target_link_libraries(NasspMission PUBLIC NasspNativeOrbiterSdk)
    add_library(NasspVesselSystems STATIC
        src_saturn/sivbsystems.cpp
        src_saturn/s1bsystems.cpp
        src_sys/connector.cpp
        src_sys/DelayTimer.cpp
        src_sys/inertial.cpp
        src_sys/payload.cpp
        src_sys/powersource.cpp
        src_sys/pyro.cpp
    )
    set_target_properties(NasspVesselSystems PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_include_directories(NasspVesselSystems PRIVATE src_launch)
    target_link_libraries(NasspVesselSystems PUBLIC PanelSDK NasspNativeOrbiterSdk)

    add_library(NasspInstrumentUnit STATIC
        src_saturn/dcs.cpp
        src_saturn/eds.cpp
        src_saturn/FCC.cpp
        src_saturn/iu.cpp
        src_saturn/IUAuxiliaryPowerDistributor.cpp
        src_saturn/IUControlDistributor.cpp
        src_saturn/IUControlSignalProcessor.cpp
        src_saturn/LVDA.cpp
        src_saturn/LVDC.cpp
        src_saturn/lvimu.cpp
        src_launch/IUUmbilical.cpp
    )
    set_target_properties(NasspInstrumentUnit PROPERTIES POSITION_INDEPENDENT_CODE ON
        CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN YES)
    target_include_directories(NasspInstrumentUnit PRIVATE src_aux src_launch src_saturn)
    target_link_libraries(NasspInstrumentUnit PUBLIC NasspVesselSystems NasspOrbMech)

    add_library(NasspSIVB MODULE src_saturn/sivb.cpp)
    set_target_properties(NasspSIVB PROPERTIES
        PREFIX "" OUTPUT_NAME SIVB
        CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN YES
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/NativeModules/Vessel/ProjectApollo"
    )
    target_include_directories(NasspSIVB PRIVATE src_aux src_launch src_saturn)
    target_link_libraries(NasspSIVB PRIVATE NasspInstrumentUnit)
    target_link_options(NasspSIVB PRIVATE "-Wl,--no-undefined")

    find_package(Threads REQUIRED)
    add_library(NasspAudio STATIC src_sys/soundlib.cpp src_sys/NasspNativeSound.cpp)
    set_target_properties(NasspAudio PROPERTIES POSITION_INDEPENDENT_CODE ON CXX_VISIBILITY_PRESET hidden)
    target_include_directories(NasspAudio PRIVATE src_aux src_csm)
    target_include_directories(NasspAudio SYSTEM PRIVATE "${ORBITER_NATIVE_SOURCE_DIR}/Sound/XRSound/src")
    target_link_libraries(NasspAudio PUBLIC NasspNativeOrbiterSdk PRIVATE Threads::Threads ${CMAKE_DL_LIBS} m)

    add_library(NasspGuidance STATIC
        src_sys/apolloguidance.cpp
        src_sys/cdu.cpp
        src_sys/dsky.cpp
        src_sys/dskyinterface.cpp
        src_sys/imu.cpp
        src_sys/imumath.cpp
        src_sys/imulog.cpp
        src_sys/yaAGC/agc_engine.c
        src_sys/yaAGC/agc_engine_init.c
        src_sys/yaAGC/agc_utilities.c
        src_sys/yaAGC/Backtrace.c
        src_sys/yaAGC/rfopen.c
    )
    set_target_properties(NasspGuidance PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_include_directories(NasspGuidance PRIVATE src_aux src_csm src_sys/PanelSDK/Internals)
    target_link_libraries(NasspGuidance PUBLIC NasspAudio NasspVesselSystems PRIVATE Threads::Threads)

    add_library(NasspCockpitSupport STATIC
        src_aux/CueCard.cpp
        src_aux/CueCardLocation.cpp
        src_aux/CueCardManager.cpp
        src_sys/Malfunction.cpp
        src_sys/MalfunctionSimulation.cpp
    )
    set_target_properties(NasspCockpitSupport PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_link_libraries(NasspCockpitSupport PUBLIC NasspNativeOrbiterSdk)

    add_library(NasspChecklist STATIC
        src_aux/BasicExcelVC6.cpp
        src_mfd/MFDconnector.cpp
        src_sys/checklistControllerHelpers.cpp
    )
    set_target_properties(NasspChecklist PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_include_directories(NasspChecklist PRIVATE src_aux src_mfd)
    target_link_libraries(NasspChecklist PUBLIC NasspNativeOrbiterSdk PRIVATE NasspAudio NasspVesselSystems)

    add_library(NasspControls STATIC src_aux/vesim.cpp src_aux/NasspJoystick.cpp)
    set_target_properties(NasspControls PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_link_libraries(NasspControls PUBLIC NasspNativeOrbiterSdk)

    find_package(OpenGL REQUIRED)
    if(NOT TARGET OpenGL::GLU)
        message(FATAL_ERROR "The native NASSP FDAI requires the OpenGL Utility Library (GLU).")
    endif()
    add_library(NasspFDAI STATIC src_sys/FDAI.cpp)
    set_target_properties(NasspFDAI PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_link_libraries(NasspFDAI PUBLIC PanelSDK NasspNativeOrbiterSdk PRIVATE OpenGL::GL OpenGL::GLU)

    include(Project/Saturn1B/NativePanelAssets.cmake)
    add_library(NasspPanelAssets STATIC src_csm/NasspCsmBitmap.cpp)
    set_target_properties(NasspPanelAssets PROPERTIES POSITION_INDEPENDENT_CODE ON)
    target_include_directories(NasspPanelAssets PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
    target_link_libraries(NasspPanelAssets PUBLIC NasspNativeOrbiterSdk)

    add_library(NasspSaturn1BObjects OBJECT
        src_aux/animations.cpp
        src_aux/CDK.cpp
        src_aux/OrbiterMath.cpp
        src_csm/CSMcomputer.cpp
        src_csm/CSMMalfunctionSimulation.cpp
        src_csm/csmcautionwarning.cpp
        src_csm/csmconnector.cpp
        src_csm/csmrcs.cpp
        src_csm/csmsensors.cpp
        src_csm/csm_telecom.cpp
        src_csm/dockingprobe.cpp
        src_csm/ecs.cpp
        src_csm/eps.cpp
        src_csm/rhc.cpp
        src_csm/satswitches.cpp
        src_csm/satsystems.cpp
        src_csm/saturn.cpp
        src_csm/saturnmesh.cpp
        src_csm/saturnpanel.cpp
        src_csm/saturnvc.cpp
        src_csm/sce.cpp
        src_csm/scs.cpp
        src_csm/secs.cpp
        src_csm/smjc.cpp
        src_csm/sps.cpp
        src_mfd/ProjectApolloChecklistMFD.cpp
        src_saturn/canard.cpp
        src_saturn/j2engine.cpp
        src_saturn/qball.cpp
        src_saturn/Saturn1b.cpp
        src_saturn/sat1bmesh.cpp
        src_saturn/siisystems.cpp
        src_sys/cautionwarning.cpp
        src_sys/checklistController.cpp
        src_sys/MechanicalAccelerometer.cpp
        src_sys/missiontimer.cpp
        src_sys/ORDEAL.cpp
        src_sys/toggleswitch.cpp
    )
    set_target_properties(NasspSaturn1BObjects PROPERTIES POSITION_INDEPENDENT_CODE ON
        CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN YES)
    target_include_directories(NasspSaturn1BObjects PRIVATE
        src_aux src_csm src_landing src_launch src_lm src_mfd src_moon src_saturn src_sys/PanelSDK/Internals
    )
    target_include_directories(NasspSaturn1BObjects SYSTEM PRIVATE "${ORBITER_NATIVE_BUILD_DIR}/native-lua/sdk/include")
    target_link_libraries(NasspSaturn1BObjects PRIVATE
        NasspNativeOrbiterSdk NasspControls NasspGuidance NasspVesselSystems NasspChecklist NasspCockpitSupport NasspFDAI NasspPanelAssets
    )

    add_library(NasspSaturn1B MODULE)
    set_target_properties(NasspSaturn1B PROPERTIES
        PREFIX "" OUTPUT_NAME Saturn1b
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/NativeModules/Vessel/ProjectApollo"
    )
    target_link_libraries(NasspSaturn1B PRIVATE
        NasspSaturn1BObjects NasspInstrumentUnit NasspMission
        "${ORBITER_NATIVE_BUILD_DIR}/native-lua/liblua.so"
    )
    target_link_options(NasspSaturn1B PRIVATE "-Wl,--no-undefined")

    add_library(NasspMCCVessel MODULE
        src_launch/mcc.cpp
        src_launch/rtcc.cpp
        src_launch/mccvessel.cpp
        src_launch/mccvc.cpp
        src_launch/MCC_Calculations.cpp
        src_launch/MCC_Mission_B.cpp
        src_launch/MCC_Mission_C.cpp
        src_launch/MCC_Mission_C_PRIME.cpp
        src_launch/MCC_Mission_D.cpp
        src_launch/MCC_Mission_F.cpp
        src_launch/MCC_Mission_G.cpp
        src_launch/MCC_Mission_H1.cpp
        src_launch/MCC_Mission_SL.cpp
        src_launch/RTCC_Mission_B.cpp
        src_launch/RTCC_Mission_C.cpp
        src_launch/RTCC_Mission_Calculations.cpp
        src_launch/RTCC_Mission_C_PRIME.cpp
        src_launch/RTCC_Mission_D.cpp
        src_launch/RTCC_Mission_F.cpp
        src_launch/RTCC_Mission_G.cpp
        src_launch/RTCC_Mission_H1.cpp
        src_launch/RTCC_Mission_SL.cpp
        src_rtccmfd/AnalyticEphemerisGenerator.cpp
        src_rtccmfd/ApolloGeneralizedOpticsProgram.cpp
        src_rtccmfd/AscentRendezvousMonitor.cpp
        src_rtccmfd/CoastNumericalIntegrator.cpp
        src_rtccmfd/CSMLMGuidanceSim.cpp
        src_rtccmfd/EnckeIntegrator.cpp
        src_rtccmfd/EntryCalculations.cpp
        src_rtccmfd/GeneralizedIterator.cpp
        src_rtccmfd/GeneralPurposeManeuver.cpp
        src_rtccmfd/LDPP.cpp
        src_rtccmfd/LMGuidanceSim.cpp
        src_rtccmfd/LOITargeting.cpp
        src_rtccmfd/LunarTargetingProgram.cpp
        src_rtccmfd/LWP.cpp
        src_rtccmfd/ReentryNumericalIntegrator.cpp
        src_rtccmfd/RTCCDisplayFormatting.cpp
        src_rtccmfd/RTCC_EMSMISS.cpp
        src_rtccmfd/rtcc_intermediate_library_programs.cpp
        src_rtccmfd/rtcc_library_programs.cpp
        src_rtccmfd/RTCCModule.cpp
        src_rtccmfd/TLIGuidanceSim.cpp
        src_rtccmfd/TLIProcessor.cpp
        src_rtccmfd/TLMCC.cpp
        src_rtccmfd/TLTrajectoryComputers.cpp
        src_rtccmfd/TwoImpulseProcessor.cpp
    )
    set_target_properties(NasspMCCVessel PROPERTIES
        PREFIX "" OUTPUT_NAME MCC
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/NativeModules/Vessel/ProjectApollo"
    )
    target_include_directories(NasspMCCVessel PRIVATE
        src_aux src_csm src_landing src_launch src_lm src_mfd src_moon
        src_rtccmfd src_saturn src_sys/PanelSDK/Internals
    )
    target_link_libraries(NasspMCCVessel PRIVATE
        NasspNativeOrbiterSdk NasspMission NasspOrbMech NasspVesselSystems Threads::Threads
    )
    target_link_options(NasspMCCVessel PRIVATE "-Wl,--no-undefined")

    add_library(NasspSM MODULE src_csm/sm.cpp src_csm/smjc.cpp)
    set_target_properties(NasspSM PROPERTIES
        PREFIX "" OUTPUT_NAME sM
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/NativeModules/Vessel/ProjectApollo"
    )
    target_include_directories(NasspSM PRIVATE src_aux)
    target_link_libraries(NasspSM PRIVATE NasspVesselSystems NasspAudio)
    target_link_options(NasspSM PRIVATE "-Wl,--no-undefined")

    add_library(NasspCMChute MODULE src_landing/CMChute.cpp)
    set_target_properties(NasspCMChute PROPERTIES
        PREFIX "" OUTPUT_NAME CMChute
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/NativeModules/Vessel/ProjectApollo"
    )
    target_include_directories(NasspCMChute PRIVATE src_aux)
    target_link_libraries(NasspCMChute PRIVATE NasspNativeOrbiterSdk)
    target_link_options(NasspCMChute PRIVATE "-Wl,--no-undefined")

    add_library(NasspS1B MODULE src_saturn/s1b.cpp)
    add_library(NasspVAB MODULE src_launch/VAB.cpp src_launch/VABAnimations.cpp)
    add_library(NasspLC34 MODULE
        src_launch/LC34.cpp
        src_launch/IU_ESE.cpp
        src_launch/IUUmbilical.cpp
        src_launch/IUUmbilicalInterface.cpp
        src_launch/RCA110A.cpp
        src_launch/SCMUmbilical.cpp
        src_launch/SI_ESE.cpp
        src_launch/SIB_ESE.cpp
        src_launch/TailUmbilical.cpp
    )
    set_target_properties(NasspS1B PROPERTIES OUTPUT_NAME s1b)
    set_target_properties(NasspVAB PROPERTIES OUTPUT_NAME VAB)
    set_target_properties(NasspLC34 PROPERTIES OUTPUT_NAME LC34)
    set_target_properties(NasspS1B NasspVAB NasspLC34 PROPERTIES
        PREFIX ""
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/NativeModules/Vessel/ProjectApollo"
    )
    foreach(target IN ITEMS NasspS1B NasspVAB NasspLC34)
        target_include_directories(${target} PRIVATE src_aux src_csm src_launch src_mfd src_saturn)
        target_link_libraries(${target} PRIVATE NasspVesselSystems NasspAudio)
        target_link_options(${target} PRIVATE "-Wl,--no-undefined")
    endforeach()
    target_link_libraries(NasspLC34 PRIVATE NasspInstrumentUnit)

    add_library(NasspFloatBag MODULE src_landing/FloatBag.cpp)
    add_library(NasspLES MODULE src_saturn/LES.cpp)
    set_target_properties(NasspFloatBag PROPERTIES OUTPUT_NAME FloatBag)
    set_target_properties(NasspLES PROPERTIES OUTPUT_NAME LES)
    set_target_properties(NasspFloatBag NasspLES PROPERTIES
        PREFIX ""
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/NativeModules/Vessel/ProjectApollo"
    )
    foreach(target IN ITEMS NasspFloatBag NasspLES)
        target_include_directories(${target} PRIVATE src_aux)
        target_link_libraries(${target} PRIVATE NasspNativeOrbiterSdk)
        target_link_options(${target} PRIVATE "-Wl,--no-undefined")
    endforeach()
    return()
endif()

if(CMAKE_SIZEOF_VOID_P EQUAL 8) # 64-bit build?
    set(BUILD64 1)
    set(ARCH "x64")
    set(PLATFORM_STRING "x64")
else()
    set(BUILD64 0)
    set(ARCH "x86")
    set(PLATFORM_STRING "Win32")
endif()

if (NOT ${CMAKE_GENERATOR} STREQUAL "Ninja")
    add_compile_options(/MP)
endif()

#Add /permissive if using C++20 or higher
#add_compile_options(/permissive)

# Group projects in VS
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

# Set NASSP-related variables
set(NASSP_SOURCE_ROOT ${CMAKE_SOURCE_DIR})
set(NASSP_REPO_ROOT ${NASSP_SOURCE_ROOT}/../../../)

# Check if the user has specified a non-default Orbiter installation location.
# If not, use the default and alert the user.
set(ORBITER_INSTALL_DIR ${NASSP_REPO_ROOT} CACHE STRING "Location of OpenOrbiter installation directory")
set(ORBITERSDK_DIR ${ORBITER_INSTALL_DIR}/Orbitersdk)

# Allow having a separate installation directory than the Orbiter installation folder.
# This is generally meant for automated build systems or for folks who want to produce 
# an installation package of just NASSP's data and modules without
# including Orbiter data or any NASSP git data or source files.
set(FINAL_INSTALL_DIR ${ORBITER_INSTALL_DIR} CACHE STRING "Location for final build/file copy output, defaults to your chosen Orbiter install directory")

if(EXISTS ${ORBITER_INSTALL_DIR}/lua.dll)
    set(OPENORBITER ON)
    message("[NASSP] Configured for OpenOrbiter build.")
else()
    set(OPENORBITER OFF)
    message("[NASSP] Configured for Orbiter Beta build.")
endif()

# Microsoft Visual C compiler specific options
if(MSVC)
    # Flag pointer truncation as an error because if it happens that's bad news!
    add_compile_options("/we4311")
    # We need to force the linker to compile us against the statically-linked
    # C runtime when building for Orbiter Beta due to XRSound.
    if(NOT OPENORBITER)
        set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        #add_compile_options("/MT")
    endif()
    add_link_options("/NODEFAULTLIB:LIBCMTD")
endif()

# Set project libraries to output their DLL files and debug info to
# the final installation dir's "Modules/ProjectApollo" directory,
# unless a sub-project's CMakeLists.txt file overrides this locally,
# such as MFDs, which need to go in "Modules/Plugins" or PanelSDK,
# which can stay in the default directory since it's statically linked.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${FINAL_INSTALL_DIR}/Modules/ProjectApollo)
# Workaround for buildbot appending build config name to output path.
# If we start building with another config besides "RelWithDebInfo", this needs
# to be changed in this file and any projects which output to a different directory,
# such as MFDs or ProjectApolloConfigurator.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO ${FINAL_INSTALL_DIR}/Modules/ProjectApollo)

# Sub-projects are what actually build all our vessels, MFDs, etc.
add_subdirectory(Project/PanelSDK)
add_subdirectory(Project/ApolloRTCCMFD)
add_subdirectory(Project/ASTP)
add_subdirectory(Project/CMChute)
add_subdirectory(Project/Crawler)
add_subdirectory(Project/EVA)
add_subdirectory(Project/Flag)
add_subdirectory(Project/FloatBag)
add_subdirectory(Project/Floodlight)
add_subdirectory(Project/LC34)
add_subdirectory(Project/LC37)
add_subdirectory(Project/LCC)
add_subdirectory(Project/LEM)
add_subdirectory(Project/LES)
add_subdirectory(Project/LEVA)
add_subdirectory(Project/LRV)
add_subdirectory(Project/MCC)
add_subdirectory(Project/ML)
add_subdirectory(Project/MSS)
add_subdirectory(Project/ProjectApolloConfigurator)
add_subdirectory(Project/ProjectApolloMFD)
add_subdirectory(Project/Saturn1B)
add_subdirectory(Project/Saturn5)
add_subdirectory(Project/s1b)
add_subdirectory(Project/s1c)
add_subdirectory(Project/Sat1bAbort1)
add_subdirectory(Project/Sat1bAbort2)
add_subdirectory(Project/Sat5Abort1)
add_subdirectory(Project/Sat5Abort2)
add_subdirectory(Project/Sat5Abort3)
add_subdirectory(Project/Sat5LMDSC)
add_subdirectory(Project/sii)
add_subdirectory(Project/SIVB)
add_subdirectory(Project/Skylab)
add_subdirectory(Project/sm)
add_subdirectory(Project/VAB)


# Copy all relevant documents/scenarios/sounds/configs from this
# repository into the configured final destination directory.
# This will only happen if the NASSP repo is NOT located inside
# the Orbiter installation directory. If we are located
# inside an Orbiter installation, we can't easily differentiate
# between our own files and those included with Orbiter.
if(${NASSP_REPO_ROOT} STREQUAL ${ORBITER_INSTALL_DIR})
    message("[NASSP] Refusing to copy config files, NASSP is cloned directly into an Orbiter installation.")
elseif(${NASSP_REPO_ROOT} STREQUAL ${FINAL_INSTALL_DIR})
    message("[NASSP] Unnecessary to copy config files, final output directory is the NASSP repo location.")
else()
    message("[NASSP] Copying config/data files to final destination directory is possible with \"Install\".")
    message("[NASSP] Final destination directory: ${FINAL_INSTALL_DIR}")

    # Create the list of input directories to be copied to the install location
    set(NASSP_INSTALL_DIR_LIST
        "Config"
        "Doc"
        "Html"
        "Meshes"
        "Missions"
        "Scenarios"
        "Script"
        "Sound"
        "Textures"
        "XRSound"
    )
    
    file(TO_CMAKE_PATH ${FINAL_INSTALL_DIR} destination_fixed)
    foreach(dir ${NASSP_INSTALL_DIR_LIST})
        install(DIRECTORY ${NASSP_REPO_ROOT}/${dir} DESTINATION ${destination_fixed})
    endforeach()
endif()
