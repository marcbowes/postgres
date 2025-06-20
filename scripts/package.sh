#!/bin/bash
set -e

# Package PostgreSQL DSQL client for distribution
# This script creates a standalone distribution with psql (renamed to pdsql) 
# and libpq that can be used without additional dependencies

echo "Packaging PostgreSQL DSQL client"
echo "================================"

# Path setup
ROOT_DIR=$(pwd)
DIST_NAME="postgres-dsql"
DIST_DIR="$ROOT_DIR/$DIST_NAME"
SRC_BIN="$ROOT_DIR/src/bin/psql/psql"
BINARY_NAME="pdsql"

# Detect OS and set appropriate library paths
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS"
    SRC_LIB="$ROOT_DIR/src/interfaces/libpq/libpq.5.dylib"
    LIB_EXT="dylib"
    PLATFORM="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Detected Linux"
    SRC_LIB="$ROOT_DIR/src/interfaces/libpq/libpq.so.5"
    LIB_EXT="so"
    PLATFORM="linux"
else
    echo "Error: Unsupported operating system: $OSTYPE"
    echo "This script supports macOS and Linux only"
    exit 1
fi

# Check if the build artifacts exist
if [ ! -f "$SRC_BIN" ]; then
    echo "Error: psql binary not found at $SRC_BIN"
    echo "Please run scripts/build-dsql.sh first"
    exit 1
fi

if [ ! -f "$SRC_LIB" ]; then
    echo "Error: libpq library not found at $SRC_LIB"
    echo "Please run scripts/build-dsql.sh first"
    exit 1
fi

# Clean any previous packaging attempts
if [ -d "$DIST_DIR" ]; then
    echo "Cleaning previous packaging directory..."
    rm -rf "$DIST_DIR"
fi

# Create directory structure
mkdir -p "$DIST_DIR/bin"
mkdir -p "$DIST_DIR/lib"

# Copy binaries and libraries
echo "Copying psql to $DIST_DIR/bin/$BINARY_NAME"
cp "$SRC_BIN" "$DIST_DIR/bin/$BINARY_NAME"

echo "Copying libpq to $DIST_DIR/lib/"
cp "$SRC_LIB" "$DIST_DIR/lib/"

# Handle platform-specific library setup
if [[ "$PLATFORM" == "macos" ]]; then
    # Copy additional dylib if it exists
    cp "$ROOT_DIR/src/interfaces/libpq/libpq.dylib" "$DIST_DIR/lib/" 2>/dev/null || true
    
    # Set up correct library paths in the binary
    echo "Updating library paths in $BINARY_NAME binary..."
    LIBRARY_PATH=$(otool -L "$DIST_DIR/bin/$BINARY_NAME" | grep libpq | awk '{print $1}')
    install_name_tool -change "$LIBRARY_PATH" "@loader_path/../lib/libpq.5.dylib" "$DIST_DIR/bin/$BINARY_NAME"
    
    # Fix library itself to refer to itself by relative path
    install_name_tool -id "@loader_path/libpq.5.dylib" "$DIST_DIR/lib/libpq.5.dylib"
    
    # Verify the changes
    echo "Verifying library path changes:"
    otool -L "$DIST_DIR/bin/$BINARY_NAME" | grep libpq
    otool -L "$DIST_DIR/lib/libpq.5.dylib" | grep libpq

elif [[ "$PLATFORM" == "linux" ]]; then
    # Copy additional .so files if they exist
    cp "$ROOT_DIR/src/interfaces/libpq/libpq.so" "$DIST_DIR/lib/" 2>/dev/null || true
    
    # Set up RPATH for the binary to find libraries in ../lib
    echo "Setting RPATH for $BINARY_NAME binary..."
    patchelf --set-rpath '$ORIGIN/../lib' "$DIST_DIR/bin/$BINARY_NAME" 2>/dev/null || {
        echo "Warning: patchelf not available. Installing patchelf..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y patchelf
            patchelf --set-rpath '$ORIGIN/../lib' "$DIST_DIR/bin/$BINARY_NAME"
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y patchelf
            patchelf --set-rpath '$ORIGIN/../lib' "$DIST_DIR/bin/$BINARY_NAME"
        else
            echo "Warning: Could not install patchelf. The binary may not find libraries correctly."
        fi
    }
    
    # Verify the changes
    echo "Verifying RPATH changes:"
    ldd "$DIST_DIR/bin/$BINARY_NAME" | grep libpq || echo "libpq dependency check complete"
fi

# Create a ZIP archive
echo "Creating ZIP archive..."
ZIP_NAME="${DIST_NAME}.zip"
rm -f "$ZIP_NAME"
(cd "$ROOT_DIR" && zip -r "$ZIP_NAME" "$DIST_NAME")

echo "Package created at $ROOT_DIR/$ZIP_NAME"
echo "Done!"

# For testing, you can:
# unzip -o postgres-dsql.zip -d /tmp
# /tmp/postgres-dsql/bin/pdsql --version
#
# On Linux, you may also need to ensure the library path is set:
# LD_LIBRARY_PATH=/tmp/postgres-dsql/lib /tmp/postgres-dsql/bin/pdsql --version
