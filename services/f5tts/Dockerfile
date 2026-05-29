FROM python:3.10-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/opt/f5-tts/src

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg libsndfile1 sox curl wget build-essential \
    && rm -rf /var/lib/apt/lists/*

# Pin torch versions BEFORE F5-TTS install so it can't overwrite them
RUN printf "torch==2.3.0\ntorchaudio==2.3.0\n" > /tmp/constraints.txt

# Install torch + torchaudio (cu121 wheel works on CPU too — CUDA just stays inactive)
RUN pip3 install \
    torch==2.3.0 \
    torchaudio==2.3.0 \
    --index-url https://download.pytorch.org/whl/cu121

# Clone F5-TTS and install all deps, constrained to keep our torch versions
RUN git clone https://github.com/SWivid/F5-TTS.git /opt/f5-tts && \
    cd /opt/f5-tts && \
    pip3 install ".[train]" -c /tmp/constraints.txt

# API service deps + tensorboard (not always pulled by F5-TTS [train])
RUN pip3 install fastapi "uvicorn[standard]" huggingface_hub tensorboard

COPY api/main.py /opt/f5tts-api/main.py

WORKDIR /data
