#!/bin/bash
set -e

echo "Building PostgreSQL with DSQL Authentication support"
echo "==================================================="

# Determine OS type for library path configuration
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS"
    LIBRARY_PATH_VAR="DYLD_LIBRARY_PATH"
    
    # Base configuration with OpenSSL and readline
    OS_SPECIFIC_CONFIG="--with-ssl=openssl --with-includes=/opt/homebrew/opt/openssl/include:/opt/homebrew/opt/readline/include --with-libraries=/opt/homebrew/opt/openssl/lib:/opt/homebrew/opt/readline/lib"
    
    # Check for ICU4C in Homebrew
    if [ -d "/opt/homebrew/opt/icu4c" ]; then
        echo "  Detected Homebrew ICU4C installation"
        # Use the Homebrew-maintained symlink to the current version
        export PKG_CONFIG_PATH="/opt/homebrew/opt/icu4c/lib/pkgconfig:$PKG_CONFIG_PATH"
        echo "  Added ICU4C to build configuration"
    elif [ -d "/usr/local/opt/icu4c" ]; then
        # For Intel Macs with Homebrew installed in /usr/local
        echo "  Detected Homebrew ICU4C installation in /usr/local"
        export PKG_CONFIG_PATH="/usr/local/opt/icu4c/lib/pkgconfig:$PKG_CONFIG_PATH"
        echo "  Added ICU4C to build configuration"
    else
        echo "  Warning: Homebrew ICU4C not detected, configure may fail if ICU is required"
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Detected Linux system"
    LIBRARY_PATH_VAR="LD_LIBRARY_PATH"
    
    # Base configuration for Linux with system packages
    OS_SPECIFIC_CONFIG="--with-ssl=openssl --with-icu"
    
    # Check if we have the required development packages
    echo "  Checking for required development packages..."
    
    # Check for essential build tools and libraries
    MISSING_PACKAGES=""
    
    if ! dpkg -l | grep -q "libssl-dev\|openssl-dev" 2>/dev/null && ! rpm -qa | grep -q "openssl-devel" 2>/dev/null; then
        MISSING_PACKAGES="$MISSING_PACKAGES libssl-dev"
    fi
    
    if ! dpkg -l | grep -q "libreadline-dev\|readline-dev" 2>/dev/null && ! rpm -qa | grep -q "readline-devel" 2>/dev/null; then
        MISSING_PACKAGES="$MISSING_PACKAGES libreadline-dev"
    fi
    
    if ! dpkg -l | grep -q "zlib1g-dev\|zlib-dev" 2>/dev/null && ! rpm -qa | grep -q "zlib-devel" 2>/dev/null; then
        MISSING_PACKAGES="$MISSING_PACKAGES zlib1g-dev"
    fi
    
    if ! dpkg -l | grep -q "libicu-dev\|icu-dev" 2>/dev/null && ! rpm -qa | grep -q "libicu-devel" 2>/dev/null; then
        MISSING_PACKAGES="$MISSING_PACKAGES libicu-dev"
    fi
    
    if ! command -v flex >/dev/null 2>&1; then
        MISSING_PACKAGES="$MISSING_PACKAGES flex"
    fi
    
    if ! command -v bison >/dev/null 2>&1; then
        MISSING_PACKAGES="$MISSING_PACKAGES bison"
    fi
    
    if [ -n "$MISSING_PACKAGES" ]; then
        echo "  Warning: Some required packages may be missing: $MISSING_PACKAGES"
        echo "  On Ubuntu/Debian, install with: sudo apt-get install $MISSING_PACKAGES"
        echo "  On RHEL/CentOS, install equivalent packages with yum/dnf"
    else
        echo "  Required development packages appear to be installed"
    fi
else
    echo "Detected Unix system (assuming Linux-like)"
    LIBRARY_PATH_VAR="LD_LIBRARY_PATH"
    OS_SPECIFIC_CONFIG="--with-ssl=openssl"
fi

# Step 1: Initialize and build aws-dsql-auth
echo "Step 1: Setting up AWS DSQL Auth library..."

# Check if aws-dsql-auth submodules are initialized
if [ ! -d "aws-dsql-auth/aws-sdk/aws-c-common/.git" ]; then
    echo "  Initializing aws-dsql-auth submodules..."
    cd aws-dsql-auth
    git submodule update --init --recursive
    cd ..
else
    echo "  aws-dsql-auth submodules already initialized."
fi

if [ ! -f "aws-dsql-auth/build/aws-dsql-auth/libaws-dsql-auth.a" ]; then
    # Build aws-dsql-auth
    echo "  Building aws-dsql-auth library..."
    cd aws-dsql-auth
    ./build.sh
    cd ..
    echo "  AWS DSQL Auth library built successfully!"
else
    echo "  aws-dsql-auth already built."
fi

# Step 2: Configure PostgreSQL with SSL support
echo "Step 2: Configuring PostgreSQL with SSL support..."
if [ ! -f "config.status" ]; then
    echo "  Running configure ..."
    ./configure $OS_SPECIFIC_CONFIG
else
    echo "  PostgreSQL already configured. If you need to reconfigure, run './configure $OS_SPECIFIC_CONFIG' manually."
fi

# Step 3: Build libpq (PostgreSQL client library)
echo "Step 3: Building libpq..."
make -C src/interfaces/libpq
echo "  libpq built successfully!"

# Step 4: Build psql
echo "Step 4: Building psql..."
make -C src/bin/psql
echo "  psql built successfully!"

# Final instructions
echo ""
echo "Build completed successfully!"
echo ""
echo "To run psql with DSQL authentication, use the following command:"
echo ""
echo "  $LIBRARY_PATH_VAR=$(pwd)/src/interfaces/libpq \\"
echo "  ./src/bin/psql/psql --dsql --host=your-dsql-endpoint.example.com --user=admin --dbname=postgres"
echo ""
echo "Or with connection string format:"
echo ""
echo "  $LIBRARY_PATH_VAR=$(pwd)/src/interfaces/libpq \\"
echo "  ./src/bin/psql/psql --dsql \"dbname=postgres user=admin host=your-dsql-endpoint.example.com\""
echo ""
echo "Note: You need to have AWS credentials configured in your environment for DSQL authentication to work."
