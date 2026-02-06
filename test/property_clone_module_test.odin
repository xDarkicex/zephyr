package test

import "core:testing"
import "core:strings"

import "../src/manifest"
import "../src/loader"

make_clone_source_module :: proc() -> manifest.Module {
    module := manifest.Module{
        name = strings.clone("clone-source"),
        version = strings.clone("1.0.0"),
        description = strings.clone("Clone source module"),
        author = strings.clone("Test Author"),
        license = strings.clone("MIT"),
        path = strings.clone("/tmp/clone-source"),
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
            shell = strings.clone("zsh"),
            min_version = strings.clone("5.8"),
        },
        hooks = manifest.Hooks{
            pre_load = strings.clone("pre_hook"),
            post_load = strings.clone("post_hook"),
        },
        priority = 100,
        loaded = false,
    }

    append(&module.required, strings.clone("dep-core"))
    append(&module.required, strings.clone("dep-utils"))
    append(&module.optional, strings.clone("opt-extras"))
    append(&module.files, strings.clone("init.zsh"))
    append(&module.files, strings.clone("functions.zsh"))
    append(&module.platforms.os, strings.clone("linux"))
    append(&module.platforms.arch, strings.clone("x86_64"))

    manifest.AddSetting(&module, "key1", "value1")
    manifest.AddSetting(&module, "key2", "value2")

    return module
}

make_empty_string_module :: proc() -> manifest.Module {
    module := manifest.Module{
        name = strings.clone("empty-test"),
        version = strings.clone("0.0.1"),
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
            min_version = strings.clone("5.0"),
        },
        hooks = manifest.Hooks{
            pre_load = "",
            post_load = strings.clone("post_hook"),
        },
        priority = 100,
        loaded = false,
    }

    append(&module.required, "")
    append(&module.required, strings.clone("dep-a"))
    append(&module.required, "")

    append(&module.optional, "")
    append(&module.optional, strings.clone("opt-a"))

    append(&module.files, strings.clone("file-a"))
    append(&module.files, "")

    append(&module.platforms.os, "")
    append(&module.platforms.os, strings.clone("darwin"))

    append(&module.platforms.arch, "")
    append(&module.platforms.arch, strings.clone("arm64"))

    manifest.AddSetting(&module, "keep", "value")
    manifest.AddSetting(&module, "", "drop-key")
    manifest.AddSetting(&module, "drop-value", "")

    return module
}

// **Validates: Requirements 2.1, 2.3, 2.5**
@(test)
test_property_clone_independence :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    module := make_clone_source_module()
    defer manifest.cleanup_module(&module)

    cloned := loader.CloneModule(module)
    defer manifest.cleanup_module(&cloned)

    // Mutate clone to ensure it does not affect the original
    if cloned.name != "" {
        delete(cloned.name)
    }
    cloned.name = strings.clone("mutated-name")

    if len(cloned.required) > 0 {
        if cloned.required[0] != "" {
            delete(cloned.required[0])
        }
        cloned.required[0] = strings.clone("mutated-dep")
    }
    append(&cloned.required, strings.clone("added-dep"))

    if len(cloned.files) > 0 {
        if cloned.files[0] != "" {
            delete(cloned.files[0])
        }
        cloned.files[0] = strings.clone("mutated-file.zsh")
    }

    if len(cloned.platforms.os) > 0 {
        if cloned.platforms.os[0] != "" {
            delete(cloned.platforms.os[0])
        }
        cloned.platforms.os[0] = strings.clone("windows")
    }

    if len(cloned.platforms.arch) > 0 {
        if cloned.platforms.arch[0] != "" {
            delete(cloned.platforms.arch[0])
        }
        cloned.platforms.arch[0] = strings.clone("arm64")
    }

    if cloned.hooks.pre_load != "" {
        delete(cloned.hooks.pre_load)
    }
    cloned.hooks.pre_load = strings.clone("mutated-pre")

    manifest.AddSetting(&cloned, "key1", "mutated-value")
    manifest.AddSetting(&cloned, "new-key", "new-value")

    // Original should remain unchanged
    testing.expect_value(t, module.name, "clone-source")
    testing.expect_value(t, module.required[0], "dep-core")
    testing.expect_value(t, module.files[0], "init.zsh")
    testing.expect_value(t, module.platforms.os[0], "linux")
    testing.expect_value(t, module.platforms.arch[0], "x86_64")
    testing.expect_value(t, module.hooks.pre_load, "pre_hook")
    testing.expect_value(t, module.settings["key1"], "value1")
    testing.expect_value(t, len(module.required), 2)
    testing.expect_value(t, len(module.files), 2)
    testing.expect_value(t, len(module.settings), 2)
}

// **Validates: Requirements 2.2**
@(test)
test_property_clone_empty_string_handling :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    module := make_empty_string_module()
    defer manifest.cleanup_module(&module)

    cloned := loader.CloneModule(module)
    defer manifest.cleanup_module(&cloned)

    // Empty string fields should remain empty
    testing.expect_value(t, cloned.description, "")
    testing.expect_value(t, cloned.author, "")
    testing.expect_value(t, cloned.license, "")
    testing.expect_value(t, cloned.path, "")
    testing.expect_value(t, cloned.platforms.shell, "")
    testing.expect_value(t, cloned.hooks.pre_load, "")

    // Non-empty fields should be preserved
    testing.expect_value(t, cloned.name, "empty-test")
    testing.expect_value(t, cloned.version, "0.0.1")
    testing.expect_value(t, cloned.platforms.min_version, "5.0")
    testing.expect_value(t, cloned.hooks.post_load, "post_hook")

    // Empty strings in arrays should be skipped
    testing.expect_value(t, len(cloned.required), 1)
    testing.expect_value(t, cloned.required[0], "dep-a")

    testing.expect_value(t, len(cloned.optional), 1)
    testing.expect_value(t, cloned.optional[0], "opt-a")

    testing.expect_value(t, len(cloned.files), 1)
    testing.expect_value(t, cloned.files[0], "file-a")

    testing.expect_value(t, len(cloned.platforms.os), 1)
    testing.expect_value(t, cloned.platforms.os[0], "darwin")

    testing.expect_value(t, len(cloned.platforms.arch), 1)
    testing.expect_value(t, cloned.platforms.arch[0], "arm64")

    // Empty key/value entries should be skipped
    testing.expect_value(t, len(cloned.settings), 1)
    testing.expect_value(t, cloned.settings["keep"], "value")
}
