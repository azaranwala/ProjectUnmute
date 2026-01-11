#!/usr/bin/env python3
"""
Process Combined Dataset: ASL Citizen (word signs) + Kaggle (alphabet)
Creates a unified dataset for training.
"""

import os
import cv2
import numpy as np
import pandas as pd
import csv
from pathlib import Path
from collections import defaultdict
import time

# MediaPipe Tasks API
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Configuration
ASL_CITIZEN_VIDEOS_DIR = "../asl_citizen_dataset/ASL_Citizen/videos"
ASL_CITIZEN_TRAIN_CSV = "../asl_citizen_dataset/ASL_Citizen/splits/train.csv"
ASL_CITIZEN_VAL_CSV = "../asl_citizen_dataset/ASL_Citizen/splits/val.csv"
ASL_CITIZEN_TEST_CSV = "../asl_citizen_dataset/ASL_Citizen/splits/test.csv"
KAGGLE_LANDMARKS_CSV = "kaggle_asl_landmarks.csv"
OUTPUT_CSV = "combined_asl_landmarks.csv"
SAMPLES_PER_VIDEO = 20
LANDMARK_COUNT = 21

# Useful word signs to extract from ASL Citizen
USEFUL_SIGNS = [
    'HELLO', 'THANKYOU', 'PLEASE', 'SORRY', 'HELP',
    'GOOD', 'BAD', 'HAPPY', 'SAD', 'LIKE',
    'WANT2', 'NEED', 'STOP', 'WAIT', 'PLAY',
    'LEARN', 'TEACH1', 'WRITE', 'SLEEP', 'WALK2',
    'STAND1', 'FAMILY', 'FRIEND', 'MOTHER', 'FATHER',
    'NAME', 'WHAT1', 'WHERE', 'WHEN', 'WHY',
    'HOW1', 'DRINK1', 'WATERDROP', 'EYES', 'NOSE',
    # Add more common signs
    'BECOME', 'WILLGO', 'LONGAGO', 'SIGNATURE', 'NETWORK'
]

# CSV header
CSV_HEADER = []
for i in range(LANDMARK_COUNT):
    CSV_HEADER.extend([f"x{i}", f"y{i}", f"z{i}"])
CSV_HEADER.append("label")


class VideoLandmarkExtractor:
    def __init__(self):
        self.detector = None
        self.setup_detector()
    
    def setup_detector(self):
        model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hand_landmarker.task')
        base_options = python.BaseOptions(model_asset_path=model_path)
        options = vision.HandLandmarkerOptions(
            base_options=base_options,
            num_hands=1,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5
        )
        self.detector = vision.HandLandmarker.create_from_options(options)
    
    def extract_from_video(self, video_path: str, samples_per_video: int = 10) -> list:
        """Extract landmarks from video frames."""
        samples = []
        cap = cv2.VideoCapture(video_path)
        
        if not cap.isOpened():
            return samples
        
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if total_frames <= 0:
            cap.release()
            return samples
        
        # Sample frames evenly
        frame_indices = np.linspace(0, total_frames - 1, samples_per_video, dtype=int)
        
        for frame_idx in frame_indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = cap.read()
            
            if not ret:
                continue
            
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            
            try:
                result = self.detector.detect(mp_image)
                
                if result.hand_landmarks:
                    landmarks = result.hand_landmarks[0]
                    coords = []
                    for lm in landmarks:
                        coords.extend([lm.x, lm.y, lm.z])
                    samples.append(coords)
            except:
                continue
        
        cap.release()
        return samples
    
    def close(self):
        if self.detector:
            self.detector.close()


def find_useful_signs() -> dict:
    """Find videos for useful signs in ASL Citizen dataset."""
    print("\n🔍 Finding useful word signs in ASL Citizen...")
    
    sign_videos = defaultdict(list)
    videos_dir = Path(ASL_CITIZEN_VIDEOS_DIR)
    
    # Read all CSVs
    csv_files = [ASL_CITIZEN_TRAIN_CSV, ASL_CITIZEN_VAL_CSV, ASL_CITIZEN_TEST_CSV]
    
    for csv_path in csv_files:
        if not os.path.exists(csv_path):
            continue
        
        df = pd.read_csv(csv_path)
        for _, row in df.iterrows():
            gloss = row['Gloss'].strip()
            video_file = row['Video file'].strip()
            
            if gloss in USEFUL_SIGNS:
                video_path = videos_dir / video_file
                if video_path.exists():
                    sign_videos[gloss].append(str(video_path))
    
    print(f"   Found {len(sign_videos)} useful signs")
    for sign, videos in sorted(sign_videos.items()):
        print(f"      {sign}: {len(videos)} videos")
    
    return dict(sign_videos)


def process_asl_citizen(sign_videos: dict, extractor: VideoLandmarkExtractor) -> list:
    """Process ASL Citizen videos."""
    all_samples = []
    total_signs = len(sign_videos)
    
    print(f"\n🎬 Processing {total_signs} word signs from ASL Citizen...")
    
    for idx, (sign, videos) in enumerate(sorted(sign_videos.items())):
        sign_samples = 0
        
        for video_path in videos:
            samples = extractor.extract_from_video(video_path, SAMPLES_PER_VIDEO)
            for coords in samples:
                all_samples.append(coords + [sign])
                sign_samples += 1
        
        progress = ((idx + 1) / total_signs) * 100
        print(f"   [{progress:5.1f}%] {sign}: {sign_samples} samples from {len(videos)} videos")
    
    return all_samples


def load_kaggle_data() -> list:
    """Load pre-processed Kaggle alphabet data."""
    print(f"\n📂 Loading Kaggle alphabet data from {KAGGLE_LANDMARKS_CSV}...")
    
    if not os.path.exists(KAGGLE_LANDMARKS_CSV):
        print("   ❌ Kaggle landmarks file not found!")
        return []
    
    df = pd.read_csv(KAGGLE_LANDMARKS_CSV)
    samples = df.values.tolist()
    
    # Count per label
    label_counts = df['label'].value_counts()
    print(f"   Loaded {len(samples)} samples")
    print(f"   Labels: {len(label_counts)} (A-Z, 0-9)")
    
    return samples


def main():
    print("=" * 60)
    print("  Combined ASL Dataset Processor")
    print("  (ASL Citizen Word Signs + Kaggle Alphabet)")
    print("=" * 60)
    
    # Load Kaggle alphabet data
    kaggle_samples = load_kaggle_data()
    
    # Find useful signs in ASL Citizen
    sign_videos = find_useful_signs()
    
    if not sign_videos:
        print("\n❌ No useful signs found!")
        return
    
    # Initialize MediaPipe
    print("\n🔧 Initializing MediaPipe...")
    extractor = VideoLandmarkExtractor()
    
    # Process ASL Citizen videos
    citizen_samples = process_asl_citizen(sign_videos, extractor)
    
    # Combine datasets
    print(f"\n📊 Combining datasets...")
    print(f"   Kaggle alphabet: {len(kaggle_samples)} samples")
    print(f"   ASL Citizen words: {len(citizen_samples)} samples")
    
    all_samples = kaggle_samples + citizen_samples
    print(f"   Combined total: {len(all_samples)} samples")
    
    # Count unique labels
    labels = set(s[-1] for s in all_samples)
    print(f"   Unique labels: {len(labels)}")
    
    # Save combined data
    print(f"\n💾 Saving to {OUTPUT_CSV}...")
    with open(OUTPUT_CSV, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(CSV_HEADER)
        writer.writerows(all_samples)
    print("   ✓ Saved successfully!")
    
    # Cleanup
    extractor.close()
    
    print("\n" + "=" * 60)
    print("  Processing Complete!")
    print("=" * 60)
    print(f"\n   Total samples: {len(all_samples)}")
    print(f"   Total labels: {len(labels)}")
    print(f"   Output file: {OUTPUT_CSV}")
    print(f"\n   Next: Train combined model with train_combined.py")
    print("=" * 60)


if __name__ == "__main__":
    main()
