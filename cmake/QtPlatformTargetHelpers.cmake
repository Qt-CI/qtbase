# Defines the public Qt::Platform target, which serves as a dependency for all internal Qt target
# as well as user projects consuming Qt.
function(qt_internal_setup_public_platform_target)
    qt_internal_get_platform_definition_include_dir(
        install_interface_definition_dir
        build_interface_definition_dir
    )

    ## QtPlatform Target:
    add_library(Platform INTERFACE)
    add_library(Qt::Platform ALIAS Platform)
    add_library(${INSTALL_CMAKE_NAMESPACE}::Platform ALIAS Platform)
    target_include_directories(Platform
        INTERFACE
        $<BUILD_INTERFACE:${build_interface_definition_dir}>
        $<BUILD_INTERFACE:${PROJECT_BINARY_DIR}/include>
        $<INSTALL_INTERFACE:${install_interface_definition_dir}>
        $<INSTALL_INTERFACE:${INSTALL_INCLUDEDIR}>
        )
    target_compile_definitions(Platform INTERFACE ${QT_PLATFORM_DEFINITIONS})

    # When building on android we need to link against the logging library
    # in order to satisfy linker dependencies. Both of these libraries are part of
    # the NDK.
    if (ANDROID)
        target_link_libraries(Platform INTERFACE log)
    endif()

    if (QT_FEATURE_stdlib_libcpp)
        target_compile_options(Platform INTERFACE "-stdlib=libc++")
        target_link_options(Platform INTERFACE "-stdlib=libc++")
    endif()

    qt_set_msvc_cplusplus_options(Platform INTERFACE)

    # Propagate minimum C++ 17 via Platform to Qt consumers (apps), after the global features
    # are computed.
    qt_set_language_standards_interface_compile_features(Platform)

    # By default enable utf8 sources for both Qt and Qt consumers. Can be opted out.
    qt_enable_utf8_sources(Platform)

    # By default enable unicode on WIN32 platforms for both Qt and Qt consumers. Can be opted out.
    qt_internal_enable_unicode_defines(Platform)
endfunction()

function(qt_internal_get_platform_definition_include_dir install_interface build_interface)
    # Used by consumers of prefix builds via INSTALL_INTERFACE (relative path).
    set(${install_interface} "${INSTALL_MKSPECSDIR}/${QT_QMAKE_TARGET_MKSPEC}" PARENT_SCOPE)

    # Used by qtbase in prefix builds via BUILD_INTERFACE
    set(build_interface_base_dir
        "${CMAKE_CURRENT_LIST_DIR}/../mkspecs"
    )

    # Used by qtbase and consumers in non-prefix builds via BUILD_INTERFACE
    if(NOT QT_WILL_INSTALL)
        set(build_interface_base_dir
            "${QT_BUILD_DIR}/${INSTALL_MKSPECSDIR}"
        )
    endif()

    get_filename_component(build_interface_dir
        "${build_interface_base_dir}/${QT_QMAKE_TARGET_MKSPEC}"
        ABSOLUTE
    )
    set(${build_interface} "${build_interface_dir}" PARENT_SCOPE)
endfunction()
