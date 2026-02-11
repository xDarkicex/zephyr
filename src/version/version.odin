package version

import "core:fmt"
import "core:os"
import "core:time"
import "core:strings"
import "../loader"

// Build metadata (set via -define at compile time)
VERSION :: #config(VERSION, "dev")
GIT_COMMIT :: #config(GIT_COMMIT, "unknown")
BUILD_TIME :: #config(BUILD_TIME, "unknown")
REPOSITORY :: "github.com/xDarkicex/zephyr"

// ASCII art logo
LOGO :: `    ███████╗███████╗██████╗ ██╗  ██╗██╗   ██╗██████╗ 
    ╚══███╔╝██╔════╝██╔══██╗██║  ██║╚██╗ ██╔╝██╔══██╗
      ███╔╝ █████╗  ██████╔╝███████║ ╚████╔╝ ██████╔╝
     ███╔╝  ██╔══╝  ██╔═══╝ ██╔══██║  ╚██╔╝  ██╔══██╗
    ███████╗███████╗██║     ██║  ██║   ██║   ██║  ██║
    ╚══════╝╚══════╝╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝`

// Color constants
CYAN  :: "\x1b[36m"
BOLD  :: "\x1b[1m"
RESET :: "\x1b[0m"

print_version :: proc(use_color: bool) {
	if use_color {
		fmt.printf("%s%s%s\n\n", CYAN, LOGO, RESET)
	} else {
		fmt.printf("%s\n\n", LOGO)
	}

	print_version_info(use_color)
	fmt.println()
	print_system_info(use_color)
}

print_version_short :: proc() {
	fmt.println(VERSION)
}

print_version_info :: proc(use_color: bool) {
	label_color := ""
	reset := ""
	if use_color {
		label_color = BOLD
		reset = RESET
	}

	fmt.printf("    %sVersion:%s        %s\n", label_color, reset, VERSION)
	fmt.printf("    %sBuild:%s          %s (%s)\n", label_color, reset, GIT_COMMIT, BUILD_TIME)
	fmt.printf("    %sRepository:%s     %s\n", label_color, reset, REPOSITORY)
}

print_system_info :: proc(use_color: bool) {
	label_color := ""
	reset := ""
	if use_color {
		label_color = BOLD
		reset = RESET
	}

	now := time.now()
	system_time := "unknown"
	if stamp, ok := time.time_to_rfc3339(now, 0, false); ok {
		system_time = strings.clone(stamp)
		delete(stamp)
	}

	platform := loader.get_current_platform()
	defer loader.cleanup_platform_info(&platform)

	shell_name, shell_version := get_shell_info()

	modules_dir := loader.get_modules_dir()
	defer delete(modules_dir)

	fmt.printf("    %sSystem Time:%s    %s\n", label_color, reset, system_time)
	fmt.printf("    %sPlatform:%s       %s/%s\n", label_color, reset, platform.os, platform.arch)
	if shell_version != "" {
		fmt.printf("    %sShell:%s          %s %s\n", label_color, reset, shell_name, shell_version)
	} else {
		fmt.printf("    %sShell:%s          %s\n", label_color, reset, shell_name)
	}
	fmt.printf("    %sModules Dir:%s    %s\n", label_color, reset, modules_dir)
}

get_shell_info :: proc() -> (name: string, version: string) {
	shell_path := os.get_env("SHELL")
	if shell_path != "" {
		defer delete(shell_path)
		if strings.contains(shell_path, "zsh") {
			name = "zsh"
			version = get_zsh_version()
			return
		}
		if strings.contains(shell_path, "bash") {
			name = "bash"
			version = get_bash_version()
			return
		}
	}

	name = "unknown"
	version = ""
	return
}

get_zsh_version :: proc() -> string {
	zsh_version := os.get_env("ZSH_VERSION")
	if zsh_version != "" {
		defer delete(zsh_version)
		return strings.clone(zsh_version)
	}
	return ""
}

get_bash_version :: proc() -> string {
	bash_version := os.get_env("BASH_VERSION")
	if bash_version != "" {
		defer delete(bash_version)
		parts := strings.split(bash_version, " ")
		defer delete(parts)
		if len(parts) > 0 {
			return strings.clone(parts[0])
		}
	}
	return ""
}

should_disable_color :: proc() -> bool {
	no_color := os.get_env("NO_COLOR")
	if no_color != "" {
		delete(no_color)
		return true
	}
	delete(no_color)

	for arg in os.args[1:] {
		if arg == "--no-color" {
			return true
		}
	}
	return false
}
