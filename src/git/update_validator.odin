package git

import "core:fmt"
import "core:strings"

import "../colors"
import "../security"

// validate_update_scan runs security scan and returns whether update can proceed.
validate_update_scan :: proc(module_name: string, module_path: string, options: Manager_Options) -> (security.Scan_Result, bool, string) {
	if options.skip_scan {
		colors.print_warning("Skipping security scan (--skip-scan)")
		return security.Scan_Result{success = true}, true, ""
	}

	colors.print_info("Scanning for security issues: %s", module_name)
	scan_options := security.Scan_Options{
		unsafe_mode = options.unsafe,
		verbose = options.verbose,
	}
	scan_result := security.scan_module(module_path, scan_options)
	if !scan_result.success {
		return scan_result, false, scan_result.error_message
	}

	if scan_result.critical_count > 0 || scan_result.warning_count > 0 {
		report := security.format_scan_report(&scan_result, module_name)
		fmt.println(report)
		delete(report)
	}

	if options.unsafe {
		security.audit_unsafe_usage(module_name, module_path, &scan_result)
	}

	if security.should_block_install(&scan_result, options.unsafe) {
		return scan_result, false, "Critical security issues detected. Use --unsafe to override."
	}

	if scan_result.warning_count > 0 && !options.unsafe {
		if !security.prompt_user_for_warnings(&scan_result, module_name) {
			return scan_result, false, "Update cancelled by user"
		}
	}

	if options.unsafe && (scan_result.critical_count > 0 || scan_result.warning_count > 0) {
		colors.print_warning("Unsafe mode enabled: security checks bypassed")
	}

	return scan_result, true, ""
}

// validate_update_manifest validates the module manifest after update.
validate_update_manifest :: proc(module_path: string, module_name: string, verbose: bool) -> Validation_Result {
	if verbose {
		colors.print_info("Validating module: %s", module_name)
	}
	return validate_module(module_path, module_name)
}
