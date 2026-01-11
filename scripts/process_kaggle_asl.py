#!/usr/bin/env python3
"""
Process Kaggle ASL Dataset (Static Hand Images)
Extracts hand landmarks from images using MediaPipe.
"""

import os
import cv2
import numpy as np
import csv
from pathlib import Path
import urllib.request

# MediaPipe Tasks API
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Configuration
KAGGLE_DATASET_DIR = "/Users/zaranwala/Downloads/asl_dataset"
OUTPUT_CSV = "kaggle_asl_landmarks.csv"
LANDMARK_COUNT = 21

# CSV header
CSV_HEADER = []
for i in range(LANDMARK_COUNT):
    CSV_HEADER.extend([f"x{i}", f"y{i}", f"z{i}"])
CSV_HEADER.append("label")


def setup_hand_landmarker():
    """Initialize MediaPipe Hand Landmarker."""
    model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hand_landmarker.task')
    
    if not os.path.exists(model_path):
        print("📥 Downloading hand_landmarker.task model...")
        model_url = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
        urllib.request.urlretrieve(model_url, model_path)
        print("   ✓ Model downloaded!")
    
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        num_hands=1,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5
    )
    return vision.HandLandmarker.create_from_options(options)


def process_image(detector, image_path: str) -> list:
    """Process a single image and extract hand landmarks."""
    try:
        # Read image
        image = cv2.imread(image_path)
        if image is None:
            return None
        
        # Convert BGR to RGB
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        # Create MediaPipe Image
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_image)
        
        # Detect hands
        result = detector.detect(mp_image)
        
        if not result.hand_landmarks:
            return None
        
        # Extract landmarks from first hand
        landmarks = result.hand_landmarks[0]
        coords = []
        for lm in landmarks:
            coords.extend([lm.x, lm.y, lm.z])
        
        return coords
    except Exception as e:
        return None


def scan_dataset(dataset_dir: str) -> dict:
    """Scan dataset for images organized by label folders."""
    print(f"\n🔍 Scanning Kaggle ASL dataset: {dataset_dir}")
    
    label_images = {}
    dataset_path = Path(dataset_dir)
    
    # Each subfolder is a label (a-z, 0-9)
    for label_dir in sorted(dataset_path.iterdir()):
        if not label_dir.is_dir():
            continue
        
        label = label_dir.name.upper()
        
        # Skip nested asl_dataset folder
        if label.lower() == 'asl_dataset':
            continue
        
        images = []
        for ext in ['*.jpg', '*.jpeg', '*.png', '*.JPG', '*.JPEG', '*.PNG']:
            images.extend(label_dir.glob(ext))
        
        if images:
            label_images[label] = [str(img) for img in images]
    
    # Print summary
    print(f"   Found {len(label_images)} labels")
    total_images = sum(len(v) for v in label_images.values())
    print(f"   Found {total_images} total images")
    
    print(f"\n   Labels and image counts:")
    for label in sorted(label_images.keys()):
        print(f"      {label}: {len(label_images[label])} images")
    
    return label_images


def process_dataset(label_images: dict, detector) -> list:
    """Process all images and extract landmarks."""
    all_samples = []
    total_images = sum(len(v) for v in label_images.values())
    processed = 0
    successful = 0
    
    print(f"\n🎬 Processing {total_images} images...")
    
    for label in sorted(label_images.keys()):
        images = label_images[label]
        label_samples = 0
        
        for image_path in images:
            coords = process_image(detector, image_path)
            processed += 1
            
            if coords:
                sample = coords + [label]
                all_samples.append(sample)
                label_samples += 1
                successful += 1
        
        progress = (processed / total_images) * 100
        print(f"   [{progress:5.1f}%] {label}: {label_samples} samples from {len(images)} images")
    
    print(f"\n   ✓ Successfully extracted {successful}/{total_images} samples ({successful/total_images*100:.1f}%)")
    
    return all_samples


def save_to_csv(samples: list, output_path: str):
    """Save samples to CSV file."""
    print(f"\n💾 Saving {len(samples)} samples to {output_path}...")
    
    with open(output_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(CSV_HEADER)
        writer.writerows(samples)
    
    print(f"   ✓ Saved successfully!")


def main():
    print("=" * 60)
    print("  Kaggle ASL Dataset Processor (Static Hand Images)")
    print("=" * 60)
    
    # Scan dataset
    label_images = scan_dataset(KAGGLE_DATASET_DIR)
    
    if not label_images:
        print("\n❌ No images found in dataset!")
        return
    
    # Initialize MediaPipe
    print("\n🔧 Initializing MediaPipe...")
    detector = setup_hand_landmarker()
    
    # Process images
    samples = process_dataset(label_images, detector)
    
    # Save to CSV
    if samples:
        save_to_csv(samples, OUTPUT_CSV)
    else:
        print("\n❌ No samples extracted!")
        return
    
    # Cleanup
    detector.close()
    
    print("\n" + "=" * 60)
    print("  Processing Complete!")
    print("=" * 60)
    print(f"\n   Total samples: {len(samples)}")
    print(f"   Output file: {OUTPUT_CSV}")
    print(f"\n   Next: Combine with ASL Citizen data and train model")
    print("=" * 60)


if __name__ == "__main__":
    main()
