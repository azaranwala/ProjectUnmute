#!/usr/bin/env python3
"""
Train ASL Model using ALL available datasets combined:
- WLASL Full (112,853 samples, 2000 classes)
- ASL Citizen (25,869 samples, 50 classes)
- Kaggle ASL Alphabet (1,622 samples, 36 classes)
- Combined dataset (11,315 samples, 76 classes)
- Custom collected (1,200 samples, 12 classes)

This creates a comprehensive model with maximum coverage.
"""

import os
import json
import csv
import numpy as np
from collections import defaultdict
from pathlib import Path

# Configuration
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_MODEL_JSON = os.path.join(BASE_DIR, "../ASLModelData_combined.json")
MIN_SAMPLES_PER_CLASS = 5  # Minimum samples to include a class

# Dataset files
DATASETS = [
    {
        "name": "WLASL Full",
        "file": "wlasl_full_landmarks.csv",
        "priority": 1,  # Lower = higher priority for duplicate classes
    },
    {
        "name": "ASL Citizen",
        "file": "asl_citizen_landmarks.csv",
        "priority": 2,
    },
    {
        "name": "Combined",
        "file": "combined_asl_landmarks.csv",
        "priority": 3,
    },
    {
        "name": "Kaggle ASL",
        "file": "kaggle_asl_landmarks.csv",
        "priority": 4,
    },
    {
        "name": "Custom ASL",
        "file": "asl_landmarks.csv",
        "priority": 5,
    },
    {
        "name": "Numbers",
        "file": "number_landmarks.csv",
        "priority": 6,
    },
]

# Class name normalization mapping
CLASS_NORMALIZATION = {
    # Normalize variations to standard names
    "THANKYOU": "THANK_YOU",
    "THANK YOU": "THANK_YOU",
    "ILOVEYOU": "I_LOVE_YOU",
    "I LOVE YOU": "I_LOVE_YOU",
    # Numbered variants - keep the base form
    "DRINK1": "DRINK",
    "COOL3": "COOL",
    "HOW1": "HOW",
    "WHAT1": "WHAT",
    "WANT2": "WANT",
    "WALK2": "WALK",
    "TEACH1": "TEACH",
    "GREET1": "GREET",
    "JUICE1": "JUICE",
    "KNIGHT1": "KNIGHT",
    "BACKPACK1": "BACKPACK",
    "EMPTY2": "EMPTY",
    "STAND1": "STAND",
    "WILLGO": "WILL_GO",
}


def normalize_class_name(name):
    """Normalize class names for consistency."""
    name = name.strip().upper().replace(" ", "_")
    return CLASS_NORMALIZATION.get(name, name)


def load_csv_dataset(filepath):
    """Load landmarks from CSV file."""
    samples_by_class = defaultdict(list)
    
    if not os.path.exists(filepath):
        print(f"   ⚠️ File not found: {filepath}")
        return samples_by_class
    
    try:
        with open(filepath, 'r') as f:
            reader = csv.reader(f)
            header = next(reader)  # Skip header
            
            # Find label column (usually last)
            label_idx = -1
            for i, col in enumerate(header):
                if col.lower() == 'label':
                    label_idx = i
                    break
            
            if label_idx == -1:
                label_idx = len(header) - 1
            
            for row in reader:
                if len(row) < 64:  # Need at least 63 coords + label
                    continue
                
                try:
                    # Extract coordinates (first 63 columns)
                    coords = [float(row[i]) for i in range(63)]
                    label = normalize_class_name(row[label_idx])
                    
                    # Skip invalid labels
                    if not label or label.startswith('-') or label.replace('.', '').replace('-', '').isdigit():
                        continue
                    
                    samples_by_class[label].append(coords)
                except (ValueError, IndexError):
                    continue
    
    except Exception as e:
        print(f"   ⚠️ Error reading {filepath}: {e}")
    
    return samples_by_class


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


def train_centroid_model(samples_by_class, min_samples=5):
    """Train centroid-based classifier."""
    print("\n🧠 Training centroid model...")
    
    # Filter classes with minimum samples
    valid_classes = {k: v for k, v in samples_by_class.items() if len(v) >= min_samples}
    print(f"   Classes with >= {min_samples} samples: {len(valid_classes)}")
    
    # Calculate centroids
    centroids = {}
    classes = sorted(valid_classes.keys())
    
    total_samples = 0
    for cls in classes:
        samples = valid_classes[cls]
        # Convert to wrist-relative
        processed = []
        for s in samples:
            wr = make_wrist_relative(s)
            if wr:
                processed.append(wr)
        
        if processed:
            centroid = np.mean(processed, axis=0).tolist()
            centroids[cls] = centroid
            total_samples += len(processed)
    
    # Identity scaling (handled in Swift)
    scaler_mean = [0.0] * 63
    scaler_scale = [1.0] * 63
    
    print(f"   Final classes: {len(centroids)}")
    print(f"   Total samples used: {total_samples}")
    
    return {
        'classes': list(centroids.keys()),
        'scaler_mean': scaler_mean,
        'scaler_scale': scaler_scale,
        'centroids': centroids
    }


def main():
    print("=" * 70)
    print("  Combined ASL Model Trainer")
    print("  Merging ALL available datasets")
    print("=" * 70)
    
    # Load all datasets
    all_samples = defaultdict(list)
    dataset_stats = []
    
    for dataset in DATASETS:
        name = dataset["name"]
        filepath = os.path.join(BASE_DIR, dataset["file"])
        
        print(f"\n📂 Loading {name}...")
        samples = load_csv_dataset(filepath)
        
        if samples:
            total = sum(len(v) for v in samples.values())
            classes = len(samples)
            print(f"   ✓ Loaded {total:,} samples across {classes} classes")
            dataset_stats.append((name, total, classes))
            
            # Merge samples
            for cls, coords_list in samples.items():
                all_samples[cls].extend(coords_list)
        else:
            print(f"   ✗ No samples loaded")
    
    # Print merge stats
    print("\n" + "=" * 70)
    print("  Dataset Summary")
    print("=" * 70)
    for name, total, classes in dataset_stats:
        print(f"   {name:20} | {total:>8,} samples | {classes:>5} classes")
    
    total_raw = sum(len(v) for v in all_samples.values())
    print(f"\n   {'MERGED TOTAL':20} | {total_raw:>8,} samples | {len(all_samples):>5} classes")
    
    # Show class distribution
    print("\n📊 Class distribution (top 20 by sample count):")
    sorted_classes = sorted(all_samples.items(), key=lambda x: -len(x[1]))
    for cls, samples in sorted_classes[:20]:
        print(f"   {cls:20} | {len(samples):>6} samples")
    
    print(f"\n   ... and {len(sorted_classes) - 20} more classes")
    
    # Show classes with few samples
    low_sample_classes = [(c, len(s)) for c, s in sorted_classes if len(s) < MIN_SAMPLES_PER_CLASS]
    if low_sample_classes:
        print(f"\n⚠️ Classes with < {MIN_SAMPLES_PER_CLASS} samples (will be excluded): {len(low_sample_classes)}")
        for cls, count in low_sample_classes[:10]:
            print(f"   {cls}: {count}")
    
    # Train model
    model_data = train_centroid_model(all_samples, MIN_SAMPLES_PER_CLASS)
    
    # Save model
    print(f"\n💾 Saving model to {OUTPUT_MODEL_JSON}...")
    with open(OUTPUT_MODEL_JSON, 'w') as f:
        json.dump(model_data, f)
    
    file_size = os.path.getsize(OUTPUT_MODEL_JSON) / 1024 / 1024
    print(f"   ✓ Saved ({file_size:.2f} MB)")
    
    # Print final summary
    print("\n" + "=" * 70)
    print("  Training Complete!")
    print("=" * 70)
    print(f"\n   Final model:")
    print(f"   - Classes: {len(model_data['classes'])}")
    print(f"   - Output: {OUTPUT_MODEL_JSON}")
    
    # Show sample of final classes
    print(f"\n   Sample classes (alphabetical):")
    for cls in sorted(model_data['classes'])[:30]:
        print(f"      {cls}")
    print(f"      ... ({len(model_data['classes']) - 30} more)")
    
    # Category breakdown
    letters = [c for c in model_data['classes'] if len(c) == 1 and c.isalpha()]
    numbers = [c for c in model_data['classes'] if c.isdigit() or c in ['ZERO', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE']]
    words = [c for c in model_data['classes'] if c not in letters and c not in numbers]
    
    print(f"\n   Category breakdown:")
    print(f"   - Letters: {len(letters)}")
    print(f"   - Numbers: {len(numbers)}")
    print(f"   - Words: {len(words)}")
    
    print("\n" + "=" * 70)
    print("   To use in iOS app, run:")
    print(f"   cp ASLModelData_combined.json '../ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute/ASLModelData.json'")
    print("=" * 70)


if __name__ == "__main__":
    main()
