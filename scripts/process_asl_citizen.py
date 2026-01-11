#!/usr/bin/env python3
"""
ASL Citizen Dataset Processor

Extracts hand landmarks from ASL Citizen videos using MediaPipe
and saves them to CSV for model training.

Usage:
    python3 process_asl_citizen.py

Requirements:
    - ASL Citizen dataset downloaded (run download_asl_citizen.py first)
    - mediapipe, opencv-python, pandas
"""

import cv2
import os
import sys
import json
import csv
import numpy as np
from pathlib import Path
from collections import defaultdict
import time

# MediaPipe Tasks API
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Configuration
DATASET_DIR = "asl_citizen_dataset"
OUTPUT_CSV = "asl_citizen_landmarks.csv"
SAMPLES_PER_VIDEO = 30  # Extract more frames per video for better coverage
LANDMARK_COUNT = 21
MAX_VIDEOS_PER_SIGN = None  # Use ALL available videos per sign
MAX_SIGNS = 50  # Target: 50 signs with >80% accuracy

# ASL Citizen specific paths
ASL_CITIZEN_VIDEOS_DIR = "../asl_citizen_dataset/ASL_Citizen/videos"
ASL_CITIZEN_TRAIN_CSV = "../asl_citizen_dataset/ASL_Citizen/splits/train.csv"
ASL_CITIZEN_VAL_CSV = "../asl_citizen_dataset/ASL_Citizen/splits/val.csv"
ASL_CITIZEN_TEST_CSV = "../asl_citizen_dataset/ASL_Citizen/splits/test.csv"

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
        """Initialize MediaPipe Hand Landmarker."""
        model_path = "hand_landmarker.task"
        
        # Download model if needed
        if not os.path.exists(model_path):
            print("📥 Downloading hand_landmarker.task model...")
            import urllib.request
            model_url = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
            urllib.request.urlretrieve(model_url, model_path)
            print("   ✓ Model downloaded!")
        
        base_options = python.BaseOptions(model_asset_path=model_path)
        options = vision.HandLandmarkerOptions(
            base_options=base_options,
            num_hands=2,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5
        )
        self.detector = vision.HandLandmarker.create_from_options(options)
        
    def extract_from_video(self, video_path: str, num_samples: int = 10) -> list:
        """Extract landmark samples from a video file."""
        samples = []
        
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return samples
        
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if total_frames == 0:
            cap.release()
            return samples
        
        # Sample frames evenly throughout video
        frame_indices = np.linspace(0, total_frames - 1, num_samples, dtype=int)
        
        for frame_idx in frame_indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = cap.read()
            if not ret:
                continue
            
            # Convert to RGB
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            
            # Detect hands
            try:
                result = self.detector.detect(mp_image)
                
                if result.hand_landmarks:
                    for hand_landmarks in result.hand_landmarks:
                        # Extract coordinates
                        coords = []
                        for lm in hand_landmarks:
                            coords.extend([lm.x, lm.y, lm.z])
                        samples.append(coords)
            except Exception as e:
                continue
        
        cap.release()
        return samples
    
    def close(self):
        if self.detector:
            self.detector.close()


def find_videos_and_labels(dataset_dir: str) -> dict:
    """Find all videos and their labels from ASL Citizen CSV metadata."""
    print("\n🔍 Scanning ASL Citizen dataset for videos and labels...")
    
    sign_videos = defaultdict(list)
    videos_dir = Path(ASL_CITIZEN_VIDEOS_DIR)
    
    # Read from all split CSVs (train, val, test)
    csv_files = [ASL_CITIZEN_TRAIN_CSV, ASL_CITIZEN_VAL_CSV, ASL_CITIZEN_TEST_CSV]
    
    for csv_path in csv_files:
        if not os.path.exists(csv_path):
            print(f"   ⚠️  CSV not found: {csv_path}")
            continue
            
        try:
            with open(csv_path, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    # ASL Citizen format: Participant ID, Video file, Gloss, ASL-LEX Code
                    gloss = row.get('Gloss', '').strip()
                    video_file = row.get('Video file', '').strip()
                    
                    if gloss and video_file:
                        label = gloss.upper()
                        video_path = videos_dir / video_file
                        
                        if video_path.exists():
                            sign_videos[label].append(str(video_path))
            
            split_name = Path(csv_path).stem
            print(f"   ✓ Loaded {split_name}.csv")
        except Exception as e:
            print(f"   ❌ Error reading {csv_path}: {e}")
            continue
    
    print(f"\n   Found {len(sign_videos)} unique signs")
    total_videos = sum(len(v) for v in sign_videos.values())
    print(f"   Found {total_videos} total videos with labels")
    
    # Show top signs by video count
    sorted_signs = sorted(sign_videos.items(), key=lambda x: len(x[1]), reverse=True)
    print(f"\n   Top 10 signs by video count:")
    for sign, videos in sorted_signs[:10]:
        print(f"      {sign}: {len(videos)} videos")
    
    return dict(sign_videos)


def process_dataset(sign_videos: dict, extractor: VideoLandmarkExtractor, 
                    max_signs: int = None, max_videos_per_sign: int = None) -> list:
    """Process videos and extract landmarks."""
    all_samples = []
    
    # Limit signs if specified
    signs_to_process = list(sign_videos.keys())
    if max_signs:
        signs_to_process = signs_to_process[:max_signs]
    
    print(f"\n🎬 Processing {len(signs_to_process)} signs...")
    
    for sign_idx, sign in enumerate(signs_to_process):
        videos = sign_videos[sign]
        
        # Limit videos per sign
        if max_videos_per_sign:
            videos = videos[:max_videos_per_sign]
        
        sign_samples = []
        
        for video_path in videos:
            samples = extractor.extract_from_video(video_path, SAMPLES_PER_VIDEO)
            for sample in samples:
                sample.append(sign)  # Add label
                sign_samples.append(sample)
        
        all_samples.extend(sign_samples)
        
        # Progress update
        progress = (sign_idx + 1) / len(signs_to_process) * 100
        print(f"   [{progress:5.1f}%] {sign}: {len(sign_samples)} samples from {len(videos)} videos")
    
    return all_samples


def save_to_csv(samples: list, output_file: str):
    """Save extracted samples to CSV."""
    print(f"\n💾 Saving {len(samples)} samples to {output_file}...")
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(CSV_HEADER)
        writer.writerows(samples)
    
    print(f"   ✓ Saved successfully!")


def main():
    print("=" * 60)
    print("  ASL Citizen Dataset Processor")
    print("=" * 60)
    
    # Check dataset exists
    if not os.path.exists(DATASET_DIR):
        print(f"\n❌ Dataset not found: {DATASET_DIR}/")
        print("   Please run: python3 download_asl_citizen.py")
        return
    
    # Find videos and labels
    sign_videos = find_videos_and_labels(DATASET_DIR)
    
    if not sign_videos:
        print("\n❌ No videos found in dataset!")
        print("   Please check the dataset structure.")
        return
    
    # Show statistics
    print(f"\n📊 Dataset Statistics:")
    print(f"   Signs: {len(sign_videos)}")
    print(f"   Total videos: {sum(len(v) for v in sign_videos.values())}")
    
    # Show sample signs
    print(f"\n   Sample signs:")
    for i, (sign, videos) in enumerate(list(sign_videos.items())[:10]):
        print(f"      {sign}: {len(videos)} videos")
    if len(sign_videos) > 10:
        print(f"      ... and {len(sign_videos) - 10} more")
    
    # Confirm processing
    print(f"\n⚙️  Processing Configuration:")
    print(f"   Max signs to process: {MAX_SIGNS or 'All'}")
    print(f"   Max videos per sign: {MAX_VIDEOS_PER_SIGN or 'All'}")
    print(f"   Samples per video: {SAMPLES_PER_VIDEO}")
    
    estimated_samples = min(len(sign_videos), MAX_SIGNS or len(sign_videos)) * \
                       (MAX_VIDEOS_PER_SIGN or 50) * SAMPLES_PER_VIDEO
    print(f"   Estimated samples: ~{estimated_samples}")
    
    # Initialize extractor
    print("\n🔧 Initializing MediaPipe...")
    extractor = VideoLandmarkExtractor()
    
    # Process videos
    start_time = time.time()
    samples = process_dataset(
        sign_videos, 
        extractor,
        max_signs=MAX_SIGNS,
        max_videos_per_sign=MAX_VIDEOS_PER_SIGN
    )
    elapsed = time.time() - start_time
    
    # Cleanup
    extractor.close()
    
    # Save results
    if samples:
        save_to_csv(samples, OUTPUT_CSV)
        
        # Summary
        print("\n" + "=" * 60)
        print("  Processing Complete!")
        print("=" * 60)
        print(f"\n   Total samples: {len(samples)}")
        print(f"   Processing time: {elapsed:.1f} seconds")
        print(f"   Output file: {OUTPUT_CSV}")
        print(f"\n   Next step: Train model with:")
        print(f"   python3 train_asl_citizen.py")
    else:
        print("\n❌ No samples extracted!")
    
    print("\n" + "=" * 60)


if __name__ == "__main__":
    main()
