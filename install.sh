#!/usr/bin/env bash
set -euo pipefail

#
# OpenRalph Installer
#
# Checks prerequisites and installs the `openralph` command.
#

SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
CHECK_ONLY=false

if [ "${1:-}" = "--check-only" ]; then
  CHECK_ONLY=true
fi

# --- Prerequisite Checks ---
check_prereq() {
  local name="$1"
  local cmd="${2:-$1}"
  if command -v "$cmd" &>/dev/null; then
    local version
    version=$("$cmd" --version 2>&1 | head -1 || echo "unknown")
    echo "  OK: $name ($version)"
    return 0
  else
    echo "  MISSING: $name"
    return 1
  fi
}

echo "Checking prerequisites..."
missing=0
check_prereq "claude" || missing=$((missing + 1))
check_prereq "openspec" || missing=$((missing + 1))
check_prereq "gh" || missing=$((missing + 1))
check_prereq "git" || missing=$((missing + 1))
check_prereq "npx" || missing=$((missing + 1))

if [ "$missing" -gt 0 ]; then
  echo ""
  echo "ERROR: $missing prerequisite(s) missing. Install them before continuing."
  exit 1
fi

echo ""
echo "All prerequisites found."

if [ "$CHECK_ONLY" = true ]; then
  exit 0
fi

# --- Install ---
echo ""
echo "Installing openralph to $BIN_DIR..."
mkdir -p "$BIN_DIR"

# Create wrapper script that resolves its real path
cat > "$BIN_DIR/openralph" << WRAPPER
#!/usr/bin/env bash
# OpenRalph wrapper — resolves real path and execs run.sh
OPENRALPH_HOME="$SCRIPT_DIR"
exec "\$OPENRALPH_HOME/run.sh" "\$@"
WRAPPER
chmod +x "$BIN_DIR/openralph"

echo "Installed: $BIN_DIR/openralph"
echo ""
echo "Make sure $BIN_DIR is in your PATH:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
