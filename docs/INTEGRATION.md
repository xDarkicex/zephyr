# Zephyr Shell Loader - Integration Guide

This guide explains how to integrate Zephyr Shell Loader with your shell configuration.

## Quick Setup

After running the installation script, add one of the following lines to your `.zshrc`:

### Option 1: Direct Path (Recommended)
```bash
eval "$($HOME/.zsh/bin/zephyr load)"
```

### Option 2: Using PATH
If you've added `$HOME/.zsh/bin` to your PATH:
```bash
eval "$(zephyr load)"
```

## Manual Integration Steps

### 1. Install Zephyr
```bash
git clone https://github.com/zephyr-systems/zephyr.git
cd zephyr
./install.sh
```

### 2. Add to .zshrc
Open your `.zshrc` file:
```bash
vim ~/.zshrc
```

Add the following line at the end:
```bash
# Load Zephyr modules
eval "$($HOME/.zsh/bin/zephyr load)"
```

### 3. Reload Your Shell
```bash
source ~/.zshrc
```

## Advanced Configuration

### Custom Module Directory
Set the `ZSH_MODULES_DIR` environment variable to use a different modules directory:

```bash
# In your .zshrc, before the eval line
export ZSH_MODULES_DIR="$HOME/my-shell-modules"
eval "$($HOME/.zsh/bin/zephyr load)"
```

### Conditional Loading
You can conditionally load Zephyr based on certain conditions:

```bash
# Only load if Zephyr is installed
if [[ -x "$HOME/.zsh/bin/zephyr" ]]; then
    eval "$($HOME/.zsh/bin/zephyr load)"
fi
```

### Performance Optimization
For faster shell startup, you can cache the generated code:

```bash
# Cache Zephyr output for faster loading
ZEPHYR_CACHE="$HOME/.zsh/.zephyr_cache"
if [[ ! -f "$ZEPHYR_CACHE" ]] || [[ "$HOME/.zephyr/modules" -nt "$ZEPHYR_CACHE" ]]; then
    $HOME/.zsh/bin/zephyr load > "$ZEPHYR_CACHE"
fi
source "$ZEPHYR_CACHE"
```

## Troubleshooting

### Zephyr Command Not Found
If you get "command not found" errors:

1. Check if the binary exists:
   ```bash
   ls -la $HOME/.zsh/bin/zephyr
   ```

2. Make sure the binary is executable:
   ```bash
   chmod +x $HOME/.zsh/bin/zephyr
   ```

3. Add the bin directory to your PATH:
   ```bash
   export PATH="$HOME/.zsh/bin:$PATH"
   ```

### No Modules Found
If Zephyr reports "No modules found":

1. Check the modules directory exists:
   ```bash
   ls -la $HOME/.zephyr/modules
   ```

2. Verify the core module was created:
   ```bash
   ls -la $HOME/.zephyr/modules/core/
   ```

3. Check for TOML syntax errors:
   ```bash
   $HOME/.zsh/bin/zephyr validate
   ```

### Module Loading Errors
If modules fail to load:

1. Validate all manifests:
   ```bash
   $HOME/.zsh/bin/zephyr validate
   ```

2. Check the load order:
   ```bash
   $HOME/.zsh/bin/zephyr list
   ```

3. Test the generated code:
   ```bash
   $HOME/.zsh/bin/zephyr load | zsh -n
   ```

## Best Practices

### 1. Module Organization
- Keep modules focused on specific functionality
- Use descriptive names and proper versioning
- Document your modules with README files

### 2. Dependency Management
- Declare all required dependencies
- Use appropriate priority values (lower = loads first)
- Avoid circular dependencies

### 3. Performance
- Keep module files small and focused
- Avoid expensive operations in module initialization
- Use lazy loading for heavy functionality

### 4. Compatibility
- Test modules on different systems
- Use portable shell constructs
- Handle missing commands gracefully

## Example .zshrc Integration

Here's a complete example of how to integrate Zephyr into your `.zshrc`:

```bash
# ~/.zshrc

# Set up environment
export ZSH_MODULES_DIR="$HOME/.zephyr/modules"

# Load Zephyr modules
if [[ -x "$HOME/.zsh/bin/zephyr" ]]; then
    # Use caching for better performance
    ZEPHYR_CACHE="$HOME/.zsh/.zephyr_cache"
    if [[ ! -f "$ZEPHYR_CACHE" ]] || [[ "$ZSH_MODULES_DIR" -nt "$ZEPHYR_CACHE" ]]; then
        $HOME/.zsh/bin/zephyr load > "$ZEPHYR_CACHE" 2>/dev/null
    fi
    
    if [[ -f "$ZEPHYR_CACHE" ]]; then
        source "$ZEPHYR_CACHE"
    else
        # Fallback to direct loading
        eval "$($HOME/.zsh/bin/zephyr load 2>/dev/null)"
    fi
else
    echo "Warning: Zephyr not found. Install with: git clone https://github.com/zephyr-systems/zephyr.git && cd zephyr && ./install.sh"
fi

# Your other shell configuration...
```

## Module Development

### Creating New Modules
Use the init command to create new modules:
```bash
zephyr init my-new-module
```

This creates a skeleton module in `$ZSH_MODULES_DIR/my-new-module/`.

### Module Structure
```
my-module/
├── module.toml          # Module manifest
├── README.md           # Documentation
├── init.zsh            # Main initialization
├── functions.zsh       # Shell functions
└── aliases.zsh         # Shell aliases
```

### Testing Modules
Always test your modules before deploying:
```bash
# Validate syntax
zephyr validate

# Check load order
zephyr list

# Test generated code
zephyr load | zsh -n
```

For more information, see the main README.md file.

## JSON Integration for Tools and Scripts

Zephyr provides JSON output for programmatic access to module information, making it easy to integrate with external tools, scripts, and AI assistants.

### Basic JSON Usage

```bash
# Get JSON output
zephyr list --json

# Pretty-printed JSON
zephyr list --json --pretty

# Filter modules
zephyr list --json --filter=git
```

### Integration with jq

**Extract module names:**
```bash
zephyr list --json | jq -r '.modules[].name'
```

**Get modules with dependencies:**
```bash
zephyr list --json | jq '.modules[] | select(.dependencies.required | length > 0)'
```

**List all exported functions:**
```bash
zephyr list --json | jq -r '.modules[].exports.functions[]'
```

### Script Integration Examples

**Check if a module exists:**
```bash
#!/bin/bash
MODULE="git-helpers"

if zephyr list --json | jq -e ".modules[] | select(.name == \"$MODULE\")" > /dev/null; then
    echo "✓ Module $MODULE is available"
    exit 0
else
    echo "✗ Module $MODULE not found"
    exit 1
fi
```

**Generate module documentation:**
```bash
#!/bin/bash
# Generate markdown docs from JSON

echo "# Available Modules"
echo ""

zephyr list --json | jq -r '.modules[] | 
  "## \(.name) v\(.version)\n\n" +
  "\(.description)\n\n" +
  "**Functions:** \(.exports.functions | join(", "))\n" +
  "**Aliases:** \(.exports.aliases | join(", "))\n"'
```

**Monitor module configuration:**
```bash
#!/bin/bash
# Save module state for comparison

SNAPSHOT_DIR="$HOME/.zsh/snapshots"
mkdir -p "$SNAPSHOT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
zephyr list --json > "$SNAPSHOT_DIR/modules_$TIMESTAMP.json"

echo "Snapshot saved: $SNAPSHOT_DIR/modules_$TIMESTAMP.json"
```

### AI Assistant Integration

AI assistants can use JSON output to discover available shell functionality:

```bash
# Discover all available functions
zephyr list --json | jq '.modules[].exports.functions[]'

# Find modules by capability
zephyr list --json | jq -r '.modules[] | select(.exports.functions[] | contains("git")) | .name'

# Get module metadata for context
zephyr list --json | jq '.modules[] | {name, description, exports: .exports.functions}'
```

### Python Integration Example

```python
#!/usr/bin/env python3
import json
import subprocess

def get_zephyr_modules():
    """Get Zephyr module information as Python dict."""
    result = subprocess.run(
        ['zephyr', 'list', '--json'],
        capture_output=True,
        text=True
    )
    return json.loads(result.stdout)

def find_module(name):
    """Find a specific module by name."""
    data = get_zephyr_modules()
    for module in data['modules']:
        if module['name'] == name:
            return module
    return None

# Usage
if __name__ == '__main__':
    modules = get_zephyr_modules()
    print(f"Total modules: {modules['summary']['total_modules']}")
    
    for module in modules['modules']:
        print(f"- {module['name']} v{module['version']}")
        print(f"  Functions: {', '.join(module['exports']['functions'])}")
```

### Node.js Integration Example

```javascript
#!/usr/bin/env node
const { execSync } = require('child_process');

function getZephyrModules() {
  const output = execSync('zephyr list --json', { encoding: 'utf-8' });
  return JSON.parse(output);
}

function findModulesWithFunction(functionName) {
  const data = getZephyrModules();
  return data.modules.filter(module =>
    module.exports.functions.includes(functionName)
  );
}

// Usage
const modules = getZephyrModules();
console.log(`Total modules: ${modules.summary.total_modules}`);

const gitModules = findModulesWithFunction('git_status_short');
console.log('Modules with git_status_short:', gitModules.map(m => m.name));
```

### Continuous Integration

Use JSON output in CI/CD pipelines to validate module configuration:

```yaml
# .github/workflows/validate-modules.yml
name: Validate Zephyr Modules

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Install Zephyr
        run: |
          make build
          sudo make install
      
      - name: Validate modules
        run: zephyr validate
      
      - name: Check module count
        run: |
          MODULE_COUNT=$(zephyr list --json | jq '.summary.total_modules')
          echo "Found $MODULE_COUNT modules"
          if [ "$MODULE_COUNT" -lt 1 ]; then
            echo "Error: No modules found"
            exit 1
          fi
      
      - name: Export module inventory
        run: zephyr list --json --pretty > module-inventory.json
      
      - name: Upload inventory
        uses: actions/upload-artifact@v2
        with:
          name: module-inventory
          path: module-inventory.json
```

For more JSON examples, see [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md#json-output).