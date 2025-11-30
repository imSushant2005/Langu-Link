# LinguaLink 🗣️🔗
**Break Language Barriers with Your Own Voice**

LinguaLink is a revolutionary real-time translation application that preserves your identity. Unlike traditional translators that use robotic voices, LinguaLink **clones your voice** in real-time, allowing you to speak in English and be heard in Hindi (and vice-versa) *as yourself*.

![LinguaLink Banner](images/banner.jpeg) 

## 🚀 Key Features

*   **Real-Time Voice Cloning**: Zero-shot cloning using Coqui XTTS v2.
*   **Cross-Lingual Synthesis**: Speak English -> Output Hindi (in your voice).
*   **"Pure Copy" Technology**: Tuned specifically to preserve Indian accents and prosody.
*   **Live Conversation Mode**: Seamless bi-directional chat interface.
*   **Multi-User Support**: Personalized login and voice storage.
*   **Privacy Focused**: On-device translation using Google ML Kit.

---

## 🛠️ Installation & Setup

### Prerequisites
*   **Python 3.10+** (for Backend)
*   **Flutter SDK** (for Mobile App)
*   **CUDA-enabled GPU** (Recommended for faster inference, but works on CPU)

### 1. Backend Setup (The Brain)
The backend handles voice cloning and speech synthesis.

```bash
cd backend
# Create virtual environment
python -m venv venv
# Activate (Windows)
.\venv\Scripts\activate
# Install dependencies
pip install -r requirements.txt
# Run the server
uvicorn server:app --host 0.0.0.0 --port 8000
```

### 2. Mobile App Setup (The Interface)
The Flutter app runs on your Android/iOS device.

```bash
# Get dependencies
flutter pub get
# Run the app (Disable Impeller if crashing on Android)
flutter run --no-enable-impeller
```

---

## 📱 How to Use

### Step 1: Login
Enter a unique username (e.g., "Arjun"). This creates your personal workspace.

![Login Screen](images/login_screen.jpeg)

### Step 2: Voice Setup
1.  Go to **Voice Setup**.
2.  Select your language (English/Hindi).
3.  Tap the **Mic** icon and read the sample text aloud (~10 seconds).
4.  Tap **Save Voice**.
    *   *Tip*: Speak clearly and naturally. This sample is used to clone your voice!

![Voice Setup English](images/voice_setup_en.jpeg)
![Voice Setup Hindi](images/voice_setup_hindi.jpeg)

### Step 3: Live Conversation
1.  Go to **Live Conversation**.
2.  **English Speaker**: Tap the "English (You)" bubble and speak.
    *   The app translates to Hindi and plays it in *your cloned voice*.
3.  **Hindi Speaker**: Tap the "Hindi" bubble and speak.
    *   The app translates to English and plays it in *their cloned voice*.
4.  **Auto Mode**: Toggle "AUTO" for hands-free conversation.

![Live Chat](images/live_chat.jpeg)

---

## 🔧 Troubleshooting

| Issue | Solution |
| :--- | :--- |
| **App Crashes on Startup** | Run with `flutter run --no-enable-impeller`. |
| **"Server Error"** | Ensure Python server is running and phone is on same Wi-Fi. Update IP in `voice_cloning_screen.dart`. |
| **Voice sounds robotic** | Re-record a cleaner sample (30s is best). Ensure no background noise. |
| **Hindi output has gibberish** | The server auto-corrects this, but try speaking shorter sentences. |

---

## 🏗️ Architecture
*   **Frontend**: Flutter (Dart)
*   **Backend**: FastAPI (Python)
*   **AI Models**:
    *   **TTS**: Coqui XTTS v2
    *   **Translation**: Google ML Kit
    *   **Audio Processing**: `noisereduce`, `scipy`

## 📄 License
This project is licensed under the MIT License.
