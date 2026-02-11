package upgrade

import "core:encoding/json"
import "core:fmt"
import "core:strings"

import "../http"

GITHUB_API_URL :: "https://api.github.com/repos/zephyr-systems/zephyr/releases"

GitHub_Release :: struct {
	tag_name:     string,
	published_at: string,
	html_url:     string,
	prerelease:   bool,
	assets:       [dynamic]GitHub_Asset,
}

GitHub_Asset :: struct {
	name:                 string,
	browser_download_url: string,
	size:                 int,
}

last_error: string

set_last_error :: proc(message: string) {
	if last_error != "" {
		delete(last_error)
		last_error = ""
	}
	if message != "" {
		last_error = strings.clone(message)
	}
}

get_last_error :: proc() -> string {
	if last_error == "" {
		return strings.clone("")
	}
	return strings.clone(last_error)
}

cleanup_github_asset :: proc(asset: ^GitHub_Asset) {
	if asset == nil do return
	if asset.name != "" {
		delete(asset.name)
		asset.name = ""
	}
	if asset.browser_download_url != "" {
		delete(asset.browser_download_url)
		asset.browser_download_url = ""
	}
}

cleanup_github_release :: proc(release: ^GitHub_Release) {
	if release == nil do return
	if release.tag_name != "" {
		delete(release.tag_name)
		release.tag_name = ""
	}
	if release.published_at != "" {
		delete(release.published_at)
		release.published_at = ""
	}
	if release.html_url != "" {
		delete(release.html_url)
		release.html_url = ""
	}
	if release.assets != nil {
		for i in 0..<len(release.assets) {
			cleanup_github_asset(&release.assets[i])
		}
		delete(release.assets)
		release.assets = nil
	}
}

cleanup_github_releases :: proc(releases: ^[dynamic]GitHub_Release) {
	if releases == nil || releases^ == nil do return
	for i in 0..<len(releases^) {
		cleanup_github_release(&releases^[i])
	}
	delete(releases^)
	releases^ = nil
}

get_latest_release :: proc(channel: Release_Channel) -> ^Release_Info {
	set_last_error("")

	headers := []string{
		"Accept: application/vnd.github+json",
	}
	response := http.get(GITHUB_API_URL, headers, 10)
	defer http.cleanup_http_result(&response)

	if !response.ok {
		if response.error != "" {
			set_last_error(response.error)
		} else {
			set_last_error("GitHub API request failed")
		}
		return nil
	}
	if response.status_code != 200 {
		set_last_error(fmt.tprintf("GitHub API returned HTTP %d", response.status_code))
		return nil
	}

	releases := parse_releases_json(response.body)
	if releases == nil || len(releases) == 0 {
		cleanup_release_list(&releases)
		set_last_error("No releases found")
		return nil
	}

	release := filter_by_channel(releases, channel)
	if release == nil {
		cleanup_release_list(&releases)
		set_last_error("No matching release found for channel")
		return nil
	}

	cloned := clone_release_info(release)
	cleanup_release_list(&releases)
	return cloned
}

parse_releases_json :: proc(json_data: []u8) -> [dynamic]Release_Info {
	releases := make([dynamic]GitHub_Release)
	unmarshal_err := json.unmarshal(json_data, &releases)
	if unmarshal_err != .None {
		cleanup_github_releases(&releases)
		set_last_error("Failed to parse GitHub releases JSON")
		return nil
	}
	defer cleanup_github_releases(&releases)

	out := make([dynamic]Release_Info, 0, len(releases))
	for release in releases {
		info := Release_Info{
			tag_name = strings.clone(release.tag_name),
			version = normalize_version(release.tag_name),
			published_at = strings.clone(release.published_at),
			release_notes_url = strings.clone(release.html_url),
			prerelease = release.prerelease,
		}

		if release.assets != nil && len(release.assets) > 0 {
			info.assets = make([dynamic]Release_Asset, 0, len(release.assets))
			for asset in release.assets {
				entry := Release_Asset{
					name = strings.clone(asset.name),
					download_url = strings.clone(asset.browser_download_url),
					size = asset.size,
				}
				append(&info.assets, entry)
			}
		}

		append(&out, info)
	}

	return out
}

filter_by_channel :: proc(releases: [dynamic]Release_Info, channel: Release_Channel) -> ^Release_Info {
	switch channel {
	case .Stable:
		for i in 0..<len(releases) {
			release := &releases[i]
			if !is_prerelease(release) && !is_beta(release.tag_name) {
				return release
			}
		}
	case .Beta:
		for i in 0..<len(releases) {
			release := &releases[i]
			if is_beta(release.tag_name) {
				return release
			}
		}
	case .Nightly:
		if len(releases) > 0 {
			return &releases[0]
		}
	}
	return nil
}

is_prerelease :: proc(release: ^Release_Info) -> bool {
	if release == nil {
		return false
	}
	return release.prerelease
}

is_beta :: proc(tag_name: string) -> bool {
	if tag_name == "" {
		return false
	}
	lower := strings.to_lower(tag_name)
	defer delete(lower)
	if strings.contains(lower, "beta") {
		return true
	}
	if strings.contains(lower, "rc") {
		return true
	}
	if strings.contains(lower, "alpha") {
		return true
	}
	return false
}
