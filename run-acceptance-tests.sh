#!/usr/bin/env bash
# Run acceptance tests for Zephyr Shell Loader

set -e

echo "=== Building Acceptance Tests ==="
odin build acceptance/acceptance_test.odin -file -out:acceptance_test

echo ""
echo "=== Running Acceptance Tests ==="
./acceptance_test

echo ""
echo "=== Acceptance Tests Complete ==="
