package test

import "core:testing"
import "core:fmt"
import "core:os"
import "core:strings"

import "../src/loader"
import "../src/manifest"

@(test)
test_bash_backend_function_check :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    backend := &loader.BASH_Backend
    code := backend.function_exists_check("test_func")
    
    testing.expect_value(t, code, "type -t test_func")
}

@(test)
test_zsh_backend_function_check :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    backend := &loader.ZSH_Backend
    code := backend.function_exists_check("test_func")
    
    testing.expect_value(t, code, "typeset -f test_func")
}

@(test)
test_bash_backend_source_command :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    backend := &loader.BASH_Backend
    code := backend.source_command("\"/path/to/file.bash\"")
    
    testing.expect(t, strings.contains(code, "source"), "Should contain source command")
}

@(test)
test_bash_backend_export_variable :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    backend := &loader.BASH_Backend
    code := backend.export_variable("TEST_VAR", "\"value\"")
    
    testing.expect(t, strings.contains(code, "export"), "Should contain export command")
    testing.expect(t, strings.contains(code, "TEST_VAR"), "Should contain variable name")
}

@(test)
test_shell_backend_names :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    testing.expect_value(t, loader.ZSH_Backend.name, "zsh")
    testing.expect_value(t, loader.BASH_Backend.name, "bash")
}

@(test)
test_force_shell_bash :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    loader.reset_shell_backend_cache()
    
    config := loader.Shell_Config{force_shell = "bash"}
    backend := loader.get_shell_backend(&config)
    
    testing.expect_value(t, backend.name, "bash")
    
    loader.reset_shell_backend_cache()
}

@(test)
test_force_shell_zsh :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    loader.reset_shell_backend_cache()
    
    config := loader.Shell_Config{force_shell = "zsh"}
    backend := loader.get_shell_backend(&config)
    
    testing.expect_value(t, backend.name, "zsh")
    
    loader.reset_shell_backend_cache()
}

@(test)
test_force_shell_invalid_defaults_to_auto :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    loader.reset_shell_backend_cache()
    
    config := loader.Shell_Config{force_shell = "invalid_shell"}
    backend := loader.get_shell_backend(&config)
    
    testing.expect(t, backend.name == "zsh" || backend.name == "bash", 
                   "Invalid shell should fall back to auto-detection")
    
    loader.reset_shell_backend_cache()
}

@(test)
test_shell_backend_caching :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    loader.reset_shell_backend_cache()
    
    config := loader.Shell_Config{force_shell = "bash"}
    backend1 := loader.get_shell_backend(&config)
    backend2 := loader.get_shell_backend(&config)
    
    testing.expect(t, backend1 == backend2, "Cached backend should return same pointer")
    
    loader.reset_shell_backend_cache()
}

@(test)
test_detect_current_shell :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    shell := loader.detect_current_shell()
    
    testing.expect(t, shell == "zsh" || shell == "bash", 
                   "Detected shell should be zsh or bash")
}

@(test)
test_is_bash_environment :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    loader.reset_shell_backend_cache()
    
    config := loader.Shell_Config{force_shell = "bash"}
    _ = loader.get_shell_backend(&config)
    
    testing.expect(t, loader.is_bash_environment(), "Should detect bash environment")
    
    loader.reset_shell_backend_cache()
}

@(test)
test_is_zsh_environment :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    loader.reset_shell_backend_cache()
    
    config := loader.Shell_Config{force_shell = "zsh"}
    _ = loader.get_shell_backend(&config)
    
    testing.expect(t, loader.is_zsh_environment(), "Should detect zsh environment")
    
    loader.reset_shell_backend_cache()
}

@(test)
test_bash_hook_check_syntax :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    backend := &loader.BASH_Backend
    hook_name := "pre_load_hook"
    
    check_cmd := backend.function_exists_check(hook_name)
    
    expected := fmt.tprintf("type -t %s", hook_name)
    testing.expect_value(t, check_cmd, expected)
}

@(test)
test_zsh_hook_check_syntax :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    backend := &loader.ZSH_Backend
    hook_name := "pre_load_hook"
    
    check_cmd := backend.function_exists_check(hook_name)
    
    expected := fmt.tprintf("typeset -f %s", hook_name)
    testing.expect_value(t, check_cmd, expected)
}

@(test)
test_backend_file_exists_check :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    zsh_check := loader.ZSH_Backend.file_exists_check("\"/path/to/file\"")
    bash_check := loader.BASH_Backend.file_exists_check("\"/path/to/file\"")
    
    testing.expect(t, strings.contains(zsh_check, "[[ -f"), "ZSH should use [[ -f ]]")
    testing.expect(t, strings.contains(bash_check, "[[ -f"), "Bash should use [[ -f ]]")
}

@(test)
test_backends_have_consistent_interface :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    test_fn := "test_function"
    test_path := "\"/test/path.sh\""
    test_key := "TEST_VAR"
    test_value := "\"test_value\""
    
    // Test ZSH backend
    zsh_fn_check := loader.ZSH_Backend.function_exists_check(test_fn)
    testing.expect(t, len(zsh_fn_check) > 0, "ZSH function_exists_check should return non-empty string")
    
    zsh_src_cmd := loader.ZSH_Backend.source_command(test_path)
    testing.expect(t, len(zsh_src_cmd) > 0, "ZSH source_command should return non-empty string")
    
    zsh_exp_cmd := loader.ZSH_Backend.export_variable(test_key, test_value)
    testing.expect(t, len(zsh_exp_cmd) > 0, "ZSH export_variable should return non-empty string")
    
    zsh_file_check := loader.ZSH_Backend.file_exists_check(test_path)
    testing.expect(t, len(zsh_file_check) > 0, "ZSH file_exists_check should return non-empty string")
    
    // Test BASH backend
    bash_fn_check := loader.BASH_Backend.function_exists_check(test_fn)
    testing.expect(t, len(bash_fn_check) > 0, "Bash function_exists_check should return non-empty string")
    
    bash_src_cmd := loader.BASH_Backend.source_command(test_path)
    testing.expect(t, len(bash_src_cmd) > 0, "Bash source_command should return non-empty string")
    
    bash_exp_cmd := loader.BASH_Backend.export_variable(test_key, test_value)
    testing.expect(t, len(bash_exp_cmd) > 0, "Bash export_variable should return non-empty string")
    
    bash_file_check := loader.BASH_Backend.file_exists_check(test_path)
    testing.expect(t, len(bash_file_check) > 0, "Bash file_exists_check should return non-empty string")
}

@(test)
test_bash_vs_zsh_function_check_difference :: proc(t: ^testing.T) {
    set_test_timeout(t)
    reset_test_state(t)
    
    fn_name := "my_hook"
    
    bash_check := loader.BASH_Backend.function_exists_check(fn_name)
    zsh_check := loader.ZSH_Backend.function_exists_check(fn_name)
    
    testing.expect(t, bash_check != zsh_check, 
                   "Bash and ZSH function checks should be different")
    
    testing.expect(t, strings.contains(bash_check, "type -t"), 
                   "Bash should use type -t")
    testing.expect(t, strings.contains(zsh_check, "typeset -f"), 
                   "ZSH should use typeset -f")
}
