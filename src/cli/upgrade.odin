package cli

import "core:fmt"
import "core:os"
import "core:strings"

import "../colors"
import "../upgrade"
import "../version"

Upgrade_Options :: struct {
	check_only: bool,
	force:      bool,
	channel:    upgrade.Release_Channel,
}

upgrade_command :: proc() {
	options := parse_upgrade_options()

	release := upgrade.get_latest_release(options.channel)
	if release == nil {
		err := upgrade.get_last_error()
		if err != "" {
			colors.print_error("%s", err)
			delete(err)
		} else {
			colors.print_error("Failed to fetch releases")
		}
		os.exit(1)
	}
	defer upgrade.cleanup_release_info(release)

	current := strings.clone(version.VERSION)
	defer delete(current)
	latest := release.version
	if latest == "" {
		latest = release.tag_name
	}
	if latest == "" {
		colors.print_error("Release version missing")
		os.exit(1)
	}

	if !is_newer_version(latest, current) {
		fmt.printf("Current version: %s\n", current)
		fmt.printf("Latest version:  %s\n", latest)
		fmt.printf("Zephyr is up to date.\n")
		return
	}

	if options.check_only {
		fmt.printf("Update available: %s -> %s\n", current, latest)
		if release.release_notes_url != "" {
			fmt.printf("Release notes: %s\n", release.release_notes_url)
		}
		fmt.println("Run 'zephyr upgrade' to install.")
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
			return
		}
	}

	if !upgrade.install_release(release) {
		colors.print_error("Upgrade failed.")
		os.exit(1)
	}

	fmt.printf("Successfully upgraded to %s!\n", latest)
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
	fmt.Printf("Upgrade Zephyr to %s?\n", version)
	if notes_url != "" {
		fmt.Printf("Release notes: %s\n", notes_url)
	}
	return prompt_yes_no("Continue with upgrade?", true)
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
