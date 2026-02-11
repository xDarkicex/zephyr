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
REPOSITORY :: "github.com/zephyr-systems/zephyr"

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
	{
		date_buf: [time.MIN_YYYY_DATE_LEN]u8
		time_buf: [time.MIN_HMS_LEN]u8
		date_str := time.to_string_mm_dd_yyyy(now, date_buf[:])
		time_str := time.to_string_hms(now, time_buf[:])
		system_time = fmt.aprintf("%s - %s", date_str, time_str)
	}
	defer delete(system_time)

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

	zsh_version := get_zsh_version()
	if zsh_version != "" {
		name = "zsh"
		version = zsh_version
		return
	}

	bash_version := get_bash_version()
	if bash_version != "" {
		name = "bash"
		version = bash_version
		return
	}

	// Fallbacks when version env vars are not set (non-interactive shells)
	zsh_name := os.get_env("ZSH_NAME")
	if zsh_name != "" {
		delete(zsh_name)
		name = "zsh"
		version = ""
		return
	}
	delete(zsh_name)

	bash_path := os.get_env("BASH")
	if bash_path != "" {
		delete(bash_path)
		name = "bash"
		version = ""
		return
	}
	delete(bash_path)

	when ODIN_OS == .Linux {
		linux_hint := get_linux_shell_hint()
		if linux_hint != "" {
			defer delete(linux_hint)
			lower_hint := strings.to_lower(linux_hint)
			defer delete(lower_hint)
			if strings.contains(lower_hint, "zsh") {
				name = "zsh"
				version = ""
				return
			}
			if strings.contains(lower_hint, "bash") {
				name = "bash"
				version = ""
				return
			}
			if strings.contains(lower_hint, "sh") {
				name = "sh"
				version = ""
				return
			}
			// Fallback: use the hint directly if it doesn't match known shells.
			name = strings.clone(lower_hint)
			version = ""
			return
		}
	}

	name = "unknown"
	version = ""
	return
}

get_parent_process_name_linux :: proc() -> string {
	data, ok := os.read_entire_file("/proc/self/status")
	if !ok {
		return ""
	}
	defer delete(data)

	content := string(data)
	lines := strings.split_lines(content)
	defer delete(lines)

	ppid := ""
	for line in lines {
		if strings.has_prefix(line, "PPid:") {
			ppid = strings.trim_space(strings.trim_prefix(line, "PPid:"))
			break
		}
	}
	if ppid == "" {
		return ""
	}

	path := fmt.aprintf("/proc/%s/comm", ppid)
	defer delete(path)
	comm_data, comm_ok := os.read_entire_file(path)
	if !comm_ok {
		if ppid != "1" {
			return ""
		}
		comm_data = nil
	}
	if comm_data != nil {
		defer delete(comm_data)
		return strings.clone(strings.trim_space(string(comm_data)))
	}

	// Container fallback: PID 1 is often the shell.
	pid1_data, pid1_ok := os.read_entire_file("/proc/1/comm")
	if !pid1_ok {
		return ""
	}
	defer delete(pid1_data)
	return strings.clone(strings.trim_space(string(pid1_data)))
}

get_linux_shell_hint :: proc() -> string {
	// Prefer PID 1 (container init) then self, then parent.
	if pid1 := read_proc_comm("/proc/1/comm"); pid1 != "" {
		return pid1
	}
	if self := read_proc_comm("/proc/self/comm"); self != "" {
		return self
	}
	return get_parent_process_name_linux()
}

read_proc_comm :: proc(path: string) -> string {
	handle, err := os.open(path)
	if err != os.ERROR_NONE {
		return ""
	}
	defer os.close(handle)

	buf: [64]byte
	n, read_err := os.read(handle, buf[:])
	if read_err != os.ERROR_NONE || n == 0 {
		return ""
	}
	return strings.clone(strings.trim_space(string(buf[:n])))
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
