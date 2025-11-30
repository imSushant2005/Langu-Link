# app.py
import os
import io
import uuid
import shutil
import glob
import time
import traceback
import math

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import asyncio

# XTTS
from TTS.api import TTS

# Audio & torch
import torch
import torchaudio

# Patch for PyTorch 2.6+ weight loading (keeps your existing patch)
_original_load = torch.load
def safe_load(*args, **kwargs):
    if "weights_only" not in kwargs:
        kwargs["weights_only"] = False
    return _original_load(*args, **kwargs)
torch.load = safe_load

# Prefer "soundfile" backend for torchaudio to avoid torchcodec dependency
try:
    torchaudio.set_audio_backend("soundfile")
    print("✅ Using torchaudio backend: soundfile")
except Exception as e:
    print(f"⚠️ Unable to set torchaudio backend: {e}")

# Optional libs - try to import, fallback if not installed
try:
    import soundfile as sf
except Exception:
    raise RuntimeError("soundfile must be installed: pip install soundfile")

try:
    import numpy as np
except Exception:
    raise RuntimeError("numpy must be installed: pip install numpy")

# Optional but recommended for better preprocessing
try:
    import webrtcvad
except Exception:
    webrtcvad = None
try:
    import pyloudnorm as pyln
except Exception:
    pyln = None
try:
    import resampy
except Exception:
    resampy = None
try:
    import librosa
except Exception:
    librosa = None

try:
    import noisereduce as nr
except Exception:
    nr = None

try:
    from scipy import signal
except Exception:
    signal = None

# ==============================
# FastAPI Setup
# ==============================
app = FastAPI(title="XTTS v2 Improved Clone Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==============================
# Global State
# ==============================
tts = None
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
speaker_cache = {}  # path -> (gpt_latent, speaker_latent) kept on DEVICE (fp16 on cuda)
inference_lock = asyncio.Lock()  # Prevent race conditions during inference

# ==============================
# Utility: Loudness normalization (numpy)
# ==============================
def normalize_loudness_numpy(x: np.ndarray, sr: int, target_lufs=-16.0):
    if pyln is None:
        # fallback: RMS normalization to approximate target LUFS
        rms = np.sqrt(np.mean(x**2) + 1e-12)
        current_db = 20 * np.log10(rms + 1e-12)
        gain_db = target_lufs - current_db
        factor = 10 ** (gain_db / 20.0)
        return x * factor
    meter = pyln.Meter(sr)
    loudness = meter.integrated_loudness(x)
    norm_audio = pyln.normalize.loudness(x, loudness, target_lufs)
    return norm_audio

# ==============================
# Utility: Trim silence (webrtcvad if available)
# ==============================
def trim_silence(x: np.ndarray, sr: int, aggressiveness=2):
    if webrtcvad is not None:
        # webrtcvad requires 16-bit PCM bytes and frame sizes of 10/20/30 ms
        vad = webrtcvad.Vad(aggressiveness)
        frame_ms = 30
        frame_len = int(sr * frame_ms / 1000)
        if x.ndim > 1:
            x_mono = x.mean(axis=1)
        else:
            x_mono = x
        # convert to 16-bit PCM bytes
        pcm16 = (np.clip(x_mono, -1.0, 1.0) * 32767).astype(np.int16).tobytes()
        num_frames = len(pcm16) // (frame_len * 2)
        voiced = []
        for i in range(num_frames):
            start = i * frame_len * 2
            chunk = pcm16[start:start + frame_len * 2]
            try:
                is_speech = vad.is_speech(chunk, sample_rate=sr)
            except Exception:
                is_speech = False
            voiced.append(is_speech)
        if any(voiced):
            first = next(i for i, v in enumerate(voiced) if v)
            last = len(voiced) - 1 - next(i for i, v in enumerate(reversed(voiced)) if v)
            start_sample = max(0, first * frame_len)
            end_sample = min(len(x_mono), (last + 1) * frame_len)
            return x[start_sample:end_sample]
        else:
            return x_mono
    else:
        # energy threshold fallback
        if x.ndim > 1:
            x_mono = x.mean(axis=1)
        else:
            x_mono = x
        energy = x_mono ** 2
        # threshold: 20th percentile scaled down a bit
        thresh = max(1e-7, np.percentile(energy, 20) * 0.5)
        indices = np.where(energy > thresh)[0]
        if len(indices) == 0:
            return x_mono
        return x_mono[indices[0]:indices[-1] + 1]

# ==============================
# Utility: Noise Reduction & Enhancement
# ==============================
def remove_noise(audio: np.ndarray, sr: int):
    """
    Applies stationary noise reduction.
    Assumes the noise is constant throughout the audio or estimated from the whole clip.
    """
    if nr is None:
        print("⚠️ noisereduce not installed, skipping noise reduction.")
        return audio
    
    # Reduce noise (stationary)
    # prop_decrease=0.5 means 50% of noise is removed (safer for preserving voice character)
    try:
        cleaned = nr.reduce_noise(y=audio, sr=sr, prop_decrease=0.5, stationary=True)
        return cleaned
    except Exception as e:
        print(f"⚠️ Noise reduction failed: {e}")
        return audio

def enhance_voice(audio: np.ndarray, sr: int):
    """
    Applies a high-pass filter to remove rumble and a slight presence boost.
    """
    if signal is None:
        return audio
    
    try:
        # 1. High-pass filter (cut below 80Hz)
        sos = signal.butter(4, 80, 'hp', fs=sr, output='sos')
        audio = signal.sosfilt(sos, audio)
        
        # 2. Presence boost (peaking filter around 3kHz for clarity) - optional
        # Implementing a simple EQ using biquad if needed, but for now just HPF is safest
        # to avoid making it sound unnatural.
        
        return audio
    except Exception as e:
        print(f"⚠️ Voice enhancement failed: {e}")
        return audio

# ==============================
# Preprocess and save sample
# ==============================
def preprocess_and_save_sample(src_path, target_path, target_sr=24000, min_duration_s=30.0):
    # read using soundfile
    data, sr = sf.read(src_path, dtype='float32')
    # to mono
    if data.ndim > 1:
        data = data.mean(axis=1)
    # resample if needed
    if sr != target_sr:
        if resampy is not None:
            data = resampy.resample(data, sr, target_sr)
            sr = target_sr
        elif librosa is not None:
            data = librosa.resample(data, orig_sr=sr, target_sr=target_sr)
            sr = target_sr
        else:
            raise RuntimeError("Resampling requires resampy or librosa. Install one: pip install resampy or librosa")
    # trim silence
    data = trim_silence(data, sr)
    
    # --- NEW: Noise Reduction & Enhancement ---
    # Apply before normalization
    data = remove_noise(data, sr)
    data = enhance_voice(data, sr)
    # ------------------------------------------

    # normalize loudness
    data = normalize_loudness_numpy(data, sr, target_lufs=-16.0)
    # check length
    dur = len(data) / sr
    if dur < min_duration_s:
        raise ValueError(f"Input too short ({dur:.1f}s). Provide >= {min_duration_s}s clean speech for best cloning.")
    # ensure numeric stability
    peak = np.max(np.abs(data)) + 1e-9
    if peak > 1.0:
        data = data / peak
    # write as 24k PCM16
    sf.write(target_path, data, sr, subtype='PCM_16')
    return target_path

# ==============================
# Model loading + warmup
# ==============================
def load_xtts_model():
    global tts
    if tts is None:
        print("⏳ Loading XTTS v2 model...")
        tts = TTS(
            model_name="tts_models/multilingual/multi-dataset/xtts_v2",
            progress_bar=True,
        ).to(DEVICE)
        
        # Monkey-patch Hindi char limit for text splitting
        try:
            if "hi" not in tts.synthesizer.tts_model.tokenizer.char_limits:
                tts.synthesizer.tts_model.tokenizer.char_limits["hi"] = 200
                print("🔧 Added Hindi char limit to tokenizer")
        except Exception as e:
            print(f"⚠️ Could not patch tokenizer: {e}")

        tts.synthesizer.tts_model.eval()
        # Warmup (short inference) to JIT caches and GPU kernels
        try:
            with torch.inference_mode():
                # create tiny dummy latents if config available
                conf = getattr(tts.synthesizer.tts_model, "config", None)
                dummy_gpt = None
                dummy_spk = None
                try:
                    if conf is not None:
                        gpt_len = conf.gpt_cond_len if hasattr(conf, "gpt_cond_len") else 1
                        spk_dim = conf.spk_emb_dim if hasattr(conf, "spk_emb_dim") else 1
                        dummy_gpt = torch.zeros((1, gpt_len), device=DEVICE)
                        dummy_spk = torch.zeros((1, spk_dim), device=DEVICE)
                except Exception:
                    dummy_gpt = None
                    dummy_spk = None

                sample = "Hello world."
                print("⏳ Performing warmup inference...")
                _ = tts.synthesizer.tts_model.inference(
                    text=sample,
                    language="en",
                    gpt_cond_latent=dummy_gpt,
                    speaker_embedding=dummy_spk,
                    enable_text_splitting=False
                )
                print("🚀 Model loaded and warmed up!")
        except Exception as e:
            print("⚠ Warmup failed:", e)

# Startup event
@app.on_event("startup")
async def startup_event():
    try:
        load_xtts_model()
    except Exception as e:
        print("❌ Error loading XTTS:", e)
        print("⚠ Running in MOCK MODE.")

# ==============================
# Improved get_speaker_latents
# ==============================
def get_speaker_latents(path):
    """Caches speaker embedding on DEVICE. Converts to fp16 on CUDA for speed."""
    global tts
    if path not in speaker_cache:
        print(f"🎧 Encoding speaker → {path}")
        if tts is None:
            raise RuntimeError("TTS model not loaded")
        with torch.inference_mode():
            gpt_latent, speaker_latent = tts.synthesizer.tts_model.get_conditioning_latents(
                audio_path=path,
                gpt_cond_len=tts.synthesizer.tts_model.config.gpt_cond_len,
                gpt_cond_chunk_len=tts.synthesizer.tts_model.config.gpt_cond_chunk_len
            )
            def to_device(t):
                if isinstance(t, torch.Tensor):
                    t = t.to(DEVICE)
                    if DEVICE == "cuda":
                        try:
                            t = t.half()
                        except Exception:
                            pass
                return t
            gpt_latent = to_device(gpt_latent)
            speaker_latent = to_device(speaker_latent)
            speaker_cache[path] = (gpt_latent, speaker_latent)
            
            # Simple LRU-like eviction: if cache grows too big, remove oldest
            if len(speaker_cache) > 20:
                # Python 3.7+ dicts preserve insertion order, so this removes the first inserted item
                removed_key = next(iter(speaker_cache))
                del speaker_cache[removed_key]
                print(f"🧹 Evicted {removed_key} from cache to save memory")

            print("✅ Cached speaker embeddings on device")
    return speaker_cache[path]

# ==============================
# Clone endpoint with preprocessing
# ==============================
# ==============================
# Clone endpoint with preprocessing
# ==============================
@app.post("/clone")
async def clone_voice(
    file: UploadFile = File(...),
    lang: str = Form("en"),
    user_id: str = Form("default")
):
    try:
        # Organize by user_id
        user_dir = f"speakers/{user_id}"
        os.makedirs(user_dir, exist_ok=True)
        
        tmp_in = f"{user_dir}/{lang}_in.wav"
        with open(tmp_in, "wb") as f:
            shutil.copyfileobj(file.file, f)

        target_path = f"{user_dir}/{lang}.wav"
        try:
            preprocess_and_save_sample(tmp_in, target_path, target_sr=24000, min_duration_s=30.0)
        except ValueError as e:
            # still save the raw file for experiments, but inform user
            shutil.copy(tmp_in, target_path)
            return {
                "speaker_id": target_path,
                "message": f"Saved sample, but warning: {e}. For high-quality cloning provide >=30s clean, mono, 24k sample."
            }

        # Remove cached embedding (force re-encode on next TTS)
        if target_path in speaker_cache:
            del speaker_cache[target_path]

        return {
            "speaker_id": target_path,
            "message": f"Speaker sample saved ({lang}) for user: {user_id}"
        }

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

# ==============================
# Synthesis endpoint (fast, in-memory)
# ==============================
@app.post("/synthesize")
async def synthesize(
    text: str = Form(...),
    language: str = Form(...),
    user_id: str = Form("default")
):
    try:
        # Look in user folder first
        user_dir = f"speakers/{user_id}"
        preferred = f"{user_dir}/{language}.wav"
        fallback_lang = "hi" if language == "en" else "en"
        fallback = f"{user_dir}/{fallback_lang}.wav"

        # Also check legacy path for backward compatibility
        legacy_preferred = f"speakers/{user_id}_{language}.wav"

        if os.path.exists(preferred):
            target_speaker = preferred
        elif os.path.exists(fallback):
            print(f"⚠️ Missing {preferred}, using fallback voice {fallback}")
            target_speaker = fallback
        elif os.path.exists(legacy_preferred):
             target_speaker = legacy_preferred
        else:
            # Fallback to any available speaker
            files = glob.glob("speakers/**/*.wav", recursive=True)
            if not files:
                raise HTTPException(status_code=404, detail="No speaker found.")
            target_speaker = files[0]

        print(f"🗣 Synthesizing: \"{text}\" ({language}) using {target_speaker}")
        
        # Force punctuation for Hindi
        if language == "hi" and not text.strip().endswith(("|", ".", "!", "?")):
            text += " ."

        # Detect cross-lingual
        is_cross_lingual = (language == "hi" and "en" in target_speaker) or (language == "en" and "hi" in target_speaker)
        
        # Get cached latents
        gpt_latent, speaker_latent = get_speaker_latents(target_speaker)

        sample_rate = 24000
        async with inference_lock:
            with torch.inference_mode():
                if DEVICE == "cuda":
                    autocast_ctx = torch.cuda.amp.autocast()
                else:
                    from contextlib import nullcontext
                    autocast_ctx = nullcontext()

                with autocast_ctx:
                    # Pure Copy / Indian Accent Tuning
                    # To capture the exact tone/accent, we need low temperature and top_p
                    # This reduces the model's "creative" filling and forces it to rely on the speaker embedding.
                    
                    # Base settings
                    temp = 0.65
                    top_p = 0.85
                    rep_pen = 5.0
                    
                    if language == "hi":
                        # Hindi needs strict control
                        temp = 0.45 
                        top_p = 0.8
                    elif language == "en":
                        # For English with Indian accent (assumed if user is cloning), 
                        # slightly lower temp helps maintain the prosody.
                        temp = 0.55
                        top_p = 0.85

                    if is_cross_lingual:
                        # Cross-lingual needs even more constraint
                        temp = 0.4
                        top_p = 0.75

                    out = tts.synthesizer.tts_model.inference(
                        text=text,
                        language=language,
                        gpt_cond_latent=gpt_latent,
                        speaker_embedding=speaker_latent,
                        temperature=temp,
                        length_penalty=1.0,
                        repetition_penalty=rep_pen,
                        top_k=50,
                        top_p=top_p,
                        speed=1.0,
                        enable_text_splitting=(language != "hi")
                    )

                    wav_tensor = torch.as_tensor(out["wav"])
                    if wav_tensor.dim() == 1:
                        wav_tensor = wav_tensor.unsqueeze(0)
                    if DEVICE == "cuda":
                        wav_tensor = wav_tensor.cpu()

                    wav_np = wav_tensor.squeeze(0).numpy()
                    wav_np = trim_silence(wav_np, sample_rate)

                    peak = np.max(np.abs(wav_np)) + 1e-9
                    if peak > 1.0:
                        wav_np = wav_np / peak

        buf = io.BytesIO()
        sf.write(buf, wav_np.T, sample_rate, format="WAV", subtype="PCM_16")
        buf.seek(0)
        return StreamingResponse(buf, media_type="audio/wav")

    except Exception as e:
        traceback.print_exc()
        with open("error.log", "w") as f:
            traceback.print_exc(file=f)
        raise HTTPException(status_code=500, detail=f"TTS Error: {e}")

# ==============================
# Simple chat endpoints (unchanged)
# ==============================
messages_db = []

@app.post("/send_message")
async def send_message(
    text: str = Form(...),
    sender_id: str = Form(...),
    channel_id: str = Form(...),
):
    msg = {
        "id": str(uuid.uuid4()),
        "text": text,
        "sender_id": sender_id,
        "channel_id": channel_id,
        "timestamp": time.time()
    }

    messages_db.append(msg)
    if len(messages_db) > 100:
        messages_db.pop(0)

    return {"status": "sent"}

@app.get("/get_messages")
async def get_messages(channel_id: str):
    return [msg for msg in messages_db if msg["channel_id"] == channel_id]

# ==============================
# Run server
# ==============================
if __name__ == "__main__":
    # Use --workers 1 if using GPU to avoid contention
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("server:app", host="0.0.0.0", port=port, workers=1)
