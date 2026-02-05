#!/usr/bin/env bash
set -euo pipefail

# Zephyr Performance Benchmark
# Validates performance requirements and system scalability
#
# Usage:
#   ./benchmark.sh              # Run standard benchmark (49 modules, 10 cycles)
#   ./benchmark.sh --quick      # Quick test (25 modules, 5 cycles)
#   ./benchmark.sh --scalability # Test with 50, 75, 100 modules
#   ./benchmark.sh --help       # Show help

# Configuration
BINARY="./zephyr"
TEST_DIR="benchmark_modules"
DEFAULT_MODULE_COUNT=49
DEFAULT_CYCLES=10
MAX_TIME_MS=100  # Requirement 4.1.1: < 100ms for < 50 modules

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"; }

# Show usage
show_help() {
    cat << EOF
Zephyr Performance Benchmark

Usage:
  ./benchmark.sh [OPTIONS]

Options:
  --quick          Quick test (25 modules, 5 cycles)
  --scalability    Test scalability (50, 75, 100 modules)
  --help           Show this help message

Default:
  Runs standard benchmark with 49 modules and 10 cycles
  Validates Requirement 4.1.1: < 100ms for < 50 modules

Examples:
  ./benchmark.sh              # Standard benchmark
  ./benchmark.sh --quick      # Quick validation
  ./benchmark.sh --scalability # Scalability test

EOF
    exit 0
}

# Check prerequisites
check_prerequisites() {
    if [[ ! -f "$BINARY" ]]; then
        log_error "Zephyr binary not found: $BINARY"
        log_info "Build it first: ./build.sh"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 required for timing"
        exit 1
    fi
}

# Cleanup
cleanup() {
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}
trap cleanup EXIT

# Create test modules
create_modules() {
    local count=$1
    local dir=$2
    
    log_info "Creating $count test modules..."
    mkdir -p "$dir"
    
    for i in $(seq 0 $((count - 1))); do
        local module_name="bench_module_$(printf "%02d" $i)"
        local module_dir="$dir/$module_name"
        mkdir -p "$module_dir"
        
        # Create module.toml
        cat > "$module_dir/module.toml" << EOF
[module]
name = "$module_name"
version = "1.0.0"
description = "Benchmark module $i"

[load]
priority = $((i * 10))
files = ["${module_name}.zsh"]

[settings]
module_id = "$i"
EOF

        # Add dependencies for realistic patterns
        if (( i > 0 && i % 5 == 0 )); then
            local deps=""
            for j in $(seq 1 2); do
                local dep_idx=$((i - j))
                if (( dep_idx >= 0 )); then
                    local dep_name="bench_module_$(printf "%02d" $dep_idx)"
                    [[ -z "$deps" ]] && deps="\"$dep_name\"" || deps="$deps, \"$dep_name\""
                fi
            done
            [[ -n "$deps" ]] && echo -e "\n[dependencies]\nrequired = [$deps]" >> "$module_dir/module.toml"
        fi
        
        # Create shell file
        cat > "$module_dir/${module_name}.zsh" << EOF
# Benchmark module $module_name
export ${module_name^^}_LOADED=1
export ${module_name^^}_ID="$i"

${module_name}_function() {
    echo "Function from $module_name"
}
EOF
    done
}

# Run benchmark
run_benchmark() {
    local module_count=$1
    local cycles=$2
    local test_dir=$3
    
    log_header "Benchmark: $module_count modules, $cycles cycles"
    
    export ZSH_MODULES_DIR="$PWD/$test_dir"
    
    local -a cycle_times_ms
    local total_time_ms=0
    local min_time_ms=999999
    local max_time_ms=0
    local violations=0
    
    for cycle in $(seq 1 $cycles); do
        local start_time=$(python3 -c "import time; print(int(time.time() * 1000))")
        
        if output=$("$BINARY" load 2>&1); then
            local end_time=$(python3 -c "import time; print(int(time.time() * 1000))")
            local cycle_time_ms=$((end_time - start_time))
            
            cycle_times_ms+=($cycle_time_ms)
            total_time_ms=$((total_time_ms + cycle_time_ms))
            
            (( cycle_time_ms < min_time_ms )) && min_time_ms=$cycle_time_ms
            (( cycle_time_ms > max_time_ms )) && max_time_ms=$cycle_time_ms
            
            if (( cycle_time_ms >= MAX_TIME_MS && module_count < 50 )); then
                log_error "  Cycle $cycle: ${cycle_time_ms}ms >= ${MAX_TIME_MS}ms (VIOLATION)"
                ((violations++))
            else
                log_success "  Cycle $cycle: ${cycle_time_ms}ms"
            fi
        else
            log_error "  Cycle $cycle failed: $output"
            return 1
        fi
    done
    
    # Statistics
    local avg_time_ms=$((total_time_ms / cycles))
    local variance_ms=$((max_time_ms - min_time_ms))
    local modules_per_sec=$(( (module_count * 1000) / avg_time_ms ))
    
    echo
    echo "Results:"
    echo "  Module Count: $module_count"
    echo "  Average Time: ${avg_time_ms}ms"
    echo "  Min/Max: ${min_time_ms}ms / ${max_time_ms}ms"
    echo "  Variance: ${variance_ms}ms"
    echo "  Rate: ${modules_per_sec} modules/second"
    
    # Validation
    if (( module_count < 50 )); then
        echo
        if (( violations == 0 )); then
            log_success "✓ Requirement 4.1.1 SATISFIED (< 100ms for < 50 modules)"
            return 0
        else
            log_error "✗ Requirement 4.1.1 VIOLATED ($violations cycles >= 100ms)"
            return 1
        fi
    else
        echo
        log_info "Scalability test: ${avg_time_ms}ms for $module_count modules"
        return 0
    fi
}

# Standard benchmark
run_standard() {
    log_header "Standard Benchmark"
    echo "Validating Requirement 4.1.1: < 100ms for < 50 modules"
    
    create_modules $DEFAULT_MODULE_COUNT "$TEST_DIR"
    run_benchmark $DEFAULT_MODULE_COUNT $DEFAULT_CYCLES "$TEST_DIR"
}

# Quick benchmark
run_quick() {
    log_header "Quick Benchmark"
    echo "Fast validation with reduced module count"
    
    create_modules 25 "$TEST_DIR"
    run_benchmark 25 5 "$TEST_DIR"
}

# Scalability test
run_scalability() {
    log_header "Scalability Test"
    echo "Testing performance beyond requirements"
    
    local sizes=(50 75 100)
    local overall_success=true
    
    for size in "${sizes[@]}"; do
        echo
        log_info "Testing $size modules..."
        
        cleanup
        create_modules $size "$TEST_DIR"
        
        if ! run_benchmark $size 5 "$TEST_DIR"; then
            overall_success=false
        fi
    done
    
    echo
    if $overall_success; then
        log_success "Scalability test completed successfully"
        return 0
    else
        log_warning "Some scalability tests showed performance concerns"
        return 1
    fi
}

# Main
main() {
    log_header "Zephyr Performance Benchmark"
    
    check_prerequisites
    
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --quick)
            run_quick
            ;;
        --scalability)
            run_scalability
            ;;
        "")
            run_standard
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    
    local exit_code=$?
    
    echo
    if (( exit_code == 0 )); then
        log_success "BENCHMARK PASSED"
        echo "  System meets performance requirements"
        echo "  Ready for production use"
    else
        log_error "BENCHMARK FAILED"
        echo "  Performance optimization needed"
    fi
    
    exit $exit_code
}

main "$@"
