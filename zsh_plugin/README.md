# Zephyr Plugin Installation

Zephyr can be installed as a zsh plugin using popular plugin managers.

## Prerequisites

1. Build Zephyr first:
   ```bash
   git clone https://github.com/zephyr-systems/zephyr.git
   cd zephyr
   make install
   ```

2. This will install the `zephyr` binary to `~/.zsh/bin/zephyr`

## Installation Methods

### Oh My Zsh

1. Clone this repo into Oh My Zsh's custom plugins directory:
   ```bash
   git clone https://github.com/zephyr-systems/zephyr.git \
       ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zephyr
   cd ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zephyr
   make install
   ```

2. Add `zephyr` to your plugins in `~/.zshrc`:
   ```bash
   plugins=(... zephyr)
   ```

3. Restart your shell:
   ```bash
   exec zsh
   ```

### Zinit

Add to your `~/.zshrc`:

```bash
zinit light xDarkicex/zephyr
```

### Antigen

Add to your `~/.zshrc`:

```bash
antigen bundle xDarkicex/zephyr
```

### Zplug

Add to your `~/.zshrc`:

```bash
zplug "xDarkicex/zephyr"
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/zephyr-systems/zephyr.git ~/.zephyr
   cd ~/.zephyr
   make install
   ```

2. Add to your `~/.zshrc`:
   ```bash
   source ~/.zephyr/zsh_plugin/zephyr.plugin.zsh
   ```

3. Restart your shell:
   ```bash
   exec zsh
   ```

## What the Plugin Does

The plugin automatically:
- Adds `zephyr` to your PATH
- Runs `eval "$(zephyr load)"` to load your modules
- Provides tab completion for zephyr commands

## Configuration

### Custom Binary Location

If you installed zephyr to a different location:

```bash
export ZEPHYR_BIN="/custom/path/to/zephyr"
```

### Custom Modules Directory

If you want modules in a different location:

```bash
export ZSH_MODULES_DIR="/custom/path/to/modules"
```

Add these exports **before** loading the plugin.

## Verification

After installation, verify it works:

```bash
# Check zephyr is in PATH
which zephyr

# List modules
zephyr list

# Test completion (type and press TAB)
zephyr <TAB>
```

## Troubleshooting

### "Zephyr binary not found"

Make sure you've built and installed zephyr first:
```bash
cd /path/to/zephyr
make install
```

Or set `ZEPHYR_BIN` to point to your binary.

### Modules not loading

Check that your modules directory exists:
```bash
ls -la ~/.zsh/modules
```

If empty, create your first module:
```bash
zephyr init my-first-module
```

### Completion not working

Make sure `compinit` is called after loading the plugin. Most plugin managers handle this automatically.

## Next Steps

1. Install the guardrails module for AI safety:
   ```bash
   zephyr install xDarkicex/zephyr-guardrails-module
   ```

2. Create your own modules:
   ```bash
   zephyr init my-aliases
   ```

3. Read the documentation:
   - [Module Development](docs/MODULE_DEVELOPMENT.md)
   - [Security](docs/SECURITY_SCAN.md)
   - [Usage Examples](docs/USAGE_EXAMPLES.md)
