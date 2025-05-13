#!/bin/bash
set -e

# Test script to verify local packaging
echo "Testing local packaging workflow"
echo "==============================="

# Check if we should skip building and packaging
SKIP_BUILD_PACKAGE=0
if [ "$1" == "--test-only" ]; then
    SKIP_BUILD_PACKAGE=1
fi

if [ $SKIP_BUILD_PACKAGE -eq 0 ]; then
    # Build DSQL if needed
    if [ ! -f "src/bin/psql/psql" ]; then
        echo "Building DSQL first..."
        ./scripts/build-dsql.sh
    else
        echo "DSQL already built, skipping build step"
    fi

    # Package the build
    echo "Packaging DSQL..."
    ./scripts/package.sh
else
    echo "Skipping build and package steps, testing only..."
fi

# Test the packaged binary
echo "Testing packaged binary..."
if [ -f "postgres-dsql.zip" ]; then
    # Clean any previous test
    rm -rf /tmp/postgres-dsql
    
    # Extract and test
    unzip -o postgres-dsql.zip -d /tmp
    
    echo "Running pdsql --version to verify:"
    /tmp/postgres-dsql/bin/pdsql --version
    
    if [ $? -eq 0 ]; then
        echo "✅ Test passed! Package is working correctly."
    else
        echo "❌ Test failed! Please check the package."
        exit 1
    fi
else
    echo "❌ Package file not found!"
    exit 1
fi

echo "All tests completed successfully."
