package loader

import "core:os"
import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "../manifest"

// DiscoveryError represents different types of discovery errors
DiscoveryError :: enum {
    None,
    DirectoryNotFound,
    DirectoryNotAccessible,
    PermissionDenied,
}

// DiscoveryResult contains the result of module discovery
DiscoveryResult :: struct {
    modules: [dynamic]manifest.Module,
    error:   DiscoveryError,
    message: string,
}

// cleanup_discovery_result cleans up allocated memory in DiscoveryResult
cleanup_discovery_result :: proc(result: ^DiscoveryResult) {
    manifest.cleanup_modules(result.modules[:])
    delete(result.modules)
    delete(result.message)
}

// get_modules_dir returns the modules directory path, checking ZSH_MODULES_DIR environment variable first
get_modules_dir :: proc() -> string {
    modules_dir := os.get_env("ZSH_MODULES_DIR")
    if modules_dir != "" {
        return modules_dir
    }
    
    // Default to $HOME/.zsh/modules
    home := os.get_env("HOME")
    if home == "" {
        // Fallback if HOME is not set
        return ".zsh/modules"
    }
    
    return filepath.join({home, ".zsh", "modules"})
}

// discover scans a base directory for modules containing module.toml files
// Returns a dynamic array of discovered modules
discover :: proc(base_path: string) -> [dynamic]manifest.Module {
    result := discover_detailed(base_path)
    return result.modules
}

// discover_detailed provides detailed error information for debugging
discover_detailed :: proc(base_path: string) -> DiscoveryResult {
    result := DiscoveryResult{
        modules = make([dynamic]manifest.Module),
        error = .None,
    }
    
    // Check if base directory exists
    if !os.exists(base_path) {
        result.error = .DirectoryNotFound
        result.message = fmt.tprintf("Base directory not found: %s", base_path)
        return result
    }
    
    // Check if it's actually a directory
    file_info, stat_err := os.stat(base_path)
    if stat_err != os.ERROR_NONE {
        result.error = .DirectoryNotAccessible
        result.message = fmt.tprintf("Cannot access directory: %s", base_path)
        return result
    }
    
    if !file_info.is_dir {
        result.error = .DirectoryNotAccessible
        result.message = fmt.tprintf("Path is not a directory: %s", base_path)
        return result
    }
    
    // Recursively scan for modules
    scan_directory(base_path, &result.modules)
    
    return result
}

// scan_directory recursively scans a directory for module.toml files
scan_directory :: proc(dir_path: string, modules: ^[dynamic]manifest.Module) {
    handle, err := os.open(dir_path)
    if err != os.ERROR_NONE {
        // Silently skip directories we can't access
        return
    }
    defer os.close(handle)
    
    entries, read_err := os.read_dir(handle, -1)
    if read_err != os.ERROR_NONE {
        // Silently skip directories we can't read
        return
    }
    defer os.file_info_slice_delete(entries)
    
    for entry in entries {
        if !entry.is_dir {
            continue
        }
        
        module_dir := filepath.join({dir_path, entry.name})
        manifest_path := filepath.join({module_dir, "module.toml"})
        
        // Check if this directory contains a module.toml file
        if os.exists(manifest_path) {
            module, ok := manifest.parse(manifest_path)
            if ok {
                // Set the module path to the directory containing the manifest
                module.path = strings.clone(module_dir)
                append(modules, module)
            }
            // If parsing failed, we silently skip this module
            // The validate command can be used to check for parsing errors
        }
        
        // Recursively scan subdirectories
        scan_directory(module_dir, modules)
    }
}