package loader

import "core:mem"
import "core:fmt"
import "core:time"
import "../debug"
import "../manifest"

// MemoryStats tracks memory usage statistics
MemoryStats :: struct {
    allocations_count: int,
    deallocations_count: int,
    peak_memory_bytes: int,
    current_memory_bytes: int,
    start_time: time.Time,
}

// Global memory tracking
memory_stats: MemoryStats

// init_memory_tracking initializes memory tracking
init_memory_tracking :: proc() {
    memory_stats = MemoryStats{
        start_time = time.now(),
    }
    debug.debug_info("Memory tracking initialized")
}

// get_memory_stats returns current memory statistics
get_memory_stats :: proc() -> MemoryStats {
    return memory_stats
}

// print_memory_stats prints current memory usage statistics
print_memory_stats :: proc() {
    elapsed := time.since(memory_stats.start_time)
    fmt.printf("Memory Statistics:\n")
    fmt.printf("  Allocations: %d\n", memory_stats.allocations_count)
    fmt.printf("  Deallocations: %d\n", memory_stats.deallocations_count)
    fmt.printf("  Peak Memory: %d bytes\n", memory_stats.peak_memory_bytes)
    fmt.printf("  Current Memory: %d bytes\n", memory_stats.current_memory_bytes)
    fmt.printf("  Elapsed Time: %v\n", elapsed)
    
    if memory_stats.allocations_count > 0 {
        leak_count := memory_stats.allocations_count - memory_stats.deallocations_count
        if leak_count > 0 {
            fmt.printf("  ⚠ Potential Memory Leaks: %d allocations not freed\n", leak_count)
        } else {
            fmt.printf("  ✓ No memory leaks detected\n")
        }
    }
}

// OptimizedAllocator provides memory pool allocation for frequently used types
OptimizedAllocator :: struct {
    module_pool: [dynamic]^manifest.Module,
    string_pool: [dynamic]^string,
    temp_allocator: mem.Allocator,
}

// create_optimized_allocator creates a new optimized allocator
create_optimized_allocator :: proc() -> OptimizedAllocator {
    return OptimizedAllocator{
        module_pool = make([dynamic]^manifest.Module),
        string_pool = make([dynamic]^string),
        temp_allocator = context.temp_allocator,
    }
}

// destroy_optimized_allocator cleans up the optimized allocator
destroy_optimized_allocator :: proc(allocator: ^OptimizedAllocator) {
    // Clean up module pool
    for module_ptr in allocator.module_pool {
        free(module_ptr)
    }
    delete(allocator.module_pool)
    
    // Clean up string pool
    for string_ptr in allocator.string_pool {
        free(string_ptr)
    }
    delete(allocator.string_pool)
}

// allocate_module allocates a module from the pool or creates a new one
allocate_module :: proc(allocator: ^OptimizedAllocator) -> ^manifest.Module {
    if len(allocator.module_pool) > 0 {
        // Reuse from pool
        module_ptr := allocator.module_pool[len(allocator.module_pool) - 1]
        ordered_remove(&allocator.module_pool, len(allocator.module_pool) - 1)
        return module_ptr
    }
    
    // Allocate new module
    module_ptr := new(manifest.Module)
    memory_stats.allocations_count += 1
    memory_stats.current_memory_bytes += size_of(manifest.Module)
    if memory_stats.current_memory_bytes > memory_stats.peak_memory_bytes {
        memory_stats.peak_memory_bytes = memory_stats.current_memory_bytes
    }
    
    return module_ptr
}

// deallocate_module returns a module to the pool
deallocate_module :: proc(allocator: ^OptimizedAllocator, module_ptr: ^manifest.Module) {
    // Reset module to clean state
    module_ptr^ = manifest.Module{}
    
    // Return to pool for reuse
    append(&allocator.module_pool, module_ptr)
    
    memory_stats.deallocations_count += 1
    memory_stats.current_memory_bytes -= size_of(manifest.Module)
}

// BatchStringBuilder provides efficient string building for large outputs
BatchStringBuilder :: struct {
    chunks: [dynamic]string,
    current_size: int,
    chunk_size: int,
}

// create_batch_string_builder creates a new batch string builder
create_batch_string_builder :: proc(initial_chunk_size: int = 4096) -> BatchStringBuilder {
    return BatchStringBuilder{
        chunks = make([dynamic]string),
        chunk_size = initial_chunk_size,
    }
}

// destroy_batch_string_builder cleans up the batch string builder
destroy_batch_string_builder :: proc(builder: ^BatchStringBuilder) {
    // ✅ CRITICAL FIX: Don't delete individual chunks!
    // The chunks are string references that may come from:
    // 1. fmt.tprintf() - uses temp allocator, can't be deleted
    // 2. Other sources that manage their own memory
    // We only need to delete the chunks array container itself
    delete(builder.chunks)
}

// batch_write_string adds a string to the batch builder
batch_write_string :: proc(builder: ^BatchStringBuilder, s: string) {
    append(&builder.chunks, s)
    builder.current_size += len(s)
}

// batch_build_string builds the final string from all chunks
batch_build_string :: proc(builder: ^BatchStringBuilder) -> string {
    if len(builder.chunks) == 0 {
        return ""
    }
    
    if len(builder.chunks) == 1 {
        return builder.chunks[0]
    }
    
    // Pre-allocate the result string with known size
    result := make([]u8, builder.current_size)
    offset := 0
    
    for chunk in builder.chunks {
        copy(result[offset:], chunk)
        offset += len(chunk)
    }
    
    return string(result)
}

// PreallocatedBuffers provides pre-allocated buffers for common operations
PreallocatedBuffers :: struct {
    path_buffer: [1024]u8,
    line_buffer: [4096]u8,
    temp_strings: [dynamic]string,
}

// create_preallocated_buffers creates pre-allocated buffers
create_preallocated_buffers :: proc() -> PreallocatedBuffers {
    return PreallocatedBuffers{
        temp_strings = make([dynamic]string, 0, 100), // Pre-allocate capacity for 100 strings
    }
}

// destroy_preallocated_buffers cleans up pre-allocated buffers
destroy_preallocated_buffers :: proc(buffers: ^PreallocatedBuffers) {
    for s in buffers.temp_strings {
        delete(s)
    }
    delete(buffers.temp_strings)
}

// get_path_buffer returns a reusable path buffer
get_path_buffer :: proc(buffers: ^PreallocatedBuffers) -> []u8 {
    return buffers.path_buffer[:]
}

// get_line_buffer returns a reusable line buffer
get_line_buffer :: proc(buffers: ^PreallocatedBuffers) -> []u8 {
    return buffers.line_buffer[:]
}

// add_temp_string adds a string to the temporary string pool
add_temp_string :: proc(buffers: ^PreallocatedBuffers, s: string) {
    append(&buffers.temp_strings, s)
}

// clear_temp_strings clears all temporary strings
clear_temp_strings :: proc(buffers: ^PreallocatedBuffers) {
    for s in buffers.temp_strings {
        delete(s)
    }
    clear(&buffers.temp_strings)
}