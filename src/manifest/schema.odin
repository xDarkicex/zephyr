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
// CRITICAL CONTRACT: ALL string fields in Module must be heap-allocated
// (created with strings.clone()) and owned by the Module.
// NEVER use string literals directly in Module structs.
cleanup_module :: proc(module: ^Module) {
    if module == nil do return
    
    // Only delete if non-empty (defense against string literals)
    if module.name != "" {
        delete(module.name)
        module.name = ""
    }
    if module.version != "" {
        delete(module.version)
        module.version = ""
    }
    if module.description != "" {
        delete(module.description)
        module.description = ""
    }
    if module.author != "" {
        delete(module.author)
        module.author = ""
    }
    if module.license != "" {
        delete(module.license)
        module.license = ""
    }
    if module.path != "" {
        delete(module.path)
        module.path = ""
    }
    
    // Clean up dynamic arrays and their string contents
    if module.required != nil {
        for dep in module.required {
            if dep != "" {
                delete(dep)
            }
        }
        delete(module.required)
        module.required = nil
    }
    
    if module.optional != nil {
        for dep in module.optional {
            if dep != "" {
                delete(dep)
            }
        }
        delete(module.optional)
        module.optional = nil
    }
    
    if module.platforms.os != nil {
        for os_name in module.platforms.os {
            if os_name != "" {
                delete(os_name)
            }
        }
        delete(module.platforms.os)
        module.platforms.os = nil
    }
    
    if module.platforms.arch != nil {
        for arch_name in module.platforms.arch {
            if arch_name != "" {
                delete(arch_name)
            }
        }
        delete(module.platforms.arch)
        module.platforms.arch = nil
    }
    
    if module.platforms.shell != "" {
        delete(module.platforms.shell)
        module.platforms.shell = ""
    }
    if module.platforms.min_version != "" {
        delete(module.platforms.min_version)
        module.platforms.min_version = ""
    }
    
    if module.files != nil {
        for file in module.files {
            if file != "" {
                delete(file)
            }
        }
        delete(module.files)
        module.files = nil
    }
    
    // Clean up hooks
    if module.hooks.pre_load != "" {
        delete(module.hooks.pre_load)
        module.hooks.pre_load = ""
    }
    if module.hooks.post_load != "" {
        delete(module.hooks.post_load)
        module.hooks.post_load = ""
    }
    
    // Clean up settings map and its strings
    if module.settings != nil {
        // ✅ CORRECT: Clean up map values before deleting the map
        for key, value in module.settings {
            if key != "" {
                delete(key)
            }
            if value != "" {
                delete(value)
            }
        }
        delete(module.settings)
        module.settings = nil
    }
}

// cleanup_modules frees all allocated memory for a slice of modules
cleanup_modules :: proc(modules: []Module) {
    for &module in modules {
        cleanup_module(&module)
    }
}