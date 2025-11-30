import numpy as np
import soundfile as sf
import os

# Mock imports to test logic if libs are missing, but we expect them to be there
try:
    import noisereduce as nr
    print("✅ noisereduce imported")
except ImportError:
    print("❌ noisereduce NOT found")

try:
    from scipy import signal
    print("✅ scipy imported")
except ImportError:
    print("❌ scipy NOT found")

# Import functions from server.py (we need to make sure server.py is importable)
# We can just copy the functions here for unit testing to avoid running the whole server app
# or we can try to import them. Importing server might trigger model load which is slow.
# Let's copy the logic for a quick unit test of the libraries.

def remove_noise(audio: np.ndarray, sr: int):
    if 'nr' not in globals(): return audio
    try:
        cleaned = nr.reduce_noise(y=audio, sr=sr, prop_decrease=0.9, stationary=True)
        return cleaned
    except Exception as e:
        print(f"Noise reduction error: {e}")
        return audio

def enhance_voice(audio: np.ndarray, sr: int):
    if 'signal' not in globals(): return audio
    try:
        sos = signal.butter(4, 80, 'hp', fs=sr, output='sos')
        audio = signal.sosfilt(sos, audio)
        return audio
    except Exception as e:
        print(f"Enhancement error: {e}")
        return audio

def test_processing():
    sr = 24000
    duration = 2.0
    t = np.linspace(0, duration, int(sr * duration))
    
    # Clean signal: 440Hz sine wave
    clean = 0.5 * np.sin(2 * np.pi * 440 * t)
    
    # Noise: random gaussian
    noise = 0.1 * np.random.normal(0, 1, len(t))
    
    # Noisy signal
    noisy = clean + noise
    
    print(f"Original RMS: {np.sqrt(np.mean(noisy**2)):.4f}")
    
    # 1. Test Noise Reduction
    denoised = remove_noise(noisy, sr)
    denoised_rms = np.sqrt(np.mean(denoised**2))
    print(f"Denoised RMS: {denoised_rms:.4f}")
    
    # Expect RMS to decrease (noise removed) but not too much (signal preserved)
    if denoised_rms < np.sqrt(np.mean(noisy**2)):
        print("✅ Noise reduction reduced signal energy (expected)")
    else:
        print("⚠️ Noise reduction didn't reduce energy?")

    # 2. Test Enhancement (High Pass)
    # Create a signal with low freq rumble (50Hz)
    rumble = 0.3 * np.sin(2 * np.pi * 50 * t)
    noisy_rumble = clean + rumble
    
    enhanced = enhance_voice(noisy_rumble, sr)
    
    # Check if 50Hz is attenuated
    # Simple check: RMS should be lower after removing rumble
    rumble_rms = np.sqrt(np.mean(noisy_rumble**2))
    enhanced_rms = np.sqrt(np.mean(enhanced**2))
    print(f"Rumble RMS: {rumble_rms:.4f}, Enhanced RMS: {enhanced_rms:.4f}")
    
    if enhanced_rms < rumble_rms:
        print("✅ High-pass filter reduced low frequency energy")
    else:
        print("⚠️ High-pass filter didn't reduce energy?")

if __name__ == "__main__":
    test_processing()
