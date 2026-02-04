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
        manifest.cleanup_modules(modules[:])
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
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 3)
        
        // Property: Dependencies must be satisfied (C before B, B before A)
        module_positions := make(map[string]int)
        
        for module, idx in resolved {
            module_positions[module.name] = idx
        }
        
        // Verify dependency order
        testing.expect(t, module_positions["module-c"] < module_positions["module-b"], 
            "module-c should come before module-b")
        testing.expect(t, module_positions["module-b"] < module_positions["module-a"], 
            "module-b should come before module-a")
        
        // Property: Priority ordering within constraints
        // Since C has no dependencies, it should be first
        // B depends on C, so it comes after C
        // A depends on B, so it comes after B
        testing.expect_value(t, resolved[0].name, "module-c")
        testing.expect_value(t, resolved[1].name, "module-b")
        testing.expect_value(t, resolved[2].name, "module-a")
    }
}

// **Validates: Requirements 3.3.2**
@(test)
test_circular_dependency_detection :: proc(t: ^testing.T) {
    // Property: Circular dependencies must be detected and reported
    
    // Create test modules with circular dependency: A -> B -> A
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
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
    
    // Module B (depends on A - creates cycle)
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
    append(&module_b.required, strings.clone("module-a"))
    append(&modules, module_b)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    
    // Property: Resolution should fail with circular dependency error
    testing.expect(t, len(err) > 0, "Should detect circular dependency")
    testing.expect(t, strings.contains(err, "Circular dependency"), 
        fmt.tprintf("Error should mention circular dependency, got: %s", err))
    
    // Property: No modules should be resolved when there's a cycle
    testing.expect(t, resolved == nil || len(resolved) == 0, 
        "No modules should be resolved when circular dependency exists")
}

// **Validates: Requirements 3.3.3**
@(test)
test_missing_dependency_detection :: proc(t: ^testing.T) {
    // Property: Missing required dependencies must be detected and reported
    
    // Create test module with missing dependency
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Module A (depends on non-existent module)
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
    append(&module_a.required, strings.clone("nonexistent-module"))
    append(&modules, module_a)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    
    // Property: Resolution should fail with missing dependency error
    testing.expect(t, len(err) > 0, "Should detect missing dependency")
    testing.expect(t, strings.contains(err, "missing dependency"), 
        fmt.tprintf("Error should mention missing dependency, got: %s", err))
    testing.expect(t, strings.contains(err, "nonexistent-module"), 
        fmt.tprintf("Error should mention the missing module name, got: %s", err))
}

// **Validates: Requirements 3.3.4**
@(test)
test_priority_ordering_within_constraints :: proc(t: ^testing.T) {
    // Property: Modules should be sorted by priority within dependency constraints
    
    // Create test modules with same dependencies but different priorities
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Base module (no dependencies)
    base_module := manifest.Module{
        name = strings.clone("base"),
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
    append(&modules, base_module)
    
    // High priority module (depends on base)
    high_priority := manifest.Module{
        name = strings.clone("high-priority"),
        version = strings.clone("1.0.0"),
        priority = 10, // Lower number = higher priority
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&high_priority.required, strings.clone("base"))
    append(&modules, high_priority)
    
    // Low priority module (depends on base)
    low_priority := manifest.Module{
        name = strings.clone("low-priority"),
        version = strings.clone("1.0.0"),
        priority = 50, // Higher number = lower priority
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&low_priority.required, strings.clone("base"))
    append(&modules, low_priority)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 3)
        
        // Property: Base module should be first (no dependencies)
        testing.expect_value(t, resolved[0].name, "base")
        
        // Property: Among modules with same dependency level, priority should determine order
        // high-priority (priority 10) should come before low-priority (priority 50)
        testing.expect_value(t, resolved[1].name, "high-priority")
        testing.expect_value(t, resolved[2].name, "low-priority")
    }
}

// **Validates: Requirements 3.3.5**
@(test)
test_no_dependencies_handling :: proc(t: ^testing.T) {
    // Property: Modules with no dependencies should be handled correctly
    
    // Create test modules with no dependencies
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Module A (no dependencies, high priority)
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
    append(&modules, module_a)
    
    // Module B (no dependencies, low priority)
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
    append(&modules, module_b)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 2)
        
        // Property: Modules should be ordered by priority
        testing.expect_value(t, resolved[0].name, "module-a") // priority 10
        testing.expect_value(t, resolved[1].name, "module-b") // priority 20
    }
}

// **Validates: Requirements 3.3.1**
@(test)
test_complex_dependency_graph :: proc(t: ^testing.T) {
    // Property: Complex dependency graphs should resolve correctly
    
    // Create a complex dependency graph:
    // A -> B, C
    // B -> D
    // C -> D, E
    // D -> (no deps)
    // E -> (no deps)
    // Expected order: D, E, B, C, A (or D, E, C, B, A depending on priority)
    
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Module D (no dependencies)
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
    
    // Module E (no dependencies)
    module_e := manifest.Module{
        name = strings.clone("module-e"),
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
    append(&modules, module_e)
    
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
    
    // Module C (depends on D, E)
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
    append(&module_c.required, strings.clone("module-e"))
    append(&modules, module_c)
    
    // Module A (depends on B, C)
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
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 5)
        
        // Property: Dependencies must be satisfied
        module_positions := make(map[string]int)
        
        for module, idx in resolved {
            module_positions[module.name] = idx
        }
        
        // D and E should come before B and C
        testing.expect(t, module_positions["module-d"] < module_positions["module-b"], 
            "module-d should come before module-b")
        testing.expect(t, module_positions["module-d"] < module_positions["module-c"], 
            "module-d should come before module-c")
        testing.expect(t, module_positions["module-e"] < module_positions["module-c"], 
            "module-e should come before module-c")
        
        // B and C should come before A
        testing.expect(t, module_positions["module-b"] < module_positions["module-a"], 
            "module-b should come before module-a")
        testing.expect(t, module_positions["module-c"] < module_positions["module-a"], 
            "module-c should come before module-a")
        
        // A should be last
        testing.expect_value(t, resolved[len(resolved)-1].name, "module-a")
    }
}