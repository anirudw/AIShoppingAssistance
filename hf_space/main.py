import os
import torch
from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from transformers import CLIPProcessor, CLIPVisionModelWithProjection
from PIL import Image
import io

app = FastAPI()

# Enable CORS so Flutter Web or local clients can call it directly
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load model and processor on startup
device = "cuda" if torch.cuda.is_available() else "cpu"
model_id = "openai/clip-vit-base-patch32"

print(f"Loading CLIP model '{model_id}' on device: {device}...")
processor = CLIPProcessor.from_pretrained(model_id)
model = CLIPVisionModelWithProjection.from_pretrained(model_id).to(device)
print("Model loaded successfully!")

@app.post("/embed")
async def get_embedding(file: UploadFile = File(...)):
    try:
        # Read image bytes
        contents = await file.read()
        image = Image.open(io.BytesIO(contents)).convert("RGB")
        
        # Process and run inference
        inputs = processor(images=image, return_tensors="pt").to(device)
        with torch.no_grad():
            outputs = model.get_image_features(**inputs)
            
        # Convert embedding tensor to list
        embedding = outputs[0].cpu().numpy().tolist()
        return {"status": "success", "embedding": embedding}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/")
def read_root():
    return {
        "status": "running", 
        "model": model_id,
        "device": device
    }
