# Zephyr Troubleshooting Guide

This guide helps you diagnose and fix common issues with Zephyr Shell Loader.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Installation Issues](#installation-issues)
- [Git Module Management](#git-module-management)
- [Update and Upgrade Issues](#update-and-upgrade-issues)
- [Module Loading Problems](#module-loading-problems)
- [Dependency Issues](#dependency-issues)
- [Performance Problems](#performance-problems)
- [Platform-Specific Issues](#platform-specific-issues)
- [Advanced Debugging](#advanced-debugging)
- [Getting Help](#getting-help)

## Quick Diagnostics

Run these commands to quickly identify common issues:

```bash
# Check if zephyr is installed and accessible
which zephyr
zephyr --help

# Validate all modules
zephyr validate

# Check module discovery
zephyr list

# Test module loading
zephyr load > /tmp/zephyr-test.sh && echo "Load successful"
```

## Installation Issues

### Problem: `zephyr: command not found`

**Symptoms:**
```bash
$ zephyr list
zsh: command not found: zephyr
```

**Causes & Solutions:**

1. **Zephyr not installed**
   ```bash
   # Install zephyr
   git clone https://github.com/zephyr-systems/zephyr.git
   cd zephyr
   ./install.sh
   ```

2. **Binary not in PATH**
   ```bash
   # Check if binary exists
   ls -la ~/.zsh/bin/zephyr
   
   # Add to PATH in ~/.zshrc
   export PATH="$HOME/.zsh/bin:$PATH"
   
   # Or use full path
   eval "$($HOME/.zsh/bin/zephyr load)"
   ```

3. **Installation failed**
   ```bash
   # Check installation logs
   ./install.sh 2>&1 | tee install.log
   
   # Manual installation
   ./build.sh
   mkdir -p ~/.zsh/bin
   cp zephyr ~/.zsh/bin/
   chmod +x ~/.zsh/bin/zephyr
   ```

### Problem: Build failures

**Symptoms:**
```bash
$ ./build.sh
Error: Odin compiler not found
```

**Solutions:**

1. **Install Odin compiler**
   ```bash
   # macOS with Homebrew
   brew install odin
   
   # Or download from https://odin-lang.org/docs/install/
   ```

2. **Check Odin installation**
   ```bash
   which odin
   odin version
   ```

3. **Manual build**
   ```bash
   # Build with specific flags
   odin build src -o:speed -out:zephyr
   ```

### Problem: Permission denied during installation

**Symptoms:**
```bash
$ ./install.sh
mkdir: cannot create directory '/Users/john/.zsh': Permission denied
```

**Solutions:**

1. **Fix directory permissions**
   ```bash
   # Create directory manually
   mkdir -p ~/.zsh/bin ~/.zsh/modules
   chmod 755 ~/.zsh ~/.zsh/bin ~/.zsh/modules
   ```

2. **Install to custom location**
   ```bash
   # Set custom installation directory
   export ZSH_DIR="/path/to/custom/location"
   ./install.sh
   ```

## Git Module Management

### Problem: Git commands are unavailable

**Symptoms:**
```bash
Git support is not available in this build
```

**Causes & Solutions:**

1. **libgit2 not installed**
   ```bash
   # macOS (Homebrew)
   brew install libgit2 pkg-config

   # Ubuntu/Debian
   sudo apt-get install -y libgit2-dev pkg-config
   ```

2. **pkg-config cannot find libgit2**
   ```bash
   # Verify libgit2 detection
   pkg-config --libs libgit2

   # If empty, check PKG_CONFIG_PATH
   echo $PKG_CONFIG_PATH
   ```

   If your system installs libgit2 in a non-standard location, set `PKG_CONFIG_PATH`
   or install a pkg-config file for libgit2.

### Problem: Clone or fetch fails

**Symptoms:**
```bash
Install failed: clone failed
Update failed: fetch failed
```

**Solutions:**

1. **Verify the URL**
   ```bash
   # Try the URL in git directly
   git clone https://github.com/user/repo
   ```

2. **Check authentication**
   - For SSH URLs, confirm your SSH keys are loaded and authorized.
   - For HTTPS, verify access to private repos.

3. **Network issues**
   - Confirm DNS and proxy settings.
   - Retry with a different protocol (HTTPS vs SSH).

### Problem: Local install fails

**Symptoms:**
```bash
Invalid install source
```

**Solutions:**

1. **Use the `--local` flag**
   ```bash
   zephyr install --local /path/to/module-repo
   ```

2. **Ensure module.toml exists**
   ```bash
   ls /path/to/module-repo/module.toml
   ```

## Update and Upgrade Issues

### Problem: `zephyr update` rolls back after pulling

**Symptoms:**
```
Update failed: validation error
Rolling back module to previous commit
```

**Explanation:** Updates run **security scan + manifest validation** after pulling. If either fails,
Zephyr hard-resets the module to the previous commit.

**Next steps:**
- Review the module’s latest commit for security or manifest issues.
- Re-run with `--force` only if you trust the module and accept the risk.

### Problem: `zephyr upgrade --check` says no releases found

**Symptoms:**
```
No releases found
```

**Cause:** There are no published GitHub releases for Zephyr yet, or the API rate limit is exceeded.

**Solutions:**
- Retry later if rate-limited.
- Ensure a release exists at:
  `https://github.com/zephyr-systems/zephyr/releases`

### Problem: `zephyr upgrade` blocked for agents

**Symptoms:**
```
Upgrade denied: agents are not allowed to run upgrade
```

**Cause:** Upgrades are restricted to **human sessions** by design.

**Solution:** Run upgrade from a human shell session.

### Problem: Checksum mismatch during upgrade

**Symptoms:**
```
Checksum mismatch
Upgrade aborted
```

**Cause:** The downloaded asset does not match the release checksum.

**Solutions:**
- Retry the upgrade (network/cache corruption).
- Verify the release asset and checksum are correct.

### Problem: Upgrade download fails

**Symptoms:**
```
Network error: GitHub API request failed
```

**Solutions:**
- Check network connectivity.
- Confirm GitHub API availability.
- Retry after rate limits reset.

## Module Loading Problems

### Problem: "No modules found"

**Symptoms:**
```bash
$ zephyr list
No modules found in: /Users/john/.zsh/modules
```

**Solutions:**

1. **Check modules directory**
   ```bash
   # List directory contents
   ls -la ~/.zsh/modules/
   
   # Create test module
   zephyr init test-module
   ```

2. **Verify directory structure**
   ```bash
   # Each module needs module.toml
   find ~/.zsh/modules -name "module.toml"
   ```

3. **Check custom modules directory**
   ```bash
   # If using custom directory
   echo $ZSH_MODULES_DIR
   ls -la "$ZSH_MODULES_DIR"
   ```

### Problem: Modules not loading in shell

**Symptoms:**
- Zephyr commands work, but aliases/functions from modules aren't available
- Shell starts without errors but modules seem inactive

**Solutions:**

1. **Check .zshrc integration**
   ```bash
   # Verify .zshrc contains zephyr load
   grep -n "zephyr" ~/.zshrc
   
   # Add if missing
   echo 'eval "$(zephyr load)"' >> ~/.zshrc
   ```

2. **Test manual loading**
   ```bash
   # Load modules manually
   eval "$(zephyr load)"
   
   # Check if aliases work
   alias | grep -i git
   ```

3. **Check for shell errors**
   ```bash
   # Start new shell with verbose output
   zsh -xv
   
   # Or check zephyr output
   zephyr load | zsh -n  # syntax check
   ```

### Problem: Module files not found

**Symptoms:**
```bash
$ zephyr load
source: can't open file: /Users/john/.zsh/modules/my-module/missing.zsh
```

**Solutions:**

1. **Check file paths in module.toml**
   ```toml
   [load]
   files = ["existing-file.zsh", "another-file.zsh"]
   ```

2. **Verify files exist**
   ```bash
   # Check module directory
   ls -la ~/.zsh/modules/my-module/
   
   # Fix missing files
   touch ~/.zsh/modules/my-module/missing.zsh
   ```

3. **Use relative paths**
   ```toml
   # Correct - relative to module directory
   files = ["aliases.zsh"]
   
   # Incorrect - absolute paths
   files = ["/full/path/to/aliases.zsh"]
   ```

## Dependency Issues

### Problem: Missing dependencies

**Symptoms:**
```bash
$ zephyr load
ERROR: Missing dependency: 'git-helpers' requires 'colors'
```

**Solutions:**

1. **Install missing modules**
   ```bash
   # Create missing dependency
   zephyr init colors
   
   # Or remove dependency from module.toml
   [dependencies]
   # required = ["colors"]  # Comment out or remove
   ```

2. **Check dependency names**
   ```bash
   # List available modules
   zephyr list
   
   # Verify exact names in module.toml
   [dependencies]
   required = ["exact-module-name"]
   ```

3. **Make dependency optional**
   ```toml
   [dependencies]
   # required = ["colors"]
   optional = ["colors"]  # Won't fail if missing
   ```

### Problem: Circular dependencies

**Symptoms:**
```bash
$ zephyr load
ERROR: Circular dependency detected
```

**Solutions:**

1. **Identify the cycle**
   ```bash
   # Check dependencies of each module
   grep -r "required.*=" ~/.zsh/modules/*/module.toml
   ```

2. **Break the cycle**
   ```bash
   # Remove or change problematic dependencies
   # Example: A depends on B, B depends on C, C depends on A
   # Solution: Remove A's dependency on B or make it optional
   ```

3. **Restructure modules**
   ```bash
   # Extract common functionality to a base module
   zephyr init base-utils
   # Make other modules depend on base-utils instead of each other
   ```

### Problem: Wrong load order

**Symptoms:**
- Functions/variables not available when needed
- Modules loading in unexpected order

**Solutions:**

1. **Check priorities**
   ```bash
   # List modules with priorities
   zephyr list
   ```

2. **Adjust priorities in module.toml**
   ```toml
   [load]
   priority = 10  # Lower numbers load first
   ```

3. **Add explicit dependencies**
   ```toml
   [dependencies]
   required = ["module-that-should-load-first"]
   ```

## Performance Problems

### Problem: Slow shell startup

**Symptoms:**
- Shell takes several seconds to start
- Noticeable delay when opening new terminal

**Solutions:**

1. **Profile module loading**
   ```bash
   # Time the loading process
   time eval "$(zephyr load)"
   
   # Time individual components
   time zephyr list
   time zephyr load >/dev/null
   ```

2. **Optimize module files**
   ```bash
   # Check for slow operations in modules
   # - Heavy computations in global scope
   # - Network calls during loading
   # - Large file operations
   ```

3. **Reduce module count**
   ```bash
   # Combine small modules
   # Remove unused modules
   # Use optional dependencies
   ```

4. **Lazy loading**
   ```bash
   # Move expensive operations to functions
   # Use autoload for functions
   # Defer initialization to first use
   ```

### Problem: High memory usage

**Symptoms:**
- Shell uses excessive memory
- System becomes slow after shell startup

**Solutions:**

1. **Check for memory leaks**
   ```bash
   # Monitor memory usage
   ps aux | grep zsh
   
   # Check for large arrays or variables
   typeset | wc -l
   ```

2. **Optimize module code**
   ```bash
   # Avoid large global arrays
   # Clean up temporary variables
   # Use local variables in functions
   ```

## Platform-Specific Issues

### macOS Issues

**Problem: Permission denied on macOS Catalina+**
```bash
# Solution: Grant terminal full disk access
# System Preferences > Security & Privacy > Privacy > Full Disk Access
# Add your terminal application
```

**Problem: Homebrew path issues**
```bash
# Check Homebrew installation
brew --version

# Fix PATH for Homebrew
export PATH="/opt/homebrew/bin:$PATH"  # Apple Silicon
export PATH="/usr/local/bin:$PATH"     # Intel
```

### Linux Issues

**Problem: Missing dependencies on minimal systems**
```bash
# Install required tools
sudo apt-get update
sudo apt-get install build-essential curl git

# Or for Red Hat systems
sudo yum groupinstall "Development Tools"
sudo yum install curl git
```

**Problem: SELinux blocking execution**
```bash
# Check SELinux status
sestatus

# Allow execution (if needed)
sudo setsebool -P allow_execstack 1
```

### WSL Issues

**Problem: Windows line endings**
```bash
# Convert line endings
dos2unix ~/.zsh/modules/*/module.toml
dos2unix ~/.zsh/modules/*/*.zsh
```

**Problem: Path translation issues**
```bash
# Use WSL paths consistently
export ZSH_MODULES_DIR="/home/user/.zsh/modules"
# Not: C:\Users\user\.zsh\modules
```

## Advanced Debugging

### Enable Debug Mode

```bash
# Set debug environment variable (if implemented)
export ZEPHYR_DEBUG=1
zephyr load

# Or use shell debugging
set -x
eval "$(zephyr load)"
set +x
```

### Trace Module Loading

```bash
# Create debug script
cat > debug-zephyr.sh << 'EOF'
#!/bin/bash
echo "=== Zephyr Debug Trace ==="
echo "Modules directory: ${ZSH_MODULES_DIR:-$HOME/.zsh/modules}"
echo "Available modules:"
find "${ZSH_MODULES_DIR:-$HOME/.zsh/modules}" -name "module.toml" -exec dirname {} \; | sort

echo -e "\n=== Module Discovery ==="
zephyr list

echo -e "\n=== Module Validation ==="
zephyr validate

echo -e "\n=== Generated Code ==="
zephyr load
EOF

chmod +x debug-zephyr.sh
./debug-zephyr.sh
```

### Check File Permissions

```bash
# Check zephyr binary permissions
ls -la ~/.zsh/bin/zephyr

# Check modules directory permissions
ls -la ~/.zsh/modules/

# Check individual module permissions
find ~/.zsh/modules -type f -name "*.zsh" -exec ls -la {} \;
```

### Validate TOML Syntax

```bash
# Use external TOML validator if available
pip install toml-cli
find ~/.zsh/modules -name "module.toml" -exec toml-cli validate {} \;

# Or use Python
python3 -c "
import toml
import sys
try:
    with open(sys.argv[1]) as f:
        toml.load(f)
    print('Valid TOML')
except Exception as e:
    print(f'Invalid TOML: {e}')
" ~/.zsh/modules/my-module/module.toml
```

### Network Debugging

```bash
# If modules make network calls
export ZEPHYR_OFFLINE=1  # Disable network (if implemented)

# Check for network dependencies
grep -r "curl\|wget\|http" ~/.zsh/modules/

# Test without network
sudo ifconfig en0 down  # Disable network temporarily
zephyr load
sudo ifconfig en0 up    # Re-enable network
```

## Common Error Messages

### "TOML parse error"

**Error:**
```
TOML parse error: expected '=' after key at line 5
```

**Solution:**
```bash
# Check TOML syntax
cat -n ~/.zsh/modules/problematic-module/module.toml

# Common issues:
# - Missing quotes around strings
# - Incorrect array syntax
# - Missing section headers
```

### "Invalid module name"

**Error:**
```
Invalid module name 'My Module'
```

**Solution:**
```bash
# Use kebab-case names
zephyr init my-module  # Good
# Not: zephyr init "My Module"  # Bad
```

### "File not readable"

**Error:**
```
File not readable: /path/to/module/file.zsh
```

**Solution:**
```bash
# Fix file permissions
chmod 644 ~/.zsh/modules/*/module.toml
chmod 644 ~/.zsh/modules/*/*.zsh
```

## Getting Help

### Collect Debug Information

Before asking for help, collect this information:

```bash
# System information
uname -a
echo $SHELL
$SHELL --version

# Zephyr information
which zephyr
zephyr --version  # If implemented

# Module information
echo "ZSH_MODULES_DIR: ${ZSH_MODULES_DIR:-$HOME/.zsh/modules}"
ls -la "${ZSH_MODULES_DIR:-$HOME/.zsh/modules}"

# Error reproduction
zephyr validate 2>&1 | tee zephyr-debug.log
zephyr list 2>&1 | tee -a zephyr-debug.log
zephyr load 2>&1 | tee -a zephyr-debug.log
```

### Report Issues

When reporting issues, include:

1. **System information** (OS, shell version, architecture)
2. **Zephyr version** and installation method
3. **Complete error messages** (copy-paste, don't paraphrase)
4. **Steps to reproduce** the issue
5. **Module configuration** (sanitized module.toml files)
6. **Expected vs actual behavior**

### Community Resources

- **GitHub Issues**: Report bugs and feature requests
- **Documentation**: Check README and docs/ directory
- **Examples**: Look at test-modules/ for working examples

### Self-Help Checklist

Before asking for help, try:

- [ ] Read error messages carefully
- [ ] Check this troubleshooting guide
- [ ] Validate all modules with `zephyr validate`
- [ ] Test with a minimal configuration
- [ ] Check file permissions and paths
- [ ] Try with a fresh module directory
- [ ] Search existing GitHub issues

Remember: Most issues are configuration problems that can be solved by carefully reading error messages and checking file paths and permissions.
