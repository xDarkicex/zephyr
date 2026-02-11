package git

import "core:fmt"
import "core:strings"

import "../errors"

// format_install_error builds a user-facing error message for install failures.
format_install_error :: proc(detail: string, module_name: string, suggestion: string = "") -> string {
	ctx := errors.ErrorContext{
		operation   = "install",
		module_name = module_name,
	}
	return format_git_error("Install failed", detail, ctx, suggestion)
}

// format_update_error builds a user-facing error message for update failures.
format_update_error :: proc(detail: string, module_name: string, suggestion: string = "") -> string {
	ctx := errors.ErrorContext{
		operation   = "update",
		module_name = module_name,
	}
	return format_git_error("Update failed", detail, ctx, suggestion)
}

// format_uninstall_error builds a user-facing error message for uninstall failures.
format_uninstall_error :: proc(detail: string, module_name: string, suggestion: string = "") -> string {
	ctx := errors.ErrorContext{
		operation   = "uninstall",
		module_name = module_name,
	}
	return format_git_error("Uninstall failed", detail, ctx, suggestion)
}

// format_validation_error builds a user-facing error message for validation failures.
format_validation_error :: proc(detail: string, module_name: string, suggestion: string = "") -> string {
	ctx := errors.ErrorContext{
		operation   = "validate",
		module_name = module_name,
	}
	return format_git_error("Validation failed", detail, ctx, suggestion)
}

// format_git_error is the shared formatter for git-related errors.
format_git_error :: proc(title: string, detail: string, ctx: errors.ErrorContext, suggestion: string = "") -> string {
	message := detail
	if message == "" {
		message = "unknown error"
	}

	ctx_local := ctx
	if suggestion != "" {
		ctx_local.suggestion = suggestion
	}

	return errors.format_error(title, message, ctx_local)
}

// handle_git_error returns a formatted error with a best-effort suggestion.
handle_git_error :: proc(operation: string, detail: string, module_name: string) -> string {
	lower := strings.to_lower(detail)
	defer delete(lower)

	suggestion := ""
	switch {
	case strings.contains(lower, "permission"):
		suggestion = "Check file permissions and SSH keys."
	case strings.contains(lower, "network") || strings.contains(lower, "timeout"):
		suggestion = "Check your network connection and remote URL."
	case strings.contains(lower, "conflict"):
		suggestion = "Resolve merge conflicts and retry."
	}

	ctx := errors.ErrorContext{
		operation   = operation,
		module_name = module_name,
	}
	return format_git_error("Git error", detail, ctx, suggestion)
}
