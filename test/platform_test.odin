package test

import "core:testing"
import "core:fmt"
import "../src/loader"
import "../src/manifest"

@(test)
test_platform_detection :: proc(t: ^testing.T) {
    platform := loader.get_current_platform()
    
    // Platform should have valid OS
    testing.expect(t, platform.os != "", "OS should be detected")
    testing.expect(t, platform.os != "unknown", "OS should be recognized")
    
    // Platform should have valid architecture
    testing.expect(t, platform.arch != "", "Architecture should be detected")
    testing.expect(t, platform.arch != "unknown", "Architecture should be recognized")
    
    // Shell might be unknown in test environment, but should not be empty
    testing.expect(t, platform.shell != "", "Shell should be detected (even if unknown)")
    
    fmt.printf("Detected platform: %s/%s, shell: %s %s\n", 
               platform.os, platform.arch, platform.shell, platform.version)
}

@(test)
test_version_parsing :: proc(t: ^testing.T) {
    // Test version parsing
    version_5_8_1 := loader.parse_version("5.8.1")
    defer delete(version_5_8_1)
    
    testing.expect(t, len(version_5_8_1) == 3, "Should parse 3 version parts")
    testing.expect(t, version_5_8_1[0] == 5, "Major version should be 5")
    testing.expect(t, version_5_8_1[1] == 8, "Minor version should be 8")
    testing.expect(t, version_5_8_1[2] == 1, "Patch version should be 1")
    
    // Test version with suffix
    version_with_suffix := loader.parse_version("5.8.1-release")
    defer delete(version_with_suffix)
    
    testing.expect(t, len(version_with_suffix) == 3, "Should parse 3 version parts ignoring suffix")
    testing.expect(t, version_with_suffix[0] == 5, "Major version should be 5")
    testing.expect(t, version_with_suffix[1] == 8, "Minor version should be 8")
    testing.expect(t, version_with_suffix[2] == 1, "Patch version should be 1")
}

@(test)
test_version_compatibility :: proc(t: ^testing.T) {
    // Test exact match
    testing.expect(t, loader.is_version_compatible("5.8.1", "5.8.1"), 
                   "Exact version match should be compatible")
    
    // Test newer version
    testing.expect(t, loader.is_version_compatible("5.9.0", "5.8.1"), 
                   "Newer version should be compatible")
    
    // Test older version
    testing.expect(t, !loader.is_version_compatible("5.7.0", "5.8.1"), 
                   "Older version should not be compatible")
    
    // Test major version difference
    testing.expect(t, loader.is_version_compatible("6.0.0", "5.8.1"), 
                   "Higher major version should be compatible")
    
    testing.expect(t, !loader.is_version_compatible("4.9.9", "5.8.1"), 
                   "Lower major version should not be compatible")
    
    // Test missing patch version
    testing.expect(t, !loader.is_version_compatible("5.8", "5.8.1"), 
                   "Version 5.8 should not be compatible with requirement 5.8.1")
    
    testing.expect(t, loader.is_version_compatible("5.9", "5.8.1"), 
                   "Higher minor version should be compatible")
}

@(test)
test_platform_compatibility_no_filters :: proc(t: ^testing.T) {
    // Create a module with no platform filters
    module := manifest.Module{
        name = "test-module",
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    defer manifest.cleanup_module(&module)
    
    // Any platform should be compatible
    platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.8.1",
    }
    
    testing.expect(t, loader.is_platform_compatible(&module, platform), 
                   "Module with no filters should be compatible with any platform")
}

@(test)
test_platform_compatibility_os_filter :: proc(t: ^testing.T) {
    // Create a module that only supports Linux and macOS
    module := manifest.Module{
        name = "test-module",
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    defer manifest.cleanup_module(&module)
    
    append(&module.platforms.os, "linux")
    append(&module.platforms.os, "darwin")
    
    // Test compatible OS
    linux_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.8.1",
    }
    
    testing.expect(t, loader.is_platform_compatible(&module, linux_platform), 
                   "Module should be compatible with Linux")
    
    darwin_platform := loader.Platform_Info{
        os = "darwin",
        arch = "arm64",
        shell = "zsh",
        version = "5.8.1",
    }
    
    testing.expect(t, loader.is_platform_compatible(&module, darwin_platform), 
                   "Module should be compatible with macOS")
    
    // Test incompatible OS
    windows_platform := loader.Platform_Info{
        os = "windows",
        arch = "x86_64",
        shell = "powershell",
        version = "5.1",
    }
    
    testing.expect(t, !loader.is_platform_compatible(&module, windows_platform), 
                   "Module should not be compatible with Windows")
}

@(test)
test_platform_compatibility_arch_filter :: proc(t: ^testing.T) {
    // Create a module that only supports x86_64
    module := manifest.Module{
        name = "test-module",
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    defer manifest.cleanup_module(&module)
    
    append(&module.platforms.arch, "x86_64")
    
    // Test compatible architecture
    x86_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.8.1",
    }
    
    testing.expect(t, loader.is_platform_compatible(&module, x86_platform), 
                   "Module should be compatible with x86_64")
    
    // Test incompatible architecture
    arm_platform := loader.Platform_Info{
        os = "linux",
        arch = "arm64",
        shell = "zsh",
        version = "5.8.1",
    }
    
    testing.expect(t, !loader.is_platform_compatible(&module, arm_platform), 
                   "Module should not be compatible with ARM64")
}

@(test)
test_platform_compatibility_shell_filter :: proc(t: ^testing.T) {
    // Create a module that only supports zsh
    module := manifest.Module{
        name = "test-module",
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
            shell = "zsh",
        },
    }
    defer manifest.cleanup_module(&module)
    
    // Test compatible shell
    zsh_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.8.1",
    }
    
    testing.expect(t, loader.is_platform_compatible(&module, zsh_platform), 
                   "Module should be compatible with zsh")
    
    // Test incompatible shell
    bash_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "bash",
        version = "5.1.0",
    }
    
    testing.expect(t, !loader.is_platform_compatible(&module, bash_platform), 
                   "Module should not be compatible with bash")
}

@(test)
test_platform_compatibility_version_filter :: proc(t: ^testing.T) {
    // Create a module that requires zsh 5.8 or higher
    module := manifest.Module{
        name = "test-module",
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
            shell = "zsh",
            min_version = "5.8",
        },
    }
    defer manifest.cleanup_module(&module)
    
    // Test compatible version
    new_zsh_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.9.0",
    }
    
    testing.expect(t, loader.is_platform_compatible(&module, new_zsh_platform), 
                   "Module should be compatible with newer zsh version")
    
    // Test exact minimum version
    exact_zsh_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.8.0",
    }
    
    testing.expect(t, loader.is_platform_compatible(&module, exact_zsh_platform), 
                   "Module should be compatible with exact minimum version")
    
    // Test incompatible version
    old_zsh_platform := loader.Platform_Info{
        os = "linux",
        arch = "x86_64",
        shell = "zsh",
        version = "5.7.1",
    }
    
    testing.expect(t, !loader.is_platform_compatible(&module, old_zsh_platform), 
                   "Module should not be compatible with older zsh version")
}

@(test)
test_filter_compatible_modules :: proc(t: ^testing.T) {
    // Create test modules with different platform requirements
    modules := make([dynamic]manifest.Module)
    defer {
        manifest.cleanup_modules(modules[:])
        delete(modules)
    }
    
    // Module 1: No platform restrictions (should always be included)
    module1 := manifest.Module{
        name = "universal-module",
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&modules, module1)
    
    // Module 2: Linux only
    module2 := manifest.Module{
        name = "linux-module",
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module2.platforms.os, "linux")
    append(&modules, module2)
    
    // Module 3: Windows only (should be filtered out on non-Windows)
    module3 := manifest.Module{
        name = "windows-module",
        platforms = manifest.Platform_Filter{
            os = make([dynamic]string),
            arch = make([dynamic]string),
        },
    }
    append(&module3.platforms.os, "windows")
    append(&modules, module3)
    
    // Filter modules using indices
    compatible_indices := loader.filter_compatible_indices(modules)
    defer delete(compatible_indices)
    
    // Should have at least one compatible module
    testing.expect(t, len(compatible_indices) >= 1, "Should have at least one compatible module")
    
    // Universal module should always be included
    found_universal := false
    for idx in compatible_indices {
        if modules[idx].name == "universal-module" {
            found_universal = true
            break
        }
    }
    testing.expect(t, found_universal, "Universal module should be included")
    
    // On non-Windows systems, Windows module should be filtered out
    current_platform := loader.get_current_platform()
    if current_platform.os != "windows" {
        found_windows := false
        for idx in compatible_indices {
            if modules[idx].name == "windows-module" {
                found_windows = true
                break
            }
        }
        testing.expect(t, !found_windows, "Windows-only module should be filtered out on non-Windows")
    }
}