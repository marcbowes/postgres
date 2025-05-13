#!/bin/bash
set -e

REPO="marcbowes/postgres"
DEFAULT_INSTALL_PATH="$HOME/.local"

# Function to display error messages and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    error_exit "This script is only supported on macOS systems."
fi

# Check if running on ARM architecture
if [[ "$(uname -m)" != "arm64" ]]; then
    error_exit "This script is only intended for ARM-based macOS (Apple Silicon) systems."
fi

echo "PostgreSQL DSQL ARM macOS Installer"
echo "==================================="

# Get latest release information using GitHub API
echo "Fetching latest release information..."
RELEASE_INFO=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
if [[ -z "$RELEASE_INFO" || "$RELEASE_INFO" == *"Not Found"* ]]; then
    error_exit "Could not fetch release information. Check your internet connection."
fi

# Extract download URL for the zip file
DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -o '"browser_download_url": *"[^"]*postgres-dsql.zip"' | cut -d'"' -f4)
if [[ -z "$DOWNLOAD_URL" ]]; then
    error_exit "No postgres-dsql.zip found in the latest release."
fi

TAG_NAME=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
echo "Latest release found: $TAG_NAME"

# Prompt for installation path
read -p "Enter installation path [$DEFAULT_INSTALL_PATH]: " INSTALL_PATH
INSTALL_PATH=${INSTALL_PATH:-$DEFAULT_INSTALL_PATH}

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

echo "Installation completed successfully!"
echo "PostgreSQL DSQL (pdsql) installed to: $INSTALL_PATH/bin/pdsql"

# Check if installation path is in PATH
if [[ ":$PATH:" != *":$INSTALL_PATH/bin:"* ]]; then
    echo ""
    echo "NOTICE: Your PATH environment variable doesn't contain $INSTALL_PATH/bin"
    echo "To add it to your PATH, add the following line to your $HOME/.bashrc or $HOME/.zshrc file:"
    echo ""
    echo "    export PATH=\"$INSTALL_PATH/bin:\$PATH\""
    echo ""
    echo "Then, reload your shell configuration by running:"
    echo ""
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "    source $HOME/.zshrc"
    else
        echo "    source $HOME/.bashrc"
    fi
fi

echo ""
echo "To verify installation, run:"
echo ""
echo "    pdsql --version"
echo ""
echo "If the command is not found, ensure your PATH is set correctly as described above."
