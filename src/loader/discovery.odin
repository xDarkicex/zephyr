package loader

import "../debug"
import "../manifest"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Global cache instance
global_cache: ModuleCache
cache_initialized: bool

// init_cache initializes the global cache
init_cache :: proc() {
	if !cache_initialized {
		global_cache = create_module_cache()
		load_cache_from_disk(&global_cache)
		cache_initialized = true
		debug.debug_info("Cache system initialized")
	}
}

// cleanup_cache cleans up the global cache
cleanup_cache :: proc() {
	if cache_initialized {
		save_cache_to_disk(&global_cache)
		destroy_module_cache(&global_cache)
		cache_initialized = false
		debug.debug_info("Cache system cleaned up")
	}
}

// get_modules_dir returns the default modules directory path
get_modules_dir :: proc() -> string {
	// Default to $HOME/.zsh/modules
	home := os.get_env("HOME")
	if home == "" {
		// Fallback if HOME is not set (shouldn't happen on Unix systems)
		return ".zsh/modules"
	}

	return filepath.join({home, ".zsh", "modules"})
}

// discover scans a base directory for modules containing module.toml files
// Returns a dynamic array of discovered modules
discover :: proc(base_path: string) -> [dynamic]manifest.Module {
	debug.debug_enter("discover")
	defer debug.debug_exit("discover")

	debug.debug_info("Scanning directory: %s", base_path)

	// Initialize cache system
	init_cache()
	// NOTE: Not calling cleanup_cache() here to avoid double-free issues
	// The cache will be cleaned up by the caller when appropriate

	// Use cached discovery for better performance
	modules := discover_with_cache(base_path)

	debug.debug_info("Discovery completed: found %d modules", len(modules))
	return modules
}

// discover_with_cache performs discovery with caching support
discover_with_cache :: proc(base_path: string) -> [dynamic]manifest.Module {
	debug.debug_enter("discover_with_cache")
	defer debug.debug_exit("discover_with_cache")

	// Use directory scanner to find all manifest files
	scanner := create_directory_scanner(base_path, "module.toml", 10)
	defer destroy_directory_scanner(&scanner)

	manifest_files := scan_directories(&scanner)
	debug.debug_info("Found %d manifest files", len(manifest_files))

	// ✅ CRITICAL FIX: Clone all paths immediately to ensure ownership
	// The scanner owns manifest_files strings, which get freed when scanner is destroyed
	// We need our own copies to use as cache keys
	owned_paths := make([dynamic]string, 0, len(manifest_files))
	defer {
		for path in owned_paths do delete(path)
		delete(owned_paths)
	}

	for manifest_file in manifest_files {
		manifest_path := strings.clone(manifest_file) // Own the path
		append(&owned_paths, manifest_path)
	}

	modules := make([dynamic]manifest.Module, 0, len(owned_paths))

	cache_hits := 0
	cache_misses := 0

	// Process each manifest file with caching
	for manifest_path in owned_paths {
		// Try to get from cache first
		if cached_module, cached := get_cached_module(&global_cache, manifest_path); cached {
			append(&modules, cached_module)
			cache_hits += 1
			debug.debug_trace("Using cached module: %s", cached_module.name)
		} else {
			// Parse from file
			module, ok := manifest.parse(manifest_path)
			if ok {
				// Set module path
				module_dir := filepath.dir(manifest_path, context.temp_allocator)
				module.path = strings.clone(module_dir)

				// ✅ CRITICAL FIX: Cache a CLONE of the module to ensure separation
				cache_module(&global_cache, manifest_path, module)

				// ✅ CRITICAL FIX: Append a SECOND CLONE to ensure complete ownership separation
				// This prevents shared ownership between cache and returned array
				cloned_module := clone_module(module)
				manifest.cleanup_module(&module) // Free the original temporary module
				
				append(&modules, cloned_module)
				cache_misses += 1
				debug.debug_module_discovered(cloned_module.name, module_dir)
			} else {
				debug.debug_warn("Failed to parse manifest: %s", manifest_path)
			}
		}
	}

	debug.debug_info(
		"Cache performance: %d hits, %d misses (%.1f%% hit rate)",
		cache_hits,
		cache_misses,
		f64(cache_hits) / f64(cache_hits + cache_misses) * 100.0,
	)

	return modules
}
