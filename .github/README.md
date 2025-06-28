# PostgreSQL DSQL Client (pdsql)

A PostgreSQL command-line client with built-in AWS DSQL authentication support. Connect to AWS DSQL databases with automatic token generation - no manual token management required.

## 🚀 Quick Installation

Install `pdsql` with a single command:

```bash
curl -sSL https://raw.githubusercontent.com/marcbowes/postgres/refs/heads/master/scripts/install.sh | sh
```

This installer automatically detects your platform (macOS/Linux) and architecture, downloads the appropriate package, and installs `pdsql` to your local environment.

### Manual Installation

If you prefer to download manually:

1. Visit the [GitHub Releases page](https://github.com/marcbowes/postgres/releases)
2. Download the appropriate package for your platform:
   - **macOS Intel**: `postgres-dsql-macos-x64.zip`
   - **macOS Apple Silicon**: `postgres-dsql-macos-arm64.zip`
   - **Linux x64**: `postgres-dsql-linux-x64.zip`
   - **Linux ARM64**: `postgres-dsql-linux-arm64.zip`
3. Extract and run:
   ```bash
   unzip postgres-dsql-*.zip
   cd postgres-dsql
   ./bin/pdsql --version
   ```

### Package Manager Installation (Linux)

For Linux users, we also provide native packages:

**Debian/Ubuntu (.deb)**:
```bash
wget https://github.com/marcbowes/postgres/releases/latest/download/postgres-dsql_1.0.0-1_amd64.deb
sudo apt install ./postgres-dsql_1.0.0-1_amd64.deb
```

**RHEL/Fedora (.rpm)**:
```bash
wget https://github.com/marcbowes/postgres/releases/latest/download/postgres-dsql-1.0.0-1.x86_64.rpm
sudo dnf install postgres-dsql-1.0.0-1.x86_64.rpm
```

## 🔧 Usage

### Basic Connection

Connect to an AWS DSQL database:

```bash
pdsql --host=your-dsql-endpoint.example.com --user=admin --port=5432 --dbname=postgres
```

### Connection String Format

You can also use PostgreSQL connection strings:

```bash
pdsql "host=your-dsql-endpoint.example.com user=admin port=5432 dbname=postgres"
```

### Key Features

- **Automatic Authentication**: No need to manually generate or manage tokens
- **Secure by Default**: Automatically enforces SSL connections
- **Token Auto-Renewal**: Handles token expiration transparently
- **Standard psql Interface**: All familiar psql commands and features work

### How It Works

When you connect with `pdsql`:

1. **SSL Required**: Automatically enforces secure connections
2. **Token Generation**: Generates temporary AWS authentication tokens automatically
3. **Admin Privileges**: When connecting as `admin` user, full admin privileges are granted
4. **Auto-Renewal**: New tokens are generated for each connection attempt
5. **Short-Lived Tokens**: Tokens expire after 5 seconds for enhanced security

## 🔐 AWS Credentials Setup

`pdsql` uses your existing AWS credentials. Ensure you have credentials configured through one of these methods:

### AWS CLI (Recommended)
```bash
aws configure
```

### Environment Variables
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_REGION=us-east-1  # Optional
```

### AWS Credentials File
Create `~/.aws/credentials`:
```ini
[default]
aws_access_key_id = your_access_key
aws_secret_access_key = your_secret_key
```

### IAM Roles (EC2/ECS/Lambda)
If running on AWS infrastructure, `pdsql` will automatically use IAM roles.

## 📋 Examples

### Interactive Session
```bash
# Start an interactive session
pdsql --host=workgroup.123456789012.us-east-1.dsql.amazonaws.com --user=admin

# Once connected, you can run SQL commands:
postgres=> \l
postgres=> CREATE TABLE users (id serial, name text);
postgres=> INSERT INTO users (name) VALUES ('Alice');
postgres=> SELECT * FROM users;
```

### One-liner Queries
```bash
# Execute a single query
pdsql --host=your-endpoint.dsql.amazonaws.com --user=admin -c "SELECT version();"

# Execute SQL from a file
pdsql --host=your-endpoint.dsql.amazonaws.com --user=admin -f queries.sql
```

### Connection with Options
```bash
# Connect with specific database and additional options
pdsql --host=your-endpoint.dsql.amazonaws.com \
      --user=admin \
      --port=5432 \
      --dbname=postgres \
      --echo-queries \
      --no-password
```

## 🆘 Troubleshooting

### Connection Issues

**Error: "could not connect to server"**
- Verify your DSQL endpoint URL is correct
- Ensure your security group allows connections on port 5432
- Check that your AWS credentials are properly configured

### Authentication Issues

**Error: "authentication failed"**
- Verify your AWS credentials have the necessary DSQL permissions
- Ensure you're connecting to the correct DSQL workgroup
- Check that your IAM user/role has `dsql:DbConnect` permissions

### AWS Credentials

**Error: "Unable to locate credentials"**
- Run `aws configure` to set up credentials
- Or set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables
- Verify your credentials work: `aws sts get-caller-identity`

## 🔍 Debug Logging

For troubleshooting authentication and connection issues, enable detailed AWS SDK logging:

### Environment Variables

- **`AWS_LOG_LEVEL`**: Controls verbosity (NONE, FATAL, ERROR, WARN, INFO, DEBUG, TRACE)
- **`AWS_LOG_FILE`**: Controls output destination (stdout, stderr, or file path)

### Basic Debugging

Enable debug logging to stderr (default):
```bash
AWS_LOG_LEVEL=DEBUG pdsql --host=your-endpoint.dsql.amazonaws.com --user=admin
```

### Detailed Tracing

Enable maximum verbosity for deep debugging:
```bash
AWS_LOG_LEVEL=TRACE pdsql --host=your-endpoint.dsql.amazonaws.com --user=admin
```

### Log to File

Save logs to a file for analysis:
```bash
AWS_LOG_LEVEL=DEBUG AWS_LOG_FILE=/tmp/dsql-debug.log pdsql --host=your-endpoint.dsql.amazonaws.com --user=admin
```

### Log to stdout

Send logs to stdout (useful for piping):
```bash
AWS_LOG_LEVEL=INFO AWS_LOG_FILE=stdout pdsql --host=your-endpoint.dsql.amazonaws.com --user=admin
```

### What the Logs Show

The debug logs will reveal:
- **Token Generation**: Process of creating DSQL authentication tokens
- **AWS Region Detection**: How the region is determined from hostname or environment
- **Credentials Provider Chain**: Which credential sources are tried (environment, files, IAM roles, IMDS)
- **HTTP Infrastructure**: Event loops and network setup for IMDS on EC2
- **Error Details**: Specific AWS SDK errors with error codes

### Example Log Output

```
[INFO] [2025-06-28T03:33:55Z] Starting DSQL token generation for endpoint: your-endpoint.dsql.amazonaws.com
[DEBUG] [2025-06-28T03:33:55Z] Using AWS_REGION from environment: us-west-2
[DEBUG] [2025-06-28T03:33:55Z] Creating credentials provider chain with bootstrap for IMDS
[INFO] [2025-06-28T03:33:55Z] Token generation successful
```

### Disable Logging

To disable all logging:
```bash
AWS_LOG_LEVEL=NONE pdsql --host=your-endpoint.dsql.amazonaws.com --user=admin
```

### Getting Help

For additional help:
```bash
pdsql --help
```

## 🔄 Updates

To update to the latest version, simply run the installation command again:

```bash
curl -sSL https://raw.githubusercontent.com/marcbowes/postgres/refs/heads/master/scripts/install.sh | sh
```

## 🏗️ Building from Source

If you need to build from source or contribute to development, see our [Development Guide](README_PACKAGING.md) for detailed build instructions.

### Quick Build

```bash
git clone https://github.com/marcbowes/postgres.git
cd postgres
git submodule update --init --recursive
./scripts/build-dsql.sh
```

## 📄 License

This project is based on PostgreSQL and maintains compatibility with the PostgreSQL license.

## 🤝 Contributing

Contributions are welcome! Please see our contributing guidelines and feel free to submit issues or pull requests.

---

**Note**: This tool is specifically designed for AWS DSQL connections. For regular PostgreSQL connections, use the standard `psql` client.
