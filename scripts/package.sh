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

# Create RPM package for Linux
if [[ "$PLATFORM" == "linux" ]]; then
    echo "Creating RPM package..."
    
    # Create RPM build directory structure
    RPM_BUILD_DIR="$ROOT_DIR/rpmbuild"
    mkdir -p "$RPM_BUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    
    # Create spec file
    SPEC_FILE="$RPM_BUILD_DIR/SPECS/postgres-dsql.spec"
    cat > "$SPEC_FILE" << 'EOF'
Name:           postgres-dsql
Version:        1.0.0
Release:        1%{?dist}
Summary:        PostgreSQL DSQL client (pdsql) - AWS DSQL authentication enabled psql
License:        PostgreSQL
URL:            https://github.com/your-org/postgres-dsql
BuildArch:      x86_64

%description
PostgreSQL DSQL client provides pdsql, a PostgreSQL client with AWS DSQL 
authentication support. This package installs alongside existing PostgreSQL 
installations without conflicts by using different binary and library names.

%prep
# No prep needed - files are already prepared

%build
# No build needed - binaries are already built

%install
mkdir -p %{buildroot}/opt/postgres-dsql/bin
mkdir -p %{buildroot}/opt/postgres-dsql/lib
mkdir -p %{buildroot}/usr/bin

# Install binaries and libraries to /opt to avoid conflicts
cp %{_sourcedir}/bin/pdsql %{buildroot}/opt/postgres-dsql/bin/
cp %{_sourcedir}/lib/* %{buildroot}/opt/postgres-dsql/lib/

# Create symlink in /usr/bin for easy access
ln -s /opt/postgres-dsql/bin/pdsql %{buildroot}/usr/bin/pdsql

%files
/opt/postgres-dsql/bin/pdsql
/opt/postgres-dsql/lib/*
/usr/bin/pdsql

%post
echo "PostgreSQL DSQL client installed successfully!"
echo "Use 'pdsql' command to connect to AWS DSQL databases."
echo "Example: pdsql --dsql --host=your-dsql-endpoint.example.com --user=admin --dbname=postgres"

%changelog
* $(date +'%a %b %d %Y') Build System <build@example.com> - 1.0.0-1
- Initial RPM package for PostgreSQL DSQL client
EOF

    # Copy files to SOURCES directory with the structure expected by the spec
    mkdir -p "$RPM_BUILD_DIR/SOURCES/bin"
    mkdir -p "$RPM_BUILD_DIR/SOURCES/lib"
    cp "$DIST_DIR/bin/pdsql" "$RPM_BUILD_DIR/SOURCES/bin/"
    cp "$DIST_DIR/lib"/* "$RPM_BUILD_DIR/SOURCES/lib/"
    
    # Build the RPM
    echo "Building RPM package..."
    if command -v rpmbuild >/dev/null 2>&1; then
        rpmbuild --define "_topdir $RPM_BUILD_DIR" -bb "$SPEC_FILE"
        
        # Find and copy the generated RPM
        RPM_FILE=$(find "$RPM_BUILD_DIR/RPMS" -name "*.rpm" | head -1)
        if [ -n "$RPM_FILE" ]; then
            cp "$RPM_FILE" "$ROOT_DIR/"
            RPM_NAME=$(basename "$RPM_FILE")
            echo "RPM package created at $ROOT_DIR/$RPM_NAME"
        else
            echo "Warning: RPM file not found after build"
        fi
    else
        echo "Warning: rpmbuild not available. Installing rpm-build..."
        if command -v yum >/dev/null 2>&1; then
            sudo yum install -y rpm-build
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y rpm-build
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y rpm
        else
            echo "Error: Could not install rpm-build. RPM package not created."
            echo "Please install rpm-build manually and re-run this script."
        fi
        
        # Retry RPM build if rpmbuild is now available
        if command -v rpmbuild >/dev/null 2>&1; then
            rpmbuild --define "_topdir $RPM_BUILD_DIR" -bb "$SPEC_FILE"
            RPM_FILE=$(find "$RPM_BUILD_DIR/RPMS" -name "*.rpm" | head -1)
            if [ -n "$RPM_FILE" ]; then
                cp "$RPM_FILE" "$ROOT_DIR/"
                RPM_NAME=$(basename "$RPM_FILE")
                echo "RPM package created at $ROOT_DIR/$RPM_NAME"
            fi
        fi
    fi
    
    echo ""
    echo "RPM Installation Instructions:"
    echo "  sudo rpm -ivh $RPM_NAME"
    echo "  # Or to upgrade: sudo rpm -Uvh $RPM_NAME"
    echo ""
    echo "RPM Removal Instructions:"
    echo "  sudo rpm -e postgres-dsql"
    echo ""
fi

echo "Done!"

# For testing, you can:
# unzip -o postgres-dsql.zip -d /tmp
# /tmp/postgres-dsql/bin/pdsql --version
#
# On Linux, you may also need to ensure the library path is set:
# LD_LIBRARY_PATH=/tmp/postgres-dsql/lib /tmp/postgres-dsql/bin/pdsql --version
#
# For RPM testing:
# sudo rpm -ivh postgres-dsql-*.rpm
# pdsql --version
