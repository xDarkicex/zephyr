package test

import "core:strings"
import "core:testing"
import "../src/cli"
import "../src/loader"
import "../src/manifest"

make_module :: proc(name: string) -> manifest.Module {
	return manifest.Module{
		name = strings.clone(name),
		version = strings.clone("1.0.0"),
		description = strings.clone(""),
		author = strings.clone(""),
		license = strings.clone(""),
		required = make([dynamic]string),
		optional = make([dynamic]string),
		platforms = manifest.Platform_Filter{},
		priority = 100,
		files = make([dynamic]string),
		hooks = manifest.Hooks{},
		settings = make(map[string]string),
		settings_storage = make([dynamic]string),
		path = strings.clone(""),
		loaded = false,
	}
}

cleanup_module_list :: proc(modules: [dynamic]manifest.Module) {
	if modules == nil {
		return
	}
	manifest.cleanup_modules(modules[:])
	delete(modules)
}

@(test)
test_graph_simple :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_module("a"))
	append(&modules, make_module("b"))
	append(&modules, make_module("c"))
	append(&modules[1].required, strings.clone("a"))
	append(&modules[2].optional, strings.clone("b"))
	defer cleanup_module_list(modules)
	graph := cli.generate_mermaid_graph(modules, false)
	defer delete(graph)

	testing.expect(t, strings.contains(graph, "graph TD"), "should include mermaid header")
	testing.expect(t, strings.contains(graph, "a --> b"), "required dependency should be solid")
	testing.expect(t, strings.contains(graph, "b -.-> c"), "optional dependency should be dashed")
}

@(test)
test_graph_verbose_critical_style :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_module("stdlib"))
	append(&modules, make_module("tooling"))
	defer cleanup_module_list(modules)
	graph := cli.generate_mermaid_graph(modules, true)
	defer delete(graph)

	testing.expect(t, strings.contains(graph, "style stdlib fill:#90EE90"), "critical modules should be styled in verbose mode")
	testing.expect(t, strings.contains(graph, "v1.0.0"), "verbose label should include version")
}

@(test)
test_graph_sanitize_node_id :: proc(t: ^testing.T) {
	id := cli.sanitize_node_id("my-module name")
	defer delete(id)
	testing.expect(t, id == "my_module_name", "sanitize should replace non-alnum with underscores")
}

@(test)
test_graph_json_embedding :: proc(t: ^testing.T) {
	all_modules := make([dynamic]manifest.Module)
	append(&all_modules, make_module("alpha"))
	append(&all_modules, make_module("beta"))
	append(&all_modules[1].required, strings.clone("alpha"))
	defer cleanup_module_list(all_modules)

	compat_indices := make([dynamic]int)
	append(&compat_indices, 0)
	append(&compat_indices, 1)
	defer delete(compat_indices)

	resolved := make([dynamic]manifest.Module)
	for module in all_modules {
		append(&resolved, loader.CloneModule(module))
	}
	defer cleanup_module_list(resolved)

	json_bytes, err := cli.generate_json_with_graph(
		"/tmp/modules",
		all_modules,
		compat_indices,
		resolved,
		"",
		true,
		"mermaid",
		false,
	)
	testing.expect(t, err == nil, "json marshal should succeed")
	defer delete(json_bytes)
	json_text := string(json_bytes)
	testing.expect(t, strings.contains(json_text, "\"dependency_graph\""), "json should include dependency_graph field")
	testing.expect(t, strings.contains(json_text, "graph TD"), "graph content should be embedded")
}

@(test)
test_graph_circular_dependencies :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_module("a"))
	append(&modules, make_module("b"))
	append(&modules[0].required, strings.clone("b"))
	append(&modules[1].required, strings.clone("a"))
	defer cleanup_module_list(modules)
	graph := cli.generate_mermaid_graph(modules, false)
	defer delete(graph)

	testing.expect(t, strings.contains(graph, "a --> b"), "should include a -> b edge")
	testing.expect(t, strings.contains(graph, "b --> a"), "should include b -> a edge")
}

@(test)
test_graph_filter_behavior :: proc(t: ^testing.T) {
	all_modules := make([dynamic]manifest.Module)
	append(&all_modules, make_module("alpha"))
	append(&all_modules, make_module("beta"))
	append(&all_modules, make_module("charlie"))
	append(&all_modules[1].required, strings.clone("alpha"))
	defer cleanup_module_list(all_modules)

	filtered := make([dynamic]manifest.Module)
	defer cleanup_module_list(filtered)
	filter_lower := strings.to_lower("alp")
	defer delete(filter_lower)
	for module in all_modules {
		module_name_lower := strings.to_lower(module.name)
		matches := strings.contains(module_name_lower, filter_lower)
		delete(module_name_lower)
		if matches {
			append(&filtered, loader.CloneModule(module))
		}
	}

	graph := cli.generate_mermaid_graph(filtered, false)
	defer delete(graph)
	testing.expect(t, strings.contains(graph, "alpha"), "filtered graph should include matching module")
	testing.expect(t, !strings.contains(graph, "charlie"), "filtered graph should exclude non-matching module")
}

@(test)
test_graph_mermaid_sanity :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_module("alpha"))
	append(&modules, make_module("beta"))
	append(&modules[1].optional, strings.clone("alpha"))
	defer cleanup_module_list(modules)
	graph := cli.generate_mermaid_graph(modules, false)
	defer delete(graph)

	testing.expect(t, strings.has_prefix(graph, "graph TD"), "mermaid output should start with graph TD")
}
