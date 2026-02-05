package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"
import "../src/loader"
import "../src/manifest"

// Helper function to create a performance test module
create_performance_test_module :: proc(base_dir: string, module_name: string, priority: int, dependencies: []string) -> bool {
    module_dir := filepath.join({base_dir, module_name})
    
    // Debug: Check if directory creation succeeds
    err := os.make_directory(module_dir, 0o755)
    if err != os.ERROR_NONE {
        fmt.printf("Failed to create directory %s: %v\n", module_dir, err)
        return false
    }
    
    // Create manifest content
    manifest_builder := strings.builder_make()
    defer strings.builder_destroy(&manifest_builder)
    
    strings.write_string(&manifest_builder, fmt.tprintf(`[module]
name = "%s"
version = "1.0.0"
description = "Test module %s"

[load]
priority = %d
files = ["%s.zsh"]
`, module_name, module_name, priority, module_name))
    
    // Add dependencies if any
    if len(dependencies) > 0 {
        strings.write_string(&manifest_builder, "\n[dependencies]\nrequired = [")
        for dep, i in dependencies {
            if i > 0 do strings.write_string(&manifest_builder, ", ")
            strings.write_string(&manifest_builder, fmt.tprintf(`"%s"`, dep))
        }
        strings.write_string(&manifest_builder, "]\n")
    }
    
    // Clone the string before the builder is destroyed
    manifest_content := strings.clone(strings.to_string(manifest_builder))
    defer delete(manifest_content)
    
    manifest_path := filepath.join({module_dir, "module.toml"})
    
    // Debug: Check if file write succeeds
    if !os.write_entire_file(manifest_path, transmute([]u8)manifest_content) {
        fmt.printf("Failed to write manifest file %s\n", manifest_path)
        return false
    }
    
    // Create shell file
    shell_content := fmt.tprintf("# Shell file for %s\necho 'Loading %s'", module_name, module_name)
    defer delete(shell_content) // Clean up shell content
    
    shell_filename := fmt.tprintf("%s.zsh", module_name)
    defer delete(shell_filename) // Clean up filename
    
    shell_path := filepath.join({module_dir, shell_filename})
    defer delete(shell_path) // Clean up the path
    
    // Debug: Check if shell file write succeeds
    if !os.write_entire_file(shell_path, transmute([]u8)shell_content) {
        fmt.printf("Failed to write shell file %s\n", shell_path)
        return false
    }
    
    return true
}

@(test)
test_large_module_set_discovery :: proc(t: ^testing.T) {
    // Test discovery performance with many modules
    temp_dir := "test_temp_large_discovery"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create a large number of modules
    module_count := 100
    
    fmt.printf("Creating %d test modules...\n", module_count)
    start_time := time.now()
    
    for i in 0..<module_count {
        module_name := fmt.tprintf("module_%03d", i)
        success := create_performance_test_module(temp_dir, module_name, i * 10, {})
        testing.expect(t, success, fmt.tprintf("Should create module %s", module_name))
    }
    
    creation_time := time.since(start_time)
    fmt.printf("Module creation took: %v\n", creation_time)
    
    // Test discovery performance
    fmt.printf("Starting discovery of %d modules...\n", module_count)
    discovery_start := time.now()
    
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    discovery_time := time.since(discovery_start)
    fmt.printf("Discovery took: %v\n", discovery_time)
    
    testing.expect(t, len(modules) == module_count, 
                   fmt.tprintf("Should discover all %d modules, found %d", module_count, len(modules)))
    
    // Performance expectation: discovery should complete in reasonable time
    // For 100 modules, should be well under 1 second on modern hardware
    max_discovery_time := time.Millisecond * 500
    testing.expect(t, discovery_time < max_discovery_time, 
                   fmt.tprintf("Discovery should complete in under %v, took %v", max_discovery_time, discovery_time))
}

@(test)
test_large_dependency_resolution :: proc(t: ^testing.T) {
    // Test dependency resolution performance with complex dependency graph
    temp_dir := "test_temp_large_resolution"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create modules with layered dependencies
    layer_count := 10
    modules_per_layer := 5
    total_modules := layer_count * modules_per_layer
    
    fmt.printf("Creating %d modules in %d layers...\n", total_modules, layer_count)
    
    for layer in 0..<layer_count {
        for module_in_layer in 0..<modules_per_layer {
            module_name := fmt.tprintf("layer_%d_module_%d", layer, module_in_layer)
            
            // Create dependencies on previous layer
            dependencies := make([dynamic]string)
            defer delete(dependencies)
            
            if layer > 0 {
                // Depend on some modules from the previous layer
                for prev_module in 0..<min(modules_per_layer, 3) {
                    prev_name := fmt.tprintf("layer_%d_module_%d", layer - 1, prev_module)
                    append(&dependencies, prev_name)
                }
            }
            
            priority := layer * 100 + module_in_layer
            success := create_performance_test_module(temp_dir, module_name, priority, dependencies[:])
            testing.expect(t, success, fmt.tprintf("Should create module %s", module_name))
        }
    }
    
    // Test discovery
    fmt.printf("Starting discovery...\n")
    discovery_start := time.now()
    
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    discovery_time := time.since(discovery_start)
    fmt.printf("Discovery took: %v\n", discovery_time)
    
    testing.expect(t, len(modules) == total_modules, 
                   fmt.tprintf("Should discover all %d modules", total_modules))
    
    // Test resolution performance
    fmt.printf("Starting resolution of %d modules with dependencies...\n", total_modules)
    resolution_start := time.now()
    
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    resolution_time := time.since(resolution_start)
    fmt.printf("Resolution took: %v\n", resolution_time)
    
    testing.expect(t, err == "", "Should resolve complex dependency graph successfully")
    testing.expect(t, len(resolved_modules) == total_modules, 
                   "Should resolve all modules")
    
    // Performance expectation: resolution should complete in reasonable time
    max_resolution_time := time.Second * 2
    testing.expect(t, resolution_time < max_resolution_time, 
                   fmt.tprintf("Resolution should complete in under %v, took %v", max_resolution_time, resolution_time))
    
    // Verify dependency ordering
    fmt.printf("Verifying dependency ordering...\n")
    verify_start := time.now()
    
    module_positions := make(map[string]int)
    defer delete(module_positions)
    
    for module, i in resolved_modules {
        module_positions[module.name] = i
    }
    
    // Check that dependencies come before dependents
    for module in resolved_modules {
        for dep in module.required {
            dep_pos, dep_exists := module_positions[dep]
            module_pos := module_positions[module.name]
            
            testing.expect(t, dep_exists, fmt.tprintf("Dependency %s should exist", dep))
            testing.expect(t, dep_pos < module_pos, 
                           fmt.tprintf("Dependency %s (pos %d) should come before %s (pos %d)", 
                                       dep, dep_pos, module.name, module_pos))
        }
    }
    
    verify_time := time.since(verify_start)
    fmt.printf("Verification took: %v\n", verify_time)
}

@(test)
test_shell_code_generation_performance :: proc(t: ^testing.T) {
    // Test shell code generation performance with many modules
    temp_dir := "test_temp_large_generation"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create modules with various settings
    module_count := 50
    
    fmt.printf("Creating %d modules with settings...\n", module_count)
    
    for i in 0..<module_count {
        module_name := fmt.tprintf("gen_module_%03d", i)
        module_dir := filepath.join({temp_dir, module_name})
        os.make_directory(module_dir, 0o755)
        
        // Create manifest with multiple settings
        manifest_content := fmt.tprintf(`[module]
name = "%s"
version = "1.0.0"
description = "Generation test module %d"

[load]
priority = %d
files = ["init.zsh", "config.zsh", "utils.zsh"]

[settings]
setting_1 = "value_%d_1"
setting_2 = "value_%d_2"
setting_3 = "value_%d_3"
path_setting = "/path/to/%s"
number_setting = "%d"
`, module_name, i, i * 10, i, i, i, module_name, i)
        
        manifest_path := filepath.join({module_dir, "module.toml"})
        os.write_entire_file(manifest_path, transmute([]u8)manifest_content)
        
        // Create multiple shell files
        shell_files := [3]string{"init.zsh", "config.zsh", "utils.zsh"}
        for file_name in shell_files {
            shell_content := fmt.tprintf("# %s for %s\necho 'Loading %s from %s'", 
                                         file_name, module_name, file_name, module_name)
            shell_path := filepath.join({module_dir, file_name})
            os.write_entire_file(shell_path, transmute([]u8)shell_content)
        }
    }
    
    // Test discovery and resolution
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    testing.expect(t, err == "", "Should resolve modules for generation test")
    
    // Test shell code generation performance
    fmt.printf("Starting shell code generation for %d modules...\n", len(resolved_modules))
    generation_start := time.now()
    
    // Note: loader.emit() writes to stdout, so we can't easily capture timing
    // For performance testing, we'll just call it and measure the time
    loader.emit(resolved_modules)
    
    generation_time := time.since(generation_start)
    fmt.printf("Shell code generation took: %v\n", generation_time)
    
    // Performance expectation: generation should be fast
    max_generation_time := time.Millisecond * 100
    testing.expect(t, generation_time < max_generation_time, 
                   fmt.tprintf("Generation should complete in under %v, took %v", max_generation_time, generation_time))
}

@(test)
test_memory_usage_with_large_sets :: proc(t: ^testing.T) {
    // Test memory usage patterns with large module sets
    temp_dir := "test_temp_memory"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create a moderate number of modules for memory testing
    module_count := 75
    
    fmt.printf("Testing memory usage with %d modules...\n", module_count)
    
    for i in 0..<module_count {
        module_name := fmt.tprintf("mem_module_%03d", i)
        
        // Create dependencies to previous modules (creates more complex memory patterns)
        dependencies := make([dynamic]string)
        defer delete(dependencies)
        
        if i > 0 {
            // Each module depends on 1-3 previous modules
            dep_count := min(i, 3)
            for j in 0..<dep_count {
                dep_name := fmt.tprintf("mem_module_%03d", i - j - 1)
                append(&dependencies, dep_name)
            }
        }
        
        success := create_performance_test_module(temp_dir, module_name, i * 10, dependencies[:])
        testing.expect(t, success, fmt.tprintf("Should create module %s", module_name))
    }
    
    // Test multiple discovery/resolution cycles to check for memory leaks
    fmt.printf("Running multiple discovery/resolution cycles...\n")
    
    for cycle in 0..<5 {
        cycle_start := time.now()
        
        modules := loader.discover(temp_dir)
        testing.expect(t, len(modules) == module_count, "Should discover all modules in each cycle")
        
        resolved_modules, err := loader.resolve(modules)
        testing.expect(t, err == "", "Should resolve successfully in each cycle")
        testing.expect(t, len(resolved_modules) == module_count, "Should resolve all modules in each cycle")
        
        // Clean up
        if resolved_modules != nil {
            delete(resolved_modules)
        }
        manifest.cleanup_modules(modules[:])
        delete(modules)
        
        cycle_time := time.since(cycle_start)
        fmt.printf("Cycle %d took: %v\n", cycle + 1, cycle_time)
        
        // Each cycle should complete in reasonable time
        max_cycle_time := time.Second * 1
        testing.expect(t, cycle_time < max_cycle_time, 
                       fmt.tprintf("Cycle %d should complete in under %v, took %v", cycle + 1, max_cycle_time, cycle_time))
    }
    
    fmt.printf("Memory usage test completed successfully\n")
}

@(test)
test_deep_dependency_chains :: proc(t: ^testing.T) {
    // Test performance with deep dependency chains
    temp_dir := "test_temp_deep_deps"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create a chain of dependencies: module_0 -> module_1 -> ... -> module_N
    chain_length := 25
    
    fmt.printf("Creating dependency chain of length %d...\n", chain_length)
    
    for i in 0..<chain_length {
        module_name := fmt.tprintf("chain_module_%02d", i)
        
        dependencies := make([dynamic]string)
        defer delete(dependencies)
        
        if i > 0 {
            // Each module depends on the previous one in the chain
            prev_name := fmt.tprintf("chain_module_%02d", i - 1)
            append(&dependencies, prev_name)
        }
        
        success := create_performance_test_module(temp_dir, module_name, i, dependencies[:])
        testing.expect(t, success, fmt.tprintf("Should create chain module %s", module_name))
    }
    
    // Test resolution of deep dependency chain
    fmt.printf("Resolving deep dependency chain...\n")
    resolution_start := time.now()
    
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    resolution_time := time.since(resolution_start)
    fmt.printf("Deep chain resolution took: %v\n", resolution_time)
    
    testing.expect(t, err == "", "Should resolve deep dependency chain successfully")
    testing.expect(t, len(resolved_modules) == chain_length, "Should resolve all chain modules")
    
    // Verify the chain order is correct
    for i in 0..<chain_length {
        expected_name := fmt.tprintf("chain_module_%02d", i)
        actual_name := resolved_modules[i].name
        testing.expect(t, actual_name == expected_name, 
                       fmt.tprintf("Module at position %d should be %s, got %s", i, expected_name, actual_name))
    }
    
    // Performance expectation: even deep chains should resolve quickly
    max_chain_resolution_time := time.Millisecond * 50
    testing.expect(t, resolution_time < max_chain_resolution_time, 
                   fmt.tprintf("Deep chain resolution should complete in under %v, took %v", 
                               max_chain_resolution_time, resolution_time))
}

@(test)
test_performance_requirements_with_optimizations :: proc(t: ^testing.T) {
    // Test the optimized performance with all improvements
    temp_dir := "test_temp_optimized_performance"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create exactly 49 modules (< 50 as per requirement 4.1.1)
    module_count := 49
    
    fmt.printf("Testing optimized performance with %d modules (< 50)...\n", module_count)
    
    // Create modules with realistic complexity and dependencies
    for i in 0..<module_count {
        module_name := fmt.tprintf("opt_module_%02d", i)
        
        dependencies := make([dynamic]string)
        defer delete(dependencies)
        
        // Create realistic dependency patterns
        if i > 0 && i % 4 == 0 {
            dep_count := min(i, 3)
            for j in 0..<dep_count {
                dep_name := fmt.tprintf("opt_module_%02d", (i - j - 1) % i)
                append(&dependencies, dep_name)
            }
        }
        
        priority := (i % 10) * 10
        success := create_performance_test_module(temp_dir, module_name, priority, dependencies[:])
        testing.expect(t, success, fmt.tprintf("Should create optimized test module %s", module_name))
    }
    
    // Run comprehensive benchmark
    fmt.printf("Running comprehensive performance benchmark...\n")
    
    // Test multiple cycles to verify consistency
    cycle_times := make([dynamic]time.Duration, 0, 5)
    defer delete(cycle_times)
    
    for cycle in 0..<5 {
        cycle_start := time.now()
        
        // Complete load cycle with optimizations
        modules := loader.discover(temp_dir)
        defer {
            manifest.cleanup_modules(modules[:])
            delete(modules)
        }
        
        testing.expect(t, len(modules) == module_count, 
                       fmt.tprintf("Cycle %d: Should discover all %d modules", cycle + 1, module_count))
        
        resolved_modules, err := loader.resolve(modules)
        defer {
            if resolved_modules != nil {
                delete(resolved_modules)
            }
        }
        
        testing.expect(t, err == "", fmt.tprintf("Cycle %d: Should resolve successfully", cycle + 1))
        testing.expect(t, len(resolved_modules) == module_count, 
                       fmt.tprintf("Cycle %d: Should resolve all modules", cycle + 1))
        
        cycle_time := time.since(cycle_start)
        append(&cycle_times, cycle_time)
        
        fmt.printf("Cycle %d: %v\n", cycle + 1, cycle_time)
    }
    
    // Analyze performance
    total_time := time.Duration(0)
    min_time := cycle_times[0]
    max_time := cycle_times[0]
    
    for cycle_time in cycle_times {
        total_time += cycle_time
        if cycle_time < min_time {
            min_time = cycle_time
        }
        if cycle_time > max_time {
            max_time = cycle_time
        }
    }
    
    avg_time := total_time / time.Duration(len(cycle_times))
    
    fmt.printf("Performance Analysis:\n")
    fmt.printf("  Average: %v\n", avg_time)
    fmt.printf("  Minimum: %v\n", min_time)
    fmt.printf("  Maximum: %v\n", max_time)
    fmt.printf("  Variance: %v\n", max_time - min_time)
    
    // CRITICAL: Test the performance requirement 4.1.1
    max_allowed_time := time.Millisecond * 100
    
    // All cycles should meet the requirement
    requirement_met := true
    for i, cycle_time in cycle_times {
        cycle_duration := time.Duration(cycle_time) * time.Millisecond
        if cycle_duration >= max_allowed_time {
            fmt.printf("✗ Cycle %d failed requirement: %v >= 100ms\n", i + 1, cycle_duration)
            requirement_met = false
        } else {
            fmt.printf("✓ Cycle %d met requirement: %v < 100ms\n", i + 1, cycle_duration)
        }
    }
    
    testing.expect(t, requirement_met, 
                   fmt.tprintf("REQUIREMENT 4.1.1: All cycles must complete in under 100ms. Average: %v", avg_time))
    
    // Test cache effectiveness (second run should be faster)
    if len(cycle_times) >= 2 {
        first_run := cycle_times[0]
        second_run := cycle_times[1]
        
        if second_run < first_run {
            speedup := time.duration_seconds(first_run) / time.duration_seconds(second_run)
            fmt.printf("✓ Cache speedup detected: %.2fx faster on second run\n", speedup)
        } else {
            fmt.printf("⚠ No cache speedup detected (first: %v, second: %v)\n", first_run, second_run)
        }
    }
    
    if requirement_met {
        fmt.printf("✓ OPTIMIZED PERFORMANCE REQUIREMENT 4.1.1 SATISFIED\n")
        fmt.printf("  All optimizations working correctly\n")
        fmt.printf("  Average processing time: %v (< 100ms)\n", avg_time)
    } else {
        fmt.printf("✗ OPTIMIZED PERFORMANCE REQUIREMENT 4.1.1 FAILED\n")
        fmt.printf("  Optimizations may need further tuning\n")
        fmt.printf("  Average processing time: %v (>= 100ms)\n", avg_time)
    }
}

@(test)
test_benchmark_suite_integration :: proc(t: ^testing.T) {
    // Test the benchmark suite with a small test dataset
    temp_dir := "test_temp_benchmark_suite"
    
    // Clean up any existing directory first
    remove_directory_recursive(temp_dir)
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create a small set of test modules
    module_count := 10
    
    for i in 0..<module_count {
        module_name := fmt.tprintf("bench_module_%02d", i)
        
        dependencies := make([dynamic]string)
        defer delete(dependencies)
        
        if i > 0 && i % 3 == 0 {
            dep_name := fmt.tprintf("bench_module_%02d", i - 1)
            append(&dependencies, dep_name)
        }
        
        success := create_performance_test_module(temp_dir, module_name, i * 10, dependencies[:])
        testing.expect(t, success, fmt.tprintf("Should create benchmark test module %s", module_name))
    }
    
    // Run the benchmark suite
    fmt.printf("Running benchmark suite integration test...\n")
    
    benchmark_passed := loader.run_performance_requirements_benchmark(temp_dir)
    
    // The benchmark should pass for this small dataset
    testing.expect(t, benchmark_passed, "Benchmark suite should pass for small test dataset")
    
    fmt.printf("Benchmark suite integration test completed\n")
}

@(test)
test_scalability_beyond_requirement :: proc(t: ^testing.T) {
    // Test scalability beyond the basic requirement to understand system limits
    temp_dir := "test_temp_scalability"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Test with progressively larger module sets
    test_sizes := []int{50, 100, 200, 500}
    
    for size in test_sizes {
        fmt.printf("\n=== Testing scalability with %d modules ===\n", size)
        
        // Clean up previous test
        remove_directory_recursive(temp_dir)
        os.make_directory(temp_dir, 0o755)
        
        // Create modules
        creation_start := time.now()
        for i in 0..<size {
            module_name := fmt.tprintf("scale_module_%03d", i)
            
            // Create some dependencies for realism
            dependencies := make([dynamic]string)
            defer delete(dependencies)
            
            if i > 0 && i % 5 == 0 {
                // Every 5th module depends on 1-3 previous modules
                dep_count := min(i, 3)
                for j in 0..<dep_count {
                    dep_idx := (i - j - 1) % i
                    dep_name := fmt.tprintf("scale_module_%03d", dep_idx)
                    append(&dependencies, dep_name)
                }
            }
            
            success := create_performance_test_module(temp_dir, module_name, i % 100, dependencies[:])
            if !success {
                fmt.printf("Failed to create module %s\n", module_name)
                break
            }
        }
        creation_time := time.since(creation_start)
        fmt.printf("Module creation took: %v\n", creation_time)
        
        // Test discovery performance
        discovery_start := time.now()
        modules := loader.discover(temp_dir)
        discovery_time := time.since(discovery_start)
        fmt.printf("Discovery of %d modules took: %v\n", len(modules), discovery_time)
        
        if len(modules) != size {
            fmt.printf("Warning: Expected %d modules, found %d\n", size, len(modules))
        }
        
        // Test resolution performance
        resolution_start := time.now()
        resolved_modules, err := loader.resolve(modules)
        resolution_time := time.since(resolution_start)
        fmt.printf("Resolution took: %v\n", resolution_time)
        
        if err != "" {
            fmt.printf("Resolution failed: %s\n", err)
            testing.expect(t, false, fmt.tprintf("Resolution should succeed for %d modules", size))
        } else {
            fmt.printf("Successfully resolved %d modules\n", len(resolved_modules))
            
            // Calculate performance metrics
            total_time := discovery_time + resolution_time
            modules_per_second := f64(size) / time.duration_seconds(total_time)
            
            fmt.printf("Total processing time: %v\n", total_time)
            fmt.printf("Processing rate: %.1f modules/second\n", modules_per_second)
            
            // Performance expectations based on size
            max_expected_time: time.Duration
            switch {
            case size <= 50:
                max_expected_time = time.Millisecond * 100  // Requirement compliance
            case size <= 100:
                max_expected_time = time.Millisecond * 200  // Should still be very fast
            case size <= 200:
                max_expected_time = time.Millisecond * 500  // Reasonable for larger sets
            case size <= 500:
                max_expected_time = time.Second * 2         // Acceptable for very large sets
            }
            
            if total_time <= max_expected_time {
                fmt.printf("✓ Performance acceptable for %d modules: %v <= %v\n", 
                          size, total_time, max_expected_time)
            } else {
                fmt.printf("⚠ Performance concern for %d modules: %v > %v\n", 
                          size, total_time, max_expected_time)
                // Don't fail the test for large sets, just warn
                if size <= 50 {
                    testing.expect(t, false, fmt.tprintf("Performance requirement violated for %d modules", size))
                }
            }
        }
        
        // Clean up
        if resolved_modules != nil {
            delete(resolved_modules)
        }
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
}

@(test)
test_stress_with_complex_dependencies :: proc(t: ^testing.T) {
    // Stress test with complex dependency patterns
    temp_dir := "test_temp_stress"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create a complex dependency graph with multiple patterns
    module_count := 80
    
    fmt.printf("Creating stress test with %d modules and complex dependencies...\n", module_count)
    
    for i in 0..<module_count {
        module_name := fmt.tprintf("stress_module_%02d", i)
        
        dependencies := make([dynamic]string)
        defer delete(dependencies)
        
        // Create various dependency patterns
        switch i % 7 {
        case 0:
            // No dependencies (base modules)
        case 1, 2:
            // Depend on base modules
            if i >= 7 {
                base_idx := (i / 7) * 7
                base_name := fmt.tprintf("stress_module_%02d", base_idx)
                append(&dependencies, base_name)
            }
        case 3, 4:
            // Depend on multiple previous modules
            if i >= 2 {
                for j in 0..<min(i, 3) {
                    dep_idx := i - j - 1
                    dep_name := fmt.tprintf("stress_module_%02d", dep_idx)
                    append(&dependencies, dep_name)
                }
            }
        case 5:
            // Depend on modules from different "layers"
            if i >= 10 {
                append(&dependencies, fmt.tprintf("stress_module_%02d", i - 5))
                append(&dependencies, fmt.tprintf("stress_module_%02d", i - 10))
            }
        case 6:
            // Depend on a mix of recent and distant modules
            if i >= 15 {
                append(&dependencies, fmt.tprintf("stress_module_%02d", i - 1))
                append(&dependencies, fmt.tprintf("stress_module_%02d", i - 7))
                append(&dependencies, fmt.tprintf("stress_module_%02d", i - 14))
            }
        }
        
        priority := (i * 13) % 100  // Pseudo-random priorities
        success := create_performance_test_module(temp_dir, module_name, priority, dependencies[:])
        testing.expect(t, success, fmt.tprintf("Should create stress test module %s", module_name))
    }
    
    // Run the stress test
    fmt.printf("Running stress test with complex dependency resolution...\n")
    
    stress_start := time.now()
    
    modules := loader.discover(temp_dir)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    testing.expect(t, len(modules) == module_count, "Should discover all stress test modules")
    
    resolved_modules, err := loader.resolve(modules)
    defer {
        if resolved_modules != nil {
            delete(resolved_modules)
        }
    }
    
    stress_time := time.since(stress_start)
    fmt.printf("Stress test completed in: %v\n", stress_time)
    
    testing.expect(t, err == "", fmt.tprintf("Should resolve complex dependency graph: %s", err))
    testing.expect(t, len(resolved_modules) == module_count, "Should resolve all modules in stress test")
    
    // Verify dependency ordering is correct
    module_positions := make(map[string]int)
    defer delete(module_positions)
    
    for module, pos in resolved_modules {
        module_positions[module.name] = pos
    }
    
    dependency_violations := 0
    for module in resolved_modules {
        for dep in module.required {
            dep_pos, dep_exists := module_positions[dep]
            module_pos := module_positions[module.name]
            
            if !dep_exists {
                fmt.printf("Missing dependency: %s requires %s\n", module.name, dep)
                dependency_violations += 1
            } else if dep_pos >= module_pos {
                fmt.printf("Dependency order violation: %s (pos %d) should come before %s (pos %d)\n", 
                          dep, dep_pos, module.name, module_pos)
                dependency_violations += 1
            }
        }
    }
    
    testing.expect(t, dependency_violations == 0, 
                   fmt.tprintf("Should have no dependency violations, found %d", dependency_violations))
    
    // Performance expectation for stress test
    max_stress_time := time.Second * 3
    testing.expect(t, stress_time < max_stress_time, 
                   fmt.tprintf("Stress test should complete in under %v, took %v", max_stress_time, stress_time))
    
    fmt.printf("✓ Stress test passed: %d modules with complex dependencies resolved in %v\n", 
               module_count, stress_time)
}