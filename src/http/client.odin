package http

import "core:fmt"
import "base:runtime"
import "core:strings"

import "../debug"

when #config(ZEPHYR_HAS_CURL, false) {
	foreign import curl "system:curl"

	foreign curl {
		curl_easy_init     :: proc() -> rawptr ---
		curl_easy_cleanup  :: proc(handle: rawptr) ---
		curl_easy_setopt   :: proc(handle: rawptr, option: int, param: rawptr) -> int ---
		curl_easy_perform  :: proc(handle: rawptr) -> int ---
		curl_easy_getinfo  :: proc(handle: rawptr, info: int, param: rawptr) -> int ---
		curl_easy_strerror :: proc(code: int) -> cstring ---
		curl_slist_append  :: proc(list: rawptr, header: cstring) -> rawptr ---
		curl_slist_free_all :: proc(list: rawptr) ---
	}

	HAS_CURL :: true
} else {
	HAS_CURL :: false
}

// Minimal CURL constants (from curl/curl.h).
CURLOPT_URL          :: 10002
CURLOPT_WRITEDATA    :: 10001
CURLOPT_WRITEFUNCTION :: 20011
CURLOPT_USERAGENT    :: 10018
CURLOPT_HTTPHEADER   :: 10023
CURLOPT_FOLLOWLOCATION :: 52
CURLOPT_TIMEOUT      :: 13

CURLINFO_RESPONSE_CODE :: 0x200002

HTTP_Result :: struct {
	ok:          bool,
	status_code: int,
	body:        []u8,
	error:       string,
}

cleanup_http_result :: proc(result: ^HTTP_Result) {
	if result == nil do return
	if result.body != nil {
		delete(result.body)
		result.body = nil
	}
	if result.error != "" {
		delete(result.error)
		result.error = ""
	}
}

HTTP_Buffer :: struct {
	data: [dynamic]u8,
}

// write_callback appends response data into the buffer.
write_callback :: proc "c" (ptr: rawptr, size: u64, nmemb: u64, userdata: rawptr) -> u64 {
	context = runtime.default_context()
	if ptr == nil || userdata == nil {
		return 0
	}
	total := size * nmemb
	if total == 0 {
		return 0
	}
	buffer := cast(^HTTP_Buffer)userdata
	src := cast([^]u8)ptr
	append(&buffer.data, ..src[0:int(total)])
	return total
}

// get performs a simple HTTP GET request and returns response body.
get :: proc(url: string, headers: []string = nil, timeout_seconds: int = 10) -> HTTP_Result {
	result := HTTP_Result{}

	when !HAS_CURL {
		result.error = strings.clone("libcurl not available")
		return result
	}

	if url == "" {
		result.error = strings.clone("empty URL")
		return result
	}

	handle := curl_easy_init()
	if handle == nil {
		result.error = strings.clone("curl_easy_init failed")
		return result
	}
	defer curl_easy_cleanup(handle)

	buffer := HTTP_Buffer{}
	defer if buffer.data != nil { delete(buffer.data) }

	url_c := strings.clone_to_cstring(url)
	defer delete(url_c)
	ua := strings.clone_to_cstring("zephyr/1.0")
	defer delete(ua)

	_ = curl_easy_setopt(handle, CURLOPT_URL, rawptr(url_c))
	_ = curl_easy_setopt(handle, CURLOPT_USERAGENT, rawptr(ua))
	_ = curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, rawptr(write_callback))
	_ = curl_easy_setopt(handle, CURLOPT_WRITEDATA, rawptr(&buffer))
	_ = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, rawptr(uintptr(1)))
	_ = curl_easy_setopt(handle, CURLOPT_TIMEOUT, rawptr(uintptr(timeout_seconds)))

	header_list: rawptr = nil
	if headers != nil && len(headers) > 0 {
		for h in headers {
			h_c := strings.clone_to_cstring(h)
			header_list = curl_slist_append(header_list, h_c)
			delete(h_c)
		}
		if header_list != nil {
			_ = curl_easy_setopt(handle, CURLOPT_HTTPHEADER, header_list)
			defer curl_slist_free_all(header_list)
		}
	}

	code := curl_easy_perform(handle)
	if code != 0 {
		err_msg := curl_easy_strerror(code)
		if err_msg != nil {
			result.error = strings.clone(string(err_msg))
		} else {
			result.error = strings.clone(fmt.tprintf("curl error %d", code))
		}
		return result
	}

	status: i64 = 0
	_ = curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, rawptr(&status))
	result.status_code = int(status)

	result.body = make([]u8, len(buffer.data))
	copy(result.body, buffer.data[:])
	result.ok = true
	return result
}
