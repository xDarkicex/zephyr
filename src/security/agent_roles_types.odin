package security

import "core:sync"

Session_Info :: struct {
	session_id:     string,
	agent_id:       string,
	agent_type:     string,
	parent_process: string,
	started_at:     string,
	role:           string,
}

Session_Registry :: struct {
	sessions: map[string]Session_Info,
	mutex:    sync.Mutex,
}

Role_Config :: struct {
	can_install:          bool,
	can_install_unsigned: bool,
	can_use_unsafe:       bool,
	can_uninstall:        bool,
	can_modify_config:    bool,
	require_confirmation: bool,
}

Security_Config :: struct {
	roles: map[string]Role_Config,
}

Permission :: enum {
	Install,
	Install_Unsigned,
	Use_Unsafe,
	Uninstall,
	Modify_Config,
}

Audit_Event :: struct {
	timestamp:          string,
	session_id:         string,
	agent_id:           string,
	agent_type:         string,
	role:               string,
	action:             string,
	module:             string,
	source:             string,
	result:             string,
	reason:             string,
	signature_verified: bool,
}

