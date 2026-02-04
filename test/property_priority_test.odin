#+feature dynamic-literals
package test

import "core:testing"
import "core:fmt"
import "core:strings"

import "../src/loader"
import "../src/manifest"

// Simple counter for generating unique test data
priority_test_counter := 0

// Generate a unique identifier
generate_priority_id :: proc() -> int {
    priority_test_counter += 1
    return priority_test_counter
}

// Generate a module with specific priority and dependencies
generate_priority_module :: proc(name: string, priority: int, dependencies: []string) -> manifest.Module {
    module := manifest.Module{
        name = strings.clone(name),
        version = strings.clone("1.0.0"),
        description = strings.clone("Test module for priority testing"),
        author = strings.clone("Test Author"),
        license = strings.clone("MIT"),
        priority = priority,
        required = make([dynamic]string),
        optional = make([dynamic]string),
        files = make([dynamic]string),
        settings = make(map[string]string),
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
        path = strings.clone(fmt.tprintf("/test/modules/%s", name)),
    }
    
    // Add dependencies
    for dep in dependencies {
        append(&module.required, strings.clone(dep))
    }
    
    // Add a test file
    append(&module.files, strings.clone("init.zsh"))
    
    return module
}

// Generate modules with no dependencies (can be ordered purely by priority)
generate_independent_modules :: proc(count: int, priorities: []int) -> [dynamic]manifest.Module {
    modules := make([dynamic]manifest.Module)
    
    for i in 0..<count {
        priority := priorities[i] if i < len(priorities) else (i + 1) * 10
        name := fmt.tprintf("independent-%d", i)
        module := generate_priority_module(name, priority, {})
        append(&modules, module)
    }
    
    return modules
}

// Generate modules with linear dependency chain
generate_chain_modules :: proc(count: int, priorities: []int) -> [dynamic]manifest.Module {
    modules := make([dynamic]manifest.Module)
    
    for i in 0..<count {
        priority := priorities[i] if i < len(priorities) else (i + 1) * 10
        name := fmt.tprintf("chain-%d", i)
        
        dependencies: []string
        if i > 0 {
            prev_name := fmt.tprintf("chain-%d", i - 1)
            dependencies = {prev_name}
        }
        
        module := generate_priority_module(name, priority, dependencies)
        append(&modules, module)
    }
    
    return modules
}

// Generate modules with tree dependency structure
generate_tree_modules :: proc(levels: int) -> [dynamic]manifest.Module {
    modules := make([dynamic]manifest.Module)
    
    // Create root module (no dependencies, high priority)
    root := generate_priority_module("root", 100, {})
    append(&modules, root)
    
    // Create level 1 modules (depend on root, medium priority)
    for i in 0..<2 {
        name := fmt.tprintf("level1-%d", i)
        module := generate_priority_module(name, 50 + i * 5, {"root"})
        append(&modules, module)
    }
    
    // Create level 2 modules (depend on level 1, low priority)
    if levels >= 3 {
        for i in 0..<2 {
            for j in 0..<2 {
                name := fmt.tprintf("level2-%d-%d", i, j)
                dep_name := fmt.tprintf("level1-%d", i)
                module := generate_priority_module(name, 10 + i * 5 + j, {dep_name})
                append(&modules, module)
            }
        }
    }
    
    return modules
}

// Check if modules are ordered correctly by priority within dependency constraints
check_priority_ordering :: proc(t: ^testing.T, resolved: []manifest.Module, test_name: string) {
    // Build dependency position map
    positions := make(map[string]int)
    defer delete(positions)
    
    for module, idx in resolved {
        positions[module.name] = idx
    }
    
    // Check dependency constraints are satisfied
    for module, idx in resolved {
        for dep in module.required {
            dep_pos, dep_exists := positions[dep]
            testing.expect(t, dep_exists, 
                fmt.tprintf("%s: Dependency '%s' should exist in resolved order", test_name, dep))
            testing.expect(t, dep_pos < idx, 
                fmt.tprintf("%s: Dependency '%s' (pos %d) should come before '%s' (pos %d)", 
                    test_name, dep, dep_pos, module.name, idx))
        }
    }
    
    // For priority ordering, only check modules that have NO dependencies at all
    // These are truly independent modules that should be ordered by priority
    independent_modules := make([dynamic]int)
    defer delete(independent_modules)
    
    for module, idx in resolved {
        if len(module.required) == 0 {
            append(&independent_modules, idx)
        }
    }
    
    // Check that independent modules are ordered by priority
    for i in 0..<len(independent_modules)-1 {
        current_idx := independent_modules[i]
        next_idx := independent_modules[i+1]
        
        current := resolved[current_idx]
        next := resolved[next_idx]
        
        // Lower priority numbers should come first
        testing.expect(t, current.priority <= next.priority, 
            fmt.tprintf("%s: Independent module '%s' (priority %d) should come before or equal to '%s' (priority %d)", 
                test_name, current.name, current.priority, next.name, next.priority))
    }
}

// **Validates: Requirements 3.3.4**
@(test)
test_property_priority_ordering_independent_modules :: proc(t: ^testing.T) {
    // Property: Modules with no dependencies should be ordered strictly by priority
    // Property: Lower priority numbers should come first
    
    test_cases := []struct{
        count: int,
        priorities: []int,
    }{
        {3, {30, 10, 20}}, // Should be ordered as: 10, 20, 30
        {4, {40, 10, 30, 20}}, // Should be ordered as: 10, 20, 30, 40
        {5, {50, 25, 75, 10, 60}}, // Should be ordered as: 10, 25, 50, 60, 75
    }
    
    for test_case in test_cases {
        for iteration in 0..<3 { // 3 iterations per test case
            modules := generate_independent_modules(test_case.count, test_case.priorities)
            defer {
                manifest.cleanup_modules(modules[:])
                delete(modules)
            }
            
            // Resolve modules
            resolved, err := loader.resolve(modules)
            
            // Property: Resolution should succeed for independent modules
            testing.expect(t, len(err) == 0, 
                fmt.tprintf("Independent modules resolution should succeed (count=%d, iter=%d), got error: %s", 
                    test_case.count, iteration, err))
            
            if len(err) == 0 {
                // Property: All modules should be included
                testing.expect_value(t, len(resolved), test_case.count)
                
                // Property: Modules should be ordered by priority
                for i in 0..<len(resolved)-1 {
                    current_priority := resolved[i].priority
                    next_priority := resolved[i+1].priority
                    
                    testing.expect(t, current_priority <= next_priority, 
                        fmt.tprintf("Independent module '%s' (priority %d) should come before '%s' (priority %d) (iter %d)", 
                            resolved[i].name, current_priority, resolved[i+1].name, next_priority, iteration))
                }
                
                // Property: Check overall priority ordering correctness
                check_priority_ordering(t, resolved[:], fmt.tprintf("Independent modules (count=%d, iter=%d)", test_case.count, iteration))
            }
        }
    }
}

// **Validates: Requirements 3.3.1, 3.3.4**
@(test)
test_property_priority_ordering_with_dependencies :: proc(t: ^testing.T) {
    // Property: Dependencies must be satisfied regardless of priority
    // Property: Within dependency constraints, priority should determine order
    
    chain_lengths := []int{3, 4, 5}
    
    for chain_length in chain_lengths {
        for iteration in 0..<3 { // 3 iterations per chain length
            // Create priorities that are reverse of dependency order
            // This tests that dependencies override priority
            priorities := make([]int, chain_length)
            defer delete(priorities)
            
            for i in 0..<chain_length {
                priorities[i] = (chain_length - i) * 10 // Higher priority for later modules
            }
            
            modules := generate_chain_modules(chain_length, priorities)
            defer {
                manifest.cleanup_modules(modules[:])
                delete(modules)
            }
            
            // Resolve modules
            resolved, err := loader.resolve(modules)
            
            // Property: Resolution should succeed for chain dependencies
            testing.expect(t, len(err) == 0, 
                fmt.tprintf("Chain modules resolution should succeed (length=%d, iter=%d), got error: %s", 
                    chain_length, iteration, err))
            
            if len(err) == 0 {
                // Property: All modules should be included
                testing.expect_value(t, len(resolved), chain_length)
                
                // Property: Dependencies must be satisfied (chain order)
                for i in 0..<len(resolved) {
                    expected_name := fmt.tprintf("chain-%d", i)
                    testing.expect_value(t, resolved[i].name, expected_name)
                }
                
                // Property: Check overall ordering correctness
                check_priority_ordering(t, resolved[:], fmt.tprintf("Chain modules (length=%d, iter=%d)", chain_length, iteration))
            }
        }
    }
}

// **Validates: Requirements 3.3.1, 3.3.4**
@(test)
test_property_priority_ordering_tree_structure :: proc(t: ^testing.T) {
    // Property: Tree dependency structures should be resolved correctly
    // Property: Priority should determine order within each dependency level
    
    tree_levels := []int{2, 3}
    
    for tree_level in tree_levels {
        for iteration in 0..<3 { // 3 iterations per tree level
            modules := generate_tree_modules(tree_level)
            defer {
                manifest.cleanup_modules(modules[:])
                delete(modules)
            }
            
            // Resolve modules
            resolved, err := loader.resolve(modules)
            
            // Property: Resolution should succeed for tree structures
            testing.expect(t, len(err) == 0, 
                fmt.tprintf("Tree modules resolution should succeed (levels=%d, iter=%d), got error: %s", 
                    tree_level, iteration, err))
            
            if len(err) == 0 {
                // Property: All modules should be included
                expected_count := 1 + 2 // root + level1
                if tree_level >= 3 {
                    expected_count += 4 // level2
                }
                testing.expect_value(t, len(resolved), expected_count)
                
                // Property: Root should come first
                testing.expect_value(t, resolved[0].name, "root")
                
                // Property: Level 1 modules should come after root but before level 2
                root_pos := 0
                level1_positions := make([dynamic]int)
                level2_positions := make([dynamic]int)
                defer delete(level1_positions)
                defer delete(level2_positions)
                
                for module, idx in resolved {
                    if strings.has_prefix(module.name, "level1-") {
                        append(&level1_positions, idx)
                    } else if strings.has_prefix(module.name, "level2-") {
                        append(&level2_positions, idx)
                    }
                }
                
                // Property: All level1 modules should come after root
                for pos in level1_positions {
                    testing.expect(t, pos > root_pos, 
                        fmt.tprintf("Level1 module at position %d should come after root at position %d", pos, root_pos))
                }
                
                // Property: All level2 modules should come after all level1 modules
                if len(level2_positions) > 0 && len(level1_positions) > 0 {
                    max_level1_pos := 0
                    for pos in level1_positions {
                        if pos > max_level1_pos {
                            max_level1_pos = pos
                        }
                    }
                    
                    for pos in level2_positions {
                        testing.expect(t, pos > max_level1_pos, 
                            fmt.tprintf("Level2 module at position %d should come after all level1 modules (max pos %d)", pos, max_level1_pos))
                    }
                }
                
                // Property: Check overall ordering correctness
                check_priority_ordering(t, resolved[:], fmt.tprintf("Tree modules (levels=%d, iter=%d)", tree_level, iteration))
            }
        }
    }
}

// **Validates: Requirements 3.3.4**
@(test)
test_property_priority_ordering_mixed_scenarios :: proc(t: ^testing.T) {
    // Property: Complex scenarios with mixed dependencies and priorities should be handled correctly
    // Property: Priority ordering should be stable and consistent
    
    for iteration in 0..<5 { // 5 iterations of mixed scenarios
        modules := make([dynamic]manifest.Module)
        defer {
            manifest.cleanup_modules(modules[:])
            delete(modules)
        }
        
        // Create a base module (no dependencies, medium priority)
        base := generate_priority_module("base", 50, {})
        append(&modules, base)
        
        // Create high priority modules that depend on base
        high1 := generate_priority_module("high-1", 10, {"base"})
        high2 := generate_priority_module("high-2", 15, {"base"})
        append(&modules, high1)
        append(&modules, high2)
        
        // Create low priority modules that depend on base
        low1 := generate_priority_module("low-1", 80, {"base"})
        low2 := generate_priority_module("low-2", 85, {"base"})
        append(&modules, low1)
        append(&modules, low2)
        
        // Create independent modules with various priorities
        indep1 := generate_priority_module("independent-1", 5, {})
        indep2 := generate_priority_module("independent-2", 90, {})
        append(&modules, indep1)
        append(&modules, indep2)
        
        // Resolve modules
        resolved, err := loader.resolve(modules)
        
        // Property: Resolution should succeed for mixed scenarios
        testing.expect(t, len(err) == 0, 
            fmt.tprintf("Mixed scenario resolution should succeed (iter=%d), got error: %s", iteration, err))
        
        if len(err) == 0 {
            // Property: All modules should be included
            testing.expect_value(t, len(resolved), 7)
            
            // Property: Independent module with priority 5 should come first
            testing.expect_value(t, resolved[0].name, "independent-1")
            
            // Property: Base should come before its dependents
            base_pos := -1
            for module, idx in resolved {
                if module.name == "base" {
                    base_pos = idx
                    break
                }
            }
            
            testing.expect(t, base_pos >= 0, "Base module should be found in resolved order")
            
            // Property: All modules depending on base should come after base
            dependent_names := []string{"high-1", "high-2", "low-1", "low-2"}
            for dep_name in dependent_names {
                for module, idx in resolved {
                    if module.name == dep_name {
                        testing.expect(t, idx > base_pos, 
                            fmt.tprintf("Dependent module '%s' (pos %d) should come after base (pos %d)", dep_name, idx, base_pos))
                        break
                    }
                }
            }
            
            // Property: Among dependents of base, priority should determine order
            high_positions := make([dynamic]int)
            low_positions := make([dynamic]int)
            defer delete(high_positions)
            defer delete(low_positions)
            
            for module, idx in resolved {
                if strings.has_prefix(module.name, "high-") {
                    append(&high_positions, idx)
                } else if strings.has_prefix(module.name, "low-") {
                    append(&low_positions, idx)
                }
            }
            
            // High priority modules should generally come before low priority ones
            if len(high_positions) > 0 && len(low_positions) > 0 {
                max_high_pos := 0
                for pos in high_positions {
                    if pos > max_high_pos {
                        max_high_pos = pos
                    }
                }
                
                min_low_pos := len(resolved)
                for pos in low_positions {
                    if pos < min_low_pos {
                        min_low_pos = pos
                    }
                }
                
                testing.expect(t, max_high_pos < min_low_pos, 
                    fmt.tprintf("High priority modules should come before low priority modules (max high: %d, min low: %d)", max_high_pos, min_low_pos))
            }
            
            // Property: Check overall ordering correctness
            check_priority_ordering(t, resolved[:], fmt.tprintf("Mixed scenario (iter=%d)", iteration))
        }
    }
}