# PostgreSQL Command Line Client (psql) with AWS DSQL Authentication

This document describes how to build the PostgreSQL command line client (`psql`) with AWS DSQL Authentication support, which allows automatic token generation when connecting to AWS Database Services for PostgreSQL.

## Overview of DSQL Authentication

DSQL Authentication allows `psql` to automatically generate temporary authentication tokens when connecting to AWS Database Services for PostgreSQL. This integration offers several advantages:

- No need to manually generate and paste tokens
- Automatic token regeneration if connections fail or tokens expire
- Simplified connection experience with a single `--dsql` flag

## Prerequisites

- C compiler (GCC or Clang)
- Make
- Readline library (for command line editing)
- OpenSSL development libraries (required for SSL support)
- AWS credentials configured in your environment (via ~/.aws/credentials, environment variables, etc.)
- AWS DSQL Auth library (located in `aws-dsql-auth` directory)

## Build Steps

### Quick Build with build-dsql.sh Script

The easiest way to build PostgreSQL with DSQL Authentication support is to use the provided `build-dsql.sh` script:

```bash
# Make the script executable if needed
chmod +x build-dsql.sh

# Run the build script
./build-dsql.sh
```

This script automates the following tasks:
1. Initializes the aws-dsql-auth submodules if needed
2. Builds the AWS DSQL Auth library
3. Configures PostgreSQL with SSL support
4. Builds libpq and psql
5. Verifies SSL support
6. Displays usage instructions

The script automatically detects your OS and sets appropriate configuration options. After running the script, you'll have a working psql binary with DSQL Authentication support.

### Manual Build Steps

If you prefer to build the components step-by-step, follow these instructions:

#### 1. Install Required Dependencies

##### On macOS:
```bash
brew install openssl readline
```

##### On Ubuntu/Debian:
```bash
sudo apt-get install libssl-dev libreadline-dev
```

##### On RHEL/Fedora:
```bash
sudo dnf install openssl-devel readline-devel
```

#### 2. Build the AWS DSQL Auth Library

Initialize submodules (if not already done) and build the AWS DSQL Auth library:

```bash
cd aws-dsql-auth
git submodule update --init --recursive
./build.sh
cd ..
```

#### 3. Configure PostgreSQL with SSL Support

Configure the PostgreSQL source code with SSL support enabled:

```bash
# macOS (with Homebrew)
./configure --with-openssl --with-includes=/opt/homebrew/opt/openssl/include --with-libraries=/opt/homebrew/opt/openssl/lib

# Linux (typically SSL is found automatically)
./configure --with-openssl
```

Additional common options include:
- `--prefix=/path/to/install` - Set installation directory
- `--without-icu` - Disable ICU support if not available
- `--enable-tap-tests` - Enable TAP tests if you plan to run test suites

#### 4. Build libpq (PostgreSQL Client Library)

Build the PostgreSQL client library that psql depends on:

```bash
make -C src/interfaces/libpq
```

#### 5. Build psql

Build the psql command line utility:

```bash
make -C src/bin/psql
```

#### 6. Verify SSL Support

Ensure SSL support was built properly:

```bash
src/bin/psql/psql --help | grep -i ssl
```
You should see SSL-related options, or alternatively:
```bash
ldd src/bin/psql/psql | grep -i ssl    # Linux
otool -L src/bin/psql/psql | grep -i ssl    # macOS
```

### 7. Running psql

To run the newly built psql with the locally built libpq:

```bash
# On macOS
DYLD_LIBRARY_PATH=$(pwd)/src/interfaces/libpq ./src/bin/psql/psql [options]

# On Linux
LD_LIBRARY_PATH=$(pwd)/src/interfaces/libpq ./src/bin/psql/psql [options]
```

Note: The AWS DSQL Auth library is statically linked into psql, so you only need to include the libpq library path.

## Using DSQL Authentication

To connect using DSQL authentication, add the `--dsql` flag to your `psql` command:

```bash
./src/bin/psql/psql --dsql --host=your-dsql-endpoint.example.com --user=admin
```

Or, with the full connection string:

```bash
./src/bin/psql/psql --dsql "dbname=postgres user=admin host=your-dsql-endpoint.example.com"
```

### How DSQL Authentication Works

When the `--dsql` flag is provided:

1. `psql` automatically sets `SSLMODE=require` to ensure a secure connection (SSL must be compiled in)
2. When connecting to a server, DSQL token generation is triggered
3. If the connection user is `admin`, the token is generated with admin privileges
4. A new token is generated for each connection attempt to ensure security
5. Tokens are set to expire after 5 seconds to enhance security
6. If the connection fails and reconnection is attempted, a new token is generated automatically

### Environment Variables

- `PGSSLMODE`: If not already set and `--dsql` is used, it will be set to `require`
- `AWS_REGION`: Optional, if not set the region will be inferred from the hostname
- `PGSSLROOTCERT`: Optional, path to SSL root certificate for verification

## Testing

To run tests specifically for libpq and psql:

```bash
# Test libpq
make -C src/interfaces/libpq check

# Test psql
make -C src/bin/psql check
```

Note: For comprehensive testing, configure with `--enable-tap-tests` before running these commands.

## Optional: Installation

If you want to install psql and libpq:

```bash
make -C src/bin/psql install
make -C src/interfaces/libpq install
make -C src/include install  # For header files
```

## Troubleshooting

### SSL-Related Issues

1. If you see "sslmode value 'require' invalid when SSL support is not compiled in":
   - Ensure you configured with `--with-openssl`
   - Check that OpenSSL development files are properly installed
   - Rebuild from scratch after configuring with SSL support

2. If you experience SSL connection issues:
   - You can specify certificate verification settings with environment variables:
     ```bash
     PGSSLMODE=verify-ca PGSSLROOTCERT=/path/to/rootcert.pem ./src/bin/psql/psql --dsql ...
     ```

### General Build Issues

If you encounter library dependency issues:

1. Ensure the library path is correctly set to point to your built libpq and aws-dsql-auth libraries
2. Check for missing dependencies with `ldd` (Linux) or `otool -L` (macOS)
3. Verify that the configure step completed without errors

### DSQL Authentication Issues

If you encounter issues with DSQL authentication:

1. Ensure your AWS credentials are correctly configured and have appropriate permissions
2. Check that you're using the correct endpoint hostname
3. Verify the `aws-dsql-auth` library is correctly built
4. Try with explicit AWS credentials via environment variables:
   ```bash
   AWS_ACCESS_KEY_ID=your_key AWS_SECRET_ACCESS_KEY=your_secret ./src/bin/psql/psql --dsql ...
   ```

## Notes

- This builds only the command line client, not the PostgreSQL server
- The built psql can connect to any compatible PostgreSQL server
- Command line editing requires readline support
- SSL support is required for DSQL Authentication to work properly
- DSQL Authentication is primarily intended for use with AWS Database Services for PostgreSQL
- Token generation happens automatically and is transparent to the user
- Currently, admin token generation is only supported for the `admin` user

## Packaging and Distribution

PostgreSQL DSQL client can be packaged into a distributable format that can be easily downloaded from GitHub Releases.

### Overview of the Packaging System

The packaging system:

- Takes the built `psql` binary and `libpq` library
- Copies them into a structured directory called `postgres-dsql`
- Renames `psql` to `pdsql`
- Sets up the proper relative library paths so `pdsql` can find `libpq`
- Creates a ZIP archive for distribution

### Directory Structure

The packaged distribution has the following structure:

```
postgres-dsql/
├── bin/
│   └── pdsql     # Renamed psql binary
└── lib/
    └── libpq.5.dylib  # PostgreSQL client library
```

### GitHub Actions Workflow

The GitHub Actions workflow automates the build and packaging process, and is triggered:

- Manually via workflow_dispatch
- On creation of version tags (v*)

To create a new release:
1. Tag a commit with a version number: `git tag v1.0.0`
2. Push the tag: `git push origin v1.0.0`

The workflow will:
1. Build PostgreSQL with DSQL support
2. Package the binaries
3. Test the package
4. Upload the package as a GitHub release artifact

### Local Development and Testing

#### Testing the Packaging Locally

To test the packaging process locally:

```bash
# Build if needed and package
./scripts/test-packaging.sh
```

This script will:
1. Build DSQL if not already built
2. Package the build into postgres-dsql.zip
3. Extract and test the binary by running `dpsql --version`

#### Manual Testing

You can also test manually:

```bash
# Build DSQL
./scripts/build-dsql.sh

# Package the build
./scripts/package.sh

# Test the packaged binary
unzip -o postgres-dsql.zip -d /tmp
/tmp/postgres-dsql/bin/pdsql --version
```

### Using the Packaged Binary

After downloading and extracting the package:

```bash
unzip postgres-dsql.zip
cd postgres-dsql
./bin/pdsql --host=your-dsql-endpoint.example.com --user=admin --dbname=postgres
```

Note: The renamed binary `pdsql` automatically enables DSQL authentication mode, so the `--dsql` flag is not necessary.

### Current Limitations

- This packaging solution currently only supports ARM macOS
- The package assumes the necessary AWS credentials are available in the environment
