#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG ----
GH_OWNER="exajoin"
GH_REPO="ep"
GH_API="https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents"

# ---- AUTH ----
read -s -p "GitHub Token (for private repo): " GITHUB_TOKEN
echo

auth_header="Authorization: token $GITHUB_TOKEN"

# ---- OPTIONAL TOKENS ----
read -s -p "AZDO PAT (optional): " AZDO_PAT; echo
read -s -p "Terraform Token (optional): " TF_TOKEN; echo
read -s -p "AWS Access Key (optional): " AWS_ACCESS_KEY_ID; echo
read -s -p "AWS Secret Key (optional): " AWS_SECRET_ACCESS_KEY; echo

export AZDO_PAT TF_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

# ---- WORKSPACE ----
read -p "Workspace name: " WORKSPACE
export USEP_WORKSPACE="$WORKSPACE"

# ---- HELPERS ----
_fetch_file() {
  local path="$1"
  curl -s -H "$auth_header" \
    "$GH_API/$path" | grep '"content"' | cut -d '"' -f4 | base64 -d
}

# ---- CREATE WORKSPACE IF NOT EXISTS ----
_create_workspace() {
  local path="backlog/$WORKSPACE/.init"
  local content=$(echo "init" | base64)

  curl -s -X PUT \
    -H "$auth_header" \
    -d "{\"message\":\"init workspace $WORKSPACE\",\"content\":\"$content\"}" \
    "https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents/$path" \
    >/dev/null 2>&1 || true
}

_create_workspace

# ---- DISPATCHER ----
_usep() {
  local domain="$1"; shift

  case "$domain" in
    azdo|tfdo|awdo)
      local script="$domain.sh"
      _fetch_file "script/$script" | bash -s -- "$@"
      ;;
    run)
      local tool="$1"; shift
      _fetch_file "toolkit/$tool.sh" | source /dev/stdin
      ;;
    exit)
      _usep_exit
      ;;
    *)
      echo "Unknown domain: $domain"
      ;;
  esac
}

# ---- HISTORY UPLOAD ----
_usep_upload_history() {
  local file="/tmp/usep_history_$(date +%s).log"
  history > "$file"

  local content=$(base64 < "$file" | tr -d '\n')

  curl -s -X PUT \
    -H "$auth_header" \
    -d "{\"message\":\"history upload\",\"content\":\"$content\"}" \
    "https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents/backlog/$WORKSPACE/history_$(date +%s).log" \
    >/dev/null
}

# ---- CLEANUP ----
_usep_cleanup() {
  unset AZDO_PAT TF_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  unset -f _usep _fetch_file _usep_exit _usep_cleanup _usep_upload_history
}

# ---- EXIT ----
_usep_exit() {
  echo "Uploading history..."
  _usep_upload_history

  echo "Cleaning up..."
  _usep_cleanup

  echo "Session terminated."
}

echo "✅ USEP session initialized"
echo "Use: _usep <domain> <command>"
