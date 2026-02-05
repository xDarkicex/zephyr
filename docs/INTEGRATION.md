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
git clone https://github.com/xDarkicex/zephyr.git
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
if [[ ! -f "$ZEPHYR_CACHE" ]] || [[ "$HOME/.zsh/modules" -nt "$ZEPHYR_CACHE" ]]; then
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
   ls -la $HOME/.zsh/modules
   ```

2. Verify the core module was created:
   ```bash
   ls -la $HOME/.zsh/modules/core/
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
export ZSH_MODULES_DIR="$HOME/.zsh/modules"

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
    echo "Warning: Zephyr not found. Install with: git clone https://github.com/xDarkicex/zephyr.git && cd zephyr && ./install.sh"
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