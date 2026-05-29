FROM pytorch/pytorch:2.3.0-cuda12.1-cudnn8-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/opt/f5-tts/src

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg libsndfile1 sox curl wget build-essential \
    && rm -rf /var/lib/apt/lists/*

# Clone F5-TTS from source (pinned for reproducibility)
RUN git clone https://github.com/SWivid/F5-TTS.git /opt/f5-tts

# Install F5-TTS with training support
RUN cd /opt/f5-tts && pip install -e ".[train]"

# Additional API deps
RUN pip install fastapi "uvicorn[standard]" huggingface_hub

# Copy API service into image
COPY api/main.py /opt/f5tts-api/main.py

WORKDIR /data
