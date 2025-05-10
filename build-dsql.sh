#!/bin/bash
set -e

echo "Building PostgreSQL with DSQL Authentication support"
echo "==================================================="

# Determine OS type for library path configuration
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS"
    LIBRARY_PATH_VAR="DYLD_LIBRARY_PATH"
    OS_SPECIFIC_CONFIG="--with-includes=/opt/homebrew/opt/openssl/include --with-libraries=/opt/homebrew/opt/openssl/lib"
else
    echo "Detected Linux/Unix system"
    LIBRARY_PATH_VAR="LD_LIBRARY_PATH"
    OS_SPECIFIC_CONFIG=""
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

# Build aws-dsql-auth
echo "  Building aws-dsql-auth library..."
cd aws-dsql-auth
./build.sh
cd ..
echo "  AWS DSQL Auth library built successfully!"

# Step 2: Configure PostgreSQL with SSL support
echo "Step 2: Configuring PostgreSQL with SSL support..."
if [ ! -f "config.status" ]; then
    echo "  Running configure with SSL support..."
    ./configure --with-openssl $OS_SPECIFIC_CONFIG
else
    echo "  PostgreSQL already configured. If you need to reconfigure, run './configure --with-openssl $OS_SPECIFIC_CONFIG' manually."
fi

# Step 3: Build libpq (PostgreSQL client library)
echo "Step 3: Building libpq..."
make -C src/interfaces/libpq
echo "  libpq built successfully!"

# Step 4: Build psql
echo "Step 4: Building psql..."
make -C src/bin/psql
echo "  psql built successfully!"

# Verify SSL support
echo "Verifying SSL support in psql binary..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    otool -L src/bin/psql/psql | grep -i ssl
else
    ldd src/bin/psql/psql | grep -i ssl
fi

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
