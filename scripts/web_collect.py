#!/usr/bin/env python3
"""Web-based ASL Collection - Works in browser"""

import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from flask import Flask, Response, jsonify, request
import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from collections import defaultdict
import json

app = Flask(__name__)

# Signs to collect
SIGNS = ['0', '1', '2', '3', '4', '5', 'OK', 'PEACE', 'ILY', 'HELLO', 'PLEASE', 'SORRY', 'DONT_UNDERSTAND']

# Global state
collected_data = defaultdict(list)
current_landmarks = None
model = None
encoder = None
scaler = None
detector = None

HTML = '''<!DOCTYPE html>
<html>
<head>
    <title>ASL Collection</title>
    <style>
        body { font-family: Arial; background: #1a1a1a; color: white; text-align: center; padding: 20px; margin: 0; }
        h1 { color: #4CAF50; margin: 10px; }
        #video { border: 3px solid #4CAF50; border-radius: 10px; width: 640px; height: 480px; }
        .buttons { margin: 20px; display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; }
        button { padding: 15px 25px; font-size: 18px; cursor: pointer; border: none; border-radius: 8px; min-width: 80px; }
        .sign-btn { background: #333; color: white; }
        .sign-btn:hover { background: #555; }
        .sign-btn.has-data { background: #2E7D32; }
        #train-btn { background: #FF9800; color: black; font-weight: bold; }
        #train-btn:hover { background: #FFB74D; }
        #status { font-size: 24px; margin: 15px; padding: 15px; background: #333; border-radius: 10px; }
        #prediction { font-size: 48px; color: #4CAF50; margin: 10px; }
        .counts { display: flex; flex-wrap: wrap; justify-content: center; gap: 5px; margin: 10px; }
        .count { background: #333; padding: 5px 10px; border-radius: 5px; font-size: 14px; }
        .instructions { background: #333; padding: 10px; border-radius: 10px; margin: 10px auto; max-width: 600px; text-align: left; }
    </style>
</head>
<body>
    <h1>🤟 ASL Sign Collection</h1>
    <img id="video" src="/feed">
    <div id="prediction">-</div>
    <div id="status">Show hand, then click a button to record</div>
    <div class="counts" id="counts"></div>
    <div class="buttons">
        <button class="sign-btn" onclick="record('0')">0</button>
        <button class="sign-btn" onclick="record('1')">1</button>
        <button class="sign-btn" onclick="record('2')">2</button>
        <button class="sign-btn" onclick="record('3')">3</button>
        <button class="sign-btn" onclick="record('4')">4</button>
        <button class="sign-btn" onclick="record('5')">5</button>
        <button class="sign-btn" onclick="record('OK')">OK 👌</button>
        <button class="sign-btn" onclick="record('PEACE')">PEACE ✌️</button>
        <button class="sign-btn" onclick="record('ILY')">I LOVE YOU 🤟</button>
        <button class="sign-btn" onclick="record('HELLO')">HELLO 👋</button>
        <button class="sign-btn" onclick="record('PLEASE')">PLEASE 🙏</button>
        <button class="sign-btn" onclick="record('SORRY')">SORRY</button>
        <button class="sign-btn" onclick="record('DONT_UNDERSTAND')">DON'T UNDERSTAND 🤷</button>
    </div>
    <div class="buttons">
        <button id="train-btn" onclick="train()">🚀 TRAIN MODEL</button>
    </div>
    <div class="instructions">
        <b>Instructions:</b>
        <ol>
            <li>Show the hand sign clearly in the camera</li>
            <li>Click the button for that sign (collect 20+ samples each)</li>
            <li>After collecting all signs, click TRAIN MODEL</li>
        </ol>
    </div>
    <script>
        function record(sign) {
            fetch('/record/' + sign).then(r => r.json()).then(data => {
                document.getElementById('status').innerText = data.message;
                updateCounts();
            });
        }
        function train() {
            document.getElementById('status').innerText = 'Training...';
            fetch('/train').then(r => r.json()).then(data => {
                document.getElementById('status').innerText = data.message;
            });
        }
        function updateCounts() {
            fetch('/counts').then(r => r.json()).then(data => {
                let html = '';
                for (let sign of ''' + json.dumps(SIGNS) + ''') {
                    let count = data[sign] || 0;
                    let color = count >= 20 ? '#4CAF50' : (count > 0 ? '#FF9800' : '#666');
                    html += '<span class="count" style="background:' + color + '">' + sign + ': ' + count + '</span>';
                }
                document.getElementById('counts').innerHTML = html;
            });
        }
        setInterval(function() {
            fetch('/prediction').then(r => r.json()).then(data => {
                if (data.prediction) {
                    document.getElementById('prediction').innerText = data.prediction + ' (' + data.confidence + '%)';
                } else {
                    document.getElementById('prediction').innerText = data.hand ? 'Ready to record' : 'No hand';
                }
            });
        }, 200);
        updateCounts();
    </script>
</body>
</html>'''

def setup_detector():
    global detector
    model_path = 'hand_landmarker.task'
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.VIDEO,
        num_hands=1,
        min_hand_detection_confidence=0.5
    )
    detector = vision.HandLandmarker.create_from_options(options)

def generate_frames():
    global current_landmarks, model, encoder, scaler
    cap = cv2.VideoCapture(0)
    ts = 0
    
    while True:
        ret, frame = cap.read()
        if not ret:
            continue
        
        ts += 33
        frame = cv2.flip(frame, 1)
        frame = cv2.resize(frame, (640, 480))
        h, w = frame.shape[:2]
        
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = detector.detect_for_video(mp_img, ts)
        
        if result.hand_landmarks:
            hand = result.hand_landmarks[0]
            
            # Draw landmarks
            for lm in hand:
                x, y = int(lm.x * w), int(lm.y * h)
                cv2.circle(frame, (x, y), 6, (0, 255, 0), -1)
            
            # Store landmarks
            current_landmarks = []
            for lm in hand:
                current_landmarks.extend([lm.x, lm.y, lm.z])
        else:
            current_landmarks = None
        
        _, buffer = cv2.imencode('.jpg', frame)
        yield (b'--frame\r\nContent-Type: image/jpeg\r\n\r\n' + buffer.tobytes() + b'\r\n')

@app.route('/')
def index():
    return HTML

@app.route('/feed')
def feed():
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/record/<sign>')
def record(sign):
    global current_landmarks
    if current_landmarks is None:
        return jsonify({'message': 'No hand detected! Show your hand first.'})
    
    collected_data[sign].append(current_landmarks.copy())
    count = len(collected_data[sign])
    return jsonify({'message': f'Recorded {sign} (total: {count})'})

@app.route('/counts')
def counts():
    return jsonify({k: len(v) for k, v in collected_data.items()})

@app.route('/prediction')
def prediction():
    global current_landmarks, model, encoder, scaler
    if current_landmarks is None:
        return jsonify({'hand': False, 'prediction': None})
    
    if model is None:
        return jsonify({'hand': True, 'prediction': None})
    
    scaled = scaler.transform([current_landmarks])
    proba = model.predict_proba(scaled)[0]
    idx = np.argmax(proba)
    pred = encoder.classes_[idx]
    conf = int(proba[idx] * 100)
    return jsonify({'hand': True, 'prediction': pred, 'confidence': conf})

@app.route('/train')
def train():
    global model, encoder, scaler, collected_data
    
    if len(collected_data) < 2:
        return jsonify({'message': 'Need at least 2 different signs!'})
    
    total = sum(len(v) for v in collected_data.values())
    if total < 20:
        return jsonify({'message': f'Need more samples! Only have {total}'})
    
    # Prepare data
    X, y = [], []
    for label, samples in collected_data.items():
        for s in samples:
            X.append(s)
            y.append(label)
            # Augment
            for _ in range(5):
                aug = np.array(s) + np.random.normal(0, 0.01, len(s))
                X.append(aug.tolist())
                y.append(label)
    
    X = np.array(X)
    y = np.array(y)
    
    encoder = LabelEncoder()
    y_enc = encoder.fit_transform(y)
    
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_scaled, y_enc)
    
    # Save
    joblib.dump(model, 'asl_citizen_model.pkl')
    joblib.dump(encoder, 'asl_citizen_encoder.pkl')
    joblib.dump(scaler, 'asl_citizen_scaler.pkl')
    
    signs = list(encoder.classes_)
    return jsonify({'message': f'✅ Model trained on {len(signs)} signs: {", ".join(signs)}'})

if __name__ == '__main__':
    print("Setting up...")
    setup_detector()
    print("\n" + "="*50)
    print("  Open: http://127.0.0.1:8080")
    print("="*50 + "\n")
    
    import webbrowser
    webbrowser.open('http://127.0.0.1:8080')
    
    app.run(host='0.0.0.0', port=8080, debug=False, threaded=True)
