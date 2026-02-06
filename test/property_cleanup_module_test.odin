package test

import "core:testing"
import "core:strings"

import "../src/manifest"

// **Validates: Requirements 1.1, 1.3, 1.4, 1.5, 7.5**
@(test)
test_property_cleanup_settings_map_safety :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    module := make_test_module("cleanup-map-safety")

    // Add some owned settings and arrays
    manifest.AddSetting(&module, "key1", "value1")
    manifest.AddSetting(&module, "key2", "value2")
    append(&module.required, strings.clone("dep-a"))
    append(&module.optional, strings.clone("opt-a"))
    append(&module.files, strings.clone("file-a.zsh"))

    // First cleanup should free all owned memory without touching map entries directly
    manifest.cleanup_module(&module)

    testing.expect(t, module.settings == nil, "Settings map should be nil after cleanup")
    testing.expect(t, module.required == nil, "Required array should be nil after cleanup")
    testing.expect(t, module.optional == nil, "Optional array should be nil after cleanup")
    testing.expect(t, module.files == nil, "Files array should be nil after cleanup")
    testing.expect(t, module.platforms.os == nil, "Platform OS array should be nil after cleanup")
    testing.expect(t, module.platforms.arch == nil, "Platform arch array should be nil after cleanup")
    testing.expect(t, module.name == "", "Name should be empty after cleanup")
    testing.expect(t, module.version == "", "Version should be empty after cleanup")

    // Second cleanup should be a no-op (idempotent)
    manifest.cleanup_module(&module)
}

// **Validates: Requirements 1.5**
@(test)
test_unit_cleanup_empty_string_fields :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    module := manifest.Module{
        name = strings.clone("empty-fields"),
        version = strings.clone("1.0.0"),
        description = "",
        author = "",
        license = "",
        path = "",
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
            shell = "",
            min_version = "",
        },
        hooks = manifest.Hooks{
            pre_load = "",
            post_load = "",
        },
    }

    // Include empty strings in arrays (should be skipped on cleanup)
    append(&module.required, "")
    append(&module.optional, "")
    append(&module.files, "")
    append(&module.platforms.os, "")
    append(&module.platforms.arch, "")

    manifest.cleanup_module(&module)

    testing.expect(t, module.required == nil, "Required array should be nil after cleanup")
    testing.expect(t, module.optional == nil, "Optional array should be nil after cleanup")
    testing.expect(t, module.files == nil, "Files array should be nil after cleanup")
    testing.expect(t, module.platforms.os == nil, "Platform OS array should be nil after cleanup")
    testing.expect(t, module.platforms.arch == nil, "Platform arch array should be nil after cleanup")
    testing.expect(t, module.description == "", "Description should remain empty after cleanup")
    testing.expect(t, module.author == "", "Author should remain empty after cleanup")
    testing.expect(t, module.license == "", "License should remain empty after cleanup")
    testing.expect(t, module.path == "", "Path should remain empty after cleanup")

    // Idempotent cleanup
    manifest.cleanup_module(&module)
}
