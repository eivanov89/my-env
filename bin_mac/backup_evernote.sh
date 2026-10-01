#!/bin/bash

# Launchd uses a minimal environment; set a stable PATH explicitly.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Exit on error, undefined variables, and pipe failures
set -Eeuo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log with timestamp prefix
log() {
    local message="${1:-}"
    printf '%s %b\n' "$(date '+%Y-%m-%d %H:%M')" "$message"
}

# Error handler
error_exit() {
    local error_msg="${1:-Command failed: ${BASH_COMMAND:-unknown}}"
    local exit_code="${2:-1}"

    # Prevent ERR trap recursion while handling a failure.
    trap - ERR
    log "${RED}Error: ${error_msg}${NC}" >&2

    /usr/bin/osascript -e \
      'display notification "Evernote backup FAILED" with title "Backup error"' || true

    exit "$exit_code"
}

# Trap ERR to catch any unhandled errors
trap 'error_exit' ERR

# Check if required directories exist
DOCUMENTS_DIR="/Users/eivanov89/Documents"
BACKUP_DIR="/Users/eivanov89/repos/evernote-backup"
EVERNOTE_BACKUP="/opt/homebrew/bin/evernote-backup"
GIT_BIN="/usr/bin/git"

if [[ ! -d "$DOCUMENTS_DIR" ]]; then
    error_exit "Documents directory not found: $DOCUMENTS_DIR" 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    error_exit "Backup directory not found: $BACKUP_DIR" 1
fi

# Check if evernote-backup command exists
if ! command -v "$EVERNOTE_BACKUP" &> /dev/null; then
    error_exit "$EVERNOTE_BACKUP command not found. Please install it first." 1
fi

# Check if git is available
if [[ ! -x "$GIT_BIN" ]]; then
    error_exit "git command not found at $GIT_BIN. Please install git first." 1
fi

log "${GREEN}Starting Evernote backup...${NC}"

# Change to Documents directory
cd "$DOCUMENTS_DIR" || error_exit "Failed to change to Documents directory" 1

# Sync Evernote
log "${YELLOW}Syncing Evernote...${NC}"
$EVERNOTE_BACKUP sync || error_exit "Failed to sync Evernote" 1

# Export notes
log "${YELLOW}Exporting notes...${NC}"
$EVERNOTE_BACKUP export --overwrite --single-notes "$BACKUP_DIR" || error_exit "Failed to export notes" 1

# Change to backup directory
cd "$BACKUP_DIR" || error_exit "Failed to change to backup directory" 1

# Check if there are any changes to commit
if ! "$GIT_BIN" diff --quiet || ! "$GIT_BIN" diff --cached --quiet || [[ -n "$("$GIT_BIN" ls-files --others --exclude-standard)" ]]; then
    log "${YELLOW}Staging changes...${NC}"
    "$GIT_BIN" add . || error_exit "Failed to stage changes" 1

    log "${YELLOW}Committing changes...${NC}"
    "$GIT_BIN" commit -m "backup $(date '+%Y-%m-%d %H:%M:%S')" || error_exit "Failed to commit changes" 1

    log "${YELLOW}Pushing to remote...${NC}"
    "$GIT_BIN" push || error_exit "Failed to push to remote" 1
    log "${GREEN}Backup completed and pushed successfully!${NC}"
else
    log "${GREEN}No changes to commit. Backup is up to date.${NC}"
fi

exit 0
