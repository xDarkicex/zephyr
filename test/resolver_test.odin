#+feature dynamic-literals
package test

import "core:testing"
import "core:fmt"
import "core:strings"

import "../src/loader"
import "../src/manifest"

// **Validates: Requirements 3.3.1, 3.3.5**
@(test)
test_dependency_resolution_acyclicity :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
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
    defer cleanup_error_message(err)
    
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

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.2**
@(test)
test_circular_dependency_detection :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
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
    defer cleanup_error_message(err)
    
    // Property: Resolution should fail with circular dependency error
    testing.expect(t, len(err) > 0, "Should detect circular dependency")
    testing.expect(t, strings.contains(err, "Circular dependency"), 
        fmt.tprintf("Error should mention circular dependency, got: %s", err))
    
    // Property: No modules should be resolved when there's a cycle
    testing.expect(t, resolved == nil || len(resolved) == 0, 
        "No modules should be resolved when circular dependency exists")

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.3**
@(test)
test_missing_dependency_detection :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
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
    defer cleanup_error_message(err)
    
    // Property: Resolution should fail with missing dependency error
    testing.expect(t, len(err) > 0, "Should detect missing dependency")
    testing.expect(t, strings.contains(err, "missing dependency"), 
        fmt.tprintf("Error should mention missing dependency, got: %s", err))
    testing.expect(t, strings.contains(err, "nonexistent-module"), 
        fmt.tprintf("Error should mention the missing module name, got: %s", err))

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.4**
@(test)
test_priority_ordering_within_constraints :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
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
    defer cleanup_error_message(err)
    
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

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.5**
@(test)
test_no_dependencies_handling :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
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
    defer cleanup_error_message(err)
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 2)
        
        // Property: Modules should be ordered by priority
        testing.expect_value(t, resolved[0].name, "module-a") // priority 10
        testing.expect_value(t, resolved[1].name, "module-b") // priority 20
    }

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.1**
@(test)
test_complex_dependency_graph :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
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
    defer cleanup_error_message(err)
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 5)
        
        // Property: Dependencies must be satisfied
        module_positions := make(map[string]int)
        defer delete(module_positions)
        
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

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.1, 3.3.4**
@(test)
test_diamond_dependency_pattern :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Diamond dependency patterns should resolve correctly
    // Pattern: A depends on B and C, both B and C depend on D
    //     A
    //    / \
    //   B   C
    //    \ /
    //     D
    
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
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
    defer cleanup_error_message(err)
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 4)
        
        // Property: D should come first (no dependencies)
        testing.expect_value(t, resolved[0].name, "module-d")
        
        // Property: B and C should come before A
        module_positions := make(map[string]int)
        defer delete(module_positions)
        for module, idx in resolved {
            module_positions[module.name] = idx
        }
        
        testing.expect(t, module_positions["module-b"] < module_positions["module-a"], 
            "module-b should come before module-a")
        testing.expect(t, module_positions["module-c"] < module_positions["module-a"], 
            "module-c should come before module-a")
        testing.expect(t, module_positions["module-d"] < module_positions["module-b"], 
            "module-d should come before module-b")
        testing.expect(t, module_positions["module-d"] < module_positions["module-c"], 
            "module-d should come before module-c")
        
        // Property: A should be last
        testing.expect_value(t, resolved[len(resolved)-1].name, "module-a")
    }

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.2**
@(test)
test_self_dependency_detection :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Self-dependencies should be detected as circular
    
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Module that depends on itself
    module_self := manifest.Module{
        name = strings.clone("self-dependent"),
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
    append(&module_self.required, strings.clone("self-dependent"))
    append(&modules, module_self)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    
    // Property: Resolution should fail with circular dependency error
    testing.expect(t, len(err) > 0, "Should detect self-dependency as circular")
    testing.expect(t, strings.contains(err, "Circular dependency"), 
        fmt.tprintf("Error should mention circular dependency, got: %s", err))

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.2**
@(test)
test_three_way_circular_dependency :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Three-way circular dependencies should be detected
    // Pattern: A -> B -> C -> A
    
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
    
    // Module C (depends on A - creates cycle)
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
    append(&module_c.required, strings.clone("module-a"))
    append(&modules, module_c)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    
    // Property: Resolution should fail with circular dependency error
    testing.expect(t, len(err) > 0, "Should detect three-way circular dependency")
    testing.expect(t, strings.contains(err, "Circular dependency"), 
        fmt.tprintf("Error should mention circular dependency, got: %s", err))

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.3**
@(test)
test_multiple_missing_dependencies :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Multiple missing dependencies should be reported
    
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Module with multiple missing dependencies
    module_missing := manifest.Module{
        name = strings.clone("missing-deps"),
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
    append(&module_missing.required, strings.clone("nonexistent-1"))
    append(&module_missing.required, strings.clone("nonexistent-2"))
    append(&modules, module_missing)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    
    // Property: Resolution should fail with missing dependency error
    testing.expect(t, len(err) > 0, "Should detect missing dependencies")
    testing.expect(t, strings.contains(err, "missing dependency"), 
        fmt.tprintf("Error should mention missing dependency, got: %s", err))
    
    // Property: Error should mention the first missing dependency found
    testing.expect(t, strings.contains(err, "nonexistent-1") || strings.contains(err, "nonexistent-2"), 
        fmt.tprintf("Error should mention one of the missing dependencies, got: %s", err))

    cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.1**
@(test)
test_large_dependency_graph :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Large dependency graphs should resolve efficiently
    
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Create a larger dependency graph with 10 modules
    // Structure: base -> level1a, level1b -> level2a, level2b, level2c -> level3a, level3b -> top
    
    module_names := []string{
        "base", "level1a", "level1b", "level2a", "level2b", "level2c", 
        "level3a", "level3b", "top"
    }
    
    dependencies := map[string][]string{
        "level1a" = {"base"},
        "level1b" = {"base"},
        "level2a" = {"level1a"},
        "level2b" = {"level1a", "level1b"},
        "level2c" = {"level1b"},
        "level3a" = {"level2a", "level2b"},
        "level3b" = {"level2b", "level2c"},
        "top" = {"level3a", "level3b"},
    }
    
    // Create modules
    for name, idx in module_names {
        module := manifest.Module{
            name = strings.clone(name),
            version = strings.clone("1.0.0"),
            priority = idx * 10, // Different priorities
            required = make([dynamic]string),
            optional = make([dynamic]string),
            files = make([dynamic]string),
            settings = make(map[string]string),
            platforms = manifest.Platform_Filter{
                os = make([dynamic]string),
                arch = make([dynamic]string),
            },
        }
        
        // Add dependencies if they exist
        if deps, has_deps := dependencies[name]; has_deps {
            for dep in deps {
                append(&module.required, strings.clone(dep))
            }
        }
        
        append(&modules, module)
    }
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    
    // Property: Resolution should succeed
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed for large graph, got error: %s", err))
    
	if len(err) == 0 {
		// Property: All modules should be included
		testing.expect_value(t, len(resolved), len(module_names))
        
        // Property: Dependencies must be satisfied
        module_positions := make(map[string]int)
        defer delete(module_positions)
        for module, idx in resolved {
            module_positions[module.name] = idx
        }
        
        // Verify key dependency relationships
        testing.expect(t, module_positions["base"] < module_positions["level1a"], 
            "base should come before level1a")
        testing.expect(t, module_positions["base"] < module_positions["level1b"], 
            "base should come before level1b")
        testing.expect(t, module_positions["level1a"] < module_positions["level2a"], 
            "level1a should come before level2a")
        testing.expect(t, module_positions["level3a"] < module_positions["top"], 
            "level3a should come before top")
        testing.expect(t, module_positions["level3b"] < module_positions["top"], 
            "level3b should come before top")
        
		// Property: Base should be first, top should be last
		testing.expect_value(t, resolved[0].name, "base")
		testing.expect_value(t, resolved[len(resolved)-1].name, "top")
	}

	cleanup_resolved_and_cache(resolved)
}

// **Validates: Requirements 3.3.4**
@(test)
test_priority_with_optional_dependencies :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    // Property: Optional dependencies should not affect resolution order
    // but priority should still be respected among modules with satisfied dependencies
    
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Base module
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
    
    // High priority module with optional dependency on non-existent module
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
    append(&high_priority.required, strings.clone("base"))
    append(&high_priority.optional, strings.clone("nonexistent-optional"))
    append(&modules, high_priority)
    
    // Low priority module
    low_priority := manifest.Module{
        name = strings.clone("low-priority"),
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
    append(&low_priority.required, strings.clone("base"))
    append(&modules, low_priority)
    
    // Resolve dependencies
    resolved, err := loader.resolve(modules)
    defer cleanup_error_message(err)
    
    // Property: Resolution should succeed despite optional missing dependency
    testing.expect(t, len(err) == 0, fmt.tprintf("Resolution should succeed with optional missing deps, got error: %s", err))
    
    if len(err) == 0 {
        // Property: All modules should be included
        testing.expect_value(t, len(resolved), 3)
        
        // Property: Base should be first
        testing.expect_value(t, resolved[0].name, "base")
        
        // Property: High priority should come before low priority
        testing.expect_value(t, resolved[1].name, "high-priority")
        testing.expect_value(t, resolved[2].name, "low-priority")
    }

    cleanup_resolved_and_cache(resolved)
}
