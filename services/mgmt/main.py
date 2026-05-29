import subprocess
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import docker
import psutil

app = FastAPI(title="F5-TTS Management API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

MANAGED = ["f5tts-api", "f5tts-infer", "f5tts-train", "f5tts-tensorboard", "f5tts-dashboard", "f5tts-mgmt"]

LABELS = {
    "f5tts-api":         {"label": "API",         "icon": "🔌"},
    "f5tts-infer":       {"label": "Inference",   "icon": "🎙️"},
    "f5tts-train":       {"label": "Fine-tune",   "icon": "🎓"},
    "f5tts-tensorboard": {"label": "TensorBoard", "icon": "📊"},
    "f5tts-dashboard":   {"label": "Dashboard",   "icon": "🏠"},
    "f5tts-mgmt":        {"label": "Management",  "icon": "⚙️"},
}


def client():
    return docker.from_env()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/status")
def get_status():
    c = client()
    result = []
    for name in MANAGED:
        meta = LABELS.get(name, {"label": name, "icon": "📦"})
        try:
            ct = c.containers.get(name)
            health = "none"
            state = ct.attrs.get("State", {})
            if state.get("Health"):
                health = state["Health"]["Status"]
            result.append({
                "name": name,
                "label": meta["label"],
                "icon": meta["icon"],
                "status": ct.status,
                "health": health,
            })
        except docker.errors.NotFound:
            result.append({"name": name, "label": meta["label"], "icon": meta["icon"], "status": "not_found", "health": "none"})
        except Exception as e:
            result.append({"name": name, "label": meta["label"], "icon": meta["icon"], "status": "error", "health": str(e)})
    return result


@app.post("/restart/{name}")
def restart(name: str):
    if name not in MANAGED:
        raise HTTPException(400, f"Unknown container: {name}")
    try:
        ct = client().containers.get(name)
        ct.restart(timeout=15)
        return {"ok": True, "name": name}
    except docker.errors.NotFound:
        raise HTTPException(404, f"Container {name} not found")
    except Exception as e:
        raise HTTPException(500, str(e))


@app.get("/logs/{name}")
def logs(name: str, lines: int = 150):
    if name not in MANAGED:
        raise HTTPException(400, f"Unknown container: {name}")
    try:
        ct = client().containers.get(name)
        raw = ct.logs(tail=lines, timestamps=False).decode("utf-8", errors="replace")
        return {"name": name, "logs": raw}
    except docker.errors.NotFound:
        raise HTTPException(404, f"Container {name} not found")
    except Exception as e:
        raise HTTPException(500, str(e))


@app.get("/system")
def system():
    info = {}

    # GPU via nvidia-smi
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total,memory.used,utilization.gpu", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0:
            info["gpu"] = []
            for line in r.stdout.strip().splitlines():
                p = [x.strip() for x in line.split(",")]
                if len(p) == 4:
                    info["gpu"].append({"name": p[0], "mem_total_mb": p[1], "mem_used_mb": p[2], "util_pct": p[3]})
    except Exception:
        info["gpu"] = []

    # RAM
    mem = psutil.virtual_memory()
    info["ram"] = {
        "total_gb": round(mem.total / 1e9, 1),
        "used_gb":  round(mem.used  / 1e9, 1),
        "pct":      mem.percent,
    }

    # Disk for /data
    try:
        disk = psutil.disk_usage("/data")
        info["disk"] = {
            "total_gb": round(disk.total / 1e9, 1),
            "used_gb":  round(disk.used  / 1e9, 1),
            "free_gb":  round(disk.free  / 1e9, 1),
            "pct":      disk.percent,
        }
    except Exception:
        info["disk"] = {}

    return info
