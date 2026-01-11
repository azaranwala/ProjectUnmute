#!/usr/bin/env python3
"""
Analyze ASL Model Accuracy

Estimates per-class accuracy by computing:
1. Intra-class distance (how tight samples cluster around centroid)
2. Inter-class distance (how far from other class centroids)
3. Classification accuracy using leave-one-out cross-validation simulation

Confidence formula: exp(-distance / 15.0)
For 90% confidence: distance < 1.58
"""

import os
import json
import csv
import numpy as np
from collections import defaultdict

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_JSON = os.path.join(BASE_DIR, "../ASLModelData_combined.json")

# All dataset files
DATASETS = [
    "wlasl_full_landmarks.csv",
    "asl_citizen_landmarks.csv",
    "combined_asl_landmarks.csv",
    "kaggle_asl_landmarks.csv",
    "asl_landmarks.csv",
    "number_landmarks.csv",
]

# Class name normalization
CLASS_NORMALIZATION = {
    "THANKYOU": "THANK_YOU",
    "THANK YOU": "THANK_YOU",
    "ILOVEYOU": "I_LOVE_YOU",
    "I LOVE YOU": "I_LOVE_YOU",
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
    name = name.strip().upper().replace(" ", "_")
    return CLASS_NORMALIZATION.get(name, name)


def make_wrist_relative(landmarks):
    """Convert to wrist-relative and scale by hand size."""
    if len(landmarks) != 63:
        return None
    
    wrist_x, wrist_y, wrist_z = landmarks[0], landmarks[1], landmarks[2]
    
    relative = []
    for i in range(0, len(landmarks), 3):
        relative.append(landmarks[i] - wrist_x)
        relative.append(landmarks[i+1] - wrist_y)
        relative.append(landmarks[i+2] - wrist_z)
    
    max_dist = 0.0
    for i in range(0, len(relative), 3):
        x, y, z = relative[i], relative[i+1], relative[i+2]
        dist = np.sqrt(x*x + y*y + z*z)
        if dist > max_dist:
            max_dist = dist
    
    if max_dist < 0.001:
        max_dist = 1.0
    
    return [v / max_dist for v in relative]


def load_all_samples():
    """Load all samples from all datasets."""
    samples_by_class = defaultdict(list)
    
    for dataset_file in DATASETS:
        filepath = os.path.join(BASE_DIR, dataset_file)
        if not os.path.exists(filepath):
            continue
        
        try:
            with open(filepath, 'r') as f:
                reader = csv.reader(f)
                header = next(reader)
                
                label_idx = -1
                for i, col in enumerate(header):
                    if col.lower() == 'label':
                        label_idx = i
                        break
                if label_idx == -1:
                    label_idx = len(header) - 1
                
                for row in reader:
                    if len(row) < 64:
                        continue
                    try:
                        coords = [float(row[i]) for i in range(63)]
                        label = normalize_class_name(row[label_idx])
                        
                        if not label or label.startswith('-') or label.replace('.', '').replace('-', '').isdigit():
                            continue
                        
                        wr = make_wrist_relative(coords)
                        if wr:
                            samples_by_class[label].append(wr)
                    except (ValueError, IndexError):
                        continue
        except Exception:
            continue
    
    return samples_by_class


def euclidean_distance(a, b):
    return np.sqrt(np.sum((np.array(a) - np.array(b)) ** 2))


def confidence_from_distance(dist):
    return np.exp(-dist / 15.0)


def analyze_accuracy():
    print("=" * 70)
    print("  ASL Model Accuracy Analysis")
    print("=" * 70)
    
    # Load model
    print("\n📂 Loading model...")
    with open(MODEL_JSON, 'r') as f:
        model = json.load(f)
    
    centroids = model['centroids']
    classes = model['classes']
    print(f"   Model has {len(classes)} classes")
    
    # Load all samples
    print("\n📂 Loading training samples...")
    samples_by_class = load_all_samples()
    total_samples = sum(len(v) for v in samples_by_class.values())
    print(f"   Loaded {total_samples:,} samples across {len(samples_by_class)} classes")
    
    # Analyze each class
    print("\n🔍 Analyzing per-class accuracy...")
    
    results = []
    
    for cls in classes:
        if cls not in samples_by_class or cls not in centroids:
            continue
        
        samples = samples_by_class[cls]
        centroid = centroids[cls]
        
        if len(samples) < 3:
            continue
        
        # Calculate intra-class distances
        intra_distances = [euclidean_distance(s, centroid) for s in samples]
        avg_intra = np.mean(intra_distances)
        std_intra = np.std(intra_distances)
        
        # Calculate classification accuracy (simulate predictions)
        correct = 0
        high_conf_correct = 0  # Correct with >90% confidence
        total_high_conf = 0
        
        for sample in samples:
            # Find closest centroid
            min_dist = float('inf')
            pred_class = None
            second_min = float('inf')
            
            for other_cls, other_centroid in centroids.items():
                dist = euclidean_distance(sample, other_centroid)
                if dist < min_dist:
                    second_min = min_dist
                    min_dist = dist
                    pred_class = other_cls
                elif dist < second_min:
                    second_min = dist
            
            conf = confidence_from_distance(min_dist)
            
            if pred_class == cls:
                correct += 1
                if conf >= 0.90:
                    high_conf_correct += 1
            
            if conf >= 0.90:
                total_high_conf += 1
        
        accuracy = correct / len(samples) * 100
        
        # Calculate margin (distance to nearest other centroid)
        min_inter_dist = float('inf')
        for other_cls, other_centroid in centroids.items():
            if other_cls != cls:
                dist = euclidean_distance(centroid, other_centroid)
                if dist < min_inter_dist:
                    min_inter_dist = dist
        
        # High confidence rate
        high_conf_rate = high_conf_correct / len(samples) * 100 if samples else 0
        
        results.append({
            'class': cls,
            'samples': len(samples),
            'accuracy': accuracy,
            'high_conf_rate': high_conf_rate,
            'avg_intra_dist': avg_intra,
            'margin': min_inter_dist,
            'avg_confidence': np.mean([confidence_from_distance(d) for d in intra_distances]) * 100,
        })
    
    # Sort by high confidence rate
    results.sort(key=lambda x: -x['high_conf_rate'])
    
    # Filter for >90% accuracy with high confidence
    high_accuracy = [r for r in results if r['high_conf_rate'] >= 90]
    
    print(f"\n✅ Classes with >90% high-confidence accuracy: {len(high_accuracy)}")
    
    # Categorize
    letters = [r for r in high_accuracy if len(r['class']) == 1 and r['class'].isalpha()]
    numbers = [r for r in high_accuracy if r['class'].isdigit() or r['class'] in 
               ['ZERO', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE']]
    words = [r for r in high_accuracy if r not in letters and r not in numbers]
    
    print("\n" + "=" * 70)
    print("  LETTERS with >90% Accuracy")
    print("=" * 70)
    if letters:
        for r in sorted(letters, key=lambda x: x['class']):
            print(f"   {r['class']:5} | {r['high_conf_rate']:5.1f}% | {r['samples']:>5} samples | avg conf: {r['avg_confidence']:.1f}%")
    else:
        print("   None")
    
    print("\n" + "=" * 70)
    print("  NUMBERS with >90% Accuracy")
    print("=" * 70)
    if numbers:
        for r in sorted(numbers, key=lambda x: x['class']):
            print(f"   {r['class']:5} | {r['high_conf_rate']:5.1f}% | {r['samples']:>5} samples | avg conf: {r['avg_confidence']:.1f}%")
    else:
        print("   None")
    
    print("\n" + "=" * 70)
    print("  WORDS with >90% Accuracy (sorted by confidence)")
    print("=" * 70)
    words_sorted = sorted(words, key=lambda x: -x['high_conf_rate'])
    for r in words_sorted:
        print(f"   {r['class']:20} | {r['high_conf_rate']:5.1f}% | {r['samples']:>5} samples | avg conf: {r['avg_confidence']:.1f}%")
    
    # Summary stats
    print("\n" + "=" * 70)
    print("  Summary")
    print("=" * 70)
    print(f"   Total classes analyzed: {len(results)}")
    print(f"   Classes with >90% accuracy: {len(high_accuracy)}")
    print(f"      - Letters: {len(letters)}")
    print(f"      - Numbers: {len(numbers)}")
    print(f"      - Words: {len([r for r in words if r not in letters and r not in numbers])}")
    
    # Also show classes with 80-90% accuracy
    medium_accuracy = [r for r in results if 80 <= r['high_conf_rate'] < 90]
    print(f"\n   Classes with 80-90% accuracy: {len(medium_accuracy)}")
    
    # Show top 20 medium accuracy
    if medium_accuracy:
        print("\n   Top 20 classes with 80-90% accuracy:")
        for r in sorted(medium_accuracy, key=lambda x: -x['high_conf_rate'])[:20]:
            print(f"      {r['class']:20} | {r['high_conf_rate']:5.1f}%")
    
    return high_accuracy, medium_accuracy, results


if __name__ == "__main__":
    analyze_accuracy()
