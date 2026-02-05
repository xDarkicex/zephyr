package test

import "core:strings"
import "core:fmt"
import "../src/manifest"

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