package test

import "core:strings"
import "core:testing"
import "../src/loader"
import "../src/manifest"

make_rev_module :: proc(name: string) -> manifest.Module {
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

cleanup_rev_modules :: proc(modules: [dynamic]manifest.Module) {
	if modules == nil {
		return
	}
	manifest.cleanup_modules(modules[:])
	delete(modules)
}

@(test)
test_reverse_deps_simple :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_rev_module("a"))
	append(&modules, make_rev_module("b"))
	append(&modules[1].required, strings.clone("a"))
	defer cleanup_rev_modules(modules)

	reverse := loader.build_reverse_deps(modules)
	defer loader.cleanup_reverse_deps(reverse)

	deps, ok := loader.get_dependents("a", reverse)
	testing.expect(t, ok, "a should have dependents")
	testing.expect(t, len(deps) == 1, "a should have one dependent")
	testing.expect(t, deps[0] == "b", "dependent should be b")
}

@(test)
test_reverse_deps_no_dependents :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_rev_module("a"))
	defer cleanup_rev_modules(modules)

	reverse := loader.build_reverse_deps(modules)
	defer loader.cleanup_reverse_deps(reverse)

	deps, ok := loader.get_dependents("a", reverse)
	testing.expect(t, !ok, "a should report no dependents")
	testing.expect(t, deps == nil, "deps should be nil when no dependents")
}

@(test)
test_reverse_deps_multiple_dependents :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_rev_module("core"))
	append(&modules, make_rev_module("tool1"))
	append(&modules, make_rev_module("tool2"))
	append(&modules[1].required, strings.clone("core"))
	append(&modules[2].required, strings.clone("core"))
	defer cleanup_rev_modules(modules)

	reverse := loader.build_reverse_deps(modules)
	defer loader.cleanup_reverse_deps(reverse)

	deps, ok := loader.get_dependents("core", reverse)
	testing.expect(t, ok, "core should have dependents")
	testing.expect(t, len(deps) == 2, "core should have two dependents")
}

@(test)
test_reverse_deps_missing_module :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_rev_module("a"))
	defer cleanup_rev_modules(modules)

	reverse := loader.build_reverse_deps(modules)
	defer loader.cleanup_reverse_deps(reverse)

	deps, ok := loader.get_dependents("missing", reverse)
	testing.expect(t, !ok, "missing module should not be found")
	testing.expect(t, deps == nil, "deps should be nil for missing module")
}

@(test)
test_reverse_deps_circular :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_rev_module("a"))
	append(&modules, make_rev_module("b"))
	append(&modules[0].required, strings.clone("b"))
	append(&modules[1].required, strings.clone("a"))
	defer cleanup_rev_modules(modules)

	reverse := loader.build_reverse_deps(modules)
	defer loader.cleanup_reverse_deps(reverse)

	deps_a, ok_a := loader.get_dependents("a", reverse)
	deps_b, ok_b := loader.get_dependents("b", reverse)
	testing.expect(t, ok_a && ok_b, "both modules should have dependents")
	testing.expect(t, len(deps_a) == 1 && len(deps_b) == 1, "each should have one dependent")
}

@(test)
test_reverse_deps_matches_forward :: proc(t: ^testing.T) {
	modules := make([dynamic]manifest.Module)
	append(&modules, make_rev_module("base"))
	append(&modules, make_rev_module("leaf"))
	append(&modules[1].required, strings.clone("base"))
	defer cleanup_rev_modules(modules)

	reverse := loader.build_reverse_deps(modules)
	defer loader.cleanup_reverse_deps(reverse)

	deps, ok := loader.get_dependents("base", reverse)
	testing.expect(t, ok, "base should have dependents")
	testing.expect(t, len(deps) == 1, "base should have one dependent")
	testing.expect(t, deps[0] == "leaf", "dependent should match forward dep")
}
