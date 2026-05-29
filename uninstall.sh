#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BOLD}F5-TTS Engine — Uninstaller${NC}"
echo ""
echo -e "${YELLOW}This will:${NC}"
echo "  • Stop and remove all F5-TTS containers"
echo "  • Remove Docker images built for this engine"
echo "  • Delete .env and .htpasswd from this directory"
echo ""
echo -e "${RED}This will NOT delete your data directory (models, datasets, checkpoints).${NC}"

[[ -f "$DIR/.env" ]] && source "$DIR/.env"
DATA_DIR="${DATA_DIR:-}"
if [[ -n "$DATA_DIR" ]]; then
  echo -e "  Data at ${BOLD}$DATA_DIR${NC} will be preserved."
fi
echo ""
read -p "Continue? [y/N]: " CONFIRM
[[ "${CONFIRM:-N}" =~ ^[Yy] ]] || { echo "Aborted."; exit 0; }

cd "$DIR"

echo "Stopping services…"
docker compose down --remove-orphans 2>/dev/null || true

echo "Removing Docker images…"
docker rmi f5tts-engine-f5tts-api f5tts-engine-f5tts-infer f5tts-engine-f5tts-train \
           f5tts-engine-tensorboard f5tts-engine-dashboard f5tts-engine-mgmt \
           f5tts-engine-f5tts 2>/dev/null || true

echo "Removing config files…"
rm -f "$DIR/.env" "$DIR/.htpasswd"

echo ""
echo -e "${GREEN}✓ Uninstallation complete.${NC}"
echo "  To reinstall, run: ./install.sh"
if [[ -n "$DATA_DIR" ]]; then
  echo "  Your data is still at: $DATA_DIR"
fi
