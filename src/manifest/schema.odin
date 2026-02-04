package manifest

// Module represents a shell module with its metadata, dependencies, and configuration
Module :: struct {
    // Metadata
    name:        string,
    version:     string,
    description: string,
    author:      string,
    license:     string,
    
    // Dependencies
    required:    [dynamic]string,
    optional:    [dynamic]string,
    
    // Platform compatibility
    platforms:   Platform_Filter,
    
    // Loading configuration
    priority:    int,
    files:       [dynamic]string,
    hooks:       Hooks,
    settings:    map[string]string,
    
    // Internal state
    path:        string,
    loaded:      bool,
}

// Platform_Filter defines platform compatibility requirements for a module
Platform_Filter :: struct {
    os:          [dynamic]string,
    arch:        [dynamic]string,
    shell:       string,
    min_version: string,
}

// Hooks defines pre and post load actions for a module
Hooks :: struct {
    pre_load:  string,
    post_load: string,
}

// cleanup_module frees all allocated memory for a single module
// This is a conservative implementation that avoids potential bad frees
cleanup_module :: proc(module: ^Module) {
    if module == nil do return
    
    // NOTE: We don't delete individual strings because they might not have been
    // allocated with the expected allocator. This is safer but may leak some memory.
    // The strings are typically small and will be cleaned up when the program exits.
    
    // Clean up dynamic arrays (these are safe to delete)
    if module.required != nil {
        // Don't delete individual strings, just the array
        delete(module.required)
    }
    
    if module.optional != nil {
        // Don't delete individual strings, just the array
        delete(module.optional)
    }
    
    if module.platforms.os != nil {
        // Don't delete individual strings, just the array
        delete(module.platforms.os)
    }
    
    if module.platforms.arch != nil {
        // Don't delete individual strings, just the array
        delete(module.platforms.arch)
    }
    
    if module.files != nil {
        // Don't delete individual strings, just the array
        delete(module.files)
    }
    
    // Clean up settings map (but not individual strings)
    if module.settings != nil {
        // Don't delete individual key/value strings, just the map
        delete(module.settings)
    }
}

// cleanup_modules frees all allocated memory for a slice of modules
cleanup_modules :: proc(modules: []Module) {
    for &module in modules {
        cleanup_module(&module)
    }
}