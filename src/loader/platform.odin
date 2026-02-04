package loader

import "core:os"
import "core:fmt"
import "core:strings"
import "../manifest"

// Platform_Info contains the current system's platform information
Platform_Info :: struct {
    os:      string,
    arch:    string,
    shell:   string,
    version: string,
}

// get_current_platform detects the current system's platform information
get_current_platform :: proc() -> Platform_Info {
    platform := Platform_Info{}
    
    // Detect OS
    when ODIN_OS == .Darwin {
        platform.os = "darwin"
    } else when ODIN_OS == .Linux {
        platform.os = "linux"
    } else when ODIN_OS == .Windows {
        platform.os = "windows"
    } else when ODIN_OS == .FreeBSD {
        platform.os = "freebsd"
    } else when ODIN_OS == .OpenBSD {
        platform.os = "openbsd"
    } else when ODIN_OS == .NetBSD {
        platform.os = "netbsd"
    } else {
        platform.os = "unknown"
    }
    
    // Detect architecture
    when ODIN_ARCH == .amd64 {
        platform.arch = "x86_64"
    } else when ODIN_ARCH == .arm64 {
        platform.arch = "arm64"
    } else when ODIN_ARCH == .i386 {
        platform.arch = "i386"
    } else when ODIN_ARCH == .arm32 {
        platform.arch = "arm32"
    } else {
        platform.arch = "unknown"
    }
    
    // Detect shell and version from environment
    shell_env := os.get_env("SHELL")
    if shell_env != "" {
        // Extract shell name from path (e.g., "/bin/zsh" -> "zsh")
        shell_parts := strings.split(shell_env, "/")
        defer delete(shell_parts)
        if len(shell_parts) > 0 {
            platform.shell = shell_parts[len(shell_parts) - 1]
        }
    } else {
        platform.shell = "unknown"
    }
    
    // Try to get shell version (this is shell-specific and may not always work)
    platform.version = get_shell_version(platform.shell)
    
    return platform
}

// get_shell_version attempts to get the version of the specified shell
get_shell_version :: proc(shell_name: string) -> string {
    switch shell_name {
    case "zsh":
        return get_zsh_version()
    case "bash":
        return get_bash_version()
    case:
        return ""
    }
}

// get_zsh_version attempts to get the ZSH version
get_zsh_version :: proc() -> string {
    // Try to get version from ZSH_VERSION environment variable first
    zsh_version := os.get_env("ZSH_VERSION")
    if zsh_version != "" {
        return zsh_version
    }
    
    // If not available, we can't easily detect it without running zsh
    // This would require executing a subprocess which is complex
    return ""
}

// get_bash_version attempts to get the Bash version
get_bash_version :: proc() -> string {
    // Try to get version from BASH_VERSION environment variable
    bash_version := os.get_env("BASH_VERSION")
    if bash_version != "" {
        // BASH_VERSION contains more info, extract just the version number
        parts := strings.split(bash_version, " ")
        defer delete(parts)
        if len(parts) > 0 {
            return parts[0]
        }
    }
    
    return ""
}

// is_platform_compatible checks if a module is compatible with the current platform
is_platform_compatible :: proc(module: ^manifest.Module, current_platform: Platform_Info) -> bool {
    filter := &module.platforms
    
    // If no platform filters are specified, assume compatible
    if len(filter.os) == 0 && len(filter.arch) == 0 && 
       filter.shell == "" && filter.min_version == "" {
        return true
    }
    
    // Check OS compatibility
    if len(filter.os) > 0 {
        os_compatible := false
        for supported_os in filter.os {
            if supported_os == current_platform.os {
                os_compatible = true
                break
            }
        }
        if !os_compatible {
            return false
        }
    }
    
    // Check architecture compatibility
    if len(filter.arch) > 0 {
        arch_compatible := false
        for supported_arch in filter.arch {
            if supported_arch == current_platform.arch {
                arch_compatible = true
                break
            }
        }
        if !arch_compatible {
            return false
        }
    }
    
    // Check shell compatibility
    if filter.shell != "" && filter.shell != current_platform.shell {
        return false
    }
    
    // Check minimum version (simplified semantic version comparison)
    if filter.min_version != "" && current_platform.version != "" {
        if !is_version_compatible(current_platform.version, filter.min_version) {
            return false
        }
    }
    
    return true
}

// is_version_compatible checks if the current version meets the minimum requirement
is_version_compatible :: proc(current_version: string, min_version: string) -> bool {
    // Parse version strings into comparable parts
    current_parts := parse_version(current_version)
    defer delete(current_parts)
    
    min_parts := parse_version(min_version)
    defer delete(min_parts)
    
    // Compare version parts
    max_len := max(len(current_parts), len(min_parts))
    
    for i in 0..<max_len {
        current_part := 0
        min_part := 0
        
        if i < len(current_parts) {
            current_part = current_parts[i]
        }
        if i < len(min_parts) {
            min_part = min_parts[i]
        }
        
        if current_part > min_part {
            return true
        } else if current_part < min_part {
            return false
        }
        // If equal, continue to next part
    }
    
    // All parts are equal, so current version meets minimum requirement
    return true
}

// parse_version parses a version string like "5.8.1" into [5, 8, 1]
parse_version :: proc(version: string) -> [dynamic]int {
    parts := make([dynamic]int)
    
    // Split by dots
    version_parts := strings.split(version, ".")
    defer delete(version_parts)
    
    for part_str in version_parts {
        // Parse each part as integer
        part_num := 0
        for char in part_str {
            if char >= '0' && char <= '9' {
                part_num = part_num * 10 + int(char - '0')
            } else {
                // Stop at first non-digit (handles cases like "5.8.1-release")
                break
            }
        }
        append(&parts, part_num)
    }
    
    return parts
}

// filter_compatible_modules returns indices of modules that are compatible with the current platform
filter_compatible_indices :: proc(modules: [dynamic]manifest.Module) -> [dynamic]int {
    current_platform := get_current_platform()
    compatible_indices := make([dynamic]int)
    
    for &module, idx in modules {
        if is_platform_compatible(&module, current_platform) {
            append(&compatible_indices, idx)
        }
    }
    
    return compatible_indices
}