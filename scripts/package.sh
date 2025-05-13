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
SRC_LIB="$ROOT_DIR/src/interfaces/libpq/libpq.5.dylib"
BINARY_NAME="pdsql"

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "This script is currently only designed for macOS"
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
