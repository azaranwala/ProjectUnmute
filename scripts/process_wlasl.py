#!/usr/bin/env python3
"""
Process WLASL Dataset (Word-Level ASL)
Extracts hand landmarks from videos using MediaPipe.
"""

import os
import json
import cv2
import numpy as np
import csv
from pathlib import Path
from collections import defaultdict

# MediaPipe Tasks API
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Configuration
WLASL_DIR = "/Users/zaranwala/Downloads/wlasl_dataset"
WLASL_JSON = os.path.join(WLASL_DIR, "nslt_100.json")  # Top 100 classes
WLASL_CLASS_LIST = os.path.join(WLASL_DIR, "wlasl_class_list.txt")
WLASL_VIDEOS_DIR = os.path.join(WLASL_DIR, "videos")
OUTPUT_CSV = "wlasl_landmarks.csv"
SAMPLES_PER_VIDEO = 15
LANDMARK_COUNT = 21

# CSV header
CSV_HEADER = []
for i in range(LANDMARK_COUNT):
    CSV_HEADER.extend([f"x{i}", f"y{i}", f"z{i}"])
CSV_HEADER.append("label")


def load_class_list():
    """Load class ID to label mapping."""
    class_map = {}
    with open(WLASL_CLASS_LIST, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) == 2:
                class_id = int(parts[0])
                label = parts[1].upper()
                class_map[class_id] = label
    return class_map


def load_video_labels():
    """Load video ID to class ID mapping from JSON."""
    with open(WLASL_JSON, 'r') as f:
        data = json.load(f)
    
    video_labels = {}
    for video_id, info in data.items():
        class_id = info['action'][0]
        video_labels[video_id] = class_id
    
    return video_labels


def setup_hand_landmarker():
    """Initialize MediaPipe Hand Landmarker."""
    model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hand_landmarker.task')
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        num_hands=1,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5
    )
    return vision.HandLandmarker.create_from_options(options)


def extract_from_video(detector, video_path: str, samples_per_video: int = 10) -> list:
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
            result = detector.detect(mp_image)
            
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


def main():
    print("=" * 60)
    print("  WLASL Dataset Processor")
    print("=" * 60)
    
    # Load mappings
    print("\n📂 Loading class mappings...")
    class_map = load_class_list()
    video_labels = load_video_labels()
    print(f"   Classes: {len(class_map)}")
    print(f"   Videos in JSON: {len(video_labels)}")
    
    # Find available videos
    print("\n🔍 Scanning for available videos...")
    videos_dir = Path(WLASL_VIDEOS_DIR)
    available_videos = list(videos_dir.glob("*.mp4"))
    print(f"   Available videos: {len(available_videos)}")
    
    # Match videos to labels
    video_to_label = {}
    for video_path in available_videos:
        video_id = video_path.stem  # filename without extension
        if video_id in video_labels:
            class_id = video_labels[video_id]
            if class_id in class_map:
                label = class_map[class_id]
                video_to_label[str(video_path)] = label
    
    print(f"   Matched videos: {len(video_to_label)}")
    
    # Count per label
    label_counts = defaultdict(int)
    for label in video_to_label.values():
        label_counts[label] += 1
    
    print(f"\n   Labels with videos:")
    for label in sorted(label_counts.keys())[:20]:
        print(f"      {label}: {label_counts[label]} videos")
    if len(label_counts) > 20:
        print(f"      ... and {len(label_counts) - 20} more")
    
    # Initialize MediaPipe
    print("\n🔧 Initializing MediaPipe...")
    detector = setup_hand_landmarker()
    
    # Process videos
    print(f"\n🎬 Processing {len(video_to_label)} videos...")
    all_samples = []
    processed = 0
    label_samples = defaultdict(int)
    
    for video_path, label in sorted(video_to_label.items()):
        samples = extract_from_video(detector, video_path, SAMPLES_PER_VIDEO)
        
        for coords in samples:
            all_samples.append(coords + [label])
            label_samples[label] += 1
        
        processed += 1
        if processed % 100 == 0:
            progress = (processed / len(video_to_label)) * 100
            print(f"   [{progress:5.1f}%] Processed {processed}/{len(video_to_label)} videos, {len(all_samples)} samples")
    
    # Final progress
    print(f"   [100.0%] Processed {processed}/{len(video_to_label)} videos, {len(all_samples)} samples")
    
    # Save to CSV
    print(f"\n💾 Saving {len(all_samples)} samples to {OUTPUT_CSV}...")
    with open(OUTPUT_CSV, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(CSV_HEADER)
        writer.writerows(all_samples)
    print("   ✓ Saved successfully!")
    
    # Print summary
    print("\n📊 Samples per label:")
    for label in sorted(label_samples.keys()):
        print(f"   {label}: {label_samples[label]} samples")
    
    # Cleanup
    detector.close()
    
    print("\n" + "=" * 60)
    print("  Processing Complete!")
    print("=" * 60)
    print(f"\n   Total samples: {len(all_samples)}")
    print(f"   Total labels: {len(label_samples)}")
    print(f"   Output file: {OUTPUT_CSV}")
    print("=" * 60)


if __name__ == "__main__":
    main()
