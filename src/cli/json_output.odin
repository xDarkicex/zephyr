package cli

import "core:time"
import "core:strings"
import "core:fmt"
import "core:encoding/json"
import "core:os"
import "../manifest"
import "../loader"
import "../colors"

// JSON_Output represents the complete JSON response structure
JSON_Output :: struct {
    schema_version:       string,
    generated_at:         string,
    environment:          Environment_Info,
    summary:              Summary_Info,
    modules:              [dynamic]Module_Info,
    incompatible_modules: [dynamic]Incompatible_Module_Info,
    dependency_graph:     Dependency_Graph_Info,
}

// Environment_Info contains system and Zephyr environment details
Environment_Info :: struct {
    zephyr_version:  string,
    modules_dir:     string,
    os:              string,
    arch:            string,
    shell:           string,
    shell_version:   string,
}

// Summary_Info contains aggregate statistics
Summary_Info :: struct {
    total_modules:        int,
    compatible_modules:   int,
    incompatible_modules: int,
}

// Module_Info contains detailed information about a compatible module
Module_Info :: struct {
    name:                 string,
    version:              string,
    description:          string,
    author:               string,
    license:              string,
    path:                 string,
    load_order:           int,
    priority:             int,
    dependencies:         Dependencies_Info,
    missing_dependencies: [dynamic]string,
    platforms:            Platform_Info_JSON,
    load:                 Load_Info,
    hooks:                Hooks_Info,
    settings:             map[string]string,
    exports:              Exports_Info,
}

// Dependencies_Info contains required and optional dependencies
Dependencies_Info :: struct {
    required: [dynamic]string,
    optional: [dynamic]string,
}

// Platform_Info_JSON contains platform compatibility requirements
Platform_Info_JSON :: struct {
    os:          [dynamic]string,
    arch:        [dynamic]string,
    shell:       string,
    min_version: string,
}

// Load_Info contains module loading configuration
Load_Info :: struct {
    files: [dynamic]string,
}

// Hooks_Info contains pre/post load hook function names
Hooks_Info :: struct {
    pre_load:  string,
    post_load: string,
}

// Exports_Info contains discovered exports from module files
Exports_Info :: struct {
    functions:             [dynamic]string,
    aliases:               [dynamic]string,
    environment_variables: [dynamic]string,
}

// Incompatible_Module_Info contains information about incompatible modules
Incompatible_Module_Info :: struct {
    name:        string,
    version:     string,
    description: string,
    path:        string,
    reason:      string,
    platforms:   Platform_Info_JSON,
}

Dependency_Graph_Info :: struct {
    format:  string,
    content: string,
}

// generate_json_output creates the complete JSON output structure and marshals it
// Returns the JSON bytes and any marshal error
generate_json_output :: proc(
    modules_dir: string,
    all_modules: [dynamic]manifest.Module,
    compatible_indices: [dynamic]int,
    resolved_modules: [dynamic]manifest.Module,
    filter: string,
    pretty: bool,
) -> ([]u8, json.Marshal_Error) {
    output := build_json_output_struct(
        modules_dir,
        all_modules,
        compatible_indices,
        resolved_modules,
        filter,
    )
    defer cleanup_json_output(&output)

    // Marshal BEFORE cleanup
    options := json.Marshal_Options{
        pretty = pretty,
        use_spaces = true,
        spaces = 2,
    }
    
    json_bytes, marshal_err := json.marshal(output, options)
    
    return json_bytes, marshal_err
}

generate_json_with_graph :: proc(
    modules_dir: string,
    all_modules: [dynamic]manifest.Module,
    compatible_indices: [dynamic]int,
    resolved_modules: [dynamic]manifest.Module,
    filter: string,
    pretty: bool,
    graph_format: string,
    verbose: bool,
) -> ([]u8, json.Marshal_Error) {
    output := build_json_output_struct(
        modules_dir,
        all_modules,
        compatible_indices,
        resolved_modules,
        filter,
    )
    defer cleanup_json_output(&output)

    if graph_format == "mermaid" {
        graph_content := generate_mermaid_graph(resolved_modules, verbose)
        output.dependency_graph = Dependency_Graph_Info{
            format = strings.clone("mermaid"),
            content = graph_content,
        }
    }

    options := json.Marshal_Options{
        pretty = pretty,
        use_spaces = true,
        spaces = 2,
    }

    return json.marshal(output, options)
}

build_json_output_struct :: proc(
    modules_dir: string,
    all_modules: [dynamic]manifest.Module,
    compatible_indices: [dynamic]int,
    resolved_modules: [dynamic]manifest.Module,
    filter: string,
) -> JSON_Output {
    platform := loader.get_current_platform()
    defer loader.cleanup_platform_info(&platform)

    env := Environment_Info{
        zephyr_version = "1.0.0",
        modules_dir = strings.clone(modules_dir),
        os = strings.clone(platform.os),
        arch = strings.clone(platform.arch),
        shell = strings.clone(platform.shell),
        shell_version = strings.clone(platform.version),
    }

    modules_info := make([dynamic]Module_Info)
    for module, idx in resolved_modules {
        if filter != "" {
            module_name_lower := strings.to_lower(module.name)
            filter_lower := strings.to_lower(filter)
            contains_filter := strings.contains(module_name_lower, filter_lower)
            delete(module_name_lower)
            delete(filter_lower)
            if !contains_filter {
                continue
            }
        }

        module_info := build_module_info(module, idx + 1, all_modules)
        append(&modules_info, module_info)
    }

    incompatible_info := make([dynamic]Incompatible_Module_Info)
    for module, idx in all_modules {
        is_compatible := false
        for comp_idx in compatible_indices {
            if comp_idx == idx {
                is_compatible = true
                break
            }
        }

        if !is_compatible {
            if filter != "" {
                module_name_lower := strings.to_lower(module.name)
                filter_lower := strings.to_lower(filter)
                contains_filter := strings.contains(module_name_lower, filter_lower)
                delete(module_name_lower)
                delete(filter_lower)
                if !contains_filter {
                    continue
                }
            }

            incomp_info := build_incompatible_module_info(module, platform)
            append(&incompatible_info, incomp_info)
        }
    }

    summary := Summary_Info{
        total_modules = len(modules_info) + len(incompatible_info),
        compatible_modules = len(modules_info),
        incompatible_modules = len(incompatible_info),
    }

    now := time.now()
    timestamp := fmt.tprintf("%v", now)

    return JSON_Output{
        schema_version = strings.clone("1.0"),
        generated_at = strings.clone(timestamp),
        environment = env,
        summary = summary,
        modules = modules_info,
        incompatible_modules = incompatible_info,
        dependency_graph = Dependency_Graph_Info{},
    }
}

// build_module_info constructs Module_Info from a manifest.Module
build_module_info :: proc(
    module: manifest.Module, 
    load_order: int,
    all_modules: [dynamic]manifest.Module,
) -> Module_Info {
    
    // Discover exports
    exports := discover_exports(module)
    
    // Find missing optional dependencies
    missing_deps := make([dynamic]string)
    for opt_dep in module.optional {
        found := false
        for other_module in all_modules {
            if other_module.name == opt_dep {
                found = true
                break
            }
        }
        if !found {
            append(&missing_deps, strings.clone(opt_dep))
        }
    }
    
    // Convert platform filter to JSON format
    platform_os := make([dynamic]string)
    for os_name in module.platforms.os {
        append(&platform_os, strings.clone(os_name))
    }
    
    platform_arch := make([dynamic]string)
    for arch_name in module.platforms.arch {
        append(&platform_arch, strings.clone(arch_name))
    }
    
    platform_json := Platform_Info_JSON{
        os = platform_os,  // Keep as dynamic array
        arch = platform_arch,  // Keep as dynamic array
        shell = strings.clone(module.platforms.shell),
        min_version = strings.clone(module.platforms.min_version),
    }
    
    // Convert dependencies
    required_deps := make([dynamic]string)
    for dep in module.required {
        append(&required_deps, strings.clone(dep))
    }
    
    optional_deps := make([dynamic]string)
    for dep in module.optional {
        append(&optional_deps, strings.clone(dep))
    }
    
    // Convert files
    files := make([dynamic]string)
    for file in module.files {
        append(&files, strings.clone(file))
    }
    
    // Clone settings map
    settings_map := make(map[string]string)
    for key, value in module.settings {
        settings_map[strings.clone(key)] = strings.clone(value)
    }
    
    return Module_Info{
        name = strings.clone(module.name),
        version = strings.clone(module.version),
        description = strings.clone(module.description),
        author = strings.clone(module.author),
        license = strings.clone(module.license),
        path = strings.clone(module.path),
        load_order = load_order,
        priority = module.priority,
        dependencies = Dependencies_Info{
            required = required_deps,  // Keep as dynamic array
            optional = optional_deps,  // Keep as dynamic array
        },
        missing_dependencies = missing_deps,  // Keep as dynamic array
        platforms = platform_json,
        load = Load_Info{
            files = files,  // Keep as dynamic array
        },
        hooks = Hooks_Info{
            pre_load = strings.clone(module.hooks.pre_load),
            post_load = strings.clone(module.hooks.post_load),
        },
        settings = settings_map,
        exports = exports,
    }
}

// build_incompatible_module_info constructs Incompatible_Module_Info
build_incompatible_module_info :: proc(
    module: manifest.Module,
    current_platform: loader.Platform_Info,
) -> Incompatible_Module_Info {
    
    // Determine incompatibility reason
    reason := determine_incompatibility_reason(module, current_platform)
    
    // Convert platform filter to JSON format
    platform_os := make([dynamic]string)
    for os_name in module.platforms.os {
        append(&platform_os, strings.clone(os_name))
    }
    
    platform_arch := make([dynamic]string)
    for arch_name in module.platforms.arch {
        append(&platform_arch, strings.clone(arch_name))
    }
    
    platform_json := Platform_Info_JSON{
        os = platform_os,  // Keep as dynamic array
        arch = platform_arch,  // Keep as dynamic array
        shell = strings.clone(module.platforms.shell),
        min_version = strings.clone(module.platforms.min_version),
    }
    
    return Incompatible_Module_Info{
        name = strings.clone(module.name),
        version = strings.clone(module.version),
        description = strings.clone(module.description),
        path = strings.clone(module.path),
        reason = reason,
        platforms = platform_json,
    }
}

// determine_incompatibility_reason identifies why a module is incompatible
determine_incompatibility_reason :: proc(
    module: manifest.Module,
    current_platform: loader.Platform_Info,
) -> string {
    
    reasons := make([dynamic]string)
    defer delete(reasons)
    
    // Check OS mismatch
    if len(module.platforms.os) > 0 {
        os_match := false
        for os_name in module.platforms.os {
            if os_name == current_platform.os {
                os_match = true
                break
            }
        }
        if !os_match {
            append(&reasons, "OS mismatch")
        }
    }
    
    // Check architecture mismatch
    if len(module.platforms.arch) > 0 {
        arch_match := false
        for arch_name in module.platforms.arch {
            if arch_name == current_platform.arch {
                arch_match = true
                break
            }
        }
        if !arch_match {
            append(&reasons, "Architecture mismatch")
        }
    }
    
    // Check shell mismatch
    if module.platforms.shell != "" && 
       module.platforms.shell != current_platform.shell {
        append(&reasons, "Shell mismatch")
    }
    
    // Check version requirement
    if module.platforms.min_version != "" && current_platform.version != "" {
        if !loader.is_version_compatible(
            current_platform.version, 
            module.platforms.min_version
        ) {
            append(&reasons, "Shell version requirement not met")
        }
    }
    
    if len(reasons) == 0 {
        return strings.clone("Unknown incompatibility")
    }
    
    // Join the reasons and clone the result
    joined := strings.join(reasons[:], ", ")
    defer delete(joined)  // Clean up the joined string
    return strings.clone(joined)
}

// create_empty_json_output creates a JSON output with empty module arrays and marshals it
create_empty_json_output :: proc(modules_dir: string, pretty: bool) -> ([]u8, json.Marshal_Error) {
    platform := loader.get_current_platform()
    now := time.now()
    
    timestamp := fmt.tprintf("%v", now)
    // NOTE: timestamp is temp-allocated by fmt.tprintf, don't delete it!
    
    output := JSON_Output{
        schema_version = strings.clone("1.0"),
        generated_at = strings.clone(timestamp),
        environment = Environment_Info{
            zephyr_version = "1.0.0",
            modules_dir = strings.clone(modules_dir),
            os = strings.clone(platform.os),
            arch = strings.clone(platform.arch),
            shell = strings.clone(platform.shell),
            shell_version = strings.clone(platform.version),
        },
        summary = Summary_Info{
            total_modules = 0,
            compatible_modules = 0,
            incompatible_modules = 0,
        },
        modules = make([dynamic]Module_Info),
        incompatible_modules = make([dynamic]Incompatible_Module_Info),
        dependency_graph = Dependency_Graph_Info{},
    }
    
    defer {
        delete(output.schema_version)
        delete(output.generated_at)
        delete(output.environment.modules_dir)
        delete(output.environment.os)
        delete(output.environment.arch)
        delete(output.environment.shell)
        delete(output.environment.shell_version)
        delete(output.modules)
        delete(output.incompatible_modules)
        loader.cleanup_platform_info(&platform)
    }
    
    options := json.Marshal_Options{
        pretty = pretty,
        use_spaces = true,
        spaces = 2,
    }
    
    return json.marshal(output, options)
}
// marshal_and_output serializes JSON_Output and writes to stdout
marshal_and_output :: proc(output: JSON_Output, pretty: bool) -> bool {
    options := json.Marshal_Options{
        pretty = pretty,
        use_spaces = true,
        spaces = 2,
    }
    
    json_bytes, err := json.marshal(output, options)
    if err != nil {
        colors.print_error("Failed to serialize JSON: %v", err)
        return false
    }
    defer delete(json_bytes)
    
    // Write to stdout
    fmt.println(string(json_bytes))
    return true
}

// cleanup_json_output frees all allocated memory in a JSON_Output struct
cleanup_json_output :: proc(output: ^JSON_Output) {
    if output == nil do return
    
    // Clean up top-level strings
    if output.schema_version != "" {
        delete(output.schema_version)
        output.schema_version = ""
    }
    if output.generated_at != "" {
        delete(output.generated_at)
        output.generated_at = ""
    }
    
    // Clean up environment strings
    if output.environment.zephyr_version != "" {
        delete(output.environment.zephyr_version)
        output.environment.zephyr_version = ""
    }
    if output.environment.modules_dir != "" {
        delete(output.environment.modules_dir)
        output.environment.modules_dir = ""
    }
    if output.environment.os != "" {
        delete(output.environment.os)
        output.environment.os = ""
    }
    if output.environment.arch != "" {
        delete(output.environment.arch)
        output.environment.arch = ""
    }
    if output.environment.shell != "" {
        delete(output.environment.shell)
        output.environment.shell = ""
    }
    if output.environment.shell_version != "" {
        delete(output.environment.shell_version)
        output.environment.shell_version = ""
    }
    
    // Clean up module info arrays
    if output.modules != nil {
        for &module in output.modules {
            cleanup_module_info(&module)
        }
        delete(output.modules)
        output.modules = nil
    }

    if output.incompatible_modules != nil {
        for &module in output.incompatible_modules {
            cleanup_incompatible_module_info(&module)
        }
        delete(output.incompatible_modules)
        output.incompatible_modules = nil
    }

    if output.dependency_graph.format != "" {
        delete(output.dependency_graph.format)
        output.dependency_graph.format = ""
    }
    if output.dependency_graph.content != "" {
        delete(output.dependency_graph.content)
        output.dependency_graph.content = ""
    }
}

// cleanup_module_info_contents frees strings inside a Module_Info (not the struct itself)
cleanup_module_info_contents :: proc(module: ^Module_Info) {
    cleanup_module_info(module)
}

// cleanup_incompatible_module_info_contents frees strings inside an Incompatible_Module_Info
cleanup_incompatible_module_info_contents :: proc(module: ^Incompatible_Module_Info) {
    cleanup_incompatible_module_info(module)
}

// cleanup_module_info frees all allocated memory in a Module_Info struct
cleanup_module_info :: proc(module: ^Module_Info) {
    if module == nil do return
    
    // Clean up basic strings
    if module.name != "" {
        delete(module.name)
        module.name = ""
    }
    if module.version != "" {
        delete(module.version)
        module.version = ""
    }
    if module.description != "" {
        delete(module.description)
        module.description = ""
    }
    if module.author != "" {
        delete(module.author)
        module.author = ""
    }
    if module.license != "" {
        delete(module.license)
        module.license = ""
    }
    if module.path != "" {
        delete(module.path)
        module.path = ""
    }
    
    // Clean up dependencies
    if module.dependencies.required != nil {
        for dep in module.dependencies.required {
            if dep != "" {
                delete(dep)
            }
        }
        delete(module.dependencies.required)
        module.dependencies.required = nil
    }
    
    if module.dependencies.optional != nil {
        for dep in module.dependencies.optional {
            if dep != "" {
                delete(dep)
            }
        }
        delete(module.dependencies.optional)
        module.dependencies.optional = nil
    }
    
    // Clean up missing dependencies
    if module.missing_dependencies != nil {
        for dep in module.missing_dependencies {
            if dep != "" {
                delete(dep)
            }
        }
        delete(module.missing_dependencies)
        module.missing_dependencies = nil
    }
    
    // Clean up platform info
    if module.platforms.os != nil {
        for os_name in module.platforms.os {
            if os_name != "" {
                delete(os_name)
            }
        }
        delete(module.platforms.os)
        module.platforms.os = nil
    }
    
    if module.platforms.arch != nil {
        for arch_name in module.platforms.arch {
            if arch_name != "" {
                delete(arch_name)
            }
        }
        delete(module.platforms.arch)
        module.platforms.arch = nil
    }
    
    if module.platforms.shell != "" {
        delete(module.platforms.shell)
        module.platforms.shell = ""
    }
    if module.platforms.min_version != "" {
        delete(module.platforms.min_version)
        module.platforms.min_version = ""
    }
    
    // Clean up load info
    if module.load.files != nil {
        for file in module.load.files {
            if file != "" {
                delete(file)
            }
        }
        delete(module.load.files)
        module.load.files = nil
    }
    
    // Clean up hooks
    if module.hooks.pre_load != "" {
        delete(module.hooks.pre_load)
        module.hooks.pre_load = ""
    }
    if module.hooks.post_load != "" {
        delete(module.hooks.post_load)
        module.hooks.post_load = ""
    }
    
    // Clean up settings map (map owns keys/values; delete map only)
    if module.settings != nil {
        delete(module.settings)
        module.settings = nil
    }
    
    // Clean up exports
    if module.exports.functions != nil {
        for func in module.exports.functions {
            if func != "" {
                delete(func)
            }
        }
        delete(module.exports.functions)
        module.exports.functions = nil
    }
    
    if module.exports.aliases != nil {
        for alias in module.exports.aliases {
            if alias != "" {
                delete(alias)
            }
        }
        delete(module.exports.aliases)
        module.exports.aliases = nil
    }
    
    if module.exports.environment_variables != nil {
        for env_var in module.exports.environment_variables {
            if env_var != "" {
                delete(env_var)
            }
        }
        delete(module.exports.environment_variables)
        module.exports.environment_variables = nil
    }
}

// cleanup_incompatible_module_info frees all allocated memory in an Incompatible_Module_Info struct
cleanup_incompatible_module_info :: proc(module: ^Incompatible_Module_Info) {
    if module == nil do return
    
    // Clean up basic strings
    if module.name != "" {
        delete(module.name)
        module.name = ""
    }
    if module.version != "" {
        delete(module.version)
        module.version = ""
    }
    if module.description != "" {
        delete(module.description)
        module.description = ""
    }
    if module.path != "" {
        delete(module.path)
        module.path = ""
    }
    if module.reason != "" {
        delete(module.reason)
        module.reason = ""
    }
    
    // Clean up platform info
    if module.platforms.os != nil {
        for os_name in module.platforms.os {
            if os_name != "" {
                delete(os_name)
            }
        }
        delete(module.platforms.os)
        module.platforms.os = nil
    }
    
    if module.platforms.arch != nil {
        for arch_name in module.platforms.arch {
            if arch_name != "" {
                delete(arch_name)
            }
        }
        delete(module.platforms.arch)
        module.platforms.arch = nil
    }
    
    if module.platforms.shell != "" {
        delete(module.platforms.shell)
        module.platforms.shell = ""
    }
    if module.platforms.min_version != "" {
        delete(module.platforms.min_version)
        module.platforms.min_version = ""
    }
}
