.PHONY: help build install clean test benchmark run dev check fmt

# Default target
.DEFAULT_GOAL := help

# Binary name
BINARY := zephyr

# Optional libgit2 flags (auto-detected via pkg-config)
LIBGIT2_LIBS ?= $(shell pkg-config --libs libgit2 2>/dev/null)
ifneq ($(strip $(LIBGIT2_LIBS)),)
LIBGIT2_FLAGS :=
endif

# Optional libmagic flags (auto-detected via pkg-config)
LIBMAGIC_LIBS ?= $(shell pkg-config --libs libmagic 2>/dev/null)
ifneq ($(strip $(LIBMAGIC_LIBS)),)
LIBMAGIC_FLAGS := -define:ZEPHYR_HAS_MAGIC=true
else
LIBMAGIC_FLAGS := -define:ZEPHYR_HAS_MAGIC=false
endif

LINKER_FLAGS := $(strip $(LIBGIT2_LIBS) $(LIBMAGIC_LIBS))
ifneq ($(LINKER_FLAGS),)
EXTRA_LINKER_FLAGS := -extra-linker-flags:"$(LINKER_FLAGS)"
endif

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help: ## Show this help message
	@echo "$(BLUE)Zephyr Shell Loader - Build System$(NC)"
	@echo ""
	@echo "$(GREEN)Usage:$(NC)"
	@echo "  make <target>"
	@echo ""
	@echo "$(GREEN)Targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2}'

check-libgit2: ## Check libgit2 detection
	@if command -v pkg-config >/dev/null 2>&1; then \
		if pkg-config --exists libgit2; then \
			echo "$(GREEN)✓ libgit2 detected: $$(pkg-config --libs libgit2)$(NC)"; \
		else \
			echo "$(YELLOW)⚠ libgit2 not detected via pkg-config$(NC)"; \
		fi; \
	else \
		echo "$(YELLOW)⚠ pkg-config not found; cannot auto-detect libgit2$(NC)"; \
	fi

build: ## Build the zephyr binary
	@echo "$(BLUE)Building $(BINARY)...$(NC)"
	@./build.sh
	@echo "$(GREEN)✓ Build complete$(NC)"

install: build ## Build and install to ~/.zsh/bin
	@echo "$(BLUE)Installing $(BINARY)...$(NC)"
	@./install.sh
	@echo "$(GREEN)✓ Installation complete$(NC)"

clean: ## Remove build artifacts
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@rm -f $(BINARY) *.bin
	@rm -rf benchmark_modules test_*
	@echo "$(GREEN)✓ Clean complete$(NC)"

test: build ## Run test suite
	@echo "$(BLUE)Running tests...$(NC)"
	@odin test test $(EXTRA_LINKER_FLAGS) $(LIBMAGIC_FLAGS)
	@echo "$(GREEN)✓ Tests passed$(NC)"

benchmark: build ## Run performance benchmark
	@echo "$(BLUE)Running benchmark...$(NC)"
	@./benchmark.sh
	@echo "$(GREEN)✓ Benchmark complete$(NC)"

benchmark-quick: build ## Run quick benchmark
	@echo "$(BLUE)Running quick benchmark...$(NC)"
	@./benchmark.sh --quick
	@echo "$(GREEN)✓ Quick benchmark complete$(NC)"

benchmark-scale: build ## Run scalability benchmark
	@echo "$(BLUE)Running scalability benchmark...$(NC)"
	@./benchmark.sh --scalability
	@echo "$(GREEN)✓ Scalability benchmark complete$(NC)"

run: build ## Build and run with test modules
	@echo "$(BLUE)Running $(BINARY) with test modules...$(NC)"
	@ZSH_MODULES_DIR="$$PWD/test-modules" ./$(BINARY) list

dev: ## Build with debug flags
	@echo "$(BLUE)Building $(BINARY) in debug mode...$(NC)"
	@odin build src -o:none -debug -out:$(BINARY) $(EXTRA_LINKER_FLAGS) $(LIBMAGIC_FLAGS)
	@echo "$(GREEN)✓ Debug build complete$(NC)"

check: ## Validate code (odin check)
	@echo "$(BLUE)Checking code...$(NC)"
	@odin check src
	@echo "$(GREEN)✓ Code check passed$(NC)"

fmt: ## Format code (if odin fmt exists)
	@echo "$(BLUE)Formatting code...$(NC)"
	@if command -v odin-fmt >/dev/null 2>&1; then \
		find src -name "*.odin" -exec odin-fmt -w {} \; ; \
		echo "$(GREEN)✓ Code formatted$(NC)"; \
	else \
		echo "$(YELLOW)⚠ odin-fmt not found, skipping$(NC)"; \
	fi

uninstall: ## Remove installed binary
	@echo "$(BLUE)Uninstalling $(BINARY)...$(NC)"
	@rm -f "$$HOME/.zsh/bin/$(BINARY)"
	@echo "$(GREEN)✓ Uninstalled$(NC)"

all: clean build test ## Clean, build, and test

.PHONY: all
