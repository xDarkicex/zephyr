package manifest

import "core:strings"

// Module represents a shell module with its metadata, dependencies, and configuration.
//
// Ownership:
// - All string fields are owned by the Module and must be heap-allocated
//   (typically via strings.clone()).
// - Dynamic arrays (required/optional/files/platforms.*) own their elements.
// - settings map keys/values are owned and tracked via settings_storage.
//
// Cloning:
// - Use loader.CloneModule() to create a deep, independent copy.
// - Do not shallow copy Modules that will be cleaned up independently.
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
	// Internal: track owned settings strings for cleanup without map iteration
	settings_storage: [dynamic]string,
    
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

// cleanup_module frees all allocated memory for a single module.
// Only owned memory is freed. Safe to call multiple times and with nil input.
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
    
	// Clean up settings map structure (strings tracked separately)
	if module.settings != nil {
		delete(module.settings)
		module.settings = nil
	}

	// Clean up tracked settings strings (if any)
	if module.settings_storage != nil {
		for setting in module.settings_storage {
			if setting != "" {
				delete(setting)
			}
		}
		delete(module.settings_storage)
		module.settings_storage = nil
	}
}

// init_settings_storage ensures settings map and storage are initialized
init_settings_storage :: proc(module: ^Module) {
	if module == nil do return
	if module.settings == nil {
		module.settings = make(map[string]string)
	}
	if module.settings_storage == nil {
		module.settings_storage = make([dynamic]string)
	}
}

// add_setting inserts a settings key/value and tracks ownership for cleanup
AddSetting :: proc(module: ^Module, key: string, value: string) {
	if module == nil do return
	init_settings_storage(module)

	owned_key := strings.clone(key)
	owned_value := strings.clone(value)
	module.settings[owned_key] = owned_value

	append(&module.settings_storage, owned_key)
	append(&module.settings_storage, owned_value)
}

// cleanup_modules frees all owned memory for a slice of modules.
// Idempotent when called multiple times on the same module values.
cleanup_modules :: proc(modules: []Module) {
    for &module in modules {
        cleanup_module(&module)
    }
}
