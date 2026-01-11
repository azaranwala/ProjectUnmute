#!/usr/bin/env python3
"""
Train ASL Model using ALL WLASL videos from wlasl_processed_data folder.
Processes videos, extracts landmarks, and trains centroid-based classifier.
"""

import os
import json
import cv2
import numpy as np
import csv
from pathlib import Path
from collections import defaultdict
import pickle

# MediaPipe Tasks API
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Configuration - Using LOCAL wlasl_processed_data folder
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WLASL_DIR = os.path.join(BASE_DIR, "wlasl_processed_data")
WLASL_JSON = os.path.join(WLASL_DIR, "nslt_2000.json")  # Full 2000 classes
WLASL_CLASS_LIST = os.path.join(WLASL_DIR, "wlasl_class_list.txt")
WLASL_VIDEOS_DIR = os.path.join(WLASL_DIR, "videos")

OUTPUT_CSV = os.path.join(BASE_DIR, "wlasl_full_landmarks.csv")
OUTPUT_MODEL_JSON = os.path.join(BASE_DIR, "../ASLModelData_expanded.json")
SAMPLES_PER_VIDEO = 15
LANDMARK_COUNT = 21
MIN_SAMPLES_PER_CLASS = 10  # Minimum samples needed to include a class

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
                label = parts[1].upper().replace(' ', '_')
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
    model_path = os.path.join(BASE_DIR, 'hand_landmarker.task')
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        num_hands=1,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5
    )
    return vision.HandLandmarker.create_from_options(options)


def extract_from_video(detector, video_path: str, samples_per_video: int = 15) -> list:
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


def make_wrist_relative(landmarks):
    """Convert landmarks to wrist-relative coordinates and scale by hand size."""
    if len(landmarks) != 63:
        return None
    
    # Extract wrist position
    wrist_x, wrist_y, wrist_z = landmarks[0], landmarks[1], landmarks[2]
    
    # Make wrist-relative
    relative = []
    for i in range(0, len(landmarks), 3):
        relative.append(landmarks[i] - wrist_x)
        relative.append(landmarks[i+1] - wrist_y)
        relative.append(landmarks[i+2] - wrist_z)
    
    # Scale by hand size (max distance from wrist)
    max_dist = 0.0
    for i in range(0, len(relative), 3):
        x, y, z = relative[i], relative[i+1], relative[i+2]
        dist = np.sqrt(x*x + y*y + z*z)
        if dist > max_dist:
            max_dist = dist
    
    if max_dist < 0.001:
        max_dist = 1.0
    
    scaled = [v / max_dist for v in relative]
    return scaled


def train_centroid_model(samples_by_class, min_samples=10):
    """Train centroid-based classifier."""
    print("\n🧠 Training centroid model...")
    
    # Filter classes with minimum samples
    valid_classes = {k: v for k, v in samples_by_class.items() if len(v) >= min_samples}
    print(f"   Classes with >= {min_samples} samples: {len(valid_classes)}")
    
    # Calculate centroids
    centroids = {}
    classes = sorted(valid_classes.keys())
    
    all_samples = []
    for cls in classes:
        samples = valid_classes[cls]
        # Convert to wrist-relative
        processed = []
        for s in samples:
            wr = make_wrist_relative(s)
            if wr:
                processed.append(wr)
                all_samples.append(wr)
        
        if processed:
            centroid = np.mean(processed, axis=0).tolist()
            centroids[cls] = centroid
    
    # For this model, we use identity scaling (handled in Swift)
    # The Swift code does wrist-relative + hand-size scaling already
    scaler_mean = [0.0] * 63
    scaler_scale = [1.0] * 63
    
    print(f"   Final classes: {len(centroids)}")
    print(f"   Total samples used: {len(all_samples)}")
    
    return {
        'classes': list(centroids.keys()),
        'scaler_mean': scaler_mean,
        'scaler_scale': scaler_scale,
        'centroids': centroids
    }


def main():
    print("=" * 70)
    print("  WLASL Full Dataset Trainer")
    print("  Processing ALL videos from wlasl_processed_data")
    print("=" * 70)
    
    # Verify paths
    print(f"\n📂 Paths:")
    print(f"   WLASL Dir: {WLASL_DIR}")
    print(f"   Videos: {WLASL_VIDEOS_DIR}")
    print(f"   JSON: {WLASL_JSON}")
    
    if not os.path.exists(WLASL_DIR):
        print(f"❌ ERROR: WLASL directory not found: {WLASL_DIR}")
        return
    
    # Load mappings
    print("\n📂 Loading class mappings...")
    class_map = load_class_list()
    video_labels = load_video_labels()
    print(f"   Classes in list: {len(class_map)}")
    print(f"   Videos in JSON: {len(video_labels)}")
    
    # Find available videos
    print("\n🔍 Scanning for available videos...")
    videos_dir = Path(WLASL_VIDEOS_DIR)
    available_videos = list(videos_dir.glob("*.mp4"))
    print(f"   Available videos: {len(available_videos)}")
    
    # Match videos to labels
    video_to_label = {}
    for video_path in available_videos:
        video_id = video_path.stem
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
    
    print(f"\n   Unique labels: {len(label_counts)}")
    print(f"   Top 10 labels by video count:")
    sorted_labels = sorted(label_counts.items(), key=lambda x: -x[1])
    for label, count in sorted_labels[:10]:
        print(f"      {label}: {count} videos")
    
    # Initialize MediaPipe
    print("\n🔧 Initializing MediaPipe...")
    detector = setup_hand_landmarker()
    
    # Process videos
    print(f"\n🎬 Processing {len(video_to_label)} videos...")
    samples_by_class = defaultdict(list)
    processed = 0
    failed = 0
    
    for video_path, label in sorted(video_to_label.items()):
        samples = extract_from_video(detector, video_path, SAMPLES_PER_VIDEO)
        
        if samples:
            for coords in samples:
                samples_by_class[label].append(coords)
        else:
            failed += 1
        
        processed += 1
        if processed % 500 == 0:
            progress = (processed / len(video_to_label)) * 100
            total_samples = sum(len(v) for v in samples_by_class.values())
            print(f"   [{progress:5.1f}%] Processed {processed}/{len(video_to_label)} videos, "
                  f"{len(samples_by_class)} classes, {total_samples} samples")
    
    # Final stats
    total_samples = sum(len(v) for v in samples_by_class.values())
    print(f"\n   ✓ Processing complete!")
    print(f"   Videos processed: {processed}")
    print(f"   Videos failed: {failed}")
    print(f"   Classes found: {len(samples_by_class)}")
    print(f"   Total samples: {total_samples}")
    
    # Save landmarks CSV
    print(f"\n💾 Saving landmarks to {OUTPUT_CSV}...")
    with open(OUTPUT_CSV, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(CSV_HEADER)
        for label, samples in samples_by_class.items():
            for coords in samples:
                writer.writerow(coords + [label])
    print(f"   ✓ Saved {total_samples} samples")
    
    # Train model
    model_data = train_centroid_model(samples_by_class, MIN_SAMPLES_PER_CLASS)
    
    # Save model JSON
    print(f"\n💾 Saving model to {OUTPUT_MODEL_JSON}...")
    with open(OUTPUT_MODEL_JSON, 'w') as f:
        json.dump(model_data, f)
    print(f"   ✓ Saved model with {len(model_data['classes'])} classes")
    
    # Print final class list
    print(f"\n📋 Final classes ({len(model_data['classes'])}):")
    for i, cls in enumerate(sorted(model_data['classes'])):
        if i < 50 or i >= len(model_data['classes']) - 5:
            print(f"   {cls}")
        elif i == 50:
            print(f"   ... ({len(model_data['classes']) - 55} more) ...")
    
    # Cleanup
    detector.close()
    
    print("\n" + "=" * 70)
    print("  Training Complete!")
    print("=" * 70)
    print(f"\n   Output files:")
    print(f"   - {OUTPUT_CSV}")
    print(f"   - {OUTPUT_MODEL_JSON}")
    print(f"\n   To use in iOS app, copy ASLModelData_expanded.json to:")
    print(f"   ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute/ASLModelData.json")
    print("=" * 70)


if __name__ == "__main__":
    main()
