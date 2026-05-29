#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

[[ -f .env ]] || { echo "Run ./install.sh first"; exit 1; }
source .env

echo "Starting F5-TTS Engine…"
docker compose up -d
echo ""
docker compose ps
echo ""
echo "Dashboard: http://${HOST_IP:-localhost}:${DASHBOARD_PORT:-80}"
