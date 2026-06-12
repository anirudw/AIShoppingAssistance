import os
import time
import urllib.request
import urllib.error
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

def load_env():
    env = {}
    env_path = os.path.join(os.path.dirname(__file__), '.env')
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    if '=' in line:
                        key, val = line.split('=', 1)
                        env[key.strip()] = val.strip()
    return env

class SaveImageHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Override to prevent default log flooding in terminal
        print(f"[Server] {format % args}")

    def do_OPTIONS(self):
        # Enable CORS for Flutter Web local testing
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_POST(self):
        # Enable CORS
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Type', 'application/json')
        self.end_headers()

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        # Target directory inside project root
        target_dir = os.path.join(os.path.dirname(__file__), 'captured_images')
        if not os.path.exists(target_dir):
            os.makedirs(target_dir)

        # Generate timestamp filename
        filename = f"capture_{int(time.time() * 1000)}.jpg"
        filepath = os.path.join(target_dir, filename)

        try:
            # Write bytes to file
            with open(filepath, 'wb') as f:
                f.write(post_data)
            print(f"[Server] Saved captured image to: {filepath}")
        except Exception as e:
            print(f"[Server] Error saving file: {e}")

        # Fetch embedding from Hugging Face Space or Inference API
        try:
            env = load_env()
            hf_space_url = env.get('HF_SPACE_URL', '')
            
            if hf_space_url:
                # Query custom Hugging Face Space (FastAPI endpoint)
                print(f"[Server] Querying custom Hugging Face Space: {hf_space_url}")
                boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW'
                body = [
                    f'--{boundary}'.encode('utf-8'),
                    'Content-Disposition: form-data; name="file"; filename="image.jpg"'.encode('utf-8'),
                    'Content-Type: image/jpeg'.encode('utf-8'),
                    b'',
                    post_data,
                    f'--{boundary}--'.encode('utf-8'),
                    b''
                ]
                payload = b'\r\n'.join(body)
                
                req = urllib.request.Request(
                    hf_space_url,
                    data=payload,
                    headers={
                        'Content-Type': f'multipart/form-data; boundary={boundary}',
                        'Content-Length': str(len(payload))
                    },
                    method='POST'
                )
            else:
                # Query Serverless Inference API (Fallback)
                hf_token = env.get('HF_API_TOKEN', '')
                if not hf_token:
                    raise Exception("Neither HF_SPACE_URL nor HF_API_TOKEN is set in .env file")
                
                model_url = 'https://router.huggingface.co/hf-inference/models/openai/clip-vit-base-patch32'
                print(f"[Server] Querying Hugging Face Serverless API: {model_url}")
                req = urllib.request.Request(
                    model_url,
                    data=post_data,
                    headers={
                        'Authorization': f'Bearer {hf_token}',
                        'Content-Type': 'application/octet-stream',
                    },
                    method='POST'
                )
            
            with urllib.request.urlopen(req) as response:
                result = response.read().decode('utf-8')
                res_json = json.loads(result)
                
                # FastAPI returns {"status": "success", "embedding": [...]}
                # Serverless Inference API returns raw float array [...] directly
                if isinstance(res_json, dict) and "embedding" in res_json:
                    embedding = res_json["embedding"]
                else:
                    embedding = res_json
                
                print(f"[Server] Successfully generated CLIP embedding vector of length {len(embedding)}")
                self.wfile.write(json.dumps({
                    "status": "success",
                    "embedding": embedding
                }).encode('utf-8'))
        except Exception as e:
            print(f"[Server] Error generating embedding: {e}")
            self.wfile.write(json.dumps({
                "status": "error",
                "message": str(e)
            }).encode('utf-8'))

def run_server():
    server_address = ('', 5001)
    httpd = HTTPServer(server_address, SaveImageHandler)
    print("\n==============================================")
    print("Local Image Saver Server running on port 5001")
    print("Saving to: ./captured_images/")
    print("==============================================\n")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer shutting down.")

if __name__ == '__main__':
    run_server()
