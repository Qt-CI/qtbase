# Generate deployment tool json

# Locate newest Android sdk build tools revision
function(_qt_internal_android_get_sdk_build_tools_revision out_var)
    if (NOT QT_ANDROID_SDK_BUILD_TOOLS_REVISION)
        file(GLOB android_build_tools
            LIST_DIRECTORIES true
            RELATIVE "${ANDROID_SDK_ROOT}/build-tools"
            "${ANDROID_SDK_ROOT}/build-tools/*")
        if (NOT android_build_tools)
            message(FATAL_ERROR "Could not locate Android SDK build tools under \"${ANDROID_SDK_ROOT}/build-tools\"")
        endif()
        list(SORT android_build_tools)
        list(REVERSE android_build_tools)
        list(GET android_build_tools 0 android_build_tools_latest)
    endif()
    set(${out_var} "${android_build_tools_latest}" PARENT_SCOPE)
endfunction()

# Generate the deployment settings json file for a cmake target.
function(qt6_android_generate_deployment_settings target)
    # Information extracted from mkspecs/features/android/android_deployment_settings.prf
    if (NOT TARGET ${target})
        message(FATAL_ERROR "${target} is not a cmake target")
    endif()

    # When parsing JSON file format backslashes and follow up symbols are regarded as special
    # characters. This puts Windows path format into a trouble.
    # _qt_internal_android_format_deployment_paths converts sensitive paths to the CMake format
    # that is supported by JSON as well. The function should be called as many times as
    # qt6_android_generate_deployment_settings, because users may change properties that contain
    # paths in between the calls.
    _qt_internal_android_format_deployment_paths(${target})

    # Avoid calling the function body twice because of 'file(GENERATE'.
    get_target_property(is_called ${target} _qt_is_android_generate_deployment_settings_called)
    if(is_called)
        return()
    endif()
    set_target_properties(${target} PROPERTIES
        _qt_is_android_generate_deployment_settings_called TRUE
    )

    get_target_property(target_type ${target} TYPE)

    if (NOT "${target_type}" STREQUAL "MODULE_LIBRARY")
        message(SEND_ERROR "QT_ANDROID_GENERATE_DEPLOYMENT_SETTINGS only works on Module targets")
        return()
    endif()

    get_target_property(target_source_dir ${target} SOURCE_DIR)
    get_target_property(target_binary_dir ${target} BINARY_DIR)
    get_target_property(target_output_name ${target} OUTPUT_NAME)
    if (NOT target_output_name)
        set(target_output_name ${target})
    endif()
    set(deploy_file "${target_binary_dir}/android-${target_output_name}-deployment-settings.json")

    set(file_contents "{\n")
    # content begin
    string(APPEND file_contents
        "   \"description\": \"This file is generated by cmake to be read by androiddeployqt and should not be modified by hand.\",\n")

    # Host Qt Android install path
    if (NOT QT_BUILDING_QT OR QT_STANDALONE_TEST_PATH)
        set(qt_path "${QT6_INSTALL_PREFIX}")
        set(android_plugin_dir_path "${qt_path}/${QT6_INSTALL_PLUGINS}/platforms")
        set(glob_expression "${android_plugin_dir_path}/*qtforandroid*${CMAKE_ANDROID_ARCH_ABI}.so")
        file(GLOB plugin_dir_files LIST_DIRECTORIES FALSE "${glob_expression}")
        if (NOT plugin_dir_files)
            message(SEND_ERROR
                "Detected Qt installation does not contain qtforandroid_${CMAKE_ANDROID_ARCH_ABI}.so in the following dir:\n"
                "${android_plugin_dir_path}\n"
                "This is most likely due to the installation not being a Qt for Android build. "
                "Please recheck your build configuration.")
            return()
        else()
            list(GET plugin_dir_files 0 android_platform_plugin_path)
            message(STATUS "Found android platform plugin at: ${android_platform_plugin_path}")
        endif()
    endif()

    set(abi_records "")
    get_target_property(qt_android_abis ${target} _qt_android_abis)
    if(qt_android_abis)
        foreach(abi IN LISTS qt_android_abis)
            _qt_internal_get_android_abi_path(qt_abi_path ${abi})
            file(TO_CMAKE_PATH "${qt_abi_path}" qt_android_install_dir_native)
            list(APPEND abi_records "\"${abi}\": \"${qt_android_install_dir_native}\"")
        endforeach()
    endif()

    # Required to build unit tests in developer build
    if(QT_BUILD_INTERNALS_RELOCATABLE_INSTALL_PREFIX)
        set(qt_android_install_dir "${QT_BUILD_INTERNALS_RELOCATABLE_INSTALL_PREFIX}")
    else()
        set(qt_android_install_dir "${QT6_INSTALL_PREFIX}")
    endif()
    file(TO_CMAKE_PATH "${qt_android_install_dir}" qt_android_install_dir_native)
    list(APPEND abi_records "\"${CMAKE_ANDROID_ARCH_ABI}\": \"${qt_android_install_dir_native}\"")

    list(JOIN abi_records "," qt_android_install_dir_records)
    set(qt_android_install_dir_records "{${qt_android_install_dir_records}}")

    string(APPEND file_contents
        "   \"qt\": ${qt_android_install_dir_records},\n")

    # Android SDK path
    file(TO_CMAKE_PATH "${ANDROID_SDK_ROOT}" android_sdk_root_native)
    string(APPEND file_contents
        "   \"sdk\": \"${android_sdk_root_native}\",\n")

    # Android SDK Build Tools Revision
    get_target_property(android_sdk_build_tools ${target} QT_ANDROID_SDK_BUILD_TOOLS_REVISION)
    if (NOT android_sdk_build_tools)
        _qt_internal_android_get_sdk_build_tools_revision(android_sdk_build_tools)
    endif()
    string(APPEND file_contents
        "   \"sdkBuildToolsRevision\": \"${android_sdk_build_tools}\",\n")

    # Android NDK
    file(TO_CMAKE_PATH "${CMAKE_ANDROID_NDK}" android_ndk_root_native)
    string(APPEND file_contents
        "   \"ndk\": \"${android_ndk_root_native}\",\n")

    # Setup LLVM toolchain
    string(APPEND file_contents
        "   \"toolchain-prefix\": \"llvm\",\n")
    string(APPEND file_contents
        "   \"tool-prefix\": \"llvm\",\n")
    string(APPEND file_contents
        "   \"useLLVM\": true,\n")

    # NDK Toolchain Version
    string(APPEND file_contents
        "   \"toolchain-version\": \"${CMAKE_ANDROID_NDK_TOOLCHAIN_VERSION}\",\n")

    # NDK Host
    string(APPEND file_contents
        "   \"ndk-host\": \"${ANDROID_NDK_HOST_SYSTEM_NAME}\",\n")

    set(architecture_record_list "")
    foreach(abi IN LISTS qt_android_abis CMAKE_ANDROID_ARCH_ABI)
        if(abi STREQUAL "x86")
            set(arch_value "i686-linux-android")
        elseif(abi STREQUAL "x86_64")
            set(arch_value "x86_64-linux-android")
        elseif(abi STREQUAL "arm64-v8a")
            set(arch_value "aarch64-linux-android")
        elseif(abi)
            set(arch_value "arm-linux-androideabi")
        endif()
        list(APPEND architecture_record_list "\"${abi}\":\"${arch_value}\"")
    endforeach()

    list(JOIN architecture_record_list "," architecture_records)
    # Architecture
    string(APPEND file_contents
        "   \"architectures\": { ${architecture_records} },\n")

    # deployment dependencies
    _qt_internal_add_android_deployment_multi_value_property(file_contents ${target}
         "QT_ANDROID_DEPLOYMENT_DEPENDENCIES" "dependencies")

    # Extra plugins
    _qt_internal_add_android_deployment_multi_value_property(file_contents ${target}
        "QT_ANDROID_EXTRA_PLUGINS" "android-extra-plugins")

    # Extra libs
    _qt_internal_add_android_deployment_multi_value_property(file_contents ${target}
        "QT_ANDROID_EXTRA_LIBS" "android-extra-libs")

    # package source dir
    _qt_internal_add_android_deployment_property(file_contents ${target}
        "_qt_android_native_package_source_dir" "android-package-source-directory")

    # version code
    _qt_internal_add_android_deployment_property(file_contents ${target}
        "QT_ANDROID_VERSION_CODE" "android-version-code")

    # version name
    _qt_internal_add_android_deployment_property(file_contents ${target}
        "QT_ANDROID_VERSION_NAME" "android-version-name")

    # minimum SDK version
    _qt_internal_add_android_deployment_property(file_contents ${target}
        "QT_ANDROID_MIN_SDK_VERSION" "android-min-sdk-version")

    # target SDK version
    _qt_internal_add_android_deployment_property(file_contents ${target}
        "QT_ANDROID_TARGET_SDK_VERSION" "android-target-sdk-version")

    # QML import paths
    _qt_internal_add_android_deployment_multi_value_property(file_contents ${target}
        "_qt_native_qml_import_paths" "qml-import-paths")

    # QML root paths
    file(TO_CMAKE_PATH "${target_source_dir}" native_target_source_dir)
    set_property(TARGET ${target} APPEND PROPERTY
        _qt_android_native_qml_root_paths "${native_target_source_dir}")
    _qt_internal_add_android_deployment_list_property(file_contents ${target}
        "_qt_android_native_qml_root_paths" "qml-root-path")

    # App binary
    string(APPEND file_contents
        "   \"application-binary\": \"${target_output_name}\",\n")

    # App command-line arguments
    if (QT_ANDROID_APPLICATION_ARGUMENTS)
        string(APPEND file_contents
            "   \"android-application-arguments\": \"${QT_ANDROID_APPLICATION_ARGUMENTS}\",\n")
    endif()

    # Override qmlimportscanner binary path
    set(qml_importscanner_binary_path "${QT_HOST_PATH}/${QT6_HOST_INFO_LIBEXECDIR}/qmlimportscanner")
    if (WIN32)
        string(APPEND qml_importscanner_binary_path ".exe")
    endif()
    file(TO_CMAKE_PATH "${qml_importscanner_binary_path}" qml_importscanner_binary_path_native)
    string(APPEND file_contents
        "   \"qml-importscanner-binary\" : \"${qml_importscanner_binary_path_native}\",\n")

    # Override rcc binary path
    set(rcc_binary_path "${QT_HOST_PATH}/${QT6_HOST_INFO_LIBEXECDIR}/rcc")
    if (WIN32)
        string(APPEND rcc_binary_path ".exe")
    endif()
    file(TO_CMAKE_PATH "${rcc_binary_path}" rcc_binary_path_native)
    string(APPEND file_contents
        "   \"rcc-binary\" : \"${rcc_binary_path_native}\",\n")

    # Extra prefix paths
    foreach(prefix IN LISTS CMAKE_FIND_ROOT_PATH)
        if (NOT "${prefix}" STREQUAL "${qt_android_install_dir_native}"
            AND NOT "${prefix}" STREQUAL "${android_ndk_root_native}")
            file(TO_CMAKE_PATH "${prefix}" prefix)
            list(APPEND extra_prefix_list "\"${prefix}\"")
        endif()
    endforeach()
    string (REPLACE ";" "," extra_prefix_list "${extra_prefix_list}")
    string(APPEND file_contents
        "   \"extraPrefixDirs\" : [ ${extra_prefix_list} ],\n")

    # Extra library paths that could be used as a dependency lookup path by androiddeployqt.
    #
    # Unlike 'extraPrefixDirs', the 'extraLibraryDirs' key doesn't expect the 'lib' subfolder
    # when looking for dependencies.
    _qt_internal_add_android_deployment_list_property(file_contents ${target}
        "_qt_android_extra_library_dirs" "extraLibraryDirs")

    if(QT_FEATURE_zstd)
        set(is_zstd_enabled "true")
    else()
        set(is_zstd_enabled "false")
    endif()
    string(APPEND file_contents
        "   \"zstdCompression\": ${is_zstd_enabled},\n")

    # Last item in json file

    # base location of stdlibc++, will be suffixed by androiddeploy qt
    # Sysroot is set by Android toolchain file and is composed of ANDROID_TOOLCHAIN_ROOT.
    set(android_ndk_stdlib_base_path "${CMAKE_SYSROOT}/usr/lib/")
    string(APPEND file_contents
        "   \"stdcpp-path\": \"${android_ndk_stdlib_base_path}\"\n")

    # content end
    string(APPEND file_contents "}\n")

    file(GENERATE OUTPUT ${deploy_file} CONTENT ${file_contents})

    set_target_properties(${target}
        PROPERTIES
            QT_ANDROID_DEPLOYMENT_SETTINGS_FILE ${deploy_file}
    )
endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    function(qt_android_generate_deployment_settings)
        qt6_android_generate_deployment_settings(${ARGV})
    endfunction()
endif()

function(qt6_android_apply_arch_suffix target)
    get_target_property(target_type ${target} TYPE)
    if (target_type STREQUAL "SHARED_LIBRARY" OR target_type STREQUAL "MODULE_LIBRARY")
        set_property(TARGET "${target}" PROPERTY SUFFIX "_${CMAKE_ANDROID_ARCH_ABI}.so")
    elseif (target_type STREQUAL "STATIC_LIBRARY")
        set_property(TARGET "${target}" PROPERTY SUFFIX "_${CMAKE_ANDROID_ARCH_ABI}.a")
    endif()
endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    function(qt_android_apply_arch_suffix)
        qt6_android_apply_arch_suffix(${ARGV})
    endfunction()
endif()

# Add custom target to package the APK
function(qt6_android_add_apk_target target)
    get_target_property(deployment_file ${target} QT_ANDROID_DEPLOYMENT_SETTINGS_FILE)
    if (NOT deployment_file)
        message(FATAL_ERROR "Target ${target} is not a valid android executable target\n")
    endif()

    # Make global apk target depend on the current apk target.
    if(TARGET apk)
        add_dependencies(apk ${target}_make_apk)
        _qt_internal_create_global_apk_all_target_if_needed()
    endif()

    set(deployment_tool "${QT_HOST_PATH}/${QT6_HOST_INFO_BINDIR}/androiddeployqt")
    set(apk_final_dir "$<TARGET_PROPERTY:${target},BINARY_DIR>/android-build")
    set(apk_intermediate_dir "${CMAKE_CURRENT_BINARY_DIR}/android-build")
    set(apk_file_name "${target}.apk")
    set(dep_file_name "${target}.d")
    set(apk_final_file_path "${apk_final_dir}/${apk_file_name}")
    set(apk_intermediate_file_path "${apk_intermediate_dir}/${apk_file_name}")
    set(dep_intermediate_file_path "${apk_intermediate_dir}/${dep_file_name}")

    # Temporary location of the library target file. If the library is built as an external project
    # inside multi-abi build the QT_ANDROID_ABI_TARGET_PATH variable will point to the ABI related
    # folder in the top-level build directory.
    set(copy_target_path "${apk_final_dir}/libs/${CMAKE_ANDROID_ARCH_ABI}")
    if(QT_IS_ANDROID_MULTI_ABI_EXTERNAL_PROJECT AND QT_ANDROID_ABI_TARGET_PATH)
        set(copy_target_path "${QT_ANDROID_ABI_TARGET_PATH}")
    endif()

    # This target is used by Qt Creator's Android support and by the ${target}_make_apk target
    # in case DEPFILEs are not supported.
    # Also the target is used to copy the library that belongs to ${target} when building multi-abi
    # apk to the abi-specific directory.
    add_custom_target(${target}_prepare_apk_dir ALL
        DEPENDS ${target}
        COMMAND ${CMAKE_COMMAND}
            -E copy_if_different $<TARGET_FILE:${target}>
            "${copy_target_path}/$<TARGET_FILE_NAME:${target}>"
        COMMENT "Copying ${target} binary to apk folder"
    )

    set(extra_args "")
    if(QT_INTERNAL_NO_ANDROID_RCC_BUNDLE_CLEANUP)
        list(APPEND extra_args "--no-rcc-bundle-cleanup")
    endif()
    # The DEPFILE argument to add_custom_command is only available with Ninja or CMake>=3.20 and make.
    if (CMAKE_GENERATOR MATCHES "Ninja" OR
        (CMAKE_VERSION VERSION_GREATER_EQUAL 3.20 AND CMAKE_GENERATOR MATCHES "Makefiles"))
        # Add custom command that creates the apk in an intermediate location.
        # We need the intermediate location, because we cannot have target-dependent generator
        # expressions in OUTPUT.
        add_custom_command(OUTPUT "${apk_intermediate_file_path}"
            COMMAND ${CMAKE_COMMAND}
                -E copy "$<TARGET_FILE:${target}>"
                "${apk_intermediate_dir}/libs/${CMAKE_ANDROID_ARCH_ABI}/$<TARGET_FILE_NAME:${target}>"
            COMMAND "${deployment_tool}"
                --input "${deployment_file}"
                --output "${apk_intermediate_dir}"
                --apk "${apk_intermediate_file_path}"
                --depfile "${dep_intermediate_file_path}"
                --builddir "${CMAKE_BINARY_DIR}"
                ${extra_args}
            COMMENT "Creating APK for ${target}"
            DEPENDS "${target}" "${deployment_file}"
            DEPFILE "${dep_intermediate_file_path}")

        # Create a ${target}_make_apk target to copy the apk from the intermediate to its final
        # location.  If the final and intermediate locations are identical, this is a no-op.
        add_custom_target(${target}_make_apk
            COMMAND "${CMAKE_COMMAND}"
                -E copy_if_different "${apk_intermediate_file_path}" "${apk_final_file_path}"
            DEPENDS "${apk_intermediate_file_path}")
    else()
        add_custom_target(${target}_make_apk
            DEPENDS ${target}_prepare_apk_dir
            COMMAND  ${deployment_tool}
                --input ${deployment_file}
                --output ${apk_final_dir}
                --apk ${apk_final_file_path}
                ${extra_args}
            COMMENT "Creating APK for ${target}"
        )
    endif()
    set_property(GLOBAL APPEND PROPERTY _qt_apk_targets ${target})
    _qt_internal_collect_target_apk_dependencies_defer(${target})
endfunction()

function(_qt_internal_create_global_apk_target)
    # Create a top-level "apk" target for convenience, so that users can call 'ninja apk'.
    # It will trigger building all the apk build targets that are added as part of the project.
    # Allow opting out.
    if(NOT QT_NO_GLOBAL_APK_TARGET)
        if(NOT TARGET apk)
            add_custom_target(apk COMMENT "Building all apks")
        endif()
    endif()
endfunction()

# The function collects all known non-imported shared libraries that are created in the build tree.
# It uses the CMake DEFER CALL feature if the CMAKE_VERSION is greater
# than or equal to 3.18.
# Note: Users that use cmake version less that 3.18 need to call qt_finalize_project
# in the end of a project's top-level CMakeLists.txt.
function(_qt_internal_collect_target_apk_dependencies_defer target)
    # User opted-out the functionality
    if(QT_NO_COLLECT_BUILD_TREE_APK_DEPS)
        return()
    endif()

    get_property(is_called GLOBAL PROPERTY _qt_is_collect_target_apk_dependencies_defer_called)
    if(is_called) # Already scheduled
        return()
    endif()
    set_property(GLOBAL PROPERTY _qt_is_collect_target_apk_dependencies_defer_called TRUE)

    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.18")
        cmake_language(EVAL CODE "cmake_language(DEFER DIRECTORY \"${CMAKE_SOURCE_DIR}\"
            CALL _qt_internal_collect_target_apk_dependencies ${target})")
    else()
        # User don't want to see the warning
        if(NOT QT_NO_WARN_BUILD_TREE_APK_DEPS)
            message(WARNING "CMake version you use is less than 3.18. APK dependencies, that are a"
                    " part of the project tree, might not be collected correctly."
                    " Please call qt_finalize_project in the end of a project's top-level"
                    " CMakeLists.txt file to make sure that all the APK dependencies are"
                    " collected correctly."
                    " You can pass -DQT_NO_WARN_BUILD_TREE_APK_DEPS=ON when configuring the project"
                    " to silence the warning.")
        endif()
    endif()
endfunction()

# The function collects shared libraries from the build system tree, that might be dependencies for
# the main apk targets.
function(_qt_internal_collect_target_apk_dependencies target)
    # User opted-out the functionality
    if(QT_NO_COLLECT_BUILD_TREE_APK_DEPS)
        return()
    endif()

    get_property(is_called GLOBAL PROPERTY _qt_is_collect_target_apk_dependencies_called)
    if(is_called)
        return()
    endif()
    set_property(GLOBAL PROPERTY _qt_is_collect_target_apk_dependencies_called TRUE)

    get_property(apk_targets GLOBAL PROPERTY _qt_apk_targets)

    _qt_internal_collect_buildsystem_shared_libraries(libs "${CMAKE_SOURCE_DIR}")

    foreach(lib IN LISTS libs)
        if(NOT lib IN_LIST apk_targets)
            list(APPEND extra_prefix_dirs "$<TARGET_FILE_DIR:${lib}>")
        endif()
    endforeach()

    set_target_properties(${target} PROPERTIES _qt_android_extra_library_dirs "${extra_prefix_dirs}")
endfunction()

# The function recursively goes through the project subfolders and collects targets that supposed to
# be shared libraries of any kind.
function(_qt_internal_collect_buildsystem_shared_libraries out_var subdir)
    set(result "")
    get_directory_property(buildsystem_targets DIRECTORY ${subdir} BUILDSYSTEM_TARGETS)
    foreach(buildsystem_target IN LISTS buildsystem_targets)
        if(buildsystem_target AND TARGET ${buildsystem_target})
            get_target_property(target_type ${buildsystem_target} TYPE)
            if(target_type STREQUAL "SHARED_LIBRARY" OR target_type STREQUAL "MODULE_LIBRARY")
                list(APPEND result ${buildsystem_target})
            endif()
        endif()
    endforeach()

    get_directory_property(subdirs DIRECTORY "${subdir}" SUBDIRECTORIES)
    foreach(dir IN LISTS subdirs)
        _qt_internal_collect_buildsystem_shared_libraries(result_inner "${dir}")
    endforeach()
    list(APPEND result ${result_inner})
    set(${out_var} "${result}" PARENT_SCOPE)
endfunction()

# This function allows deciding whether apks should be built as part of the ALL target at first
# add_executable call point, rather than when the 'apk' target is created as part of the
# find_package(Core) call.
#
# It does so by creating a custom 'apk_all' target as an implementation detail.
#
# This is needed to ensure that the decision is made only when the value of QT_BUILDING_QT is
# available, which is defined in qt_repo_build() -> include(QtSetup), which is included after the
# execution of _qt_internal_create_global_apk_target.
function(_qt_internal_create_global_apk_all_target_if_needed)
    if(TARGET apk AND NOT TARGET apk_all)
        # Some Qt tests helper executables have their apk build process failing.
        # qt_internal_add_executables that are excluded from ALL should also not have apks built
        # for them.
        # Don't build apks by default when doing a Qt build.
        set(skip_add_to_all FALSE)
        if(QT_BUILDING_QT)
            set(skip_add_to_all TRUE)
        endif()

        option(QT_NO_GLOBAL_APK_TARGET_PART_OF_ALL
            "Skip building apks as part of the default 'ALL' target" ${skip_add_to_all})

        set(part_of_all "ALL")
        if(QT_NO_GLOBAL_APK_TARGET_PART_OF_ALL)
            set(part_of_all "")
        endif()

        add_custom_target(apk_all ${part_of_all})
        add_dependencies(apk_all apk)
    endif()
endfunction()

# The function converts the target property to a json record and appends it to the output
# variable.
function(_qt_internal_add_android_deployment_property out_var target property json_key)
    set(property_genex "$<TARGET_PROPERTY:${target},${property}>")
    string(APPEND ${out_var}
        "$<$<BOOL:${property_genex}>:"
            "   \"${json_key}\": \"${property_genex}\"\,\n"
        ">"
    )

    set(${out_var} "${${out_var}}" PARENT_SCOPE)
endfunction()

# The function converts the target list property to a json list record and appends it to the output
# variable.
# The generated JSON object is the normal JSON array, e.g.:
#    "qml-root-path": ["qml/root/path1","qml/root/path2"],
function(_qt_internal_add_android_deployment_list_property out_var target property json_key)
    set(property_genex
        "$<TARGET_PROPERTY:${target},${property}>"
    )
    set(add_quote_genex
        "$<$<BOOL:${property_genex}>:\">"
    )
    string(JOIN "" list_join_genex
        "${add_quote_genex}"
            "$<JOIN:"
                "$<GENEX_EVAL:${property_genex}>,"
                "\",\""
            ">"
        "${add_quote_genex}"
    )
    string(APPEND ${out_var}
        "   \"${json_key}\" : [ ${list_join_genex} ],\n")
    set(${out_var} "${${out_var}}" PARENT_SCOPE)
endfunction()

# The function converts the target list property to a json multi-value string record and appends it
# to the output variable.
# The generated JSON object is a simple string with the list property items separated by commas,
# e.g:
#    "android-extra-plugins": "plugin1,plugin2",
function(_qt_internal_add_android_deployment_multi_value_property out_var target property json_key)
    set(property_genex
        "$<TARGET_PROPERTY:${target},${property}>"
    )
    string(JOIN "" list_join_genex
        "$<JOIN:"
            "$<GENEX_EVAL:${property_genex}>,"
            ","
        ">"
    )
    string(APPEND ${out_var}
        "$<$<BOOL:${property_genex}>:"
            "   \"${json_key}\" : \"${list_join_genex}\",\n"
        ">"
    )

    set(${out_var} "${${out_var}}" PARENT_SCOPE)
endfunction()

# The function converts paths to the CMake format to make them acceptable for JSON.
# It doesn't overwrite public properties, but instead writes formatted values to internal
# properties.
function(_qt_internal_android_format_deployment_paths target)
    _qt_internal_android_format_deployment_path_property(${target}
        QT_QML_IMPORT_PATH _qt_android_native_qml_import_paths)

    _qt_internal_android_format_deployment_path_property(${target}
        QT_QML_ROOT_PATH _qt_android_native_qml_root_paths)

    _qt_internal_android_format_deployment_path_property(${target}
        QT_ANDROID_PACKAGE_SOURCE_DIR _qt_android_native_package_source_dir)
endfunction()

# The function converts the value of target property to JSON compatible path and writes the
# result to out_property. Property might be either single value, semicolon separated list or system
# path spec.
function(_qt_internal_android_format_deployment_path_property target property out_property)
    get_target_property(_paths ${target} ${property})
    if(_paths)
        set(native_paths "")
        foreach(_path IN LISTS _paths)
            file(TO_CMAKE_PATH "${_path}" _path)
            list(APPEND native_paths "${_path}")
        endforeach()
        set_target_properties(${target} PROPERTIES
            ${out_property} "${native_paths}")
    endif()
endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    function(qt_android_add_apk_target)
        qt6_android_add_apk_target(${ARGV})
    endfunction()
endif()

# The function returns the installation path to Qt for Android for the specified ${abi}.
# By default function expects to find a layout as is installed by the Qt online installer:
#   Qt_install_dir/Version/
#   |__  gcc_64
#   |__  android_arm64_v8a
#   |__  android_armv7
#   |__  android_x86
#   |__  android_x86_64
function(_qt_internal_get_android_abi_path out_path abi)
    if(DEFINED QT_PATH_ANDROID_ABI_${abi})
        get_filename_component(${out_path} "${QT_PATH_ANDROID_ABI_${abi}}" ABSOLUTE)
    else()
        # Map the ABI value to the Qt for Android folder.
        if (abi STREQUAL "x86")
            set(abi_directory_suffix "${abi}")
        elseif (abi STREQUAL "x86_64")
            set(abi_directory_suffix "${abi}")
        elseif (abi STREQUAL "arm64-v8a")
            set(abi_directory_suffix "arm64_v8a")
        else()
            set(abi_directory_suffix "armv7")
        endif()

        get_filename_component(${out_path}
            "${_qt_cmake_dir}/../../../android_${abi_directory_suffix}" ABSOLUTE)
    endif()
    set(${out_path} "${${out_path}}" PARENT_SCOPE)
endfunction()

# The function collects list of existing Qt for Android using _qt_internal_get_android_abi_path
# and pre-defined set of known Android ABIs. The result is written to QT_DEFAULT_ANDROID_ABIS
# cache variable.
# Note that QT_DEFAULT_ANDROID_ABIS is not intended to be set outside the function and will be
# rewritten.
function(_qt_internal_collect_default_android_abis)
    set(known_android_abis armeabi-v7a arm64-v8a x86 x86_64)

    set(default_abis)
    foreach(abi IN LISTS known_android_abis)
        _qt_internal_get_android_abi_path(qt_abi_path ${abi})
        # It's expected that Qt for Android contains ABI specific toolchain file.
        if(EXISTS "${qt_abi_path}/lib/cmake/${QT_CMAKE_EXPORT_NAMESPACE}/qt.toolchain.cmake"
            OR CMAKE_ANDROID_ARCH_ABI STREQUAL abi)
            list(APPEND default_abis ${abi})
        endif()
    endforeach()
    set(QT_DEFAULT_ANDROID_ABIS "${default_abis}" CACHE STRING
        "The list of autodetected Qt for Android ABIs" FORCE
    )
    set(QT_ANDROID_ABIS "${CMAKE_ANDROID_ARCH_ABI}" CACHE STRING
        "The list of Qt for Android ABIs used to build the project apk"
    )
    set(QT_ANDROID_BUILD_ALL_ABIS FALSE CACHE BOOL
        "Build project using the list of autodetected Qt for Android ABIs"
    )
endfunction()
