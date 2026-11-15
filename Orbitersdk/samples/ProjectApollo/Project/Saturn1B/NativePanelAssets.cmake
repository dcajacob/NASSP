set(_saturn_rc "${NASSP_SOURCE_ROOT}/src_csm/Resources.rc")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_saturn_rc}")
file(STRINGS "${_saturn_rc}" _saturn_rc_bitmaps
    REGEX "^[ \t]*IDB_[A-Za-z0-9_]+[ \t]+BITMAP[ \t]+")

# Resolve the original resource filenames on a case-sensitive filesystem.
file(GLOB _saturn_original_bitmaps CONFIGURE_DEPENDS "${NASSP_SOURCE_ROOT}/Bitmaps/*")
foreach(_original IN LISTS _saturn_original_bitmaps)
    get_filename_component(_name "${_original}" NAME)
    string(TOLOWER "${_name}" _key)
    set("_saturn_bitmap_${_key}" "${_original}")
endforeach()

set(_saturn_bitmap_code "")
set(_saturn_bitmap_files "")
foreach(_resource IN LISTS _saturn_rc_bitmaps)
    string(REGEX MATCH "^[ \t]*(IDB_[A-Za-z0-9_]+)[ \t]+BITMAP[ \t]+[\" ]*[^\"]*[/\\\\]([^\"/\\\\]+)\"" _match "${_resource}")
    if(NOT _match)
        message(FATAL_ERROR "Cannot read Saturn panel bitmap resource: ${_resource}")
    endif()
    set(_id "${CMAKE_MATCH_1}")
    string(TOLOWER "${CMAKE_MATCH_2}" _key)
    set(_bitmap "${_saturn_bitmap_${_key}}")
    if(NOT EXISTS "${_bitmap}")
        message(FATAL_ERROR "Missing Saturn panel bitmap source: ${_resource}")
    endif()
    get_filename_component(_name "${_bitmap}" NAME)
    string(APPEND _saturn_bitmap_code "    {${_id}, \"ProjectApollo/CSMPanel/${_name}\"},\n")
    list(APPEND _saturn_bitmap_files "${_bitmap}")
endforeach()
list(REMOVE_DUPLICATES _saturn_bitmap_files)
file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/nassp-csm-bitmaps.inc" CONTENT "${_saturn_bitmap_code}")
install(FILES ${_saturn_bitmap_files} "${NASSP_SOURCE_ROOT}/Bitmaps/Logo.bmp"
    DESTINATION "Textures/ProjectApollo/CSMPanel" COMPONENT SaturnPanelAssets)
set(_saturn_checklist_root "${NASSP_SOURCE_ROOT}/../../../Doc/Project Apollo - NASSP/Checklists")
install(FILES
    "${_saturn_checklist_root}/Apollo 7 Checklists.xls"
    "${_saturn_checklist_root}/CSM Default Checklists.xls"
    DESTINATION "Doc/Project Apollo - NASSP/Checklists" COMPONENT SaturnPanelAssets)
