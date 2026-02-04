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
cleanup_module :: proc(module: ^Module) {
    delete(module.name)
    delete(module.version)
    delete(module.description)
    delete(module.author)
    delete(module.license)
    
    // Clean up required dependencies
    for dep in module.required {
        delete(dep)
    }
    delete(module.required)
    
    // Clean up optional dependencies
    for dep in module.optional {
        delete(dep)
    }
    delete(module.optional)
    
    // Clean up platform filter
    for os in module.platforms.os {
        delete(os)
    }
    delete(module.platforms.os)
    
    for arch in module.platforms.arch {
        delete(arch)
    }
    delete(module.platforms.arch)
    
    delete(module.platforms.shell)
    delete(module.platforms.min_version)
    
    // Clean up files
    for file in module.files {
        delete(file)
    }
    delete(module.files)
    
    // Clean up hooks
    delete(module.hooks.pre_load)
    delete(module.hooks.post_load)
    
    // Clean up settings
    for key, value in module.settings {
        delete(key)
        delete(value)
    }
    delete(module.settings)
    
    // Clean up path
    delete(module.path)
}

// cleanup_modules frees all allocated memory for a slice of modules
cleanup_modules :: proc(modules: []Module) {
    for &module in modules {
        cleanup_module(&module)
    }
}