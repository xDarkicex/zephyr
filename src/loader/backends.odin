package loader

import "core:fmt"
import "core:os"
import "core:strings"

Shell_Backend :: struct {
    name:                   string,
    function_exists_check:  proc(fn_name: string) -> string,
    source_command:         proc(path: string) -> string,
    export_variable:        proc(key, value: string) -> string,
    file_exists_check:      proc(path: string) -> string,
}

ZSH_Backend := Shell_Backend {
    name                   = "zsh",
    function_exists_check  = zsh_function_exists_check,
    source_command         = zsh_source_command,
    export_variable        = zsh_export_variable,
    file_exists_check      = zsh_file_exists_check,
}

BASH_Backend := Shell_Backend {
    name                   = "bash",
    function_exists_check  = bash_function_exists_check,
    source_command         = bash_source_command,
    export_variable        = bash_export_variable,
    file_exists_check      = bash_file_exists_check,
}

zsh_function_exists_check :: proc(fn_name: string) -> string {
    return fmt.tprintf("typeset -f %s", fn_name)
}

bash_function_exists_check :: proc(fn_name: string) -> string {
    return fmt.tprintf("type -t %s", fn_name)
}

zsh_source_command :: proc(path: string) -> string {
    return fmt.tprintf("source %s", path)
}

bash_source_command :: proc(path: string) -> string {
    return fmt.tprintf("source %s", path)
}

zsh_export_variable :: proc(key, value: string) -> string {
    return fmt.tprintf("export %s=%s", key, value)
}

bash_export_variable :: proc(key, value: string) -> string {
    return fmt.tprintf("export %s=%s", key, value)
}

zsh_file_exists_check :: proc(path: string) -> string {
    return fmt.tprintf("[[ -f %s ]]", path)
}

bash_file_exists_check :: proc(path: string) -> string {
    return fmt.tprintf("[[ -f %s ]]", path)
}

_cached_backend: ^Shell_Backend = nil

Shell_Config :: struct {
    force_shell: string,
}

get_shell_backend :: proc(config: ^Shell_Config = nil) -> ^Shell_Backend {
    if _cached_backend != nil {
        return _cached_backend
    }

    if config != nil && config.force_shell != "" {
        switch config.force_shell {
        case "bash":
            _cached_backend = &BASH_Backend
            return _cached_backend
        case "zsh":
            _cached_backend = &ZSH_Backend
            return _cached_backend
        case:
            fmt.eprintln("Warning: Unknown shell '%s', using auto-detection", config.force_shell)
        }
    }

    shell_env := os.get_env("SHELL")
    defer delete(shell_env)

    if strings.contains(shell_env, "bash") {
        _cached_backend = &BASH_Backend
    } else {
        _cached_backend = &ZSH_Backend
    }

    return _cached_backend
}

reset_shell_backend_cache :: proc() {
    _cached_backend = nil
}

detect_current_shell :: proc() -> string {
    shell_env := os.get_env("SHELL")
    defer delete(shell_env)

    if strings.contains(shell_env, "bash") {
        return "bash"
    } else if strings.contains(shell_env, "zsh") {
        return "zsh"
    }

    return "zsh"
}

is_bash_environment :: proc() -> bool {
    backend := get_shell_backend()
    return backend.name == "bash"
}

is_zsh_environment :: proc() -> bool {
    backend := get_shell_backend()
    return backend.name == "zsh"
}
