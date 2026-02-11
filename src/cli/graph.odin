package cli

import "core:fmt"
import "core:strings"
import "../manifest"

CRITICAL_MODULES :: []string{
	"stdlib",
	"guardrails",
	"shell-guard",
}

generate_mermaid_graph :: proc(modules: [dynamic]manifest.Module, verbose: bool = false) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "graph TD\n")

	for module in modules {
		node_id := sanitize_node_id(module.name)
		defer delete(node_id)
		node_label := format_node_label(module, verbose)
		defer delete(node_label)
		fmt.sbprintf(&builder, "    %s[%s]\n", node_id, node_label)
	}

	strings.write_string(&builder, "\n")

	for module in modules {
		node_id := sanitize_node_id(module.name)
		defer delete(node_id)

		for dep in module.required {
			dep_id := sanitize_node_id(dep)
			defer delete(dep_id)
			fmt.sbprintf(&builder, "    %s --> %s\n", dep_id, node_id)
		}

		for dep in module.optional {
			dep_id := sanitize_node_id(dep)
			defer delete(dep_id)
			fmt.sbprintf(&builder, "    %s -.-> %s\n", dep_id, node_id)
		}
	}

	if verbose {
		strings.write_string(&builder, "\n")
		for module in modules {
			if is_critical_module(module.name) {
				node_id := sanitize_node_id(module.name)
				defer delete(node_id)
				fmt.sbprintf(&builder, "    style %s fill:#90EE90\n", node_id)
			}
		}
	}

	return strings.clone(strings.to_string(builder))
}

format_node_label :: proc(module: manifest.Module, verbose: bool) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	if !verbose {
		fmt.sbprintf(&builder, "\"%s\"", module.name)
		return strings.clone(strings.to_string(builder))
	}

	if module.version != "" {
		fmt.sbprintf(&builder, "\"%s v%s", module.name, module.version)
	} else {
		fmt.sbprintf(&builder, "\"%s", module.name)
	}

	if module.priority != 100 {
		fmt.sbprintf(&builder, "<br/>Priority: %d", module.priority)
	}

	if len(module.platforms.os) > 0 {
		os_list := strings.join(module.platforms.os[:], ",")
		defer delete(os_list)
		fmt.sbprintf(&builder, "<br/>OS: %s", os_list)
	}

	strings.write_string(&builder, "\"")
	return strings.clone(strings.to_string(builder))
}

sanitize_node_id :: proc(name: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for c in name {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			strings.write_byte(&builder, byte(c))
		} else {
			strings.write_byte(&builder, '_')
		}
	}

	return strings.clone(strings.to_string(builder))
}

is_critical_module :: proc(name: string) -> bool {
	for critical in CRITICAL_MODULES {
		if name == critical {
			return true
		}
	}
	return false
}
