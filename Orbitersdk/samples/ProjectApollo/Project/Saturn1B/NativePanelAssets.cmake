function(nassp_native_panel_assets resources directory generated component)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${resources}")
    file(STRINGS "${resources}" _panel_rc_bitmaps
        REGEX "^[ \t]*IDB_[A-Za-z0-9_]+[ \t]+BITMAP[ \t]+")

    # Resolve the original resource filenames on a case-sensitive filesystem.
    file(GLOB _panel_original_bitmaps CONFIGURE_DEPENDS "${NASSP_SOURCE_ROOT}/Bitmaps/*")
    foreach(_original IN LISTS _panel_original_bitmaps)
        get_filename_component(_name "${_original}" NAME)
        string(TOLOWER "${_name}" _key)
        set("_panel_bitmap_${_key}" "${_original}")
    endforeach()

    set(_panel_bitmap_code "")
    set(_panel_bitmap_files "")
    foreach(_resource IN LISTS _panel_rc_bitmaps)
        string(REGEX MATCH "^[ \t]*(IDB_[A-Za-z0-9_]+)[ \t]+BITMAP[ \t]+[\" ]*[^\"]*[/\\\\]([^\"/\\\\]+)\"" _match "${_resource}")
        if(NOT _match)
            message(FATAL_ERROR "Cannot read NASSP panel bitmap resource: ${_resource}")
        endif()
        set(_id "${CMAKE_MATCH_1}")
        string(TOLOWER "${CMAKE_MATCH_2}" _key)
        set(_bitmap "${_panel_bitmap_${_key}}")
        if(NOT EXISTS "${_bitmap}")
            message(FATAL_ERROR "Missing NASSP panel bitmap source: ${_resource}")
        endif()
        get_filename_component(_name "${_bitmap}" NAME)
        string(APPEND _panel_bitmap_code "    {${_id}, \"ProjectApollo/${directory}/${_name}\"},\n")
        list(APPEND _panel_bitmap_files "${_bitmap}")
    endforeach()
    list(REMOVE_DUPLICATES _panel_bitmap_files)
    file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${generated}" CONTENT "${_panel_bitmap_code}")
    install(FILES ${_panel_bitmap_files}
        DESTINATION "Textures/ProjectApollo/${directory}" COMPONENT "${component}")
endfunction()

nassp_native_panel_assets("${NASSP_SOURCE_ROOT}/src_csm/Resources.rc" CSMPanel nassp-csm-bitmaps.inc SaturnPanelAssets)
nassp_native_panel_assets("${NASSP_SOURCE_ROOT}/src_lm/LEMResources.rc" LMPanel nassp-lm-bitmaps.inc LunarPanelAssets)
install(FILES "${NASSP_SOURCE_ROOT}/Bitmaps/Logo.bmp"
    DESTINATION "Textures/ProjectApollo/CSMPanel" COMPONENT SaturnPanelAssets)
set(_saturn_checklist_root "${NASSP_SOURCE_ROOT}/../../../Doc/Project Apollo - NASSP/Checklists")
install(FILES
    "${_saturn_checklist_root}/Apollo 7 Checklists.xls"
    "${_saturn_checklist_root}/CSM Default Checklists.xls"
    DESTINATION "Doc/Project Apollo - NASSP/Checklists" COMPONENT SaturnPanelAssets)
