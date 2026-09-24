#!/usr/bin/env bash
# ==============================================================================
# setup_claude_deepseek.sh
# 
# Backup existing Claude Desktop configuration and configure / enable
# DeepSeek V4.1 Flash (Modal Endpoint) via Claude Desktop's 3rd-Party Gateway.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration Values
# ------------------------------------------------------------------------------
BACKUP_ROOT="$HOME/.claude_desktop_backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CURRENT_BACKUP_DIR="$BACKUP_ROOT/backup_$TIMESTAMP"

CLAUDE_DIR="$HOME/Library/Application Support/Claude"
CLAUDE_3P_DIR="$HOME/Library/Application Support/Claude-3p"

MODAL_BASE_URL="https://imfreak695--ep-deepseek-v4-1-flash-server.us-west.modal.direct"
MODAL_API_KEY="${MODAL_API_KEY:-}"
PROFILE_ID="00000000-0000-4000-8000-000000000001"
PROFILE_NAME="DeepSeek Flash (Modal)"
MODEL_ID="claude-3-7-sonnet"
MODEL_LABEL="deepseek-v4-1-flash"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ------------------------------------------------------------------------------
# 1. Backup Function
# ------------------------------------------------------------------------------
create_backup() {
    log_info "Creating backup of current Claude configurations..."
    mkdir -p "$CURRENT_BACKUP_DIR"

    local backed_up=0

    if [ -d "$CLAUDE_DIR" ]; then
        mkdir -p "$CURRENT_BACKUP_DIR/Claude"
        if [ -f "$CLAUDE_DIR/claude_desktop_config.json" ]; then
            cp "$CLAUDE_DIR/claude_desktop_config.json" "$CURRENT_BACKUP_DIR/Claude/"
            backed_up=1
        fi
        if [ -d "$CLAUDE_DIR/configLibrary" ]; then
            cp -R "$CLAUDE_DIR/configLibrary" "$CURRENT_BACKUP_DIR/Claude/"
            backed_up=1
        fi
    fi

    if [ -d "$CLAUDE_3P_DIR" ]; then
        mkdir -p "$CURRENT_BACKUP_DIR/Claude-3p"
        if [ -f "$CLAUDE_3P_DIR/claude_desktop_config.json" ]; then
            cp "$CLAUDE_3P_DIR/claude_desktop_config.json" "$CURRENT_BACKUP_DIR/Claude-3p/"
            backed_up=1
        fi
        if [ -d "$CLAUDE_3P_DIR/configLibrary" ]; then
            cp -R "$CLAUDE_3P_DIR/configLibrary" "$CURRENT_BACKUP_DIR/Claude-3p/"
            backed_up=1
        fi
    fi

    if [ "$backed_up" -eq 1 ]; then
        log_success "Backup saved to: $CURRENT_BACKUP_DIR"
    else
        log_warn "No existing configuration files found to back up."
    fi
}

# ------------------------------------------------------------------------------
# 2. List Backups
# ------------------------------------------------------------------------------
list_backups() {
    echo -e "${BLUE}=== Available Claude Desktop Backups ===${NC}"
    if [ ! -d "$BACKUP_ROOT" ] || [ -z "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
        echo "No backups found in $BACKUP_ROOT."
        return
    fi

    for d in "$BACKUP_ROOT"/backup_*; do
        if [ -d "$d" ]; then
            echo -e "  - $(basename "$d") (${d})"
        fi
    done
}

# ------------------------------------------------------------------------------
# 3. Restore Function
# ------------------------------------------------------------------------------
restore_backup() {
    local target_dir="${1:-}"

    if [ -z "$target_dir" ]; then
        # Pick the latest backup
        target_dir=$(find "$BACKUP_ROOT" -maxdepth 1 -name "backup_*" 2>/dev/null | sort -r | head -n 1)
        if [ -z "$target_dir" ]; then
            log_error "No backups found to restore."
            exit 1
        fi
    elif [ ! -d "$target_dir" ] && [ -d "$BACKUP_ROOT/$target_dir" ]; then
        target_dir="$BACKUP_ROOT/$target_dir"
    fi

    if [ ! -d "$target_dir" ]; then
        log_error "Backup directory not found: $target_dir"
        exit 1
    fi

    log_info "Restoring configuration from: $target_dir"

    if [ -d "$target_dir/Claude" ]; then
        mkdir -p "$CLAUDE_DIR"
        if [ -f "$target_dir/Claude/claude_desktop_config.json" ]; then
            cp "$target_dir/Claude/claude_desktop_config.json" "$CLAUDE_DIR/"
        fi
        if [ -d "$target_dir/Claude/configLibrary" ]; then
            rm -rf "$CLAUDE_DIR/configLibrary"
            cp -R "$target_dir/Claude/configLibrary" "$CLAUDE_DIR/"
        fi
    fi

    if [ -d "$target_dir/Claude-3p" ]; then
        mkdir -p "$CLAUDE_3P_DIR"
        if [ -f "$target_dir/Claude-3p/claude_desktop_config.json" ]; then
            cp "$target_dir/Claude-3p/claude_desktop_config.json" "$CLAUDE_3P_DIR/"
        fi
        if [ -d "$target_dir/Claude-3p/configLibrary" ]; then
            rm -rf "$CLAUDE_3P_DIR/configLibrary"
            cp -R "$target_dir/Claude-3p/configLibrary" "$CLAUDE_3P_DIR/"
        fi
    fi

    log_success "Restoration complete! Please restart Claude Desktop."
}

# ------------------------------------------------------------------------------
# 4. Apply DeepSeek Settings Function
# ------------------------------------------------------------------------------
apply_settings_to_dir() {
    local target_base="$1"
    local config_lib="$target_base/configLibrary"
    local desktop_cfg="$target_base/claude_desktop_config.json"

    mkdir -p "$config_lib"

    # 1. Update or create claude_desktop_config.json to enable 3p deploymentMode
    if [ -f "$desktop_cfg" ]; then
        python3 -c '
import json, sys
cfg_path = sys.argv[1]
try:
    with open(cfg_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}
data["deploymentMode"] = "3p"
with open(cfg_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
' "$desktop_cfg"
    else
        echo '{"deploymentMode": "3p"}' > "$desktop_cfg"
    fi

    # 2. Write DeepSeek Gateway Profile JSON
    cat <<EOF > "$config_lib/${PROFILE_ID}.json"
{
  "inferenceGatewayBaseUrl": "${MODAL_BASE_URL}",
  "inferenceGatewayApiKey": "${MODAL_API_KEY}",
  "inferenceGatewayAuthScheme": "bearer",
  "modelDiscoveryEnabled": false,
  "modelPrefer1mContext": false,
  "inferenceModels": [
    {
      "name": "${MODEL_ID}",
      "labelOverride": "${MODEL_LABEL}",
      "supports1m": false
    }
  ],
  "defaultModelEffort": "max",
  "coworkEgressAllowedHosts": [
    "*"
  ],
  "disableDeploymentModeChooser": true,
  "inferenceProvider": "gateway",
  "inferenceCredentialKind": "static"
}
EOF

    # 3. Update _meta.json safely without removing other profiles
    local meta_path="$config_lib/_meta.json"
    python3 -c '
import json, sys, os

meta_path = sys.argv[1]
profile_id = sys.argv[2]
profile_name = sys.argv[3]

meta = {"appliedId": profile_id, "entries": []}
if os.path.exists(meta_path):
    try:
        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
    except Exception:
        meta = {"appliedId": profile_id, "entries": []}

meta["appliedId"] = profile_id
entries = meta.get("entries", [])

# Check if entry already exists, update name; otherwise add to beginning
found = False
for entry in entries:
    if entry.get("id") == profile_id:
        entry["name"] = profile_name
        found = True
        break

if not found:
    entries.insert(0, {"id": profile_id, "name": profile_name})

meta["entries"] = entries

with open(meta_path, "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=2)
' "$meta_path" "$PROFILE_ID" "$PROFILE_NAME"

    log_success "Applied settings to: $target_base"
}

apply_deepseek_settings() {
    log_info "Configuring Claude Desktop for DeepSeek V4.1 Flash..."

    # Apply to standard Claude directory
    apply_settings_to_dir "$CLAUDE_DIR"

    # Apply to Claude-3p directory (used when 3p mode is engaged)
    apply_settings_to_dir "$CLAUDE_3P_DIR"

    echo ""
    log_success "Configuration complete!"
    echo -e "  • Gateway Endpoint : ${BLUE}${MODAL_BASE_URL}${NC}"
    echo -e "  • Wire Model ID    : ${BLUE}${MODEL_ID}${NC}"
    echo -e "  • UI Display Name  : ${GREEN}${MODEL_LABEL}${NC}"
    echo -e "  • Auth Scheme      : ${BLUE}Bearer (Authorization Header)${NC}"
    echo -e "  • Active Profile   : ${GREEN}${PROFILE_NAME}${NC}"
}

# ------------------------------------------------------------------------------
# 5. Restart Claude Desktop Helper
# ------------------------------------------------------------------------------
restart_claude() {
    log_info "Restarting Claude Desktop..."
    if pgrep -i "Claude" > /dev/null 2>&1; then
        killall "Claude" 2>/dev/null || true
        sleep 2
    fi
    open -a "Claude" 2>/dev/null || open -a "/Applications/Claude.app" 2>/dev/null || log_warn "Could not launch Claude Desktop automatically. Please open it manually."
    log_success "Claude Desktop launched."
}

# ------------------------------------------------------------------------------
# Main Dispatcher
# ------------------------------------------------------------------------------
main() {
    case "${1:-enable}" in
        enable|apply)
            create_backup
            apply_deepseek_settings
            if [[ "${2:-}" == "--restart" ]] || [[ "${2:-}" == "-r" ]]; then
                restart_claude
            else
                echo ""
                echo -e "${YELLOW}Tip:${NC} Run with '${GREEN}./setup_claude_deepseek.sh enable --restart${NC}' to automatically relaunch Claude Desktop."
            fi
            ;;
        backup)
            create_backup
            ;;
        restore)
            restore_backup "${2:-}"
            if [[ "${3:-}" == "--restart" ]] || [[ "${3:-}" == "-r" ]]; then
                restart_claude
            fi
            ;;
        list)
            list_backups
            ;;
        restart)
            restart_claude
            ;;
        help|--help|-h)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  enable [--restart]   Back up current settings and enable DeepSeek settings (Default)"
            echo "  backup               Create a timestamped backup of current Claude configurations"
            echo "  restore [backup_dir] Restore configuration from latest or specified backup"
            echo "  list                 List all stored backups"
            echo "  restart              Close and relaunch Claude Desktop"
            echo "  help                 Show this help message"
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use '$0 help' for usage instructions."
            exit 1
            ;;
    esac
}

main "$@"
