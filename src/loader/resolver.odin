package loader

import "core:fmt"
import "core:slice"
import "../manifest"

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
    manifest.cleanup_modules(result.modules[:])
    delete(result.modules)
    delete(result.message)
}

// resolve performs dependency resolution using Kahn's algorithm for topological sorting
// Returns modules in dependency order with priority sorting within constraints
resolve :: proc(modules: [dynamic]manifest.Module) -> ([dynamic]manifest.Module, string) {
    result := resolve_detailed(modules)
    if result.error != .None {
        return nil, result.message
    }
    return result.modules, ""
}

// resolve_detailed provides detailed error information for debugging
resolve_detailed :: proc(modules: [dynamic]manifest.Module) -> ResolutionResult {
    result := ResolutionResult{
        modules = make([dynamic]manifest.Module),
        error = .None,
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
            result.message = fmt.tprintf("Module at index %d has empty name", idx)
            return result
        }
        
        // Check for duplicate module names
        if existing_idx, exists := registry[module.name]; exists {
            result.error = .InvalidModule
            result.message = fmt.tprintf("Duplicate module name '%s' found at indices %d and %d", 
                module.name, existing_idx, idx)
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
                result.message = fmt.tprintf("Module '%s' requires missing dependency '%s'", 
                    module.name, dep)
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
    for i in 0..<len(queue) {
        for j in i+1..<len(queue) {
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
        
        current_module := modules[current_idx]
        append(&result.modules, current_module)
        
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
        for i in 0..<len(newly_ready) {
            for j in i+1..<len(newly_ready) {
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
        
        result.message = fmt.tprintf("Circular dependency detected involving modules: %v", unprocessed[:])
        return result
    }
    
    return result
}