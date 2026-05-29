#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*"; exit 1; }
info() { echo -e "${BLUE}▸${NC} $*"; }
ask()  { read -p "  $1" "$2"; }
asks() { read -s -p "  $1" "$2"; echo; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BOLD}"
cat << 'BANNER'
╔══════════════════════════════════════════════╗
║          F5-TTS Engine  —  Installer         ║
║    Easy-deploy voice AI training platform    ║
╚══════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# ── 1. Dependencies ──────────────────────────────────────────────
echo -e "${BOLD}[1/6] Checking dependencies…${NC}"
command -v docker &>/dev/null     || err "Docker not found. Install: https://docs.docker.com/get-docker/"
docker info &>/dev/null 2>&1      || err "Docker daemon not running. Run: sudo systemctl start docker"
docker compose version &>/dev/null || err "Docker Compose plugin not found"
command -v git &>/dev/null        || err "Git not found: sudo apt-get install git"
ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?')"
ok "Docker Compose $(docker compose version --short 2>/dev/null || echo '?')"
ok "Git $(git --version | awk '{print $3}')"

# ── 2. Configuration ─────────────────────────────────────────────
echo -e "\n${BOLD}[2/6] Configuration${NC}"

ask "Data directory for models, datasets, outputs [/opt/f5tts-data]: " DATA_DIR
DATA_DIR="${DATA_DIR:-/opt/f5tts-data}"

DETECTED_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
ask "Host IP or hostname [$DETECTED_IP]: " HOST_IP
HOST_IP="${HOST_IP:-$DETECTED_IP}"

ask "Web interface port [80]: " DASHBOARD_PORT
DASHBOARD_PORT="${DASHBOARD_PORT:-80}"

ask "API port (also accessible directly) [8301]: " API_PORT
API_PORT="${API_PORT:-8301}"

ask "Admin username [admin]: " ADMIN_USER
ADMIN_USER="${ADMIN_USER:-admin}"

ADMIN_PASS=""
while true; do
  asks "Admin password: " ADMIN_PASS
  asks "Confirm password: " ADMIN_PASS2
  [[ "$ADMIN_PASS" == "$ADMIN_PASS2" ]] && break
  warn "Passwords don't match, try again."
done

ask "Voice label name (shown in API) [voice]: " VOICE_NAME
VOICE_NAME="${VOICE_NAME:-voice}"

# ── 3. GPU ───────────────────────────────────────────────────────
echo -e "\n${BOLD}[3/6] GPU Configuration${NC}"
GPU_ENABLED=false

if command -v nvidia-smi &>/dev/null; then
  GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1 || true)
  if [[ -n "$GPU_INFO" ]]; then
    ok "NVIDIA GPU detected: $GPU_INFO"
    ask "Use GPU for inference/training? [Y/n]: " USE_GPU
    USE_GPU="${USE_GPU:-Y}"
    if [[ "$USE_GPU" =~ ^[Yy] ]]; then
      GPU_ENABLED=true
      info "Testing GPU passthrough to Docker…"
      if docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi &>/dev/null 2>&1; then
        ok "GPU Docker passthrough works"
      else
        warn "nvidia-container-toolkit may not be installed."
        warn "Install: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
        ask "Continue without verified GPU passthrough? [y/N]: " CNT
        [[ "${CNT:-N}" =~ ^[Yy] ]] || exit 1
      fi
    fi
  fi
else
  warn "No NVIDIA GPU detected — running in CPU mode (inference will be slow)"
fi

# ── 4. Reference audio ───────────────────────────────────────────
echo -e "\n${BOLD}[4/6] Reference Audio${NC}"
info "The reference audio is a 10–30 second sample of the voice to clone."
info "You can skip this and add it later by editing .env"

ask "Path to reference audio WAV [skip]: " REF_AUDIO_SRC
REF_AUDIO="" REF_TEXT=""
if [[ -n "$REF_AUDIO_SRC" && -f "$REF_AUDIO_SRC" ]]; then
  mkdir -p "$DATA_DIR/refs"
  cp "$REF_AUDIO_SRC" "$DATA_DIR/refs/ref_audio.wav"
  REF_AUDIO="/data/refs/ref_audio.wav"
  ok "Reference audio copied"
  ask "Transcript of the reference audio (what is said in it): " REF_TEXT
else
  warn "Skipped — set REF_AUDIO and REF_TEXT in .env before using the API"
fi

# ── 5. Base model download ───────────────────────────────────────
echo -e "\n${BOLD}[5/6] Base Model${NC}"
MODEL_PATH="" VOCAB_FILE=""

ask "Download F5TTS_v1_Base model from HuggingFace? (~1.3 GB) [Y/n]: " DL_MODEL
DL_MODEL="${DL_MODEL:-Y}"
if [[ "$DL_MODEL" =~ ^[Yy] ]]; then
  mkdir -p "$DATA_DIR/models/base"
  info "Downloading from HuggingFace (SWivid/F5-TTS)…"
  python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='SWivid/F5-TTS',
    local_dir='$DATA_DIR/models/base',
    allow_patterns=['F5TTS_v1_Base/*','vocab.txt'],
    ignore_patterns=['*.index.json']
)
print('OK')
" 2>&1 | tail -5 || {
    warn "huggingface_hub not found — installing…"
    pip3 install huggingface_hub -q
    python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='SWivid/F5-TTS',
    local_dir='$DATA_DIR/models/base',
    allow_patterns=['F5TTS_v1_Base/*','vocab.txt'],
    ignore_patterns=['*.index.json']
)
print('OK')
"
  }
  ok "Base model downloaded to $DATA_DIR/models/base"
  MODEL_PATH="/data/models/base/F5TTS_v1_Base/model_1250000.safetensors"
  VOCAB_FILE="/data/models/base/vocab.txt"
else
  warn "Skipped — set MODEL_PATH in .env when you have a model"
fi

# Create data directories
mkdir -p "$DATA_DIR"/{models,datasets,outputs,refs,runs,checkpoints}
ok "Data directories created at $DATA_DIR"

# ── Generate .env ────────────────────────────────────────────────
if [[ "$GPU_ENABLED" == "true" ]]; then
  COMPOSE_FILE="docker-compose.yml:docker-compose.gpu.yml"
else
  COMPOSE_FILE="docker-compose.yml"
fi

cat > "$DIR/.env" << EOF
# F5-TTS Engine — generated by install.sh
DATA_DIR=$DATA_DIR
HOST_IP=$HOST_IP
DASHBOARD_PORT=$DASHBOARD_PORT
API_PORT=$API_PORT
VOICE_NAME=$VOICE_NAME
MODEL_PATH=$MODEL_PATH
REF_AUDIO=$REF_AUDIO
REF_TEXT=$REF_TEXT
VOCAB_FILE=$VOCAB_FILE
ADMIN_USER=$ADMIN_USER
GPU_ENABLED=$GPU_ENABLED
COMPOSE_FILE=$COMPOSE_FILE
EOF
ok ".env generated"

# ── Generate .htpasswd ───────────────────────────────────────────
if command -v htpasswd &>/dev/null; then
  htpasswd -bc "$DIR/.htpasswd" "$ADMIN_USER" "$ADMIN_PASS"
elif command -v openssl &>/dev/null; then
  echo "$ADMIN_USER:$(openssl passwd -apr1 "$ADMIN_PASS")" > "$DIR/.htpasswd"
else
  apt-get install -y apache2-utils -qq && htpasswd -bc "$DIR/.htpasswd" "$ADMIN_USER" "$ADMIN_PASS"
fi
ok ".htpasswd generated"

# ── 6. Build & start ─────────────────────────────────────────────
echo -e "\n${BOLD}[6/6] Building Docker images…${NC}"
info "First build takes 15–30 minutes (downloading PyTorch + F5-TTS). Grab a coffee ☕"
echo

cd "$DIR"
docker compose build 2>&1 | grep -E '^(Step|#|ERROR|Successfully)' | head -50 || docker compose build

ok "Images built"
info "Starting all services…"
docker compose up -d
sleep 5
docker compose ps

echo -e "\n${BOLD}${GREEN}"
cat << DONE
╔══════════════════════════════════════════════╗
║          Installation Complete! 🎉           ║
╚══════════════════════════════════════════════╝
DONE
echo -e "${NC}"
echo -e "  Dashboard:   ${BLUE}http://${HOST_IP}:${DASHBOARD_PORT}${NC}"
echo -e "  API direct:  ${BLUE}http://${HOST_IP}:${API_PORT}/voice/tts${NC}"
echo -e "  Username:    ${BOLD}${ADMIN_USER}${NC}"
echo ""
echo "  Useful commands:"
echo "    ./start.sh              — start all services"
echo "    ./stop.sh               — stop all services"
echo "    docker compose logs -f  — stream all logs"
echo "    ./uninstall.sh          — remove everything"
echo ""
echo "  Next step: open the dashboard, go to Fine-tune, and train your voice!"
