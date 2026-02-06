package test

import "core:fmt"
import "core:strings"
import "core:testing"

import "../src/git"

// **Property 30: Error message completeness**
// **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7**
@(test)
test_property_git_error_message_completeness :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	message := git.format_install_error("clone failed", "demo-module", "check network connectivity")
	normalized := normalize_output_git_error(message)
	lower := strings.to_lower(normalized)
	ansi_free := strip_ansi(message)
	stripped := strings.to_lower(ansi_free)

	testing.expect(t, strings.contains(lower, "install failed"), "message should include title")
	testing.expect(t, strings.contains(lower, "clone failed"), "message should include detail")
	testing.expect(t, strings.contains(lower, "operation"), "message should include operation context")
	testing.expect(t, strings.contains(lower, "install"), "message should include operation name")
	testing.expect(t, strings.contains(lower, "module"), "message should include module context")
	testing.expect(t, strings.contains(lower, "demo-module"), "message should include module name")
	testing.expect(t, strings.contains(lower, "suggested fix"), "message should include suggestion label")
	testing.expect(t, strings.contains(stripped, "network"), "message should include suggestion text")

	delete(message)
	delete(normalized)
	delete(lower)
	delete(stripped)
	delete(ansi_free)
}

// **Property 31: Status symbol usage**
// **Validates: Requirements 7.8**
@(test)
test_property_git_error_status_symbol :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	message := git.format_update_error("fetch failed", "demo-module", "")
	testing.expect(t, strings.contains(message, "✗"), "error output should include status symbol")

	delete(message)
}

normalize_output_git_error :: proc(input: string) -> string {
	if input == "" {
		return strings.clone("")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	i := 0
	for i < len(input) {
		c := input[i]

		if c == 0 {
			i += 1
			continue
		}

		if c == 0x1b { // ESC
			i += 1
			if i < len(input) && input[i] == '[' {
				i += 1
				for i < len(input) && input[i] != 'm' {
					i += 1
				}
				if i < len(input) {
					i += 1
				}
				continue
			}
		}

		if c < 0x20 {
			i += 1
			continue
		}

		fmt.sbprintf(&builder, "%c", c)
		i += 1
	}

	return strings.clone(strings.to_string(builder))
}

strip_ansi :: proc(input: string) -> string {
	if input == "" {
		return strings.clone("")
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	i := 0
	for i < len(input) {
		c := input[i]
		if c == 0x1b {
			i += 1
			if i < len(input) && input[i] == '[' {
				i += 1
				for i < len(input) && input[i] != 'm' {
					i += 1
				}
				if i < len(input) {
					i += 1
				}
				continue
			}
		}
		fmt.sbprintf(&builder, "%c", c)
		i += 1
	}

	return strings.clone(strings.to_string(builder))
}
