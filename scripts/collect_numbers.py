#!/usr/bin/env python3
"""
Quick data collection for ASL numbers 0-5 and I LOVE YOU
Run this, then retrain the model.

Controls:
    - Press 0-5 to set number label
    - Press 'i' for I LOVE YOU
    - Press 's' to start/stop recording
    - Press 'q' to quit and save
"""

import cv2
import csv
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

SAMPLES_PER_LABEL = 100  # Quick collection
OUTPUT_FILE = "number_landmarks.csv"

# Labels to collect
LABELS = ['0', '1', '2', '3', '4', '5', 'I_LOVE_YOU']

CSV_HEADER = [f"{c}{i}" for i in range(21) for c in ['x', 'y', 'z']] + ['label']

class NumberCollector:
    def __init__(self):
        self.data = []
        self.current_label = None
        self.is_recording = False
        self.samples_count = {label: 0 for label in LABELS}
        self.last_result = None
        
        # Setup MediaPipe
        base_options = python.BaseOptions(model_asset_path='hand_landmarker.task')
        options = vision.HandLandmarkerOptions(
            base_options=base_options,
            running_mode=vision.RunningMode.LIVE_STREAM,
            num_hands=1,
            min_hand_detection_confidence=0.5,
            min_tracking_confidence=0.5,
            result_callback=self._result_callback
        )
        self.detector = vision.HandLandmarker.create_from_options(options)
        
    def _result_callback(self, result, output_image, timestamp_ms):
        self.last_result = result
        
    def add_sample(self, landmarks):
        if not self.is_recording or self.current_label is None:
            return False
        if self.samples_count[self.current_label] >= SAMPLES_PER_LABEL:
            print(f"✅ Done with {self.current_label}!")
            self.is_recording = False
            return False
        
        row = []
        for lm in landmarks:
            row.extend([lm.x, lm.y, lm.z])
        row.append(self.current_label)
        self.data.append(row)
        self.samples_count[self.current_label] += 1
        return True
        
    def save(self):
        if not self.data:
            print("No data to save")
            return
        with open(OUTPUT_FILE, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(CSV_HEADER)
            writer.writerows(self.data)
        print(f"✅ Saved {len(self.data)} samples to {OUTPUT_FILE}")

def main():
    collector = NumberCollector()
    cap = cv2.VideoCapture(0)
    
    if not cap.isOpened():
        print("❌ Cannot open camera")
        return
        
    print("\n" + "="*50)
    print("  ASL Number Collection (0-5 + I LOVE YOU)")
    print("="*50)
    print("\nControls:")
    print("  0-5: Set number label")
    print("  i: Set 'I LOVE YOU' label")
    print("  s: Start/Stop recording")
    print("  q: Quit and save")
    print("="*50 + "\n")
    
    frame_count = 0
    
    while True:
        ret, frame = cap.read()
        if not ret:
            continue
            
        frame = cv2.flip(frame, 1)  # Mirror like iOS front camera
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        collector.detector.detect_async(mp_image, frame_count)
        frame_count += 1
        
        # Process landmarks
        if collector.last_result and collector.last_result.hand_landmarks:
            landmarks = collector.last_result.hand_landmarks[0]
            collector.add_sample(landmarks)
            
            # Draw landmarks
            h, w = frame.shape[:2]
            for lm in landmarks:
                x, y = int(lm.x * w), int(lm.y * h)
                cv2.circle(frame, (x, y), 3, (0, 255, 0), -1)
        
        # Display info
        status = "RECORDING" if collector.is_recording else "PAUSED"
        label = collector.current_label or "None"
        count = collector.samples_count.get(label, 0) if label != "None" else 0
        
        cv2.putText(frame, f"Label: {label} ({count}/{SAMPLES_PER_LABEL})", 
                    (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        cv2.putText(frame, f"Status: {status}", 
                    (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.7, 
                    (0, 0, 255) if collector.is_recording else (128, 128, 128), 2)
        
        # Show progress
        y = 100
        for lbl in LABELS:
            cnt = collector.samples_count[lbl]
            color = (0, 255, 0) if cnt >= SAMPLES_PER_LABEL else (255, 255, 255)
            cv2.putText(frame, f"{lbl}: {cnt}", (10, y), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1)
            y += 20
        
        cv2.imshow('Collect Numbers', frame)
        
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('s'):
            collector.is_recording = not collector.is_recording
            print(f"Recording: {collector.is_recording}")
        elif key in [ord(str(i)) for i in range(6)]:
            collector.current_label = chr(key)
            print(f"Label set to: {collector.current_label}")
        elif key == ord('i'):
            collector.current_label = 'I_LOVE_YOU'
            print(f"Label set to: I_LOVE_YOU")
    
    cap.release()
    cv2.destroyAllWindows()
    collector.save()

if __name__ == "__main__":
    main()
