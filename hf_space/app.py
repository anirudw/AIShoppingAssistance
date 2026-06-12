import os
import io
import time
import datetime
from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from transformers import CLIPProcessor
from PIL import Image
from huggingface_hub import hf_hub_download
import onnxruntime as ort
import numpy as np

app = FastAPI()

# Enable CORS so Flutter Web or local clients can call it directly
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load model and processor on startup using ONNX Runtime
model_id = "Xenova/clip-vit-base-patch32"
device = "cpu"

print(f"Loading CLIP processor '{model_id}'...")
processor = CLIPProcessor.from_pretrained(model_id)

print(f"Downloading ONNX model '{model_id}'...")
model_file = hf_hub_download(repo_id=model_id, filename="onnx/vision_model.onnx")

print("Initializing ONNX Runtime session...")
session = ort.InferenceSession(model_file, providers=["CPUExecutionProvider"])
print("Model loaded successfully!")

# Ensure captured_images directory exists
IMAGES_DIR = "captured_images"
os.makedirs(IMAGES_DIR, exist_ok=True)

@app.post("/embed")
async def get_embedding(file: UploadFile = File(...)):
    try:
        # Read image bytes
        contents = await file.read()
        
        # Save image locally inside container for viewing/debugging
        filename = f"capture_{int(time.time() * 1000)}.jpg"
        filepath = os.path.join(IMAGES_DIR, filename)
        try:
            with open(filepath, "wb") as f:
                f.write(contents)
            print(f"Saved scanned image to {filepath}")
        except Exception as save_err:
            print(f"Error saving image: {save_err}")

        # Open and process the image
        image = Image.open(io.BytesIO(contents)).convert("RGB")
        
        # Process and run inference
        inputs = processor(images=image, return_tensors="np")
        pixel_values = inputs["pixel_values"]
        
        # Run inference using ONNX Runtime
        outputs = session.run(["image_embeds"], {"pixel_values": pixel_values})
        image_embeds = outputs[0]
        
        # L2 normalize the embedding
        norm = np.linalg.norm(image_embeds, axis=-1, keepdims=True)
        normalized_image_embeds = image_embeds / (norm + 1e-12)
        
        # Convert embedding numpy array to list
        embedding = normalized_image_embeds[0].tolist()
        return {"status": "success", "embedding": embedding}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/captured_images/{filename}")
async def get_captured_image(filename: str):
    filepath = os.path.join(IMAGES_DIR, filename)
    if os.path.exists(filepath):
        return FileResponse(filepath)
    return {"error": "File not found"}

@app.get("/gallery", response_class=HTMLResponse)
async def get_gallery():
    files = []
    if os.path.exists(IMAGES_DIR):
        for f in os.listdir(IMAGES_DIR):
            if f.lower().endswith(('.jpg', '.jpeg', '.png')):
                fp = os.path.join(IMAGES_DIR, f)
                mtime = os.path.getmtime(fp)
                files.append((f, mtime))
    
    files.sort(key=lambda x: x[1], reverse=True)
    
    # Render Scandinavian modern light themed gallery page
    html_content = """<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Scanned Products Gallery | QLESS</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background-color: #F4F7F8;
            color: #2D3748;
            margin: 0;
            padding: 40px 24px;
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        .container {
            width: 100%;
            max-width: 1100px;
        }
        header {
            margin-bottom: 40px;
            text-align: center;
        }
        h1 {
            font-size: 2.25rem;
            font-weight: 700;
            color: #1A202C;
            margin: 0 0 8px 0;
            letter-spacing: -0.025em;
        }
        p {
            color: #718096;
            font-size: 1.1rem;
            margin: 0;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
            gap: 24px;
            margin-top: 20px;
        }
        .card {
            background: #FFFFFF;
            border-radius: 18px;
            overflow: hidden;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.03);
            border: 1px solid rgba(0, 0, 0, 0.04);
            transition: transform 0.25s cubic-bezier(0.4, 0, 0.2, 1), box-shadow 0.25s cubic-bezier(0.4, 0, 0.2, 1);
        }
        .card:hover {
            transform: translateY(-4px);
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.06);
        }
        .card-img-wrapper {
            position: relative;
            width: 100%;
            padding-top: 100%; /* 1:1 Aspect Ratio */
            background-color: #EDF2F7;
        }
        .card img {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            object-fit: cover;
        }
        .info {
            padding: 16px;
            font-size: 0.85rem;
            color: #718096;
            font-weight: 500;
            text-align: center;
            background: #FAFCFC;
            border-top: 1px solid #E2E8F0;
        }
        .empty-state {
            grid-column: 1 / -1;
            text-align: center;
            padding: 80px 20px;
            background: #FFFFFF;
            border-radius: 18px;
            border: 1px dashed #E2E8F0;
            color: #A0AEC0;
            font-size: 1.1rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Product Scan History</h1>
            <p>A history of all product images captured by the AI Shopping Assistant.</p>
        </header>
        <div class="grid">
    """
    
    for f, mtime in files:
        dt = datetime.datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M:%S')
        html_content += f"""
            <div class="card">
                <a href="/captured_images/{f}" target="_blank">
                    <div class="card-img-wrapper">
                        <img src="/captured_images/{f}" alt="Scan from {dt}">
                    </div>
                </a>
                <div class="info">{dt}</div>
            </div>
        """
        
    if not files:
        html_content += """
            <div class="empty-state">
                No scanned images found yet. Start scanning from the app!
            </div>
        """
        
    html_content += """
        </div>
    </div>
</body>
</html>
    """
    return html_content

@app.get("/")
def read_root():
    return {
        "status": "running", 
        "model": model_id,
        "device": device
    }

