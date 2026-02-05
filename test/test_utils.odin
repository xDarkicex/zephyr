package test

import "core:os"
import "core:fmt"
import "core:strings"
import "core:path/filepath"

// remove_directory_recursive removes a directory and all its contents
remove_directory_recursive :: proc(path: string) {
    if !os.exists(path) {
        return
    }
    
    handle, err := os.open(path)
    if err != os.ERROR_NONE {
        return
    }
    defer os.close(handle)
    
    entries, read_err := os.read_dir(handle, -1)
    if read_err != os.ERROR_NONE {
        return
    }
    defer os.file_info_slice_delete(entries)
    
    for entry in entries {
        entry_path := filepath.join({path, entry.name})
        if entry.is_dir {
            remove_directory_recursive(entry_path)
        } else {
            os.remove(entry_path)
        }
    }
    
    os.remove(path)
}

// create_test_module creates a test module directory with manifest
create_test_module :: proc(base_dir: string, module_name: string, dependencies: []string = {}) -> string {
    module_dir := filepath.join({base_dir, module_name})
    os.make_directory(module_dir, 0o755)
    
    manifest_path := filepath.join({module_dir, "module.toml"})
    
    content := fmt.tprintf(`[module]
name = "%s"
version = "1.0.0"
description = "Test module"

[dependencies]
required = [%s]

[load]
files = ["%s.zsh"]
`, module_name, strings.join(dependencies, ", "), module_name)
    
    os.write_entire_file(manifest_path, transmute([]u8)content)
    
    // Create the shell file
    shell_file := filepath.join({module_dir, fmt.tprintf("%s.zsh", module_name)})
    shell_content := fmt.tprintf("# %s module\necho 'Loading %s'\n", module_name, module_name)
    os.write_entire_file(shell_file, transmute([]u8)shell_content)
    
    return module_dir
}

// create_test_shell_file creates a test shell file
create_test_shell_file :: proc(path: string, content: string) -> bool {
    return os.write_entire_file(path, transmute([]u8)content)
}

// cleanup_test_directory removes a test directory
cleanup_test_directory :: proc(dir_path: string) {
    remove_directory_recursive(dir_path)
}