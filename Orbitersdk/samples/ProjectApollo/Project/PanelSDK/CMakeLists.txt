project(PanelSDK)

set(INCLUDE_DIRS
    ${NASSP_SOURCE_ROOT}/src_sys
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/Internals
    ${ORBITERSDK_DIR}/include
)
set(SOURCES
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/PanelSDK.cpp
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/BUILD.CPP
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/Matrix.cpp
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/Vectors.cpp
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/VSMGMT.CPP
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/Internals/esysparse.cpp
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/Internals/Esystems.cpp
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/Internals/Hsysparse.cpp
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/Internals/Hsystems.cpp
    ${NASSP_SOURCE_ROOT}/src_sys/PanelSDK/Internals/Thermal.cpp
)

link_directories(${ORBITERSDK_DIR}/lib)
link_directories(${ORBITERSDK_DIR}/XRSound)

add_library(${PROJECT_NAME} STATIC ${SOURCES})
target_include_directories(${PROJECT_NAME} PRIVATE ${INCLUDE_DIRS})
target_link_libraries(${PROJECT_NAME} PRIVATE
    Orbiter
    Orbitersdk
    XRSound
)