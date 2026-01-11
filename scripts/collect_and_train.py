#!/usr/bin/env python3
"""
Interactive ASL Data Collection and Training
Press keys to record samples, then train a personalized model.
"""

import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from collections import defaultdict

def main():
    print("=" * 60)
    print("  Interactive ASL Collection & Training")
    print("=" * 60)
    print("\nInstructions:")
    print("  1. Show a hand sign in the camera")
    print("  2. Press the key for that sign (0-9, a-z)")
    print("  3. Collect at least 20 samples per sign")
    print("  4. Press 'T' to train the model")
    print("  5. Press 'Q' to quit")
    print("=" * 60)
    
    # Setup MediaPipe
    model_path = 'hand_landmarker.task'
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        num_hands=1,
        min_hand_detection_confidence=0.5
    )
    detector = vision.HandLandmarker.create_from_options(options)
    
    cap = cv2.VideoCapture(0)
    
    # Data storage
    collected_data = defaultdict(list)
    current_landmarks = None
    model = None
    encoder = None
    scaler = None
    
    print("\nCamera ready. Show your hand and press keys to collect samples.")
    
    while True:
        ret, frame = cap.read()
        if not ret:
            continue
        
        frame = cv2.flip(frame, 1)
        frame = cv2.resize(frame, (800, 600))
        h, w = frame.shape[:2]
        
        # Detect hand
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = detector.detect(mp_img)
        
        prediction = ""
        
        if result.hand_landmarks:
            hand = result.hand_landmarks[0]
            
            # Draw landmarks
            for lm in hand:
                x, y = int(lm.x * w), int(lm.y * h)
                cv2.circle(frame, (x, y), 5, (0, 255, 0), -1)
            
            # Store current landmarks
            current_landmarks = []
            for lm in hand:
                current_landmarks.extend([lm.x, lm.y, lm.z])
            
            # If model exists, predict
            if model is not None:
                scaled = scaler.transform([current_landmarks])
                proba = model.predict_proba(scaled)[0]
                idx = np.argmax(proba)
                pred = encoder.classes_[idx]
                conf = proba[idx]
                prediction = f"{pred} ({conf*100:.0f}%)"
        else:
            current_landmarks = None
        
        # Draw UI
        cv2.rectangle(frame, (0, 0), (w, 120), (30, 30, 30), -1)
        
        # Show collected counts
        counts_text = " ".join([f"{k}:{len(v)}" for k, v in sorted(collected_data.items())[:15]])
        cv2.putText(frame, f"Collected: {counts_text}", (10, 30), 
                   cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
        
        # Show prediction or instruction
        if prediction:
            cv2.putText(frame, prediction, (10, 80), 
                       cv2.FONT_HERSHEY_SIMPLEX, 2, (0, 255, 0), 3)
        elif current_landmarks:
            cv2.putText(frame, "Press key to record", (10, 80),
                       cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 255, 0), 2)
        else:
            cv2.putText(frame, "Show hand", (10, 80),
                       cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 0, 255), 2)
        
        cv2.putText(frame, "T=Train | Q=Quit", (10, 110),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)
        
        cv2.imshow("ASL Collector", frame)
        
        key = cv2.waitKey(1) & 0xFF
        
        if key == ord('q'):
            break
        elif key == ord('t') or key == ord('T'):
            # Train model
            if len(collected_data) < 2:
                print("Need at least 2 different signs to train!")
                continue
            
            print("\nTraining model...")
            X, y = [], []
            for label, samples in collected_data.items():
                for s in samples:
                    X.append(s)
                    y.append(label)
            
            X = np.array(X)
            y = np.array(y)
            
            # Augment
            X_aug, y_aug = [], []
            for x, label in zip(X, y):
                X_aug.append(x)
                y_aug.append(label)
                for _ in range(5):
                    aug = x + np.random.normal(0, 0.01, len(x))
                    X_aug.append(aug)
                    y_aug.append(label)
            
            X = np.array(X_aug)
            y = np.array(y_aug)
            
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
            
            print(f"✅ Model trained on {len(encoder.classes_)} signs: {list(encoder.classes_)}")
            print("   Model saved! Now testing...")
        
        elif key != 255 and current_landmarks is not None:
            # Record sample
            if 48 <= key <= 57:  # 0-9
                label = chr(key)
            elif 97 <= key <= 122:  # a-z
                label = chr(key).upper()
            else:
                continue
            
            collected_data[label].append(current_landmarks)
            print(f"Recorded {label} (total: {len(collected_data[label])})")
    
    cap.release()
    cv2.destroyAllWindows()
    detector.close()
    
    print("\nDone!")

if __name__ == "__main__":
    main()
