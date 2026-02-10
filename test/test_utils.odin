package test

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "core:fmt"
import "core:testing"
import "core:sync"
import "base:runtime"

import "../src/loader"

DEFAULT_TEST_TIMEOUT :: 30 * time.Second

// home_env_mutex serializes HOME mutations across tests.
home_env_mutex: sync.Mutex

Agent_Env_Snapshot :: struct {
	anthropic_api_key:      string,
	anthropic_agent_id:     string,
	cursor_agent_id:        string,
	github_copilot_token:   string,
	github_copilot_session: string,
	windsurf_session:       string,
	aider_session:          string,
	term_program:           string,
}

lock_home_env :: proc() {
    sync.mutex_lock(&home_env_mutex)
}

unlock_home_env :: proc() {
    sync.mutex_unlock(&home_env_mutex)
}

capture_agent_env :: proc() -> Agent_Env_Snapshot {
	return Agent_Env_Snapshot{
		anthropic_api_key      = os.get_env("ANTHROPIC_API_KEY"),
		anthropic_agent_id     = os.get_env("ANTHROPIC_AGENT_ID"),
		cursor_agent_id        = os.get_env("CURSOR_AGENT_ID"),
		github_copilot_token   = os.get_env("GITHUB_COPILOT_TOKEN"),
		github_copilot_session = os.get_env("GITHUB_COPILOT_SESSION"),
		windsurf_session       = os.get_env("WINDSURF_SESSION"),
		aider_session          = os.get_env("AIDER_SESSION"),
		term_program           = os.get_env("TERM_PROGRAM"),
	}
}

clear_agent_env :: proc() {
	os.unset_env("ANTHROPIC_API_KEY")
	os.unset_env("ANTHROPIC_AGENT_ID")
	os.unset_env("CURSOR_AGENT_ID")
	os.unset_env("GITHUB_COPILOT_TOKEN")
	os.unset_env("GITHUB_COPILOT_SESSION")
	os.unset_env("WINDSURF_SESSION")
	os.unset_env("AIDER_SESSION")
	os.unset_env("TERM_PROGRAM")
}

restore_agent_env :: proc(snapshot: Agent_Env_Snapshot) {
	restore_env := proc(key: string, value: string) {
		if value == "" {
			os.unset_env(key)
			return
		}
		os.set_env(key, value)
	}

	restore_env("ANTHROPIC_API_KEY", snapshot.anthropic_api_key)
	restore_env("ANTHROPIC_AGENT_ID", snapshot.anthropic_agent_id)
	restore_env("CURSOR_AGENT_ID", snapshot.cursor_agent_id)
	restore_env("GITHUB_COPILOT_TOKEN", snapshot.github_copilot_token)
	restore_env("GITHUB_COPILOT_SESSION", snapshot.github_copilot_session)
	restore_env("WINDSURF_SESSION", snapshot.windsurf_session)
	restore_env("AIDER_SESSION", snapshot.aider_session)
	restore_env("TERM_PROGRAM", snapshot.term_program)

	delete(snapshot.anthropic_api_key)
	delete(snapshot.anthropic_agent_id)
	delete(snapshot.cursor_agent_id)
	delete(snapshot.github_copilot_token)
	delete(snapshot.github_copilot_session)
	delete(snapshot.windsurf_session)
	delete(snapshot.aider_session)
	delete(snapshot.term_program)
}

set_test_timeout :: proc(t: ^testing.T, duration: time.Duration = DEFAULT_TEST_TIMEOUT) {
    reset_test_state(t)
    testing.set_fail_timeout(t, duration)
}

cleanup_test_allocations :: proc() {
    loader.reset_global_cache()
}

cleanup_test_allocations_proc :: proc(_: rawptr) {
    cleanup_test_allocations()
}

reset_test_state :: proc(t: ^testing.T) {
    loader.reset_global_cache()
    testing.cleanup(t, cleanup_test_allocations_proc, nil)
}

// is_stdlib_allocation returns true for known Odin stdlib one-time allocations
// that are outside project control and should not fail memory-stability tests.
is_stdlib_allocation :: proc(loc: runtime.Source_Code_Location) -> bool {
    if strings.contains(loc.file_path, "os_darwin.odin") && loc.line == 1044 {
        return true
    }
    if strings.contains(loc.file_path, "path.odin") && (loc.line == 548 || loc.line == 579 || loc.line == 584) {
        return true
    }
    if strings.contains(loc.file_path, "conversion.odin") && (loc.line == 106) {
        return true
    }
    return false
}

// ✅ CRITICAL FIX: Force cleanup test directories to prevent EEXIST errors
cleanup_test_directory :: proc(dir_path: string) {
    if dir_path == "" do return
    
    // Force remove directory if it exists
    if os.exists(dir_path) {
        remove_directory_recursive(dir_path)
    }
}

// ✅ CRITICAL FIX: Recursive directory removal
remove_directory_recursive :: proc(dir_path: string) {
    if !os.exists(dir_path) do return
    
    // Get directory contents
    handle, open_err := os.open(dir_path)
    if open_err != os.ERROR_NONE {
        return
    }
    defer os.close(handle)
    
    entries, read_err := os.read_dir(handle, -1)
    if read_err != os.ERROR_NONE {
        return
    }
    defer os.file_info_slice_delete(entries)
    
    // Remove all contents first
    for entry in entries {
        full_path := filepath.join({dir_path, entry.name})
        defer delete(full_path)
        
        if entry.is_dir {
            remove_directory_recursive(full_path)
        } else {
            os.remove(full_path)
        }
    }
    
    // Remove the directory itself
    os.remove(dir_path)
}

// ✅ CRITICAL FIX: Create unique test directory with timestamp
create_unique_test_directory :: proc(base_name: string) -> string {
    timestamp := time.now()._nsec
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(&builder, "%s_%d", base_name, timestamp)
    unique_name := strings.clone(strings.to_string(builder))
    defer delete(unique_name)

    cwd := os.get_current_directory()
    defer delete(cwd)

    absolute_path := filepath.join({cwd, unique_name})
    
    // Ensure it doesn't exist
    cleanup_test_directory(absolute_path)
    
    // Create the directory
    os.make_directory(absolute_path, 0o755)
    
    return absolute_path
}

// ✅ CRITICAL FIX: Setup test with proper cleanup
setup_test_environment :: proc(test_name: string) -> string {
    base_dir := create_unique_test_directory(test_name)
    return base_dir
}

// ✅ CRITICAL FIX: Teardown test with complete cleanup
teardown_test_environment :: proc(test_dir: string) {
    cleanup_test_directory(test_dir)
    if test_dir != "" {
        delete(test_dir)
    }
}

get_test_modules_dir :: proc() -> string {
    cwd := os.get_current_directory()
    defer delete(cwd)
    return filepath.join({cwd, "test-modules"})
}
