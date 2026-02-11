package test

import "core:strings"
import "core:testing"
import "../src/cli"
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

@(test)
test_graph_simple :: proc(t: ^testing.T) {
	mod_a := make_module("a")
	defer manifest.cleanup_module(&mod_a)
	mod_b := make_module("b")
	defer manifest.cleanup_module(&mod_b)
	mod_c := make_module("c")
	defer manifest.cleanup_module(&mod_c)

	mod_b.required = append(mod_b.required, strings.clone("a"))
	mod_c.optional = append(mod_c.optional, strings.clone("b"))

	modules := []manifest.Module{mod_a, mod_b, mod_c}
	graph := cli.generate_mermaid_graph(modules, false)
	defer delete(graph)

	testing.expect(t, strings.contains(graph, "graph TD"), "should include mermaid header")
	testing.expect(t, strings.contains(graph, "a --> b"), "required dependency should be solid")
	testing.expect(t, strings.contains(graph, "b -.-> c"), "optional dependency should be dashed")
}

@(test)
test_graph_verbose_critical_style :: proc(t: ^testing.T) {
	mod_stdlib := make_module("stdlib")
	defer manifest.cleanup_module(&mod_stdlib)
	mod_other := make_module("tooling")
	defer manifest.cleanup_module(&mod_other)

	modules := []manifest.Module{mod_stdlib, mod_other}
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
	mod_a := make_module("alpha")
	defer manifest.cleanup_module(&mod_a)
	mod_b := make_module("beta")
	defer manifest.cleanup_module(&mod_b)
	mod_b.required = append(mod_b.required, strings.clone("alpha"))

	all_modules := []manifest.Module{mod_a, mod_b}
	compat_indices := []int{0, 1}
	resolved := []manifest.Module{mod_a, mod_b}

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
