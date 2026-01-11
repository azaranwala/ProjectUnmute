#!/usr/bin/env python3
"""
Find the best ASL signs based on:
1. High number of training samples
2. High accuracy/confidence
3. No overlap with other signs (unique hand shapes)
"""

import os
import json
import csv
import numpy as np
from collections import defaultdict

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Load all datasets
DATASETS = [
    "wlasl_full_landmarks.csv",
    "asl_citizen_landmarks.csv", 
    "combined_asl_landmarks.csv",
    "kaggle_asl_landmarks.csv",
    "asl_landmarks.csv",
    "number_landmarks.csv",
]

CLASS_NORMALIZATION = {
    "THANKYOU": "THANK_YOU", "THANK YOU": "THANK_YOU",
    "ILOVEYOU": "I_LOVE_YOU", "DRINK1": "DRINK", "HOW1": "HOW",
    "WHAT1": "WHAT", "WANT2": "WANT", "WALK2": "WALK", "TEACH1": "TEACH",
    "STAND1": "STAND", "GRANDPA": "GRANDFATHER", "MARRIAGE": "MARRY", "DIVORCED": "DIVORCE",
}

def normalize_class_name(name):
    name = name.strip().upper().replace(" ", "_")
    return CLASS_NORMALIZATION.get(name, name)

def make_wrist_relative(landmarks):
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

def load_all_data():
    samples_by_class = defaultdict(list)
    for dataset_file in DATASETS:
        filepath = os.path.join(BASE_DIR, dataset_file)
        if not os.path.exists(filepath):
            continue
        try:
            with open(filepath, 'r') as f:
                reader = csv.reader(f)
                header = next(reader)
                label_idx = len(header) - 1
                for i, col in enumerate(header):
                    if col.lower() == 'label':
                        label_idx = i
                        break
                for row in reader:
                    if len(row) < 64:
                        continue
                    try:
                        label = normalize_class_name(row[label_idx])
                        if not label or label.startswith('-'):
                            continue
                        coords = [float(row[i]) for i in range(63)]
                        wr = make_wrist_relative(coords)
                        if wr:
                            samples_by_class[label].append(wr)
                    except:
                        continue
        except:
            continue
    return samples_by_class

def euclidean_distance(a, b):
    return np.sqrt(np.sum((np.array(a) - np.array(b)) ** 2))

def analyze_signs(samples_by_class, min_samples=30):
    """Analyze signs for quality metrics."""
    print("Calculating centroids and metrics...")
    
    # Calculate centroids
    centroids = {}
    for cls, samples in samples_by_class.items():
        if len(samples) >= min_samples:
            centroids[cls] = np.mean(samples, axis=0).tolist()
    
    results = []
    
    for cls in centroids:
        samples = samples_by_class[cls]
        centroid = centroids[cls]
        
        # 1. Sample count
        sample_count = len(samples)
        
        # 2. Intra-class tightness (lower = tighter cluster = more consistent)
        intra_distances = [euclidean_distance(s, centroid) for s in samples]
        avg_intra = np.mean(intra_distances)
        std_intra = np.std(intra_distances)
        
        # 3. Classification accuracy
        correct = 0
        for sample in samples:
            min_dist = float('inf')
            pred = None
            for other_cls, other_centroid in centroids.items():
                dist = euclidean_distance(sample, other_centroid)
                if dist < min_dist:
                    min_dist = dist
                    pred = other_cls
            if pred == cls:
                correct += 1
        accuracy = correct / len(samples) * 100
        
        # 4. Margin to nearest other class (higher = more unique)
        min_inter_dist = float('inf')
        nearest_class = ""
        for other_cls, other_centroid in centroids.items():
            if other_cls != cls:
                dist = euclidean_distance(centroid, other_centroid)
                if dist < min_inter_dist:
                    min_inter_dist = dist
                    nearest_class = other_cls
        
        # 5. Separation ratio (margin / intra-class spread)
        separation_ratio = min_inter_dist / (avg_intra + 0.001)
        
        results.append({
            'class': cls,
            'samples': sample_count,
            'accuracy': accuracy,
            'intra_dist': avg_intra,
            'intra_std': std_intra,
            'margin': min_inter_dist,
            'nearest': nearest_class,
            'separation': separation_ratio,
        })
    
    return results

def main():
    print("=" * 80)
    print("  Best ASL Signs Analysis")
    print("  Criteria: High samples + High accuracy + No overlap")
    print("=" * 80)
    
    # Load data
    print("\nLoading data...")
    samples_by_class = load_all_data()
    total = sum(len(v) for v in samples_by_class.values())
    print(f"Loaded {total:,} samples across {len(samples_by_class)} classes")
    
    # Analyze (minimum 30 samples for reliability)
    results = analyze_signs(samples_by_class, min_samples=30)
    
    # Filter for best signs:
    # - Accuracy >= 80%
    # - Separation ratio >= 2.0 (well separated from other signs)
    # - At least 50 samples
    best_signs = [
        r for r in results 
        if r['accuracy'] >= 80 
        and r['separation'] >= 2.0
        and r['samples'] >= 50
    ]
    
    # Sort by combined score (accuracy * separation * log(samples))
    for r in best_signs:
        r['score'] = r['accuracy'] * r['separation'] * np.log(r['samples'])
    
    best_signs.sort(key=lambda x: -x['score'])
    
    print("\n" + "=" * 80)
    print("  TOP SIGNS: High Samples + High Accuracy + Well Separated")
    print("=" * 80)
    print(f"\n{'Sign':<20} {'Samples':>8} {'Accuracy':>10} {'Separation':>12} {'Nearest Class':<20}")
    print("-" * 80)
    
    for r in best_signs[:50]:
        print(f"{r['class']:<20} {r['samples']:>8} {r['accuracy']:>9.1f}% {r['separation']:>12.2f} {r['nearest']:<20}")
    
    # Categorize
    letters = [r for r in best_signs if len(r['class']) == 1 and r['class'].isalpha()]
    numbers = [r for r in best_signs if r['class'].isdigit()]
    words = [r for r in best_signs if r not in letters and r not in numbers]
    
    print("\n" + "=" * 80)
    print("  SUMMARY BY CATEGORY")
    print("=" * 80)
    
    print(f"\n📝 LETTERS ({len(letters)}):")
    for r in sorted(letters, key=lambda x: x['class']):
        print(f"   {r['class']} - {r['accuracy']:.1f}% accuracy, {r['samples']} samples, separation: {r['separation']:.2f}")
    
    print(f"\n🔢 NUMBERS ({len(numbers)}):")
    for r in sorted(numbers, key=lambda x: x['class']):
        print(f"   {r['class']} - {r['accuracy']:.1f}% accuracy, {r['samples']} samples, separation: {r['separation']:.2f}")
    
    print(f"\n💬 WORDS ({len(words)}):")
    for r in sorted(words, key=lambda x: -x['score']):
        print(f"   {r['class']:<20} - {r['accuracy']:>5.1f}% accuracy, {r['samples']:>4} samples, separation: {r['separation']:.2f}")
    
    print("\n" + "=" * 80)
    print(f"  TOTAL BEST SIGNS: {len(best_signs)}")
    print(f"  - Letters: {len(letters)}")
    print(f"  - Numbers: {len(numbers)}")
    print(f"  - Words: {len(words)}")
    print("=" * 80)

if __name__ == "__main__":
    main()
