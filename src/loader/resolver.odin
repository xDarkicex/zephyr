package loader

import "../debug"
import "../manifest"
import "core:fmt"
import "core:slice"
import "core:strings"

// ResolutionError represents different types of dependency resolution errors
ResolutionError :: enum {
	None,
	MissingDependency,
	CircularDependency,
	InvalidModule,
}

// ResolutionResult contains the result of dependency resolution
ResolutionResult :: struct {
	modules: [dynamic]manifest.Module,
	error:   ResolutionError,
	message: string,
}

// cleanup_resolution_result cleans up allocated memory in ResolutionResult
cleanup_resolution_result :: proc(result: ^ResolutionResult) {
	if result == nil do return

	if result.modules != nil {
		manifest.cleanup_modules(result.modules[:])
		delete(result.modules)
		result.modules = nil
	}

	if result.message != "" {
		delete(result.message)
		result.message = ""
	}
}

cleanup_string_array :: proc(values: [dynamic]string) {
	if values == nil do return

	for &value in values {
		if value != "" {
			delete(value)
			value = ""
		}
	}
	delete(values)
}

// resolve_filtered performs dependency resolution on a filtered set of modules
resolve_filtered :: proc(
	modules: [dynamic]manifest.Module,
	indices: [dynamic]int,
) -> (
	[dynamic]manifest.Module,
	string,
) {
	debug.debug_enter("resolve_filtered")
	defer debug.debug_exit("resolve_filtered")

	debug.debug_info("Resolving dependencies for %d filtered modules", len(indices))

	if len(indices) == 0 {
		debug.debug_warn("No modules to resolve")
		return make([dynamic]manifest.Module), ""
	}

	// ✅ CRITICAL FIX: Use shallow copies (references only)
	// resolve() and resolve_detailed() will create deep clones when needed
	// We only need to filter which modules to process
	filtered_modules := make([dynamic]manifest.Module)
	defer delete(filtered_modules) // Only delete the array container, not the modules

	for idx in indices {
		// Shallow copy - just reference the module
		append(&filtered_modules, modules[idx])
		debug.debug_trace("Including module: %s", modules[idx].name)
	}

	// Use the existing resolve function
	return resolve(filtered_modules)
}
// Returns modules in dependency order with priority sorting within constraints
resolve :: proc(modules: [dynamic]manifest.Module) -> ([dynamic]manifest.Module, string) {
	debug.debug_enter("resolve")
	defer debug.debug_exit("resolve")

	if cache_guard() {
		debug.debug_info("Resolving dependencies for %d modules", len(modules))

		// Initialize cache if not already done
		if !cache_initialized {
			init_cache()
		}

		// Try to get cached result first
		if cached_order, cached := get_cached_dependency_result(&global_cache, modules); cached {
			debug.debug_info("Using cached dependency resolution")

			// Convert cached names back to modules in correct order
			result := make([dynamic]manifest.Module, 0, len(cached_order))

			for name in cached_order {
				// Find module with this name
				for module in modules {
					if module.name == name {
						// Clone the module to avoid double-free issues
						cloned_module := CloneModule(module)
						append(&result, cloned_module)
						break
					}
				}
			}

			cleanup_string_array(cached_order)

			if len(result) == len(modules) {
				debug.debug_info("Cached resolution successful: %d modules in order", len(result))
				return result, ""
			} else {
				// Cache was invalid, fall through to normal resolution
				manifest.cleanup_modules(result[:])
				delete(result)
				debug.debug_warn("Cached resolution was invalid, performing fresh resolution")
			}
		}

		// Perform fresh resolution
		resolved_modules: [dynamic]manifest.Module
		err_msg: string

		// Use detailed resolution (optimized version can be added later)
		result := resolve_detailed(modules)
		if result.error != .None {
			debug.debug_error("Resolution failed: %s", result.message)
			return nil, result.message
		}
		resolved_modules = result.modules

		if err_msg == "" && len(resolved_modules) > 0 {
			// Cache the successful result
			cache_dependency_result(&global_cache, modules, resolved_modules)
			debug.debug_info(
				"Resolution successful and cached: %d modules in order",
				len(resolved_modules),
			)
		}

		return resolved_modules, err_msg
	}

	return nil, "cache lock failed"
}

// resolve_detailed provides detailed error information for debugging
resolve_detailed :: proc(modules: [dynamic]manifest.Module) -> ResolutionResult {
	result := ResolutionResult {
		modules = make([dynamic]manifest.Module),
		error   = .None,
	}

	if len(modules) == 0 {
		return result
	}

	// Step 5.1: Build module registry (name -> index mapping)
	registry := make(map[string]int)
	defer delete(registry)

	for module, idx in modules {
		if len(module.name) == 0 {
			result.error = .InvalidModule
			result.message = strings.clone(fmt.tprintf("Module at index %d has empty name", idx))
			return result
		}

		// Check for duplicate module names
		if existing_idx, exists := registry[module.name]; exists {
			result.error = .InvalidModule
			result.message = strings.clone(fmt.tprintf(
				"Duplicate module name '%s' found at indices %d and %d",
				module.name,
				existing_idx,
				idx,
			))
			return result
		}

		registry[module.name] = idx
	}

	// Step 5.2: Calculate in-degrees for topological sort
	in_degree := make(map[string]int)
	defer delete(in_degree)

	// Initialize all modules with in-degree 0
	for module in modules {
		in_degree[module.name] = 0
	}

	// Calculate in-degrees by counting incoming dependencies
	// Step 5.5: Report missing required dependencies (integrated here)
	for module in modules {
		for dep in module.required {
			if dep_idx, exists := registry[dep]; exists {
				// module depends on dep, so there's an edge from dep to module
				// This means module has an incoming edge, so increment its in-degree
				in_degree[module.name] += 1
			} else {
				// Missing dependency detected
				result.error = .MissingDependency
				result.message = strings.clone(fmt.tprintf(
					"Module '%s' requires missing dependency '%s'",
					module.name,
					dep,
				))
				return result
			}
		}
	}

	// Step 5.3: Implement queue-based topological sorting (Kahn's algorithm)
	queue := make([dynamic]int)
	defer delete(queue)

	// Find all modules with in-degree 0 (no dependencies)
	for module, idx in modules {
		if in_degree[module.name] == 0 {
			append(&queue, idx)
		}
	}

	// Step 5.6: Sort by priority within dependency constraints
	// Sort the initial queue by priority to ensure priority ordering within each level
	// Manual bubble sort to avoid closure issues
	for i in 0 ..< len(queue) {
		for j in i + 1 ..< len(queue) {
			if modules[queue[i]].priority > modules[queue[j]].priority {
				queue[i], queue[j] = queue[j], queue[i]
			}
		}
	}

	// Process modules in topological order
	for len(queue) > 0 {
		// Remove first element from queue (already sorted by priority)
		current_idx := queue[0]
		ordered_remove(&queue, 0)

		// ✅ CRITICAL FIX: Deep clone before appending to avoid shared ownership
		current_module := modules[current_idx]
		cloned_module := CloneModule(current_module)
		append(&result.modules, cloned_module)

		// Collect modules that become ready after processing current module
		newly_ready := make([dynamic]int)
		defer delete(newly_ready)

		// Reduce in-degree for all modules that depend on current module
		for module, idx in modules {
			for dep in module.required {
				if dep == current_module.name {
					in_degree[module.name] -= 1
					if in_degree[module.name] == 0 {
						append(&newly_ready, idx)
					}
				}
			}
		}

		// Sort newly ready modules by priority before adding to queue
		// Manual bubble sort to avoid closure issues
		for i in 0 ..< len(newly_ready) {
			for j in i + 1 ..< len(newly_ready) {
				if modules[newly_ready[i]].priority > modules[newly_ready[j]].priority {
					newly_ready[i], newly_ready[j] = newly_ready[j], newly_ready[i]
				}
			}
		}

		// Add newly ready modules to queue (they're already sorted by priority)
		for idx in newly_ready {
			append(&queue, idx)
		}
	}

	// Step 5.4: Detect and report circular dependencies
	if len(result.modules) != len(modules) {
		// If we couldn't process all modules, there must be a cycle
		result.error = .CircularDependency

		// Find which modules are involved in the cycle
		processed_names := make(map[string]bool)
		defer delete(processed_names)

		for module in result.modules {
			processed_names[module.name] = true
		}

		unprocessed := make([dynamic]string)
		defer delete(unprocessed)

		for module in modules {
			if !processed_names[module.name] {
				append(&unprocessed, module.name)
			}
		}

		result.message = strings.clone(fmt.tprintf(
			"Circular dependency detected involving modules: %v",
			unprocessed[:],
		))
		return result
	}

	return result
}
