package git

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

// Git client helpers backed by libgit2.
// Ownership: any non-empty Git_Result.message or returned string is owned by the caller.
// Build-time feature gate; libgit2 must be installed and linked.
LIBGIT2_ENABLED :: true

// Git_Error maps high-level operation failures to stable error codes.
Git_Error :: enum {
	None,
	Init_Failed,
	Shutdown_Failed,
	Clone_Failed,
	Fetch_Failed,
	Pull_Failed,
	Reset_Failed,
	Revparse_Failed,
	Invalid_URL,
	Unknown,
}

// Git_Result wraps success status plus an optional, owned error message.
Git_Result :: struct {
	success: bool,
	error:   Git_Error,
	message: string,
}

// cleanup_git_result frees any owned message string.
cleanup_git_result :: proc(result: ^Git_Result) {
	if result == nil do return
	if result.message != "" {
		delete(result.message)
		result.message = ""
	}
}

// libgit2_enabled reports whether the build is linked with libgit2.
libgit2_enabled :: proc() -> bool {
	return LIBGIT2_ENABLED
}

// init_libgit2 initializes libgit2 for the current process.
init_libgit2 :: proc() -> Git_Result {
	when !LIBGIT2_ENABLED {
		return Git_Result{
			success = false,
			error = .Init_Failed,
			message = strings.clone("libgit2 disabled (build with -define:LIBGIT2_ENABLED=true)"),
		}
	}
	rc := git_libgit2_init()
	if rc < 0 {
		return Git_Result{
			success = false,
			error = .Init_Failed,
			message = clone_git_error_message(),
		}
	}
	return Git_Result{success = true, error = .None}
}

// shutdown_libgit2 shuts down libgit2 for the current process.
shutdown_libgit2 :: proc() -> Git_Result {
	when !LIBGIT2_ENABLED {
		return Git_Result{
			success = false,
			error = .Shutdown_Failed,
			message = strings.clone("libgit2 disabled (build with -define:LIBGIT2_ENABLED=true)"),
		}
	}
	rc := git_libgit2_shutdown()
	if rc < 0 {
		return Git_Result{
			success = false,
			error = .Shutdown_Failed,
			message = clone_git_error_message(),
		}
	}
	return Git_Result{success = true, error = .None}
}

// clone_git_error_message clones the last libgit2 error message (if any).
clone_git_error_message :: proc() -> string {
	when !LIBGIT2_ENABLED {
		return ""
	}
	last := git_error_last()
	if last == nil || last.message == nil do return ""
	return clone_cstring(last.message)
}

// clone_cstring copies a null-terminated C string into an owned Odin string.
clone_cstring :: proc(cstr: cstring) -> string {
	if cstr == nil do return ""
	data := cast([^]u8)cstr
	length := 0
	for data[length] != 0 {
		length += 1
	}
	if length == 0 do return ""
	view := string(data[0:length])
	return strings.clone(view)
}

// clone_repository clones a git repository to a target directory.
// If target_path is empty, a unique temp directory is created and used.
clone_repository :: proc(url: string, target_path: string) -> Git_Result {
	if url == "" {
		return Git_Result{success = false, error = .Invalid_URL, message = strings.clone("empty URL")}
	}
	when !LIBGIT2_ENABLED {
		return Git_Result{
			success = false,
			error = .Clone_Failed,
			message = strings.clone("libgit2 disabled (build with -define:LIBGIT2_ENABLED=true)"),
		}
	}

	final_target := target_path
	if final_target == "" {
		final_target = create_unique_temp_dir("zephyr_git")
		if final_target == "" {
			return Git_Result{success = false, error = .Clone_Failed, message = strings.clone("failed to create temp directory")}
		}
	}

	url_buf, url_c := to_cstring_buffer(url)
	defer if url_buf != nil { delete(url_buf) }

	path_buf, path_c := to_cstring_buffer(final_target)
	defer if path_buf != nil { delete(path_buf) }

	repo: ^git_repository
	rc := git_clone(&repo, url_c, path_c, nil)
	if rc < 0 {
		return Git_Result{
			success = false,
			error = .Clone_Failed,
			message = clone_git_error_message(),
		}
	}

	if repo != nil {
		git_repository_free(repo)
	}

	return Git_Result{success = true, error = .None}
}

// fetch_repository fetches updates from origin for the repository at repo_path.
fetch_repository :: proc(repo_path: string) -> Git_Result {
	if repo_path == "" {
		return Git_Result{success = false, error = .Fetch_Failed, message = strings.clone("empty repository path")}
	}
	when !LIBGIT2_ENABLED {
		return Git_Result{
			success = false,
			error = .Fetch_Failed,
			message = strings.clone("libgit2 disabled (build with libgit2 installed)"),
		}
	}

	path_buf, path_c := to_cstring_buffer(repo_path)
	defer if path_buf != nil { delete(path_buf) }

	repo: ^git_repository
	if git_repository_open(&repo, path_c) < 0 {
		return Git_Result{success = false, error = .Fetch_Failed, message = clone_git_error_message()}
	}
	defer if repo != nil { git_repository_free(repo) }

	origin_buf, origin_c := to_cstring_buffer("origin")
	defer if origin_buf != nil { delete(origin_buf) }

	remote: ^git_remote
	if git_remote_lookup(&remote, repo, origin_c) < 0 {
		return Git_Result{success = false, error = .Fetch_Failed, message = clone_git_error_message()}
	}
	defer if remote != nil { git_remote_free(remote) }

	if git_remote_fetch(remote, nil, nil, nil) < 0 {
		return Git_Result{success = false, error = .Fetch_Failed, message = clone_git_error_message()}
	}

	return Git_Result{success = true, error = .None}
}

// pull_repository performs a fetch and fast-forward reset to origin/main.
pull_repository :: proc(repo_path: string) -> Git_Result {
	if repo_path == "" {
		return Git_Result{success = false, error = .Pull_Failed, message = strings.clone("empty repository path")}
	}
	when !LIBGIT2_ENABLED {
		return Git_Result{
			success = false,
			error = .Pull_Failed,
			message = strings.clone("libgit2 disabled (build with libgit2 installed)"),
		}
	}

	path_buf, path_c := to_cstring_buffer(repo_path)
	defer if path_buf != nil { delete(path_buf) }

	repo: ^git_repository
	if git_repository_open(&repo, path_c) < 0 {
		return Git_Result{success = false, error = .Pull_Failed, message = clone_git_error_message()}
	}
	defer if repo != nil { git_repository_free(repo) }

	origin_buf, origin_c := to_cstring_buffer("origin")
	defer if origin_buf != nil { delete(origin_buf) }

	remote: ^git_remote
	if git_remote_lookup(&remote, repo, origin_c) < 0 {
		return Git_Result{success = false, error = .Pull_Failed, message = clone_git_error_message()}
	}
	defer if remote != nil { git_remote_free(remote) }

	if git_remote_fetch(remote, nil, nil, nil) < 0 {
		return Git_Result{success = false, error = .Pull_Failed, message = clone_git_error_message()}
	}

	// Fast-forward to origin/main for now (simple merge pipeline).
	oid: git_oid
	ref_buf, ref_c := to_cstring_buffer("refs/remotes/origin/main")
	defer if ref_buf != nil { delete(ref_buf) }

	if git_reference_name_to_id(&oid, repo, ref_c) < 0 {
		return Git_Result{success = false, error = .Pull_Failed, message = clone_git_error_message()}
	}

	target: ^git_object
	if git_object_lookup(&target, repo, &oid, .COMMIT) < 0 {
		return Git_Result{success = false, error = .Pull_Failed, message = clone_git_error_message()}
	}
	defer if target != nil { git_object_free(target) }

	if git_reset(repo, target, .HARD, nil) < 0 {
		return Git_Result{success = false, error = .Pull_Failed, message = clone_git_error_message()}
	}

	return Git_Result{success = true, error = .None}
}

// get_head_commit_hash returns the current HEAD commit hash.
get_head_commit_hash :: proc(repo_path: string) -> (string, Git_Result) {
	if repo_path == "" {
		return "", Git_Result{success = false, error = .Revparse_Failed, message = strings.clone("empty repository path")}
	}
	when !LIBGIT2_ENABLED {
		return "", Git_Result{success = false, error = .Revparse_Failed, message = strings.clone("libgit2 disabled (build with libgit2 installed)")}
	}

	path_buf, path_c := to_cstring_buffer(repo_path)
	defer if path_buf != nil { delete(path_buf) }

	repo: ^git_repository
	if git_repository_open(&repo, path_c) < 0 {
		return "", Git_Result{success = false, error = .Revparse_Failed, message = clone_git_error_message()}
	}
	defer if repo != nil { git_repository_free(repo) }

	head: ^git_reference
	if git_repository_head(&head, repo) < 0 {
		return "", Git_Result{success = false, error = .Revparse_Failed, message = clone_git_error_message()}
	}
	defer if head != nil { git_reference_free(head) }

	resolved: ^git_reference
	if git_reference_resolve(&resolved, head) < 0 {
		return "", Git_Result{success = false, error = .Revparse_Failed, message = clone_git_error_message()}
	}
	defer if resolved != nil { git_reference_free(resolved) }

	oid_ptr := git_reference_target(resolved)
	if oid_ptr == nil {
		return "", Git_Result{success = false, error = .Revparse_Failed, message = strings.clone("failed to resolve HEAD target")}
	}

	cs := git_oid_tostr_s(oid_ptr)
	if cs == nil {
		return "", Git_Result{success = false, error = .Revparse_Failed, message = strings.clone("failed to format commit hash")}
	}

	return clone_cstring(cs), Git_Result{success = true, error = .None}
}

// reset_to_commit hard-resets the repository to the given commit hash.
reset_to_commit :: proc(repo_path: string, commit_hash: string) -> Git_Result {
	if repo_path == "" {
		return Git_Result{success = false, error = .Reset_Failed, message = strings.clone("empty repository path")}
	}
	if commit_hash == "" {
		return Git_Result{success = false, error = .Reset_Failed, message = strings.clone("empty commit hash")}
	}
	when !LIBGIT2_ENABLED {
		return Git_Result{success = false, error = .Reset_Failed, message = strings.clone("libgit2 disabled (build with libgit2 installed)")}
	}

	path_buf, path_c := to_cstring_buffer(repo_path)
	defer if path_buf != nil { delete(path_buf) }

	repo: ^git_repository
	if git_repository_open(&repo, path_c) < 0 {
		return Git_Result{success = false, error = .Reset_Failed, message = clone_git_error_message()}
	}
	defer if repo != nil { git_repository_free(repo) }

	hash_buf, hash_c := to_cstring_buffer(commit_hash)
	defer if hash_buf != nil { delete(hash_buf) }

	oid: git_oid
	if git_oid_fromstr(&oid, hash_c) < 0 {
		return Git_Result{success = false, error = .Reset_Failed, message = clone_git_error_message()}
	}

	target: ^git_object
	if git_object_lookup(&target, repo, &oid, .COMMIT) < 0 {
		return Git_Result{success = false, error = .Reset_Failed, message = clone_git_error_message()}
	}
	defer if target != nil { git_object_free(target) }

	if git_reset(repo, target, .HARD, nil) < 0 {
		return Git_Result{success = false, error = .Reset_Failed, message = clone_git_error_message()}
	}

	return Git_Result{success = true, error = .None}
}

// create_unique_temp_dir creates a unique temp directory and returns its path.
create_unique_temp_dir :: proc(prefix: string) -> string {
	base_env := os.get_env("TMPDIR")
	base := ""
	if base_env == "" {
		delete(base_env)
		base = strings.clone("/tmp")
	} else {
		base = strings.clone(base_env)
		delete(base_env)
	}
	defer delete(base)

	timestamp := time.now()._nsec
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "%s_%d", prefix, timestamp)
	name := strings.clone(strings.to_string(builder))
	defer delete(name)

	path := filepath.join({base, name})
	if path == "" do return ""
	if os.exists(path) {
		delete(path)
		return ""
	}
	os.make_directory(path, 0o755)
	return path
}

// to_cstring_buffer returns a null-terminated byte buffer and cstring view.
// The returned buffer must be deleted by the caller.
to_cstring_buffer :: proc(s: string) -> ([]u8, cstring) {
	if s == "" do return nil, nil
	buf := make([]u8, len(s)+1)
	copy(buf[:len(s)], s)
	buf[len(s)] = 0
	return buf, cast(cstring)&buf[0]
}

// libgit2 FFI
when LIBGIT2_ENABLED {
	foreign import "system:git2"

	foreign git2 {
		git_libgit2_init :: proc() -> c.int ---
		git_libgit2_shutdown :: proc() -> c.int ---
		git_error_last :: proc() -> ^git_error ---
		git_clone :: proc(out: ^^git_repository, url: cstring, path: cstring, options: ^git_clone_options) -> c.int ---
		git_repository_free :: proc(repo: ^git_repository) ---
		git_repository_open :: proc(out: ^^git_repository, path: cstring) -> c.int ---
		git_repository_head :: proc(out: ^^git_reference, repo: ^git_repository) -> c.int ---
		git_remote_lookup :: proc(out: ^^git_remote, repo: ^git_repository, name: cstring) -> c.int ---
		git_remote_fetch :: proc(remote: ^git_remote, refspecs: ^git_strarray, opts: ^git_fetch_options, reflog_message: cstring) -> c.int ---
		git_remote_free :: proc(remote: ^git_remote) ---
		git_reference_resolve :: proc(out: ^^git_reference, ref: ^git_reference) -> c.int ---
		git_reference_target :: proc(ref: ^git_reference) -> ^git_oid ---
		git_reference_free :: proc(ref: ^git_reference) ---
		git_reference_name_to_id :: proc(out: ^git_oid, repo: ^git_repository, name: cstring) -> c.int ---
		git_object_lookup :: proc(out: ^^git_object, repo: ^git_repository, id: ^git_oid, kind: git_object_t) -> c.int ---
		git_object_free :: proc(obj: ^git_object) ---
		git_reset :: proc(repo: ^git_repository, target: ^git_object, reset_type: git_reset_t, checkout_opts: ^git_checkout_options) -> c.int ---
		git_oid_fromstr :: proc(out: ^git_oid, str: cstring) -> c.int ---
		git_oid_tostr_s :: proc(id: ^git_oid) -> cstring ---
	}
} else {
	git_libgit2_init :: proc() -> c.int { return -1 }
	git_libgit2_shutdown :: proc() -> c.int { return -1 }
	git_error_last :: proc() -> ^git_error { return nil }
	git_clone :: proc(out: ^^git_repository, url: cstring, path: cstring, options: ^git_clone_options) -> c.int { return -1 }
	git_repository_free :: proc(repo: ^git_repository) {}
	git_repository_open :: proc(out: ^^git_repository, path: cstring) -> c.int { return -1 }
	git_repository_head :: proc(out: ^^git_reference, repo: ^git_repository) -> c.int { return -1 }
	git_remote_lookup :: proc(out: ^^git_remote, repo: ^git_repository, name: cstring) -> c.int { return -1 }
	git_remote_fetch :: proc(remote: ^git_remote, refspecs: ^git_strarray, opts: ^git_fetch_options, reflog_message: cstring) -> c.int { return -1 }
	git_remote_free :: proc(remote: ^git_remote) {}
	git_reference_resolve :: proc(out: ^^git_reference, ref: ^git_reference) -> c.int { return -1 }
	git_reference_target :: proc(ref: ^git_reference) -> ^git_oid { return nil }
	git_reference_free :: proc(ref: ^git_reference) {}
	git_reference_name_to_id :: proc(out: ^git_oid, repo: ^git_repository, name: cstring) -> c.int { return -1 }
	git_object_lookup :: proc(out: ^^git_object, repo: ^git_repository, id: ^git_oid, kind: git_object_t) -> c.int { return -1 }
	git_object_free :: proc(obj: ^git_object) {}
	git_reset :: proc(repo: ^git_repository, target: ^git_object, reset_type: git_reset_t, checkout_opts: ^git_checkout_options) -> c.int { return -1 }
	git_oid_fromstr :: proc(out: ^git_oid, str: cstring) -> c.int { return -1 }
	git_oid_tostr_s :: proc(id: ^git_oid) -> cstring { return nil }
}

git_error :: struct {
	message: cstring,
	klass:   c.int,
}

git_repository :: struct {}
git_clone_options :: struct {}
git_remote :: struct {}
git_reference :: struct {}
git_object :: struct {}
git_checkout_options :: struct {}
git_object_t :: enum c.int {
	ANY    = -2,
	COMMIT = 1,
}
git_reset_t :: enum c.int {
	SOFT  = 1,
	MIXED = 2,
	HARD  = 3,
}
git_oid :: struct {
	id: [20]u8,
}
git_strarray :: struct {
	strings: ^cstring,
	count:   c.size_t,
}
git_fetch_options :: struct {}
