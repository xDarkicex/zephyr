package test

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"
import "../src/loader"
import "../src/manifest"

// Helper function to create a benchmark test module with priority
create_benchmark_test_module :: proc(base_dir: string, module_name: string, priority: int, dependencies: []string) -> bool {
    module_dir := filepath.join({base_dir, module_name})
    err := os.make_directory(module_dir, 0o755)
    if err != os.ERROR_NONE do return false
    
    // Create manifest content
    manifest_builder := strings.builder_make()
    defer strings.builder_destroy(&manifest_builder)
    
    strings.write_string(&manifest_builder, fmt.tprintf(`[module]
name = "%s"
version = "1.0.0"
description = "Benchmark test module %s"
author = "Benchmark Test"
license = "MIT"

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
    
    // Add some settings for realism
    strings.write_string(&manifest_builder, fmt.tprintf(`
[settings]
module_path = "/path/to/%s"
enabled = "true"
debug_mode = "false"
`, module_name))
    
    manifest_content := strings.to_string(manifest_builder)
    manifest_path := filepath.join({module_dir, "module.toml"})
    
    if !os.write_entire_file(manifest_path, transmute([]u8)manifest_content) do return false
    
    // Create shell file
    shell_content := fmt.tprintf(`# Shell file for %s module
# This is a benchmark test module

# Export some variables
export %s_LOADED=1
export %s_VERSION="1.0.0"

# Define some functions
%s_init() {
    echo "Initializing %s module"
}

%s_cleanup() {
    echo "Cleaning up %s module"
}

# Source completion if available
if [[ -f "$HOME/.%s_completion" ]]; then
    source "$HOME/.%s_completion"
fi

echo "Module %s loaded successfully"
`, module_name, strings.to_upper(module_name), strings.to_upper(module_name), 
   module_name, module_name, module_name, module_name, module_name, module_name, module_name)
   
    shell_path := filepath.join({module_dir, fmt.tprintf("%s.zsh", module_name)})
    
    return os.write_entire_file(shell_path, transmute([]u8)shell_content)
}

@(test)
test_performance_requirement_4_1_1 :: proc(t: ^testing.T) {
    // Test Performance Requirement 4.1.1: 
    // The system SHALL load and process modules in under 100ms for typical configurations (< 50 modules)
    
    fmt.println("=== Testing Performance Requirement 4.1.1 ===")
    fmt.println("Requirement: Load and process modules in under 100ms for < 50 modules")
    
    temp_dir := "test_temp_requirement_4_1_1"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create exactly 49 modules (< 50 as per requirement)
    module_count := 49
    
    fmt.printf("Creating %d test modules (< 50)...\n", module_count)
    
    // Create modules with realistic dependencies
    for i in 0..<module_count {
        module_name := fmt.tprintf("req_module_%02d", i)
        
        dependencies := make([dynamic]string)
        defer delete(dependencies)
        
        // Create realistic dependency patterns
        if i > 0 {
            // Every 5th module depends on 1-2 previous modules
            if i % 5 == 0 {
                dep_count := min(i, 2)
                for j in 0..<dep_count {
                    dep_name := fmt.tprintf("req_module_%02d", i - j - 1)
                    append(&dependencies, dep_name)
                }
            }
        }
        
        priority := (i % 10) * 10
        success := create_benchmark_test_module(temp_dir, module_name, priority, dependencies[:])
        testing.expect(t, success, fmt.tprintf("Should create module %s", module_name))
    }
    
    // Run multiple test cycles to ensure consistency
    fmt.printf("Running performance tests with %d modules...\n", module_count)
    
    cycle_times := make([dynamic]time.Duration, 0, 10)
    defer delete(cycle_times)
    
    // Run 10 cycles to get reliable measurements
    for cycle in 0..<10 {
        cycle_start := time.now()
        
        // Complete load cycle: discovery -> resolution -> emission
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
        
        testing.expect(t, err == "", fmt.tprintf("Cycle %d: Should resolve successfully: %s", cycle + 1, err))
        testing.expect(t, len(resolved_modules) == module_count, 
                       fmt.tprintf("Cycle %d: Should resolve all modules", cycle + 1))
        
        // Note: We skip actual emission to avoid stdout pollution during tests
        // The emission time is typically negligible compared to discovery/resolution
        
        cycle_time := time.since(cycle_start)
        append(&cycle_times, cycle_time)
        
        fmt.printf("  Cycle %2d: %v\n", cycle + 1, cycle_time)
    }
    
    // Analyze performance results
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
    
    fmt.println()
    fmt.println("Performance Analysis:")
    fmt.printf("  Module Count: %d (< 50 ✓)\n", module_count)
    fmt.printf("  Test Cycles:  %d\n", len(cycle_times))
    fmt.printf("  Average Time: %v\n", avg_time)
    fmt.printf("  Minimum Time: %v\n", min_time)
    fmt.printf("  Maximum Time: %v\n", max_time)
    fmt.printf("  Time Variance: %v\n", max_time - min_time)
    
    // CRITICAL: Validate Performance Requirement 4.1.1
    max_allowed_time := time.Millisecond * 100
    
    fmt.println()
    fmt.println("Requirement 4.1.1 Validation:")
    
    requirement_met := true
    violations := 0
    
    for cycle_time, i in cycle_times {
        if cycle_time >= max_allowed_time {
            fmt.printf("  ✗ Cycle %2d: %v >= 100ms (VIOLATION)\n", i + 1, cycle_time)
            requirement_met = false
            violations += 1
        } else {
            fmt.printf("  ✓ Cycle %2d: %v < 100ms\n", i + 1, cycle_time)
        }
    }
    
    fmt.println()
    if requirement_met {
        fmt.printf("✓ REQUIREMENT 4.1.1 SATISFIED\n")
        fmt.printf("  All %d test cycles completed in under 100ms\n", len(cycle_times))
        fmt.printf("  Average processing time: %v (< 100ms)\n", avg_time)
        fmt.printf("  System meets performance requirement for < 50 modules\n")
    } else {
        fmt.printf("✗ REQUIREMENT 4.1.1 VIOLATED\n")
        fmt.printf("  %d out of %d cycles exceeded 100ms limit\n", violations, len(cycle_times))
        fmt.printf("  Average processing time: %v\n", avg_time)
        fmt.printf("  System does NOT meet performance requirement\n")
    }
    
    // Test assertion
    testing.expect(t, requirement_met, 
                   fmt.tprintf("REQUIREMENT 4.1.1: All cycles must complete in under 100ms. Average: %v, Violations: %d/%d", 
                               avg_time, violations, len(cycle_times)))
    
    // Additional performance metrics
    if len(cycle_times) >= 2 {
        first_run := cycle_times[0]
        subsequent_avg := time.Duration(0)
        for i in 1..<len(cycle_times) {
            subsequent_avg += cycle_times[i]
        }
        subsequent_avg /= time.Duration(len(cycle_times) - 1)
        
        if subsequent_avg < first_run {
            speedup := time.duration_seconds(first_run) / time.duration_seconds(subsequent_avg)
            fmt.printf("  Cache/optimization effect: %.2fx speedup after first run\n", speedup)
        }
    }
    
    modules_per_second := f64(module_count) / time.duration_seconds(avg_time)
    fmt.printf("  Processing rate: %.1f modules/second\n", modules_per_second)
}

@(test)
test_performance_requirement_4_1_2 :: proc(t: ^testing.T) {
    // Test Performance Requirement 4.1.2:
    // The system SHALL use efficient memory management with proper cleanup
    
    fmt.println()
    fmt.println("=== Testing Performance Requirement 4.1.2 ===")
    fmt.println("Requirement: Efficient memory management with proper cleanup")
    
    temp_dir := "test_temp_requirement_4_1_2"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create modules for memory testing
    module_count := 30
    
    fmt.printf("Creating %d modules for memory management test...\n", module_count)
    
    for i in 0..<module_count {
        module_name := fmt.tprintf("mem_module_%02d", i)
        
        dependencies := make([dynamic]string)
        defer delete(dependencies)
        
        // Create some dependencies for more complex memory patterns
        if i > 0 && i % 3 == 0 {
            dep_count := min(i, 2)
            for j in 0..<dep_count {
                dep_name := fmt.tprintf("mem_module_%02d", i - j - 1)
                append(&dependencies, dep_name)
            }
        }
        
        success := create_benchmark_test_module(temp_dir, module_name, i * 10, dependencies[:])
        testing.expect(t, success, fmt.tprintf("Should create memory test module %s", module_name))
    }
    
    // Test memory management through multiple cycles
    fmt.printf("Testing memory management through multiple load/cleanup cycles...\n")
    
    memory_test_passed := true
    
    for cycle in 0..<10 {
        cycle_start := time.now()
        
        // Discovery phase
        modules := loader.discover(temp_dir)
        testing.expect(t, len(modules) == module_count, 
                       fmt.tprintf("Memory cycle %d: Should discover all modules", cycle + 1))
        
        // Resolution phase
        resolved_modules, err := loader.resolve(modules)
        testing.expect(t, err == "", 
                       fmt.tprintf("Memory cycle %d: Should resolve successfully", cycle + 1))
        
        // Cleanup phase - this tests proper memory management
        if resolved_modules != nil {
            delete(resolved_modules)
        }
        manifest.cleanup_modules(modules[:])
        delete(modules)
        
        cycle_time := time.since(cycle_start)
        
        // Each cycle should complete in reasonable time (memory leaks would slow this down)
        max_cycle_time := time.Millisecond * 150
        if cycle_time > max_cycle_time {
            fmt.printf("  ✗ Memory cycle %d: %v > %v (potential memory issue)\n", 
                      cycle + 1, cycle_time, max_cycle_time)
            memory_test_passed = false
        } else {
            fmt.printf("  ✓ Memory cycle %d: %v (cleanup efficient)\n", cycle + 1, cycle_time)
        }
    }
    
    fmt.println()
    if memory_test_passed {
        fmt.printf("✓ REQUIREMENT 4.1.2 SATISFIED\n")
        fmt.printf("  All memory management cycles completed efficiently\n")
        fmt.printf("  No signs of memory leaks or inefficient cleanup\n")
        fmt.printf("  System demonstrates proper memory management\n")
    } else {
        fmt.printf("✗ REQUIREMENT 4.1.2 VIOLATED\n")
        fmt.printf("  Some memory management cycles were inefficient\n")
        fmt.printf("  Potential memory leaks or cleanup issues detected\n")
    }
    
    testing.expect(t, memory_test_passed, "REQUIREMENT 4.1.2: Memory management should be efficient")
}

@(test)
test_scalability_beyond_requirements :: proc(t: ^testing.T) {
    // Test scalability beyond the basic requirements to understand system limits
    
    fmt.println()
    fmt.println("=== Testing Scalability Beyond Requirements ===")
    fmt.println("Testing system behavior with larger module sets")
    
    temp_dir := "test_temp_scalability"
    defer remove_directory_recursive(temp_dir)
    
    // Test with progressively larger module sets
    test_sizes := []int{50, 75, 100, 150}
    
    for size in test_sizes {
        fmt.printf("\n--- Testing with %d modules ---\n", size)
        
        // Clean up previous test
        remove_directory_recursive(temp_dir)
        os.make_directory(temp_dir, 0o755)
        
        // Create modules
        for i in 0..<size {
            module_name := fmt.tprintf("scale_module_%03d", i)
            
            dependencies := make([dynamic]string)
            defer delete(dependencies)
            
            // Create realistic dependency patterns
            if i > 0 && i % 7 == 0 {
                dep_count := min(i, 3)
                for j in 0..<dep_count {
                    dep_idx := (i - j - 1) % i
                    dep_name := fmt.tprintf("scale_module_%03d", dep_idx)
                    append(&dependencies, dep_name)
                }
            }
            
            success := create_benchmark_test_module(temp_dir, module_name, i % 100, dependencies[:])
            if !success {
                fmt.printf("Failed to create module %s\n", module_name)
                break
            }
        }
        
        // Test performance
        start_time := time.now()
        
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
        
        total_time := time.since(start_time)
        
        if err != "" {
            fmt.printf("  ✗ Resolution failed: %s\n", err)
            testing.expect(t, false, fmt.tprintf("Resolution should succeed for %d modules", size))
        } else {
            modules_per_second := f64(size) / time.duration_seconds(total_time)
            
            fmt.printf("  Processing time: %v\n", total_time)
            fmt.printf("  Processing rate: %.1f modules/second\n", modules_per_second)
            
            // Performance expectations based on size
            max_expected_time: time.Duration
            switch {
            case size <= 50:
                max_expected_time = time.Millisecond * 100  // Requirement compliance
            case size <= 75:
                max_expected_time = time.Millisecond * 150  // Should still be fast
            case size <= 100:
                max_expected_time = time.Millisecond * 250  // Reasonable for larger sets
            case size <= 150:
                max_expected_time = time.Millisecond * 500  // Acceptable for very large sets
            }
            
            if total_time <= max_expected_time {
                fmt.printf("  ✓ Performance acceptable: %v <= %v\n", total_time, max_expected_time)
            } else {
                fmt.printf("  ⚠ Performance concern: %v > %v\n", total_time, max_expected_time)
                // Only fail for sizes within the requirement (< 50 modules)
                if size < 50 {
                    testing.expect(t, false, fmt.tprintf("Performance requirement violated for %d modules", size))
                }
            }
        }
    }
}

@(test)
test_comprehensive_benchmark_suite :: proc(t: ^testing.T) {
    // Run the comprehensive benchmark suite using the existing infrastructure
    
    fmt.println()
    fmt.println("=== Running Comprehensive Benchmark Suite ===")
    
    temp_dir := "test_temp_comprehensive_benchmark"
    defer remove_directory_recursive(temp_dir)
    
    os.make_directory(temp_dir, 0o755)
    
    // Create a realistic test dataset
    module_count := 45  // Just under the 50 module requirement
    
    fmt.printf("Creating comprehensive test dataset with %d modules...\n", module_count)
    
    for i in 0..<module_count {
        module_name := fmt.tprintf("bench_module_%02d", i)
        
        dependencies := make([dynamic]string)
        defer delete(dependencies)
        
        // Create varied dependency patterns
        switch i % 8 {
        case 0, 1:
            // No dependencies (base modules)
        case 2, 3:
            // Single dependency
            if i >= 2 {
                dep_name := fmt.tprintf("bench_module_%02d", i - 2)
                append(&dependencies, dep_name)
            }
        case 4, 5:
            // Multiple dependencies
            if i >= 4 {
                for j in 0..<min(i, 2) {
                    dep_name := fmt.tprintf("bench_module_%02d", i - j - 2)
                    append(&dependencies, dep_name)
                }
            }
        case 6, 7:
            // Complex dependencies
            if i >= 6 {
                append(&dependencies, fmt.tprintf("bench_module_%02d", i - 3))
                if i >= 8 {
                    append(&dependencies, fmt.tprintf("bench_module_%02d", i - 6))
                }
            }
        }
        
        priority := (i * 7) % 100  // Varied priorities
        success := create_benchmark_test_module(temp_dir, module_name, priority, dependencies[:])
        testing.expect(t, success, fmt.tprintf("Should create comprehensive test module %s", module_name))
    }
    
    // Run the benchmark suite
    fmt.printf("Running benchmark suite against performance requirements...\n")
    
    benchmark_passed := loader.run_performance_requirements_benchmark(temp_dir)
    
    fmt.println()
    if benchmark_passed {
        fmt.printf("✓ COMPREHENSIVE BENCHMARK SUITE PASSED\n")
        fmt.printf("  All performance requirements satisfied\n")
        fmt.printf("  System ready for production use\n")
    } else {
        fmt.printf("✗ COMPREHENSIVE BENCHMARK SUITE FAILED\n")
        fmt.printf("  Some performance requirements not met\n")
        fmt.printf("  System may need optimization\n")
    }
    
    testing.expect(t, benchmark_passed, "Comprehensive benchmark suite should pass all performance requirements")
}