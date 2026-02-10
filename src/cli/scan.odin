package cli

import "core:fmt"
import "core:os"
import "core:strings"

import "../colors"
import "../debug"
import "../git"
import "../security"

Scan_Options :: struct {
	source: string,
	json:   bool,
	mode:   Scan_Mode,
	command: string,
}

Scan_Mode :: enum {
	Module,
	Command,
}

parse_scan_options :: proc() -> Scan_Options {
	options := Scan_Options{mode = .Command}

	non_flag_args := make([dynamic]string)
	args := os.args[1:]
	for arg in args {
		if arg == "scan" {
			continue
		}
		if is_global_flag(arg) {
			continue
		}
		if arg == "--json" {
			options.json = true
			continue
		}
		if strings.has_prefix(arg, "-") {
			continue
		}
		append(&non_flag_args, arg)
	}

	if len(non_flag_args) == 1 {
		candidate := non_flag_args[0]
		if git.is_valid_git_url(candidate) || (candidate != "" && os.exists(candidate)) {
			options.mode = .Module
			options.source = candidate
		} else {
			options.mode = .Command
			options.command = candidate
		}
	} else if len(non_flag_args) > 1 {
		options.mode = .Command
		options.command = strings.join(non_flag_args[:], " ")
	}

	delete(non_flag_args)
	return options
}

scan_command :: proc() {
	options := parse_scan_options()
	if options.mode == .Command {
		exit_code := scan_command_string(options.command)
		os.exit(exit_code)
	}

	if options.source == "" {
		colors.print_error("Scan source required")
		fmt.eprintln("Usage: zephyr scan <git-url> [--json]")
		os.exit(4)
	}

	init_git_or_exit()
	defer shutdown_git()

	scan_result, temp_path, commit := git.scan_source(options.source)
	defer security.cleanup_scan_result(&scan_result)
	if temp_path != "" {
		git.cleanup_temp(temp_path)
		delete(temp_path)
	}

	if !scan_result.success {
		if scan_result.error_message != "" {
			fmt.eprintln(scan_result.error_message)
		}
		os.exit(3)
	}

	if options.json {
		json := security.format_scan_report_json(&scan_result, options.source, commit)
		fmt.println(json)
		delete(json)
		if commit != "" {
			delete(commit)
		}
		os.exit(security.exit_code_for_scan(&scan_result))
	}

	if commit != "" {
		delete(commit)
	}
	report := security.format_scan_report(&scan_result, options.source)
	fmt.println(report)
	delete(report)
}

scan_command_string :: proc(command: string) -> int {
	if command == "" {
		return 0
	}
	result := security.Scan_Command_Safe(command)
	if !result.has_findings {
		return 0
	}
	return command_exit_code(result.severity)
}

command_exit_code :: proc(severity: security.Severity) -> int {
	switch severity {
	case .Critical:
		return 1
	case .Warning:
		return 2
	case .Info:
		return 0
	}
	return 0
}
