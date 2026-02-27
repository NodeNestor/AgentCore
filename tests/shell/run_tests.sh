#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install bats-core if not present
if ! command -v bats &>/dev/null; then
    echo "Installing bats-core..."
    git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
    cd /tmp/bats-core && sudo ./install.sh /usr/local
fi

echo "Running shell tests..."
bats "$SCRIPT_DIR/shell/"*.bats
