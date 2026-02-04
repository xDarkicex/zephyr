package manifest

// Module represents a shell module with its metadata, dependencies, and configuration
Module :: struct {
    // Metadata
    name:        string,
    version:     string,
    description: string,
    author:      string,
    license:     string,
    
    // Dependencies
    required:    [dynamic]string,
    optional:    [dynamic]string,
    
    // Platform compatibility
    platforms:   Platform_Filter,
    
    // Loading configuration
    priority:    int,
    files:       [dynamic]string,
    hooks:       Hooks,
    settings:    map[string]string,
    
    // Internal state
    path:        string,
    loaded:      bool,
}

// Platform_Filter defines platform compatibility requirements for a module
Platform_Filter :: struct {
    os:          [dynamic]string,
    arch:        [dynamic]string,
    shell:       string,
    min_version: string,
}
// Hooks defines pre and post load actions for a module
Hooks :: struct {
    pre_load:  string,
    post_load: string,
}