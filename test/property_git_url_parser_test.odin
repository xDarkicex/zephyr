package test

import "core:fmt"
import "core:testing"
import "core:strings"

import "../src/git"

// **Property 1: URL parsing normalization**
// **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5**
@(test)
test_property_git_url_parsing :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	cases := []struct{ input: string, expected: string }{
		{"https://github.com/user/zephyr-module-foo.git", "foo"},
		{"https://github.com/user/zephyr-foo", "foo"},
		{"git@github.com:user/zephyr-module-bar.git", "bar"},
		{"git://git.example.com/team/baz.git", "baz"},
		{"https://git.company.com/team/awesome-module", "awesome-module"},
	}

	for c in cases {
		result := git.parse_module_name_from_url(c.input)
		defer git.cleanup_url_parse_result(&result)
		testing.expect(
			t,
			result.valid,
			fmt.tprintf("URL should parse successfully (error: %s)", result.error),
		)
		testing.expect(
			t,
			result.module_name == c.expected,
			fmt.tprintf("expected '%s' got '%s' for '%s'", c.expected, result.module_name, c.input),
		)
	}
}

@(test)
test_property_git_url_shorthand :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	source := git.parse_install_source("user/zephyr-module-foo", false)
	defer git.cleanup_install_source(&source)

	testing.expect(t, source.valid, "GitHub shorthand should be valid")
	testing.expect(t, source.source_type == .GitHub_Shorthand, "Source type should be GitHub_Shorthand")
	testing.expect(t, strings.has_prefix(source.url, "https://github.com/"), "Shorthand should expand to GitHub URL")
}

@(test)
test_property_git_url_validation :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	invalids := []string{
		"",
		"htp://bad-url",
		"not a url",
		"git@github.com",
	}

	for input in invalids {
		result := git.parse_module_name_from_url(input)
		defer git.cleanup_url_parse_result(&result)
		testing.expect(t, !result.valid, "Invalid URL should not parse")
	}
}
