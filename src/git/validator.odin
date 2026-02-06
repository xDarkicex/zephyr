package git

import "core:os"
import "core:path/filepath"
import "core:strings"

import "../manifest"
import "../loader"

// Validation pipeline for git-installed modules.
// Ownership: Validation_Result strings and missing_files are owned by the caller.

// Validation_Error enumerates validation failures for module manifests.
Validation_Error :: enum {
	None,
	No_Manifest,
	Invalid_Manifest,
	Name_Mismatch,
	Platform_Incompatible,
	Missing_Files,
	Validation_Failed,
}

// Validation_Result captures validation status plus details.
Validation_Result :: struct {
	valid:         bool,
	error:         Validation_Error,
	message:       string,
	warning:       string,
	missing_files: [dynamic]string,
	module:        manifest.Module,
}

// cleanup_validation_result frees all owned strings and arrays.
cleanup_validation_result :: proc(result: ^Validation_Result) {
	if result == nil do return

	if result.message != "" {
		delete(result.message)
		result.message = ""
	}
	if result.warning != "" {
		delete(result.warning)
		result.warning = ""
	}
	if result.missing_files != nil {
		for file in result.missing_files {
			if file != "" {
				delete(file)
			}
		}
		delete(result.missing_files)
		result.missing_files = nil
	}

	manifest.cleanup_module(&result.module)
	result.valid = false
	result.error = .None
}

// validate_module runs the full validation pipeline for a module path.
validate_module :: proc(module_path: string, expected_name: string) -> Validation_Result {
	result := Validation_Result{}
	result.missing_files = make([dynamic]string)

	if !validate_manifest_exists(module_path) {
		result.error = .No_Manifest
		result.message = strings.clone("module.toml not found")
		return result
	}

	module, ok, err := validate_manifest_format(module_path)
	if !ok {
		result.error = .Invalid_Manifest
		result.message = err
		return result
	}
	result.module = module

	if result.module.name == "" {
		result.error = .Invalid_Manifest
		result.message = strings.clone("manifest missing name field")
		manifest.cleanup_module(&result.module)
		return result
	}

	if expected_name != "" && result.module.name != expected_name {
		result.warning = strings.clone("module name does not match expected name")
	}

	if !validate_platform_compatibility(&result.module) {
		result.error = .Platform_Incompatible
		result.message = strings.clone("module is not compatible with current platform")
		return result
	}

	missing := validate_load_files(module_path, &result.module)
	if len(missing) > 0 {
		result.error = .Missing_Files
		result.message = strings.clone("missing load files")
		if result.missing_files != nil {
			delete(result.missing_files)
			result.missing_files = nil
		}
		// Transfer ownership of missing files to the result.
		result.missing_files = missing
		return result
	}
	delete(missing)

	result.valid = true
	result.error = .None
	return result
}

// validate_manifest_exists checks for module.toml.
validate_manifest_exists :: proc(module_path: string) -> bool {
	manifest_path := filepath.join({module_path, "module.toml"})
	defer delete(manifest_path)
	return os.exists(manifest_path)
}

// validate_manifest_format parses module.toml and returns a module plus error text.
validate_manifest_format :: proc(module_path: string) -> (manifest.Module, bool, string) {
	manifest_path := filepath.join({module_path, "module.toml"})
	defer delete(manifest_path)

	parsed := manifest.parse_detailed(manifest_path)
	if parsed.error != .None {
		err := parsed.message
		parsed.message = ""
		return manifest.Module{}, false, err
	}

	if parsed.message != "" {
		delete(parsed.message)
		parsed.message = ""
	}

	return parsed.module, true, ""
}

// validate_platform_compatibility returns true when module supports current platform.
validate_platform_compatibility :: proc(module: ^manifest.Module) -> bool {
	current := loader.get_current_platform()
	defer loader.cleanup_platform_info(&current)
	return loader.is_platform_compatible(module, current)
}

// validate_load_files returns missing load files relative to module_path.
validate_load_files :: proc(module_path: string, module: ^manifest.Module) -> [dynamic]string {
	missing := make([dynamic]string)
	if module == nil do return missing

	for file in module.files {
		if file == "" do continue
		path := filepath.join({module_path, file})
		if !os.exists(path) {
			append(&missing, strings.clone(file))
		}
		delete(path)
	}

	return missing
}
