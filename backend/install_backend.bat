@echo off
echo 🚀 Installing Backend Dependencies...

echo 📦 Uninstalling potential conflicts...
pip uninstall torchcodec -y 2>nul
pip uninstall protobuf -y 2>nul

echo 📦 Installing Core ML Stack (Torch 2.1.0 + CUDA 12.1)...
pip install torch==2.1.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cu121

echo 📦 Installing TorchCodec (Required for XTTS v2)...
pip install torchcodec==0.2.0 --index-url https://download.pytorch.org/whl/cu121

echo 📦 Installing Other Requirements...
pip install -r requirements.txt

echo ✅ Installation Complete!
echo 🧪 Testing TorchCodec...
python -c "import torchcodec; print('TorchCodec OK')"

pause
