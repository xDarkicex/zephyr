package test

import "core:testing"
import "core:fmt"
import "core:strings"
import "../src/loader"
import "../src/manifest"

// **Validates: Requirements 3.3.1, 3.3.5**
@(test)
test_dependency_resolution_acyclicity :: proc(t: ^testing.T) {
    // Property: Resolved module order must never contain cycles
    // Property: All modules with satisfied dependencies must be included
    
    // Create test modules with valid dependency chain: A -> B -> C
    modules := make([dynamic]manifest.Module)
    defer {
        for module in modules {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(modules)
    }
    
    // Module C (no dependencies)
    module_c := manifest.Module{
        name = strings.clone("module-c"),
        version = strings.clone("1.0.0"),
        priority = 30,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&modules, module_c)
    
    // Module B (depends on C)
    module_b := manifest.Module{
        name = strings.clone("module-b"),
        version = strings.clone("1.0.0"),
        priority = 20,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module_b.required, strings.clone("module-c"))
    append(&modules, module_b)
    
    // Module A (depends on B)
    module_a := manifest.Module{
        name = strings.clone("module-a"),
        version = strings.clone("1.0.0"),
        priority = 10,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module_a.required, strings.clone("module-b"))
    append(&modules, module_a)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer {
        for module in resolved {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(resolved)
    }
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 3)
        
        // Property: Dependencies must be satisfied (C before B, B before A)
        module_positions := make(map[string]int)
        defer delete(module_positions)
        
        for module, idx in resolved {
            module_positions[module.name] = idx
        }
        
        // Check dependency order
        testing.expect(t, module_positions["module-c"] < module_positions["module-b"], 
                      "module-c should come before module-b")
        testing.expect(t, module_positions["module-b"] < module_positions["module-a"], 
                      "module-b should come before module-a")
    }
}

// **Validates: Requirements 3.3.2**
@(test)
test_circular_dependency_detection :: proc(t: ^testing.T) {
    // Property: Circular dependencies must be detected and reported
    
    modules := make([dynamic]manifest.Module)
    defer {
        for module in modules {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(modules)
    }
    
    // Create circular dependency: A -> B -> A
    module_a := manifest.Module{
        name = strings.clone("module-a"),
        version = strings.clone("1.0.0"),
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module_a.required, strings.clone("module-b"))
    append(&modules, module_a)
    
    module_b := manifest.Module{
        name = strings.clone("module-b"),
        version = strings.clone("1.0.0"),
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module_b.required, strings.clone("module-a"))
    append(&modules, module_b)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer delete(resolved)
    
    // Property: Should detect circular dependency
    testing.expect(t, len(err) > 0, "Should detect circular dependency")
    testing.expect(t, strings.contains(err, "Circular dependency"), 
                  fmt.tprintf("Error should mention circular dependency, got: %s", err))
}

// **Validates: Requirements 3.3.3**
@(test)
test_missing_dependency_detection :: proc(t: ^testing.T) {
    // Property: Missing required dependencies must be detected and reported
    
    modules := make([dynamic]manifest.Module)
    defer {
        for module in modules {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(modules)
    }
    
    // Create module with missing dependency
    module_a := manifest.Module{
        name = strings.clone("module-a"),
        version = strings.clone("1.0.0"),
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module_a.required, strings.clone("missing-module"))
    append(&modules, module_a)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer delete(resolved)
    
    // Property: Should detect missing dependency
    testing.expect(t, len(err) > 0, "Should detect missing dependency")
    testing.expect(t, strings.contains(err, "missing dependency"), 
                  fmt.tprintf("Error should mention missing dependency, got: %s", err))
    testing.expect(t, strings.contains(err, "missing-module"), 
                  fmt.tprintf("Error should mention the missing module name, got: %s", err))
}

// **Validates: Requirements 3.3.4**
@(test)
test_priority_ordering_within_constraints :: proc(t: ^testing.T) {
    // Property: Modules should be sorted by priority within dependency constraints
    
    modules := make([dynamic]manifest.Module)
    defer {
        for module in modules {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(modules)
    }
    
    // Create modules with different priorities but no dependencies
    high_priority := manifest.Module{
        name = strings.clone("high-priority"),
        version = strings.clone("1.0.0"),
        priority = 10,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&modules, high_priority)
    
    low_priority := manifest.Module{
        name = strings.clone("low-priority"),
        version = strings.clone("1.0.0"),
        priority = 100,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&modules, low_priority)
    
    medium_priority := manifest.Module{
        name = strings.clone("medium-priority"),
        version = strings.clone("1.0.0"),
        priority = 50,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&modules, medium_priority)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer {
        for module in resolved {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(resolved)
    }
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 && len(resolved) == 3 {
        // Property: Should be ordered by priority (lower values first)
        testing.expect(t, strings.compare(resolved[0].name, "high-priority") == 0, 
                      fmt.tprintf("First module should be high-priority, got %s", resolved[0].name))
        testing.expect(t, strings.compare(resolved[1].name, "medium-priority") == 0, 
                      fmt.tprintf("Second module should be medium-priority, got %s", resolved[1].name))
        testing.expect(t, strings.compare(resolved[2].name, "low-priority") == 0, 
                      fmt.tprintf("Third module should be low-priority, got %s", resolved[2].name))
    }
}

// **Validates: Requirements 3.3.5**
@(test)
test_no_dependencies_handling :: proc(t: ^testing.T) {
    // Property: Modules with no dependencies should be handled correctly
    
    modules := make([dynamic]manifest.Module)
    defer {
        for module in modules {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(modules)
    }
    
    // Create standalone module
    standalone := manifest.Module{
        name = strings.clone("standalone"),
        version = strings.clone("1.0.0"),
        priority = 50,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&modules, standalone)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer {
        for module in resolved {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(resolved)
    }
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: Module should be included
        testing.expect_value(t, len(resolved), 1)
        testing.expect(t, strings.compare(resolved[0].name, "standalone") == 0, 
                      fmt.tprintf("Expected standalone module, got %s", resolved[0].name))
    }
}

// **Validates: Requirements 3.3.1**
@(test)
test_complex_dependency_graph :: proc(t: ^testing.T) {
    // Property: Complex dependency graphs should resolve correctly
    // Test case: A->B, A->C, B->D, C->D (diamond dependency)
    
    modules := make([dynamic]manifest.Module)
    defer {
        for module in modules {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(modules)
    }
    
    // Module D (base dependency)
    module_d := manifest.Module{
        name = strings.clone("module-d"),
        version = strings.clone("1.0.0"),
        priority = 40,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&modules, module_d)
    
    // Module C (depends on D)
    module_c := manifest.Module{
        name = strings.clone("module-c"),
        version = strings.clone("1.0.0"),
        priority = 30,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module_c.required, strings.clone("module-d"))
    append(&modules, module_c)
    
    // Module B (depends on D)
    module_b := manifest.Module{
        name = strings.clone("module-b"),
        version = strings.clone("1.0.0"),
        priority = 20,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module_b.required, strings.clone("module-d"))
    append(&modules, module_b)
    
    // Module A (depends on B and C)
    module_a := manifest.Module{
        name = strings.clone("module-a"),
        version = strings.clone("1.0.0"),
        priority = 10,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module_a.required, strings.clone("module-b"))
    append(&module_a.required, strings.clone("module-c"))
    append(&modules, module_a)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer {
        for module in resolved {
            delete(module.required)
            delete(module.optional)
            delete(module.files)
            delete(module.platforms.os)
            delete(module.platforms.arch)
            delete(module.settings)
        }
        delete(resolved)
    }
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 4)
        
        // Property: D should come before B and C, B and C should come before A
        module_positions := make(map[string]int)
        defer delete(module_positions)
        
        for module, idx in resolved {
            module_positions[module.name] = idx
        }
        
        testing.expect(t, module_positions["module-d"] < module_positions["module-b"], 
                      "module-d should come before module-b")
        testing.expect(t, module_positions["module-d"] < module_positions["module-c"], 
                      "module-d should come before module-c")
        testing.expect(t, module_positions["module-b"] < module_positions["module-a"], 
                      "module-b should come before module-a")
        testing.expect(t, module_positions["module-c"] < module_positions["module-a"], 
                      "module-c should come before module-a")
    }
}