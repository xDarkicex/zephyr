package git

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Update_Stats captures update delta information.
Update_Stats :: struct {
	commits_pulled: int,
	files_changed:  int,
}

// is_git_repository returns true when the path is a git repository.
is_git_repository :: proc(repo_path: string) -> bool {
	if repo_path == "" {
		return false
	}
	if !os.exists(repo_path) {
		return false
	}
	if os.exists(filepath.join({repo_path, ".git"})) {
		return true
	}
	// Fallback to libgit2 open attempt for bare or non-standard layouts.
	path_buf, path_c := to_cstring_buffer(repo_path)
	defer if path_buf != nil { delete(path_buf) }

	repo: ^git_repository
	if git_repository_open(&repo, path_c) < 0 {
		return false
	}
	if repo != nil {
		git_repository_free(repo)
	}
	return true
}

// has_remote_origin returns true if the repository has an origin remote.
has_remote_origin :: proc(repo_path: string) -> bool {
	if repo_path == "" {
		return false
	}
	path_buf, path_c := to_cstring_buffer(repo_path)
	defer if path_buf != nil { delete(path_buf) }

	repo: ^git_repository
	if git_repository_open(&repo, path_c) < 0 {
		return false
	}
	defer if repo != nil { git_repository_free(repo) }

	origin_buf, origin_c := to_cstring_buffer("origin")
	defer if origin_buf != nil { delete(origin_buf) }

	remote: ^git_remote
	if git_remote_lookup(&remote, repo, origin_c) < 0 {
		return false
	}
	if remote != nil {
		git_remote_free(remote)
	}
	return true
}

// get_current_commit returns the current HEAD commit hash.
get_current_commit :: proc(repo_path: string) -> (string, Git_Result) {
	return get_head_commit_hash(repo_path)
}

// get_current_branch returns the current branch name.
get_current_branch :: proc(repo_path: string) -> (string, Git_Result) {
	return get_head_branch(repo_path)
}

// fetch_origin fetches updates from origin.
fetch_origin :: proc(repo_path: string) -> Git_Result {
	return fetch_repository(repo_path)
}

// pull_origin pulls updates for the specified branch (fast-forward reset).
pull_origin :: proc(repo_path: string, branch: string) -> Git_Result {
	return pull_repository_branch(repo_path, branch)
}

// reset_hard performs a hard reset to the given commit.
reset_hard :: proc(repo_path: string, commit_hash: string) -> Git_Result {
	return reset_to_commit(repo_path, commit_hash)
}

// compute_update_stats returns commit and file delta counts between two commits.
compute_update_stats :: proc(repo_path: string, old_hash: string, new_hash: string) -> (Update_Stats, Git_Result) {
	stats := Update_Stats{}
	if old_hash == "" || new_hash == "" {
		return stats, Git_Result{success = false, error = .Revparse_Failed, message = strings.clone("empty commit hash")}
	}
	if old_hash == new_hash {
		return stats, Git_Result{success = true, error = .None}
	}

	commits, commit_result := count_commits_between(repo_path, old_hash, new_hash)
	defer cleanup_git_result(&commit_result)
	if !commit_result.success {
		return stats, commit_result
	}

	files, files_result := count_files_changed_between(repo_path, old_hash, new_hash)
	defer cleanup_git_result(&files_result)
	if !files_result.success {
		return stats, files_result
	}

	stats.commits_pulled = commits
	stats.files_changed = files
	return stats, Git_Result{success = true, error = .None}
}

// format_update_stats formats stats for display.
format_update_stats :: proc(stats: Update_Stats) -> string {
	if stats.commits_pulled == 0 && stats.files_changed == 0 {
		return strings.clone("no changes")
	}
	return strings.clone(fmt.tprintf("%d commits, %d files changed", stats.commits_pulled, stats.files_changed))
}
