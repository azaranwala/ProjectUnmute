#!/usr/bin/env python3
"""Web-based ASL Detection - Opens in browser"""

import cv2
import numpy as np
import joblib
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from flask import Flask, Response, render_template_string
import threading

app = Flask(__name__)

# Global variables
model = None
encoder = None
detector = None
current_prediction = "Loading..."
current_confidence = 0

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>ASL Detection</title>
    <style>
        body { font-family: Arial; background: #1a1a1a; color: white; text-align: center; margin: 0; padding: 20px; }
        h1 { color: #4CAF50; }
        #video { border: 3px solid #4CAF50; border-radius: 10px; max-width: 100%; }
        #prediction { font-size: 72px; color: #4CAF50; margin: 20px; }
        #confidence { font-size: 24px; color: #888; }
        .instructions { background: #333; padding: 15px; border-radius: 10px; margin: 20px auto; max-width: 600px; }
    </style>
</head>
<body>
    <h1>🤟 ASL Detection</h1>
    <img id="video" src="/video_feed">
    <div id="prediction">Loading...</div>
    <div id="confidence"></div>
    <div class="instructions">
        <p>Hold your hand clearly in front of the camera</p>
        <p>Try: L, Y, A, B, C, 1, 2, 3, YES, NO</p>
    </div>
    <script>
        setInterval(function() {
            fetch('/status').then(r => r.json()).then(data => {
                document.getElementById('prediction').innerText = data.prediction;
                document.getElementById('confidence').innerText = data.confidence + '% confidence';
            });
        }, 200);
    </script>
</body>
</html>
"""

def normalize_to_wrist(coords):
    coords = np.array(coords).reshape(21, 3)
    wrist = coords[0].copy()
    centered = coords - wrist
    hand_size = np.linalg.norm(centered[9])
    if hand_size < 0.001:
        hand_size = 1.0
    return np.clip((centered / hand_size).flatten(), -5, 5)

def generate_frames():
    global current_prediction, current_confidence
    
    cap = cv2.VideoCapture(0)
    timestamp = 0
    
    while True:
        ret, frame = cap.read()
        if not ret:
            continue
        
        timestamp += 33
        frame = cv2.flip(frame, 1)
        frame = cv2.resize(frame, (640, 480))
        
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = detector.detect_for_video(mp_image, timestamp)
        
        h, w = frame.shape[:2]
        
        if result.hand_landmarks:
            hand = result.hand_landmarks[0]
            
            # Draw landmarks
            for lm in hand:
                x, y = int(lm.x * w), int(lm.y * h)
                cv2.circle(frame, (x, y), 6, (0, 255, 0), -1)
            
            # Predict
            raw = []
            for lm in hand:
                raw.extend([lm.x, lm.y, lm.z])
            
            norm = normalize_to_wrist(raw)
            proba = model.predict_proba(norm.reshape(1, -1))[0]
            pred_idx = np.argmax(proba)
            pred = str(encoder.classes_[pred_idx])
            conf = proba[pred_idx]
            
            current_prediction = pred
            current_confidence = int(conf * 100)
            
            # Draw on frame
            cv2.rectangle(frame, (0, 0), (200, 60), (0, 0, 0), -1)
            cv2.putText(frame, pred, (10, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 255, 0), 3)
        else:
            current_prediction = "No hand"
            current_confidence = 0
            cv2.rectangle(frame, (0, 0), (200, 60), (0, 0, 0), -1)
            cv2.putText(frame, "No hand", (10, 45), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
        
        _, buffer = cv2.imencode('.jpg', frame)
        yield (b'--frame\r\nContent-Type: image/jpeg\r\n\r\n' + buffer.tobytes() + b'\r\n')

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/video_feed')
def video_feed():
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/status')
def status():
    return {'prediction': current_prediction, 'confidence': current_confidence}

if __name__ == '__main__':
    print("Loading model...")
    model = joblib.load('asl_citizen_model.pkl')
    encoder = joblib.load('asl_citizen_encoder.pkl')
    print(f"Model: {len(encoder.classes_)} classes")
    
    print("Setting up MediaPipe...")
    model_path = 'hand_landmarker.task'
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.VIDEO,
        num_hands=1,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5
    )
    detector = vision.HandLandmarker.create_from_options(options)
    
    print("\n" + "="*50)
    print("  Open in browser: http://127.0.0.1:5000")
    print("="*50 + "\n")
    
    import webbrowser
    webbrowser.open('http://127.0.0.1:5000')
    
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
