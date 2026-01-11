#!/usr/bin/env python3
"""Simple ASL Detection Test - Shows camera feed and detections"""

import cv2
import numpy as np
import joblib
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

def normalize_to_wrist(coords):
    """Normalize landmarks to wrist-centered coordinates."""
    coords = np.array(coords).reshape(21, 3)
    wrist = coords[0].copy()
    centered = coords - wrist
    hand_size = np.linalg.norm(centered[9])
    if hand_size < 0.001:
        hand_size = 1.0
    return np.clip((centered / hand_size).flatten(), -5, 5)

def main():
    print("=" * 50)
    print("  ASL Detection Test")
    print("=" * 50)
    
    # Load model
    model = joblib.load('asl_citizen_model.pkl')
    encoder = joblib.load('asl_citizen_encoder.pkl')
    print(f"Model: {len(encoder.classes_)} classes")
    
    # Setup MediaPipe
    model_path = 'hand_landmarker.task'
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.VIDEO,
        num_hands=1,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5
    )
    detector = vision.HandLandmarker.create_from_options(options)
    
    # Camera
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("ERROR: Cannot open camera")
        return
    
    print("\nCamera ready!")
    print("- Hold your hand clearly in front of the camera")
    print("- Make sure there's good lighting")
    print("- Press 'q' to quit")
    print("=" * 50)
    
    frame_count = 0
    detect_count = 0
    timestamp = 0
    
    while True:
        ret, frame = cap.read()
        if not ret:
            continue
        
        frame_count += 1
        timestamp += 33  # ~30 fps
        
        # Flip for mirror effect
        frame = cv2.flip(frame, 1)
        
        # Detect
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = detector.detect_for_video(mp_image, timestamp)
        
        h, w = frame.shape[:2]
        
        if result.hand_landmarks:
            detect_count += 1
            hand = result.hand_landmarks[0]
            
            # Draw landmarks
            for lm in hand:
                x, y = int(lm.x * w), int(lm.y * h)
                cv2.circle(frame, (x, y), 5, (0, 255, 0), -1)
            
            # Draw connections
            connections = [
                (0, 1), (1, 2), (2, 3), (3, 4),  # Thumb
                (0, 5), (5, 6), (6, 7), (7, 8),  # Index
                (0, 9), (9, 10), (10, 11), (11, 12),  # Middle
                (0, 13), (13, 14), (14, 15), (15, 16),  # Ring
                (0, 17), (17, 18), (18, 19), (19, 20),  # Pinky
                (5, 9), (9, 13), (13, 17)  # Palm
            ]
            for start, end in connections:
                x1, y1 = int(hand[start].x * w), int(hand[start].y * h)
                x2, y2 = int(hand[end].x * w), int(hand[end].y * h)
                cv2.line(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            
            # Predict
            raw = []
            for lm in hand:
                raw.extend([lm.x, lm.y, lm.z])
            
            norm = normalize_to_wrist(raw)
            proba = model.predict_proba(norm.reshape(1, -1))[0]
            pred_idx = np.argmax(proba)
            pred = str(encoder.classes_[pred_idx])
            conf = proba[pred_idx]
            
            # Display prediction
            color = (0, 255, 0) if conf > 0.5 else (0, 255, 255)
            cv2.rectangle(frame, (10, 50), (400, 130), (0, 0, 0), -1)
            cv2.putText(frame, f"{pred}", (20, 110), 
                       cv2.FONT_HERSHEY_SIMPLEX, 2, color, 3)
            cv2.putText(frame, f"{conf*100:.0f}%", (220, 110),
                       cv2.FONT_HERSHEY_SIMPLEX, 1.5, color, 2)
            
            # Top 3 predictions
            top3 = np.argsort(proba)[-3:][::-1]
            y_pos = 160
            for i, idx in enumerate(top3):
                label = str(encoder.classes_[idx])
                p = proba[idx] * 100
                cv2.putText(frame, f"{i+1}. {label}: {p:.0f}%", (20, y_pos),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
                y_pos += 25
            
            if frame_count % 30 == 0:
                print(f"Detected: {pred} ({conf*100:.1f}%)")
        else:
            cv2.rectangle(frame, (10, 50), (400, 130), (0, 0, 0), -1)
            cv2.putText(frame, "No hand detected", (20, 100),
                       cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
        
        # Stats
        rate = detect_count / max(1, frame_count) * 100
        cv2.putText(frame, f"Detection rate: {rate:.0f}%", (10, 30),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
        
        cv2.imshow('ASL Detection Test', frame)
        
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break
    
    cap.release()
    cv2.destroyAllWindows()
    detector.close()
    
    print(f"\nDone: {detect_count}/{frame_count} frames ({detect_count/max(1,frame_count)*100:.1f}% detection rate)")

if __name__ == "__main__":
    main()
