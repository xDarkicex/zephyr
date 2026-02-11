package upgrade

import "core:fmt"
import "core:strings"

handle_download_error :: proc(status_code: int, detail: string) -> string {
	if status_code == 404 {
		return strings.clone("download failed (404 not found)")
	}
	if status_code == 403 {
		return strings.clone("download failed (403 forbidden)")
	}
	if status_code >= 500 && status_code <= 599 {
		return strings.clone(fmt.tprintf("download failed (server error %d)", status_code))
	}
	if detail != "" {
		return strings.clone(fmt.tprintf("download failed: %s", detail))
	}
	return strings.clone("download failed")
}
