package test

import "core:strings"
import "core:fmt"
import "core:os"
import "../src/manifest"
import "../src/loader"

// make_test_module creates a properly allocated test module
// ALL strings are cloned to ensure proper ownership
make_test_module :: proc(
    name: string,
    version: string = "1.0.0",
    description: string = "Test module",
    allocator := context.allocator,
) -> manifest.Module {
    return manifest.Module{
        name = strings.clone(name, allocator),
        version = strings.clone(version, allocator),
        description = strings.clone(description, allocator),
        author = strings.clone("Test Author", allocator),
        license = strings.clone("MIT", allocator),
        path = strings.clone("/test/path", allocator),
        required = make([dynamic]string, allocator),
        optional = make([dynamic]string, allocator),
        files = make([dynamic]string, allocator),
        settings = make(map[string]string, allocator),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string, allocator),
            arch = make([dynamic]string, allocator),
            shell = strings.clone("zsh", allocator),
            min_version = strings.clone("5.0", allocator),
        },
        hooks = manifest.Hooks{
            pre_load = strings.clone("", allocator),
            post_load = strings.clone("", allocator),
        },
        priority = 100,
        loaded = false,
    }
}

// make_test_module_with_deps creates a test module with dependencies
make_test_module_with_deps :: proc(
    name: string,
    required_deps: []string,
    optional_deps: []string = nil,
    allocator := context.allocator,
) -> manifest.Module {
    module := make_test_module(name, allocator = allocator)
    
    // Add required dependencies
    for dep in required_deps {
        append(&module.required, strings.clone(dep, allocator))
    }
    
    // Add optional dependencies
    if optional_deps != nil {
        for dep in optional_deps {
            append(&module.optional, strings.clone(dep, allocator))
        }
    }
    
    return module
}

// make_test_modules creates multiple test modules with proper naming
make_test_modules :: proc(count: int, prefix: string = "test_module", allocator := context.allocator) -> [dynamic]manifest.Module {
    modules := make([dynamic]manifest.Module, 0, count, allocator)
    
    for i in 0..<count {
        name := strings.concatenate({prefix, "_", fmt.tprintf("%02d", i)}, allocator)
        defer delete(name, allocator)
        
        module := make_test_module(name, allocator = allocator)
        append(&modules, module)
    }
    
    return modules
}

// create_test_shell_file creates a file with the given content
// Returns true if successful, false otherwise
create_test_shell_file :: proc(path: string, content: string) -> bool {
    // Write the content to the file
    ok := os.write_entire_file(path, transmute([]byte)content)
    return ok
}

// cleanup_modules_and_cache frees module allocations and resets the loader cache
cleanup_modules_and_cache :: proc(modules: []manifest.Module) {
    manifest.cleanup_modules(modules)
    loader.reset_global_cache()
}

cleanup_resolved_and_cache :: proc(resolved: [dynamic]manifest.Module) {
    if resolved != nil {
        manifest.cleanup_modules(resolved[:])
        delete(resolved)
    }
    loader.reset_global_cache()
}

cleanup_resolved :: proc(resolved: [dynamic]manifest.Module) {
    if resolved != nil {
        manifest.cleanup_modules(resolved[:])
        delete(resolved)
    }
}

cleanup_error_message :: proc(err: string) {
    if err != "" {
        delete(err)
    }
}

require_long_tests :: proc() -> bool {
    value := os.get_env("ZEPHYR_RUN_LONG_TESTS")
    if value == "" {
        delete(value)
        return false
    }
    
    lower := strings.to_lower(value)
    defer delete(lower)
    delete(value)
    
    return lower != "0" && lower != "false" && lower != "no" && lower != "off"
}
