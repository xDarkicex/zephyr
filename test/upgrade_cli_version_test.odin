package test

import "core:testing"

import "../src/cli"

@(test)
test_upgrade_version_comparison :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	testing.expect(t, cli.IsNewerVersion("1.2.0", "1.1.9"), "newer version should be detected")
	testing.expect(t, !cli.IsNewerVersion("1.2.0", "1.2.0"), "same version should not be newer")
	testing.expect(t, !cli.IsNewerVersion("1.2.0", "1.3.0"), "older version should not be newer")
	testing.expect(t, cli.IsNewerVersion("v2.0.0", "1.9.9"), "v prefix should be ignored")
}
