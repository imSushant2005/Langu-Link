import requests

url = "http://localhost:8000/synthesize"
data = {
    "text": "मैं हूँ",
    "language": "hi",
    "user_id": "default"
}

try:
    response = requests.post(url, data=data)
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")
except Exception as e:
    print(f"Error: {e}")
