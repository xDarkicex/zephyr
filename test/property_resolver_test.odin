#+feature dynamic-literals
package test

import "core:testing"
import "core:fmt"
import "core:strings"

import "../src/loader"
import "../src/manifest"

// Simple counter for generating unique names
test_counter := 0

// Generate a unique module name
generate_module_name :: proc(prefix: string = "module") -> string {
    test_counter += 1
    return fmt.tprintf("%s-%d", prefix, test_counter)
}

// Generate a simple priority value
generate_priority :: proc(base: int) -> int {
    return base * 10
}

// Generate a simple version string
generate_version :: proc(major: int = 1) -> string {
    return fmt.tprintf("%d.0.0", major)
}

// Generate a valid acyclic dependency graph
generate_acyclic_modules :: proc(count: int) -> [dynamic]manifest.Module {
    modules := make([dynamic]manifest.Module)
    
    // Generate modules with names that allow for ordering
    module_names := make([dynamic]string)
    defer delete(module_names)
    
    for i in 0..<count {
        name := fmt.tprintf("module-%d", i)
        append(&module_names, strings.clone(name))
    }
    
    // Create modules where each module can only depend on modules with lower indices
    // This guarantees acyclicity
    for i in 0..<count {
        module := manifest.Module{
            name = strings.clone(module_names[i]),
            version = strings.clone(generate_version(i + 1)),
            priority = generate_priority(i + 1),
            required = make([dynamic]string),
            optional = make([dynamic]string),
            files = make([dynamic]string),
            settings = make(map[string]string),
            platforms = manifest.Platform_Filter{
                os = make([dynamic]string),
                arch = make([dynamic]string),
            },
        }
        
        // Add dependencies only to modules with lower indices (guarantees acyclicity)
        if i > 0 {
            // Simple pattern: each module depends on the previous one
            if i == 1 {
                append(&module.required, strings.clone(module_names[0]))
            } else if i == 2 {
                append(&module.required, strings.clone(module_names[0]))
                append(&module.required, strings.clone(module_names[1]))
            } else {
                // For larger graphs, depend on first and previous
                append(&module.required, strings.clone(module_names[0]))
                append(&module.required, strings.clone(module_names[i-1]))
            }
        }
        
        append(&modules, module)
    }
    
    return modules
}

// **Validates: Requirements 3.3.1, 3.3.2**
@(test)
test_property_dependency_resolution_acyclicity :: proc(t: ^testing.T) {
    // Property: For any valid acyclic dependency graph, resolution must succeed
    // Property: The resolved order must satisfy all dependency constraints
    // Property: No cycles should exist in the resolved order
    
    // Test with multiple configurations
    test_cases := []int{3, 5, 8, 10}
    
    for module_count in test_cases {
        for iteration in 0..<5 { // 5 iterations per size
            modules := generate_acyclic_modules(module_count)
            defer {
                manifest.cleanup_modules(modules[:])
                delete(modules)
            }
            
            // Resolve dependencies
            resolved, err := loader.resolve(modules)
            
            // Property: Resolution should succeed for acyclic graphs
            testing.expect(t, len(err) == 0, 
                fmt.tprintf("Acyclic graph resolution should succeed (size=%d, iter=%d), got error: %s", 
                    module_count, iteration, err))
            
            if len(err) == 0 {
                // Property: All modules should be included
                testing.expect_value(t, len(resolved), module_count)
                
                // Property: Dependencies must be satisfied (no module appears before its dependencies)
                module_positions := make(map[string]int)
                defer delete(module_positions)
                
                for module, idx in resolved {
                    module_positions[module.name] = idx
                }
                
                // Check that each module appears after all its dependencies
                for module in resolved {
                    for dep in module.required {
                        dep_pos, dep_exists := module_positions[dep]
                        module_pos := module_positions[module.name]
                        
                        testing.expect(t, dep_exists, 
                            fmt.tprintf("Dependency '%s' should exist in resolved order", dep))
                        testing.expect(t, dep_pos < module_pos, 
                            fmt.tprintf("Dependency '%s' (pos %d) should come before '%s' (pos %d)", 
                                dep, dep_pos, module.name, module_pos))
                    }
                }
                
                // Property: No cycles in resolved order (each module appears exactly once)
                seen_modules := make(map[string]bool)
                defer delete(seen_modules)
                
                for module in resolved {
                    testing.expect(t, !seen_modules[module.name], 
                        fmt.tprintf("Module '%s' should appear only once in resolved order", module.name))
                    seen_modules[module.name] = true
                }
            }
        }
    }
}

// Generate modules with guaranteed circular dependencies
generate_cyclic_modules :: proc(count: int) -> [dynamic]manifest.Module {
    modules := make([dynamic]manifest.Module)
    
    if count < 2 {
        return modules
    }
    
    // Generate module names
    module_names := make([dynamic]string)
    defer delete(module_names)
    
    for i in 0..<count {
        name := fmt.tprintf("cyclic-%d", i)
        append(&module_names, strings.clone(name))
    }
    
    // Create modules with a guaranteed cycle
    for i in 0..<count {
        module := manifest.Module{
            name = strings.clone(module_names[i]),
            version = strings.clone(generate_version(i + 1)),
            priority = generate_priority(i + 1),
            required = make([dynamic]string),
            optional = make([dynamic]string),
            files = make([dynamic]string),
            settings = make(map[string]string),
            platforms = manifest.Platform_Filter{
                os = make([dynamic]string),
                arch = make([dynamic]string),
            },
        }
        
        // Create a cycle: each module depends on the next one, last depends on first
        next_idx := (i + 1) % count
        append(&module.required, strings.clone(module_names[next_idx]))
        
        append(&modules, module)
    }
    
    return modules
}

// **Validates: Requirements 3.3.2**
@(test)
test_property_circular_dependency_detection :: proc(t: ^testing.T) {
    // Property: Any dependency graph with cycles must be detected and rejected
    
    // Test with different cycle sizes
    cycle_sizes := []int{2, 3, 4, 5}
    
    for cycle_size in cycle_sizes {
        for iteration in 0..<3 { // 3 iterations per cycle size
            modules := generate_cyclic_modules(cycle_size)
            defer {
                manifest.cleanup_modules(modules[:])
                delete(modules)
            }
            
            // Resolve dependencies
            resolved, err := loader.resolve(modules)
            
            // Property: Resolution should fail for cyclic graphs
            testing.expect(t, len(err) > 0, 
                fmt.tprintf("Cyclic graph resolution should fail (cycle_size=%d, iter=%d)", 
                    cycle_size, iteration))
            
            // Property: Error should mention circular dependency
            testing.expect(t, strings.contains(err, "Circular dependency"), 
                fmt.tprintf("Error should mention circular dependency, got: %s", err))
            
            // Property: No modules should be resolved when there's a cycle
            testing.expect(t, resolved == nil || len(resolved) == 0, 
                "No modules should be resolved when circular dependency exists")
        }
    }
}

// Generate modules with missing dependencies
generate_modules_with_missing_deps :: proc(valid_count: int, missing_count: int) -> [dynamic]manifest.Module {
    modules := make([dynamic]manifest.Module)
    
    // Generate valid modules
    for i in 0..<valid_count {
        module := manifest.Module{
            name = strings.clone(fmt.tprintf("valid-%d", i)),
            version = strings.clone(generate_version(i + 1)),
            priority = generate_priority(i + 1),
            required = make([dynamic]string),
            optional = make([dynamic]string),
            files = make([dynamic]string),
            settings = make(map[string]string),
            platforms = manifest.Platform_Filter{
                os = make([dynamic]string),
                arch = make([dynamic]string),
            },
        }
        
        // Add some missing dependencies
        for j in 0..<missing_count {
            missing_dep := fmt.tprintf("missing-%d", j)
            append(&module.required, strings.clone(missing_dep))
        }
        
        append(&modules, module)
    }
    
    return modules
}

// **Validates: Requirements 3.3.3**
@(test)
test_property_missing_dependency_detection :: proc(t: ^testing.T) {
    // Property: Any module with missing required dependencies must cause resolution to fail
    
    // Test with different numbers of valid modules and missing dependencies
    test_configs := []struct{valid: int, missing: int}{
        {1, 1}, {2, 1}, {3, 2},
    }
    
    for config in test_configs {
        for iteration in 0..<3 { // 3 iterations per configuration
            modules := generate_modules_with_missing_deps(config.valid, config.missing)
            defer {
                manifest.cleanup_modules(modules[:])
                delete(modules)
            }
            
            // Resolve dependencies
            resolved, err := loader.resolve(modules)
            
            // Property: Resolution should fail when dependencies are missing
            testing.expect(t, len(err) > 0, 
                fmt.tprintf("Resolution should fail with missing dependencies (valid=%d, missing=%d, iter=%d)", 
                    config.valid, config.missing, iteration))
            
            // Property: Error should mention missing dependency
            testing.expect(t, strings.contains(err, "missing dependency"), 
                fmt.tprintf("Error should mention missing dependency, got: %s", err))
        }
    }
}

// Generate modules with priority constraints
generate_priority_test_modules :: proc(count: int) -> [dynamic]manifest.Module {
    modules := make([dynamic]manifest.Module)
    
    // Create a base module that others can depend on
    base_module := manifest.Module{
        name = strings.clone("base"),
        version = strings.clone("1.0.0"),
        priority = 100, // Low priority (high number)
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&modules, base_module)
    
    // Create modules that depend on base with different priorities
    for i in 1..<count {
        module := manifest.Module{
            name = strings.clone(fmt.tprintf("priority-%d", i)),
            version = strings.clone(generate_version(i)),
            priority = i * 5, // Different priorities: 5, 10, 15, etc.
            required = make([dynamic]string),
            optional = make([dynamic]string),
            files = make([dynamic]string),
            settings = make(map[string]string),
            platforms = manifest.Platform_Filter{
                os = make([dynamic]string),
                arch = make([dynamic]string),
            },
        }
        
        // All depend on base
        append(&module.required, strings.clone("base"))
        append(&modules, module)
    }
    
    return modules
}

// **Validates: Requirements 3.3.4**
@(test)
test_property_priority_ordering_correctness :: proc(t: ^testing.T) {
    // Property: Within dependency constraints, modules should be ordered by priority
    // Property: Lower priority numbers should come first
    
    // Test with different numbers of modules
    module_counts := []int{3, 5, 8}
    
    for module_count in module_counts {
        for iteration in 0..<5 { // 5 iterations per count
            modules := generate_priority_test_modules(module_count)
            defer {
                manifest.cleanup_modules(modules[:])
                delete(modules)
            }
            
            // Resolve dependencies
            resolved, err := loader.resolve(modules)
            
            // Property: Resolution should succeed
            testing.expect(t, len(err) == 0, 
                fmt.tprintf("Priority test resolution should succeed (count=%d, iter=%d), got error: %s", 
                    module_count, iteration, err))
            
            if len(err) == 0 {
                // Property: Base module should be first (it has no dependencies)
                testing.expect_value(t, resolved[0].name, "base")
                
                // Property: Among modules with same dependency level, priority should determine order
                // All non-base modules depend on base, so they should be ordered by priority
                for i in 1..<len(resolved)-1 {
                    current_priority := resolved[i].priority
                    next_priority := resolved[i+1].priority
                    
                    testing.expect(t, current_priority <= next_priority, 
                        fmt.tprintf("Module '%s' (priority %d) should come before or equal to '%s' (priority %d)", 
                            resolved[i].name, current_priority, resolved[i+1].name, next_priority))
                }
            }
        }
    }
}