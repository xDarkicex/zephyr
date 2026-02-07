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
}

parse_scan_options :: proc() -> Scan_Options {
	options := Scan_Options{}

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
		if options.source == "" {
			options.source = arg
		}
	}

	return options
}

scan_command :: proc() {
	options := parse_scan_options()
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
