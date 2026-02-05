# Acceptance Tests

This directory contains acceptance tests that verify all functional requirements from the requirements specification.

## Running Acceptance Tests

The acceptance tests are standalone and separate from the unit test suite:

```bash
# Build the acceptance test
odin build acceptance/acceptance_test.odin -file -out:acceptance_test

# Run the acceptance test
./acceptance_test
```

## What's Tested

The acceptance test suite verifies:

- **3.1.x**: Manifest parsing with all fields
- **3.2.x**: Module discovery (recursive and error handling)
- **3.3.x**: Dependency resolution (topological sort, circular detection, missing deps)
- **3.4.x**: Shell code generation
- **3.5.x**: CLI commands
- **4.2.x**: Error handling (malformed TOML, missing files)
- **4.3.x**: Platform compatibility and filtering

## Expected Output

All tests should pass:

```
=== Zephyr Acceptance Test Suite ===

Testing Manifest Parsing (Requirements 3.1.x)...
  ✓ PASS: 3.1.1-3.1.8: Parse complete manifest
Testing Module Discovery (Requirements 3.2.x)...
  ✓ PASS: 3.2.1-3.2.3: Discover modules recursively
  ✓ PASS: 3.2.4: Handle missing directories gracefully
...

=== Test Summary ===
Total: 11 tests
Passed: 11
Failed: 0
```

## Why Separate from Unit Tests?

The acceptance tests are kept separate from the unit test suite (`test/`) because:

1. **Different Purpose**: Acceptance tests verify end-to-end requirements, while unit tests verify individual components
2. **Standalone Execution**: Acceptance tests have their own `main()` function and run independently
3. **No Conflicts**: Avoids function name conflicts with test utilities
4. **Clear Separation**: Makes it clear which tests are for acceptance vs. unit testing

## Unit Tests

For unit and property-based tests, see the `test/` directory and run:

```bash
odin test test
```

Note: The unit test suite may have some hanging tests or memory leak warnings that are being investigated. The acceptance tests provide a reliable verification of all core functionality.
