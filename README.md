# F5-TTS Engine

Easy-deploy voice AI training and inference platform based on [F5-TTS](https://github.com/SWivid/F5-TTS).

## What's included

| Service | URL | Purpose |
|---|---|---|
| Dashboard | `http://HOST:80` | Unified control panel |
| Inference UI | `http://HOST:80/infer/` | Generate speech (Gradio) |
| Fine-tune UI | `http://HOST:80/train/` | Train your voice model (Gradio) |
| TensorBoard | `http://HOST:80/tensorboard/` | Monitor training |
| API Console | `http://HOST:80/console.html` | Test the REST API |
| TTS API | `http://HOST:80/api/` or `http://HOST:8301` | REST API for integrations |

## Requirements

- Linux (Ubuntu 22.04+ or Debian 12+)
- Docker Engine 24+
- Docker Compose plugin
- NVIDIA GPU recommended (CPU works but is very slow for training)
- 20 GB+ disk space
- 16 GB+ RAM

## Quick Start

```bash
git clone <this-repo> f5tts-engine
cd f5tts-engine
chmod +x install.sh uninstall.sh start.sh stop.sh
./install.sh
```

The installer will ask you:
- Where to store data (models, datasets, outputs)
- Your host IP
- Admin username/password
- Whether to use GPU
- Whether to download the base model

First build takes **15–30 minutes** (downloads PyTorch + F5-TTS dependencies).

## Daily use

```bash
./start.sh      # start all services
./stop.sh       # stop all services
./uninstall.sh  # remove containers and config (data is preserved)
```

## Training your own voice

1. **Record** — 5–20 minutes of clean speech, natural pacing, clear pauses
2. **Fine-tune UI** → Prepare tab → upload audio → auto-transcribe with Whisper
3. **Fine-tune UI** → Train tab → set epochs (100–130), start training
4. **TensorBoard** → watch loss curve, stop when it plateaus
5. **Inference UI** → test checkpoints, find the best one
6. Edit `.env`: set `MODEL_PATH`, `REF_AUDIO`, `REF_TEXT` → `./start.sh`

See the **Training Guide** in the dashboard for step-by-step instructions.

## Data directory layout

```
DATA_DIR/
├── models/
│   └── base/           ← F5TTS_v1_Base (downloaded by installer)
├── datasets/           ← training datasets (created by Fine-tune UI)
├── checkpoints/        ← your trained model checkpoints
├── refs/               ← reference audio files
├── outputs/            ← generated audio files
└── runs/               ← TensorBoard log files
```

## API Quick Reference

```bash
# Generate speech
curl "http://HOST:8301/voice/tts?text=Hello+world" -o output.wav

# Health check
curl "http://HOST:8301/voice/healthz"
```

Full API docs are available in the dashboard under **API Docs**.

## Configuration

Edit `.env` to change model, reference audio, ports, etc:

```bash
MODEL_PATH=/data/checkpoints/my_voice/model_last.pt
REF_AUDIO=/data/refs/my_ref.wav
REF_TEXT=The text spoken in the reference audio.
VOCAB_FILE=/data/checkpoints/my_voice/vocab.txt
```

Then restart: `./start.sh`
