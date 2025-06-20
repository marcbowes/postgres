#!/bin/bash
set -e

REPO="marcbowes/postgres"
INSTALL_PATH="$HOME/.local"

# Function to display error messages and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        error_exit "Unsupported operating system: $OSTYPE"
    fi
}

# Function to detect architecture
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "X64"
            ;;
        aarch64|arm64)
            echo "ARM64"
            ;;
        *)
            error_exit "Unsupported architecture: $arch"
            ;;
    esac
}

# Function to detect Linux distribution
detect_linux_distro() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "debian"
    elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# Function to install via package manager (Linux)
install_via_package() {
    local os="$1"
    local arch="$2"
    local distro="$3"
    
    echo "Attempting package manager installation..."
    
    # Get latest release information
    echo "Fetching latest release information..."
    RELEASE_INFO=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
    if [[ -z "$RELEASE_INFO" || "$RELEASE_INFO" == *"Not Found"* ]]; then
        error_exit "Could not fetch release information. Check your internet connection."
    fi
    
    TAG_NAME=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
    echo "Latest release found: $TAG_NAME"
    
    # Determine package type and download URL
    local package_type=""
    local download_url=""
    local package_file=""
    
    if [[ "$distro" == "debian" ]]; then
        package_type="deb"
        # Convert arch format for DEB (X64 -> amd64, ARM64 -> arm64)
        local deb_arch=""
        if [[ "$arch" == "X64" ]]; then
            deb_arch="amd64"
        elif [[ "$arch" == "ARM64" ]]; then
            deb_arch="arm64"
        fi
        package_file="postgres-dsql_1.0.0-1_${deb_arch}.deb"
    elif [[ "$distro" == "rhel" ]]; then
        package_type="rpm"
        # Convert arch format for RPM (X64 -> x86_64, ARM64 -> aarch64)
        local rpm_arch=""
        if [[ "$arch" == "X64" ]]; then
            rpm_arch="x86_64"
        elif [[ "$arch" == "ARM64" ]]; then
            rpm_arch="aarch64"
        fi
        package_file="postgres-dsql-1.0.0-1.${rpm_arch}.rpm"
    else
        echo "Unknown Linux distribution, falling back to ZIP installation..."
        return 1
    fi
    
    # Find download URL for the package
    download_url=$(echo "$RELEASE_INFO" | grep -o "\"browser_download_url\": *\"[^\"]*${package_file}\"" | cut -d'"' -f4)
    if [[ -z "$download_url" ]]; then
        echo "Package ${package_file} not found in release, falling back to ZIP installation..."
        return 1
    fi
    
    # Download and install package
    echo "Downloading ${package_type} package..."
    TEMP_DIR=$(mktemp -d)
    local temp_package="$TEMP_DIR/$package_file"
    curl -L "$download_url" -o "$temp_package"
    
    echo "Installing package (may require sudo password)..."
    if [[ "$package_type" == "deb" ]]; then
        if command -v apt >/dev/null 2>&1; then
            sudo apt install -y "$temp_package"
        else
            sudo dpkg -i "$temp_package"
            # Fix dependencies if needed
            sudo apt-get install -f -y 2>/dev/null || true
        fi
    elif [[ "$package_type" == "rpm" ]]; then
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y "$temp_package"
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y "$temp_package"
        else
            sudo rpm -ivh "$temp_package"
        fi
    fi
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    echo "Package installation completed successfully!"
    echo "PostgreSQL DSQL (pdsql) is now available system-wide."
    return 0
}

# Function to install via ZIP extraction
install_via_zip() {
    local os="$1"
    local arch="$2"
    
    echo "Installing via ZIP extraction..."
    
    # Get latest release information
    echo "Fetching latest release information..."
    RELEASE_INFO=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
    if [[ -z "$RELEASE_INFO" || "$RELEASE_INFO" == *"Not Found"* ]]; then
        error_exit "Could not fetch release information. Check your internet connection."
    fi
    
    TAG_NAME=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
    echo "Latest release found: $TAG_NAME"
    
    # Find appropriate ZIP file
    local zip_pattern=""
    if [[ "$os" == "macos" ]]; then
        zip_pattern="postgres-dsql-macos-latest-${arch}"
    elif [[ "$os" == "linux" ]]; then
        zip_pattern="postgres-dsql-ubuntu-22.04-${arch}"
    fi
    
    # Extract download URL for the zip file
    DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -o "\"browser_download_url\": *\"[^\"]*${zip_pattern}[^\"]*\.zip\"" | cut -d'"' -f4)
    if [[ -z "$DOWNLOAD_URL" ]]; then
        # Fallback to generic postgres-dsql.zip
        DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -o '"browser_download_url": *"[^"]*postgres-dsql.zip"' | cut -d'"' -f4)
        if [[ -z "$DOWNLOAD_URL" ]]; then
            error_exit "No compatible ZIP file found in the latest release."
        fi
    fi
    
    # Create directories if they don't exist
    mkdir -p "$INSTALL_PATH/bin"
    mkdir -p "$INSTALL_PATH/lib"
    
    # Download the release
    echo "Downloading release from $DOWNLOAD_URL..."
    TEMP_DIR=$(mktemp -d)
    curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/postgres-dsql.zip"
    
    # Extract the release
    echo "Extracting files to $INSTALL_PATH..."
    unzip -o "$TEMP_DIR/postgres-dsql.zip" -d "$TEMP_DIR"
    
    # Copy files to install location
    cp -r "$TEMP_DIR/postgres-dsql/bin/"* "$INSTALL_PATH/bin/"
    cp -r "$TEMP_DIR/postgres-dsql/lib/"* "$INSTALL_PATH/lib/"
    
    # Clean up temp files
    rm -rf "$TEMP_DIR"
    
    # Make the binary executable
    chmod +x "$INSTALL_PATH/bin/pdsql"
    
    echo "ZIP installation completed successfully!"
    echo "PostgreSQL DSQL (pdsql) installed to: $INSTALL_PATH/bin/pdsql"
    
    # Check if installation path is in PATH
    if [[ ":$PATH:" != *":$INSTALL_PATH/bin:"* ]]; then
        echo ""
        echo "NOTICE: Your PATH environment variable doesn't contain $INSTALL_PATH/bin"
        echo "To add it to your PATH, add the following line to your shell configuration file:"
        echo ""
        echo "    export PATH=\"$INSTALL_PATH/bin:\$PATH\""
        echo ""
        echo "Shell configuration files:"
        echo "  - Bash: $HOME/.bashrc or $HOME/.bash_profile"
        echo "  - Zsh: $HOME/.zshrc"
        echo "  - Fish: $HOME/.config/fish/config.fish"
        echo ""
        echo "Then, reload your shell configuration or restart your terminal."
    fi
}

# Main installation logic
main() {
    echo "PostgreSQL DSQL Universal Installer"
    echo "==================================="
    
    # Detect system information
    OS=$(detect_os)
    ARCH=$(detect_arch)
    
    echo "Detected system: $OS $ARCH"
    
    if [[ "$OS" == "linux" ]]; then
        DISTRO=$(detect_linux_distro)
        echo "Detected Linux distribution type: $DISTRO"
        
        # Try package manager installation first, fall back to ZIP if it fails
        if ! install_via_package "$OS" "$ARCH" "$DISTRO"; then
            echo "Package installation failed or unavailable, trying ZIP installation..."
            install_via_zip "$OS" "$ARCH"
        fi
    else
        # macOS - use ZIP installation
        install_via_zip "$OS" "$ARCH"
    fi
    
    echo ""
    echo "Installation completed! To verify, run:"
    echo ""
    echo "    pdsql --version"
    echo ""
    echo "For usage help, run:"
    echo ""
    echo "    pdsql --help"
    echo ""
    echo "Example DSQL connection:"
    echo ""
    echo "    pdsql --host=your-dsql-endpoint.example.com --user=admin --dbname=postgres"
}

# Run main function
main "$@"
