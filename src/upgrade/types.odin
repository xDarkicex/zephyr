package upgrade

import "core:strings"

Release_Info :: struct {
	version:           string,
	tag_name:          string,
	published_at:      string,
	release_notes_url: string,
	assets:            [dynamic]Release_Asset,
	prerelease:        bool,
}

Release_Asset :: struct {
	name:         string,
	download_url: string,
	size:         int,
}

Release_Channel :: enum {
	Stable,
	Beta,
	Nightly,
}

cleanup_release_asset :: proc(asset: ^Release_Asset) {
	if asset == nil do return
	if asset.name != "" {
		delete(asset.name)
		asset.name = ""
	}
	if asset.download_url != "" {
		delete(asset.download_url)
		asset.download_url = ""
	}
}

cleanup_release_info :: proc(info: ^Release_Info) {
	if info == nil do return
	if info.version != "" {
		delete(info.version)
		info.version = ""
	}
	if info.tag_name != "" {
		delete(info.tag_name)
		info.tag_name = ""
	}
	if info.published_at != "" {
		delete(info.published_at)
		info.published_at = ""
	}
	if info.release_notes_url != "" {
		delete(info.release_notes_url)
		info.release_notes_url = ""
	}
	if info.assets != nil {
		for i in 0..<len(info.assets) {
			cleanup_release_asset(&info.assets[i])
		}
		delete(info.assets)
		info.assets = nil
	}
}

cleanup_release_list :: proc(releases: ^[dynamic]Release_Info) {
	if releases == nil || releases^ == nil do return
	for i in 0..<len(releases^) {
		cleanup_release_info(&releases^[i])
	}
	delete(releases^)
	releases^ = nil
}

normalize_version :: proc(tag_name: string) -> string {
	if tag_name == "" {
		return strings.clone("")
	}
	if strings.has_prefix(tag_name, "v") && len(tag_name) > 1 {
		return strings.clone(tag_name[1:])
	}
	return strings.clone(tag_name)
}

clone_release_info :: proc(info: ^Release_Info) -> ^Release_Info {
	if info == nil {
		return nil
	}

	cloned := new(Release_Info)
	cloned.version = strings.clone(info.version)
	cloned.tag_name = strings.clone(info.tag_name)
	cloned.published_at = strings.clone(info.published_at)
	cloned.release_notes_url = strings.clone(info.release_notes_url)
	cloned.prerelease = info.prerelease

	if info.assets != nil && len(info.assets) > 0 {
		cloned.assets = make([dynamic]Release_Asset, 0, len(info.assets))
		for asset in info.assets {
			entry := Release_Asset{
				name = strings.clone(asset.name),
				download_url = strings.clone(asset.download_url),
				size = asset.size,
			}
			append(&cloned.assets, entry)
		}
	}

	return cloned
}
