package test

import "core:fmt"
import "core:strings"
import "core:testing"

import "../src/security"
import "../src/upgrade"

@(test)
test_upgrade_github_parsing :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	json_text := `[
  {"tag_name":"v1.2.3","published_at":"2026-01-01T00:00:00Z","html_url":"https://example.com/release","prerelease":false,
   "assets":[{"name":"zephyr-darwin-arm64","browser_download_url":"https://example.com/zephyr-darwin-arm64","size":123}]},
  {"tag_name":"v1.2.4-beta","published_at":"2026-01-02T00:00:00Z","html_url":"https://example.com/beta","prerelease":true,
   "assets":[{"name":"zephyr-darwin-arm64","browser_download_url":"https://example.com/zephyr-darwin-arm64-beta","size":456}]}
]`
	json_body := transmute([]u8)json_text

	releases := upgrade.ParseReleasesJSON(json_body)
	defer upgrade.cleanup_release_list(&releases)
	if releases == nil || len(releases) != 2 {
		err := upgrade.get_github_error()
		msg := "should parse releases"
		if err != "" {
			msg = fmt.tprintf("should parse releases (%s)", err)
			delete(err)
		}
		testing.expect(t, false, msg)
		if msg != "" {
			delete(msg)
		}
		return
	}
	if releases == nil || len(releases) < 1 {
		return
	}

	stable := upgrade.filter_by_channel(releases, .Stable)
	testing.expect(t, stable != nil, "stable release should be found")
	if stable != nil {
		testing.expect(t, stable.version == "1.2.3", "stable version should normalize")
	}

	beta := upgrade.filter_by_channel(releases, .Beta)
	testing.expect(t, beta != nil, "beta release should be found")
	if beta != nil {
		testing.expect(t, strings.contains(beta.tag_name, "beta"), "beta tag should contain beta")
	}
}

@(test)
test_upgrade_platform_detection :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	platform := upgrade.DetectPlatform()
	defer delete(platform)
	testing.expect(t, platform != "", "platform should not be empty")
	testing.expect(t, strings.contains(platform, "-"), "platform should include os-arch separator")
}

@(test)
test_upgrade_checksum_verification :: proc(t: ^testing.T) {
	set_test_timeout(t)
	reset_test_state(t)

	data_text := "hello"
	data := transmute([]u8)data_text
	hash := security.compute_sha256_bytes(data)
	expected := security.hex_encode(hash[:])
	defer delete(expected)

	line := strings.clone(fmt.tprintf("%s  zephyr-darwin-arm64", expected))
	defer delete(line)

	testing.expect(t, upgrade.VerifyChecksum(data, line), "checksum should match")
	testing.expect(t, !upgrade.VerifyChecksum(data, "deadbeef"), "checksum mismatch should fail")
}
