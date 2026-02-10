package security

import "core:fmt"

check_permission :: proc(perm: Permission) -> bool {
	session, ok := get_current_session()
	if !ok {
		return true
	}

	role := load_role_config(session.role)

	switch perm {
	case .Install:
		return role.can_install
	case .Install_Unsigned:
		return role.can_install_unsigned
	case .Use_Unsafe:
		return role.can_use_unsafe
	case .Uninstall:
		return role.can_uninstall
	case .Modify_Config:
		return role.can_modify_config
	}

	return false
}

require_permission :: proc(perm: Permission, operation: string) -> bool {
	if check_permission(perm) {
		return true
	}

	session, _ := get_current_session()

	fmt.printf("❌ Permission denied: %s\n\n", operation)
	fmt.printf("  Agent: %s (%s)\n", session.agent_id, session.agent_type)
	fmt.printf("  Role: %s\n", session.role)
	fmt.printf("  Required permission: %v\n\n", perm)

	switch perm {
	case .Install:
		// Generic install denial (agent can't install at all).
		fmt.println("Agents cannot install modules.")
		fmt.println("This prevents untrusted code execution.")
	case .Install_Unsigned:
		fmt.println("Agents can only install signed modules for security.")
		fmt.println("Signed modules are cryptographically verified.")
	case .Use_Unsafe:
		fmt.println("Agents cannot use the --unsafe flag.")
		fmt.println("This flag bypasses security checks.")
	case .Uninstall:
		fmt.println("Agents cannot uninstall modules.")
		fmt.println("This prevents accidental removal of dependencies.")
	case .Modify_Config:
		fmt.println("Agents cannot modify configuration.")
		fmt.println("This prevents config tampering.")
	}

	log_permission_denied(session, perm, operation)
	return false
}

requires_confirmation :: proc() -> bool {
	session, ok := get_current_session()
	if !ok {
		return false
	}

	role := load_role_config(session.role)
	return role.require_confirmation
}
