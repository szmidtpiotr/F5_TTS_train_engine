import os, io, tempfile, time
from collections import deque
from datetime import datetime
from fastapi import FastAPI, Query, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import torch

app = FastAPI(title="F5-TTS Voice Service")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

MODEL_PATH = os.environ.get("MODEL_PATH", "")
REF_AUDIO  = os.environ.get("REF_AUDIO",  "")
REF_TEXT   = os.environ.get("REF_TEXT",   "")
VOICE_NAME = os.environ.get("VOICE_NAME", "voice")
VOCAB_FILE = os.environ.get("VOCAB_FILE", "")

tts_pipeline = None
log_buffer = deque(maxlen=200)


def log(msg: str):
    ts = datetime.now().strftime("%H:%M:%S")
    entry = f"[{ts}] {msg}"
    log_buffer.append(entry)
    print(entry, flush=True)


def load_model():
    global tts_pipeline
    if tts_pipeline is not None:
        return
    log("Loading F5-TTS model...")
    from f5_tts.api import F5TTS
    device = "cuda" if torch.cuda.is_available() else "cpu"
    log(f"Device: {device}")

    kwargs = dict(model="F5TTS_v1_Base", ckpt_file=MODEL_PATH, use_ema=True, device=device)
    if VOCAB_FILE and os.path.exists(VOCAB_FILE):
        kwargs["vocab_file"] = VOCAB_FILE

    t0 = time.time()
    tts_pipeline = F5TTS(**kwargs)
    log(f"Model loaded in {time.time()-t0:.1f}s")


@app.on_event("startup")
async def startup():
    log(f"Service started. Model: {MODEL_PATH or '(default base)'}")
    if not MODEL_PATH or os.path.exists(MODEL_PATH):
        load_model()
    else:
        log(f"WARNING: MODEL_PATH not found: {MODEL_PATH}")


@app.get("/voice/healthz")
def healthz():
    return {
        "status": "ok",
        "tts_voice": VOICE_NAME,
        "tts_loaded": tts_pipeline is not None,
        "device": "cuda" if torch.cuda.is_available() else "cpu",
    }


@app.get("/voice/voices")
def voices():
    return {"voices": [VOICE_NAME]}


@app.get("/voice/logs")
def get_logs():
    return {"logs": list(log_buffer)}


@app.get("/voice/tts")
def tts(
    text: str = Query(...),
    voice: str = Query(default=None),
    speed: float = Query(default=1.0),
    nfe_step: int = Query(default=32, ge=4, le=64),
    cfg_strength: float = Query(default=2.0, ge=0.0, le=5.0),
    cross_fade_duration: float = Query(default=0.15, ge=0.0, le=1.0),
    sway_sampling_coef: float = Query(default=-1.0),
    seed: int = Query(default=-1),
):
    if not text.strip():
        raise HTTPException(400, "text is required")
    if not REF_AUDIO or not os.path.exists(REF_AUDIO):
        raise HTTPException(500, f"Reference audio not found: {REF_AUDIO}. Set REF_AUDIO in .env")

    load_model()
    log(f"Generating {len(text)} chars | nfe={nfe_step} cfg={cfg_strength} speed={speed}")

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        t0 = time.time()
        wav, sr, _ = tts_pipeline.infer(
            ref_file=REF_AUDIO,
            ref_text=REF_TEXT,
            gen_text=text,
            speed=speed,
            nfe_step=nfe_step,
            cfg_strength=cfg_strength,
            cross_fade_duration=cross_fade_duration,
            sway_sampling_coef=sway_sampling_coef,
            seed=seed,
            file_wave=tmp_path,
        )
        elapsed = time.time() - t0
        with open(tmp_path, "rb") as f:
            audio_bytes = f.read()
        log(f"Done: {elapsed:.1f}s | {len(audio_bytes)//1024} KB")
    except Exception as e:
        log(f"ERROR: {e}")
        raise HTTPException(500, str(e))
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    return StreamingResponse(
        io.BytesIO(audio_bytes),
        media_type="audio/wav",
        headers={"Content-Disposition": 'attachment; filename="tts.wav"'},
    )
