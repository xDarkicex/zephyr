// False Positive Validation Tests
// 
// These tests scan real-world shell modules (oh-my-zsh, nvm, rbenv, etc.)
// to validate that the scanner achieves < 5% false positive rate.
//
// Tests skip gracefully if modules are not installed locally.
// Results should be documented in docs_internal/PHASE1_FALSE_POSITIVE_VALIDATION.md

package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "../src/security"

// Helper to get home directory
get_home_dir :: proc() -> string {
	home := os.get_env("HOME")
	if home == "" {
		home = os.get_env("USERPROFILE") // Windows fallback
	}
	return home
}

// Helper to check if path exists
path_exists :: proc(path: string) -> bool {
	fi, err := os.stat(path)
	if err != os.ERROR_NONE {
		return false
	}
	defer os.file_info_delete(fi)
	return true
}

// Helper to format scan results
format_scan_results :: proc(module_name: string, result: security.Scan_Result) {
	header := strings.repeat("=", 60)
	defer delete(header)
	fmt.printf("\n%s\n", header)
	fmt.printf("False Positive Validation: %s\n", module_name)
	fmt.printf("%s\n", header)
	
	fmt.printf("Files scanned: %d\n", result.summary.files_scanned)
	fmt.printf("Lines scanned: %d\n", result.summary.lines_scanned)
	fmt.printf("Scan time: %dms\n", result.summary.duration_ms)
	fmt.printf("\n")
	
	fmt.printf("Findings:\n")
	fmt.printf("  Critical: %d\n", result.critical_count)
	fmt.printf("  Warning:  %d\n", result.warning_count)
	fmt.printf("  Info:     %d\n", result.info_count)
	fmt.printf("\n")
	
	if result.critical_count > 0 {
		fmt.printf("⚠️  CRITICAL FINDINGS (potential false positives):\n")
		for finding in result.findings {
			if finding.severity == .Critical {
				fmt.printf("  %s:%d\n", finding.file_path, finding.line_number)
				fmt.printf("    Pattern: %s\n", finding.pattern.pattern)
				fmt.printf("    Description: %s\n", finding.pattern.description)
				fmt.printf("    Code: %s\n", finding.line_text)
				fmt.printf("\n")
			}
		}
	}
	
	if result.warning_count > 0 {
		fmt.printf("⚠️  WARNING FINDINGS (potential false positives):\n")
		for finding in result.findings {
			if finding.severity == .Warning {
				fmt.printf("  %s:%d\n", finding.file_path, finding.line_number)
				fmt.printf("    Pattern: %s\n", finding.pattern.pattern)
				fmt.printf("    Description: %s\n", finding.pattern.description)
				fmt.printf("    Code: %s\n", finding.line_text)
				fmt.printf("\n")
			}
		}
	}
	
	if len(result.git_hooks) > 0 {
		fmt.printf("🪝 Git hooks: %d\n", len(result.git_hooks))
		for hook in result.git_hooks {
			fmt.printf("  %s\n", hook.hook_name)
		}
		fmt.printf("\n")
	}
	
	if len(result.symlink_evasions) > 0 {
		fmt.printf("🔗 Symlink evasions: %d\n", len(result.symlink_evasions))
		for symlink in result.symlink_evasions {
			fmt.printf("  %s -> %s\n", symlink.file_path, symlink.real_path)
		}
		fmt.printf("\n")
	}
	
	fmt.printf("%s\n", header)
	fmt.printf("ACTION REQUIRED:\n")
	fmt.printf("1. Review findings above\n")
	fmt.printf("2. Classify as true positive or false positive\n")
	fmt.printf("3. Document in docs_internal/PHASE1_FALSE_POSITIVE_VALIDATION.md\n")
	fmt.printf("4. Calculate FP rate: (Critical FPs + Warning FPs) / Total Findings\n")
	fmt.printf("5. Target: < 5%% false positive rate\n")
	fmt.printf("%s\n\n", header)
}

@(test)
test_oh_my_zsh_false_positives :: proc(t: ^testing.T) {
	home := get_home_dir()
	omz_path := strings.concatenate({home, "/.oh-my-zsh"})
	defer delete(omz_path)
	
	if !path_exists(omz_path) {
		fmt.printf("SKIP: oh-my-zsh not installed at ~/.oh-my-zsh\n")
		return
	}
	
	fmt.printf("\n🔍 Scanning oh-my-zsh for false positives...\n")
	
	result := security.scan_module(omz_path, security.Scan_Options{unsafe_mode = false})
	defer security.cleanup_scan_result(&result)
	
	format_scan_results("oh-my-zsh", result)
	
	// Soft assertion - log but don't fail
	// User must manually review and classify findings
	if result.critical_count > 0 || result.warning_count > 0 {
		fmt.printf("⚠️  Manual review required - see output above\n")
	}
}

@(test)
test_nvm_false_positives :: proc(t: ^testing.T) {
	home := get_home_dir()
	nvm_path := strings.concatenate({home, "/.nvm"})
	defer delete(nvm_path)
	
	if !path_exists(nvm_path) {
		fmt.printf("SKIP: nvm not installed at ~/.nvm\n")
		return
	}
	
	fmt.printf("\n🔍 Scanning nvm for false positives...\n")
	
	result := security.scan_module(nvm_path, security.Scan_Options{unsafe_mode = false})
	defer security.cleanup_scan_result(&result)
	
	format_scan_results("nvm", result)
	
	if result.critical_count > 0 || result.warning_count > 0 {
		fmt.printf("⚠️  Manual review required - see output above\n")
	}
}

@(test)
test_rbenv_false_positives :: proc(t: ^testing.T) {
	home := get_home_dir()
	rbenv_path := strings.concatenate({home, "/.rbenv"})
	defer delete(rbenv_path)
	
	if !path_exists(rbenv_path) {
		fmt.printf("SKIP: rbenv not installed at ~/.rbenv\n")
		return
	}
	
	fmt.printf("\n🔍 Scanning rbenv for false positives...\n")
	
	result := security.scan_module(rbenv_path, security.Scan_Options{unsafe_mode = false})
	defer security.cleanup_scan_result(&result)
	
	format_scan_results("rbenv", result)
	
	if result.critical_count > 0 || result.warning_count > 0 {
		fmt.printf("⚠️  Manual review required - see output above\n")
	}
}

@(test)
test_pyenv_false_positives :: proc(t: ^testing.T) {
	home := get_home_dir()
	pyenv_path := strings.concatenate({home, "/.pyenv"})
	defer delete(pyenv_path)
	
	if !path_exists(pyenv_path) {
		fmt.printf("SKIP: pyenv not installed at ~/.pyenv\n")
		return
	}
	
	fmt.printf("\n🔍 Scanning pyenv for false positives...\n")
	
	result := security.scan_module(pyenv_path, security.Scan_Options{unsafe_mode = false})
	defer security.cleanup_scan_result(&result)
	
	format_scan_results("pyenv", result)
	
	if result.critical_count > 0 || result.warning_count > 0 {
		fmt.printf("⚠️  Manual review required - see output above\n")
	}
}

@(test)
test_zinit_false_positives :: proc(t: ^testing.T) {
	home := get_home_dir()
	zinit_path := strings.concatenate({home, "/.zinit"})
	defer delete(zinit_path)
	
	if !path_exists(zinit_path) {
		fmt.printf("SKIP: zinit not installed at ~/.zinit\n")
		return
	}
	
	fmt.printf("\n🔍 Scanning zinit for false positives...\n")
	
	result := security.scan_module(zinit_path, security.Scan_Options{unsafe_mode = false})
	defer security.cleanup_scan_result(&result)
	
	format_scan_results("zinit", result)
	
	if result.critical_count > 0 || result.warning_count > 0 {
		fmt.printf("⚠️  Manual review required - see output above\n")
	}
}

@(test)
test_asdf_false_positives :: proc(t: ^testing.T) {
	home := get_home_dir()
	asdf_path := strings.concatenate({home, "/.asdf"})
	defer delete(asdf_path)
	
	if !path_exists(asdf_path) {
		fmt.printf("SKIP: asdf not installed at ~/.asdf\n")
		return
	}
	
	fmt.printf("\n🔍 Scanning asdf for false positives...\n")
	
	result := security.scan_module(asdf_path, security.Scan_Options{unsafe_mode = false})
	defer security.cleanup_scan_result(&result)
	
	format_scan_results("asdf", result)
	
	if result.critical_count > 0 || result.warning_count > 0 {
		fmt.printf("⚠️  Manual review required - see output above\n")
	}
}

// Summary test - runs after all individual tests
@(test)
test_false_positive_validation_summary :: proc(t: ^testing.T) {
	header := strings.repeat("=", 60)
	defer delete(header)
	fmt.printf("\n%s\n", header)
	fmt.printf("FALSE POSITIVE VALIDATION SUMMARY\n")
	fmt.printf("%s\n\n", header)
	
	fmt.printf("Tests completed. Review output above for findings.\n\n")
	
	fmt.printf("Next steps:\n")
	fmt.printf("1. Review all findings from tests above\n")
	fmt.printf("2. Classify each finding as true positive or false positive\n")
	fmt.printf("3. Document results in docs_internal/PHASE1_FALSE_POSITIVE_VALIDATION.md\n")
	fmt.printf("4. Calculate FP rate: (Critical FPs + Warning FPs) / Total Findings\n")
	fmt.printf("5. Target: < 5%% false positive rate\n")
	fmt.printf("6. If FP rate > 5%%, refine patterns and re-test\n")
	fmt.printf("7. Update Phase 1 findings in SCANNER_ENHANCEMENT_PLAN.md\n\n")
	
	fmt.printf("If modules were not available locally:\n")
	fmt.printf("- Mark validation as 'pending real-world validation'\n")
	fmt.printf("- Phase 1 can be completed without this validation\n")
	fmt.printf("- Validation can be done later when modules are available\n\n")
	
	fmt.printf("%s\n", header)
}
