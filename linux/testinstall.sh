#!/bin/bash

# Setting Variables
REPO_URL="https://github.com/BrockBlaze/zabbixAgent.git"
TARGET_DIR="/zabbixAgent"
SCRIPTS_DIR="/etc/zabbix/scripts"

# Cloning the repository
echo "Cloning the repository..."
git clone "$REPO_URL" "$TARGET_DIR" || { echo "Failed to clone the repository."; exit 1; }

# Ensuring the target directory exists
echo "Ensuring the target directory exists..."
mkdir -p "$SCRIPTS_DIR" || { echo "Failed to create the target directory."; exit 1; }

# Moving scripts to the target directory
echo "Moving scripts to the target directory..."
cp -r "$TARGET_DIR"/* "$SCRIPTS_DIR" || { echo "Failed to move scripts."; exit 1; }

# Setting permissions
echo "Setting permissions..."
chmod +x "$SCRIPTS_DIR"/*.sh || { echo "Failed to set permissions."; exit 1; }

echo "Installation completed successfully!"