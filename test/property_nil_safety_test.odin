package test

import "core:testing"
import "core:strings"

import "../src/loader"
import "../src/manifest"

// **Validates: Requirements 5.1, 5.2, 5.5**
@(test)
test_property_nil_safety_module_and_cache :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    module := make_test_module("nil-safety")

    manifest.AddSetting(&module, "key", "value")
    append(&module.required, strings.clone("dep-a"))
    append(&module.optional, strings.clone("dep-b"))
    append(&module.files, strings.clone("file-a.zsh"))
    append(&module.platforms.os, strings.clone("linux"))
    append(&module.platforms.arch, strings.clone("amd64"))

    manifest.cleanup_module(&module)

    testing.expect(t, module.settings == nil, "Settings map should be nil after cleanup")
    testing.expect(t, module.required == nil, "Required array should be nil after cleanup")
    testing.expect(t, module.optional == nil, "Optional array should be nil after cleanup")
    testing.expect(t, module.files == nil, "Files array should be nil after cleanup")
    testing.expect(t, module.platforms.os == nil, "Platform OS array should be nil after cleanup")
    testing.expect(t, module.platforms.arch == nil, "Platform arch array should be nil after cleanup")
    testing.expect(t, module.name == "", "Name should be empty after cleanup")
    testing.expect(t, module.version == "", "Version should be empty after cleanup")

    // Idempotent cleanup
    manifest.cleanup_module(&module)

    temp_dir := setup_test_environment("nil_safety_cache")
    defer teardown_test_environment(temp_dir)

    cache := loader.create_module_cache(temp_dir, 4)
    loader.destroy_module_cache(&cache)

    testing.expect(t, cache.modules == nil, "Cache modules map should be nil after destroy")
    testing.expect(t, cache.dependency_cache == nil, "Dependency cache should be nil after destroy")
    testing.expect(t, cache.file_timestamps == nil, "File timestamps map should be nil after destroy")
    testing.expect(t, cache.cache_dir == "", "Cache dir should be empty after destroy")

    // Idempotent cleanup
    loader.destroy_module_cache(&cache)
}
