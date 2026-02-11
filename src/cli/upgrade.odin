package cli

import "core:fmt"
import "core:os"
import "core:strings"

import "../colors"
import "../security"
import "../upgrade"
import "../version"

Upgrade_Options :: struct {
	check_only: bool,
	force:      bool,
	channel:    upgrade.Release_Channel,
}

upgrade_command :: proc() {
	options := parse_upgrade_options()

	if !check_upgrade_permissions() {
		colors.print_error("Permission denied: agents cannot run upgrade")
		security.log_zephyr_upgrade(version.VERSION, "", false, "permission denied")
		os.exit(2)
	}

	release := upgrade.get_latest_release(options.channel)
	if release == nil {
		err := upgrade.get_github_error()
		if err != "" {
			colors.print_error("%s", err)
			security.log_zephyr_upgrade(version.VERSION, "", false, err)
			delete(err)
		} else {
			colors.print_error("Failed to fetch releases")
			security.log_zephyr_upgrade(version.VERSION, "", false, "failed to fetch releases")
		}
		os.exit(exit_code_for_upgrade_error(err))
	}
	defer upgrade.destroy_release_info(release)

	current := strings.clone(version.VERSION)
	defer delete(current)
	latest := release.version
	if latest == "" {
		latest = release.tag_name
	}
	if latest == "" {
		colors.print_error("Release version missing")
		security.log_zephyr_upgrade(version.VERSION, "", false, "release version missing")
		os.exit(4)
	}

	if !is_newer_version(latest, current) {
		fmt.printf("Current version: %s\n", current)
		fmt.printf("Latest version:  %s\n", latest)
		fmt.printf("Zephyr is up to date.\n")
		if options.check_only {
			security.log_zephyr_upgrade(current, latest, true, "up to date")
		}
		return
	}

	if options.check_only {
		fmt.printf("Update available: %s -> %s\n", current, latest)
		if release.release_notes_url != "" {
			fmt.printf("Release notes: %s\n", release.release_notes_url)
		}
		fmt.println("Run 'zephyr upgrade' to install.")
		security.log_zephyr_upgrade(current, latest, true, "check only")
		return
	}

	fmt.printf("Current version: %s\n", current)
	fmt.printf("Latest version:  %s\n", latest)
	if release.release_notes_url != "" {
		fmt.printf("Release notes: %s\n", release.release_notes_url)
	}

	if !options.force {
		if !confirm_upgrade(latest, release.release_notes_url) {
			fmt.println("Upgrade cancelled.")
			security.log_zephyr_upgrade(current, latest, false, "cancelled by user")
			return
		}
	}

	if !upgrade.install_release(release) {
		install_err := upgrade.get_last_error()
		if install_err != "" {
			colors.print_error("Upgrade failed: %s", install_err)
			security.log_zephyr_upgrade(current, latest, false, install_err)
		} else {
			colors.print_error("Upgrade failed.")
			security.log_zephyr_upgrade(current, latest, false, "install failed")
		}
		code := exit_code_for_upgrade_error(install_err)
		if install_err != "" {
			delete(install_err)
		}
		os.exit(code)
	}

	fmt.printf("Successfully upgraded to %s!\n", latest)
	security.log_zephyr_upgrade(current, latest, true, "")
}

exit_code_for_upgrade_error :: proc(message: string) -> int {
	if message == "" {
		return 1
	}
	lower := strings.to_lower(message)
	defer delete(lower)
	if strings.contains(lower, "permission") {
		return 2
	}
	if strings.contains(lower, "network") || strings.contains(lower, "rate limit") {
		return 3
	}
	if strings.contains(lower, "checksum") || strings.contains(lower, "validation") {
		return 4
	}
	if strings.contains(lower, "disk") || strings.contains(lower, "space") {
		return 1
	}
	return 1
}

parse_upgrade_options :: proc() -> Upgrade_Options {
	opts := Upgrade_Options{
		check_only = false,
		force = false,
		channel = .Stable,
	}

	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		if arg == "upgrade" {
			continue
		}
		if arg == "--check" {
			opts.check_only = true
			continue
		}
		if arg == "--force" {
			opts.force = true
			continue
		}
		if strings.has_prefix(arg, "--channel=") {
			value := strings.trim_prefix(arg, "--channel=")
			opts.channel = parse_release_channel(value)
			continue
		}
		if arg == "--channel" && i+1 < len(args) {
			opts.channel = parse_release_channel(args[i+1])
			i += 1
			continue
		}
	}

	return opts
}

parse_release_channel :: proc(value: string) -> upgrade.Release_Channel {
	if value == "" {
		return .Stable
	}
	lower := strings.to_lower(value)
	defer delete(lower)
	switch lower {
	case "stable":
		return .Stable
	case "beta":
		return .Beta
	case "nightly":
		return .Nightly
	}
	return .Stable
}

confirm_upgrade :: proc(version: string, notes_url: string) -> bool {
	fmt.printf("Upgrade Zephyr to %s?\n", version)
	if notes_url != "" {
		fmt.printf("Release notes: %s\n", notes_url)
	}
	return prompt_yes_no("Continue with upgrade?", true)
}

check_upgrade_permissions :: proc() -> bool {
	return !security.is_agent_environment()
}

is_newer_version :: proc(latest: string, current: string) -> bool {
	if latest == "" {
		return false
	}
	if current == "" {
		return true
	}
	if current == "dev" {
		return true
	}
	if latest == "dev" {
		return false
	}

	latest_parts := parse_version_parts(latest)
	defer delete(latest_parts)
	current_parts := parse_version_parts(current)
	defer delete(current_parts)

	max_len := len(latest_parts)
	if len(current_parts) > max_len {
		max_len = len(current_parts)
	}

	for i := 0; i < max_len; i += 1 {
		latest_value := 0
		current_value := 0
		if i < len(latest_parts) {
			latest_value = latest_parts[i]
		}
		if i < len(current_parts) {
			current_value = current_parts[i]
		}
		if latest_value > current_value {
			return true
		}
		if latest_value < current_value {
			return false
		}
	}

	return false
}

// IsNewerVersion exposes version comparison for tests.
IsNewerVersion :: proc(latest: string, current: string) -> bool {
	return is_newer_version(latest, current)
}

parse_version_parts :: proc(version_str: string) -> [dynamic]int {
	if version_str == "" {
		return make([dynamic]int)
	}

	trimmed := version_str
	if strings.has_prefix(trimmed, "v") && len(trimmed) > 1 {
		trimmed = trimmed[1:]
	}

	if dash := strings.index(trimmed, "-"); dash >= 0 {
		trimmed = trimmed[:dash]
	}

	parts := strings.split(trimmed, ".")
	defer delete(parts)

	values := make([dynamic]int, 0, len(parts))
	for part in parts {
		value := parse_version_part(part)
		append(&values, value)
	}

	return values
}

parse_version_part :: proc(part: string) -> int {
	if part == "" {
		return 0
	}
	value := 0
	for ch in part {
		if ch < '0' || ch > '9' {
			break
		}
		value = value*10 + int(ch-'0')
	}
	return value
}
