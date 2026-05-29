FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/opt/f5-tts/src

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3-pip \
    git ffmpeg libsndfile1 sox curl wget build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.10 /usr/bin/python3 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python

# Install PyTorch + torchaudio with locked matching versions (CUDA 12.1)
RUN pip3 install --no-cache-dir \
    torch==2.3.0 \
    torchaudio==2.3.0 \
    --index-url https://download.pytorch.org/whl/cu121

# Clone F5-TTS from source
RUN git clone https://github.com/SWivid/F5-TTS.git /opt/f5-tts

# Install F5-TTS deps — then force-restore torch/torchaudio versions
RUN cd /opt/f5-tts && pip3 install --no-cache-dir -e ".[train]"

# Restore pinned versions in case F5-TTS deps overwrote them
RUN pip3 install --no-cache-dir --force-reinstall \
    torch==2.3.0 \
    torchaudio==2.3.0 \
    --index-url https://download.pytorch.org/whl/cu121

# API service deps
RUN pip3 install --no-cache-dir fastapi "uvicorn[standard]" huggingface_hub

COPY api/main.py /opt/f5tts-api/main.py

WORKDIR /data
