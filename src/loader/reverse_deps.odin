package loader

import "core:strings"
import "../manifest"

build_reverse_deps :: proc(modules: [dynamic]manifest.Module) -> map[string][dynamic]string {
	reverse := make(map[string][dynamic]string)

	for module in modules {
		if module.name not_in reverse {
			reverse[strings.clone(module.name)] = make([dynamic]string)
		}
	}

	for module in modules {
		for dep in module.required {
			if dep not_in reverse {
				reverse[strings.clone(dep)] = make([dynamic]string)
			}
			append(&reverse[dep], strings.clone(module.name))
		}
	}

	return reverse
}

cleanup_reverse_deps :: proc(reverse: map[string][dynamic]string) {
	for key, deps in reverse {
		for dep in deps {
			if dep != "" {
				delete(dep)
			}
		}
		delete(deps)
		if key != "" {
			delete(key)
		}
	}
	delete(reverse)
}

get_dependents :: proc(module_name: string, reverse: map[string][dynamic]string) -> ([]string, bool) {
	deps, ok := reverse[module_name]
	if !ok || len(deps) == 0 {
		return nil, false
	}
	return deps[:], true
}
