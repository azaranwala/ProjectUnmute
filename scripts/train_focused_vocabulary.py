#!/usr/bin/env python3
"""
Train Focused ASL Model for Curated Vocabulary

Categories:
- Family, Places, Time, Temperature, Food, Clothes, Health
- Feelings, Requests, Amounts, Colors, Money, Animals

This creates a smaller, more accurate model with ~100 carefully selected signs.
"""

import os
import json
import csv
import numpy as np
from collections import defaultdict

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_MODEL_JSON = os.path.join(BASE_DIR, "../ASLModelData_focused.json")
MIN_SAMPLES_PER_CLASS = 3

# Target vocabulary with category organization
TARGET_VOCABULARY = {
    'Family': [
        'MOM', 'MOTHER', 'DAD', 'FATHER', 'BOY', 'GIRL', 'MARRY', 'BROTHER', 'SISTER',
        'GRANDMA', 'GRANDMOTHER', 'GRANDFATHER', 'AUNT', 'UNCLE', 'BABY', 'SINGLE',
        'DIVORCE', 'SEPARATE', 'FAMILY', 'SON', 'DAUGHTER', 'HUSBAND', 'WIFE', 'COUSIN'
    ],
    'Places': [
        'HOME', 'WORK', 'SCHOOL', 'STORE', 'CHURCH', 'COME', 'GO', 'CAR', 'DRIVE',
        'IN', 'OUT', 'WITH', 'HERE', 'THERE'
    ],
    'Time': [
        'DAY', 'NIGHT', 'WEEK', 'MONTH', 'YEAR', 'WILL', 'FUTURE', 'BEFORE', 'PAST',
        'TODAY', 'NOW', 'FINISH', 'DONE', 'MORNING', 'AFTERNOON', 'TOMORROW', 'YESTERDAY',
        'TIME', 'HOUR', 'MINUTE', 'SECOND', 'WAIT', 'LATE', 'EARLY'
    ],
    'Temperature': ['HOT', 'COLD', 'WARM', 'COOL'],
    'Food': [
        'PIZZA', 'MILK', 'HAMBURGER', 'HOT_DOG', 'EGG', 'APPLE', 'CHEESE', 'DRINK',
        'SPOON', 'FORK', 'CUP', 'CEREAL', 'WATER', 'CANDY', 'COOKIE', 'HUNGRY',
        'EAT', 'FOOD', 'BREAD', 'MEAT', 'FRUIT', 'VEGETABLE', 'BREAKFAST', 'LUNCH', 'DINNER'
    ],
    'Clothes': ['SHIRT', 'PANTS', 'SOCKS', 'SHOES', 'COAT', 'UNDERWEAR', 'HAT', 'DRESS'],
    'Health': [
        'WASH', 'HURT', 'BATHROOM', 'BRUSH', 'TEETH', 'SLEEP', 'NICE', 'CLEAN',
        'SICK', 'MEDICINE', 'DOCTOR', 'HOSPITAL', 'TIRED'
    ],
    'Feelings': [
        'HAPPY', 'ANGRY', 'SAD', 'SORRY', 'CRY', 'LIKE', 'GOOD', 'BAD', 'LOVE',
        'EXCITED', 'SCARED', 'WORRIED', 'PROUD', 'EMBARRASSED', 'BORED', 'SURPRISED'
    ],
    'Requests': [
        'PLEASE', 'EXCUSE', 'THANK_YOU', 'HELP', 'WHO', 'WHAT', 'WHEN', 'WHERE', 'WHY',
        'HOW', 'STOP', 'YES', 'NO', 'WANT', 'NEED', 'CAN', 'GIVE', 'TAKE', 'SHOW'
    ],
    'Amounts': ['BIG', 'TALL', 'FULL', 'MORE', 'SMALL', 'SHORT', 'EMPTY', 'LESS', 'ALL', 'SOME', 'MANY', 'FEW'],
    'Colors': ['BLUE', 'GREEN', 'YELLOW', 'RED', 'BROWN', 'ORANGE', 'GOLD', 'SILVER', 'BLACK', 'WHITE', 'PINK', 'PURPLE'],
    'Money': ['DOLLAR', 'CENT', 'COST', 'MONEY', 'BUY', 'PAY', 'FREE', 'EXPENSIVE', 'CHEAP'],
    'Animals': ['CAT', 'DOG', 'BIRD', 'HORSE', 'COW', 'SHEEP', 'PIG', 'BUG', 'FISH', 'RABBIT', 'CHICKEN'],
    'Common': [
        'HELLO', 'GOODBYE', 'NAME', 'MY', 'YOUR', 'I', 'YOU', 'HE', 'SHE', 'IT', 'WE', 'THEY',
        'THIS', 'THAT', 'AND', 'OR', 'BUT', 'NOT', 'HAVE', 'BE', 'DO', 'MAKE', 'SEE', 'LOOK',
        'THINK', 'KNOW', 'LEARN', 'TEACH', 'READ', 'WRITE', 'PLAY', 'WALK', 'RUN', 'SIT', 'STAND'
    ],
    'Numbers': ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
    'Letters': list('ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
}

# Flatten target list
TARGET_CLASSES = set()
for signs in TARGET_VOCABULARY.values():
    TARGET_CLASSES.update(signs)

# Dataset files
DATASETS = [
    "wlasl_full_landmarks.csv",
    "asl_citizen_landmarks.csv",
    "combined_asl_landmarks.csv",
    "kaggle_asl_landmarks.csv",
    "asl_landmarks.csv",
    "number_landmarks.csv",
]

# Class normalization
CLASS_NORMALIZATION = {
    "THANKYOU": "THANK_YOU",
    "THANK YOU": "THANK_YOU",
    "ILOVEYOU": "I_LOVE_YOU",
    "DRINK1": "DRINK",
    "HOW1": "HOW",
    "WHAT1": "WHAT",
    "WANT2": "WANT",
    "WALK2": "WALK",
    "TEACH1": "TEACH",
    "STAND1": "STAND",
    # Map variations to standard
    "GRANDPA": "GRANDFATHER",
    "MARRIAGE": "MARRY",
    "DIVORCED": "DIVORCE",
}


def normalize_class_name(name):
    name = name.strip().upper().replace(" ", "_")
    return CLASS_NORMALIZATION.get(name, name)


def load_csv_dataset(filepath, target_classes):
    """Load only target classes from CSV file."""
    samples_by_class = defaultdict(list)
    
    if not os.path.exists(filepath):
        return samples_by_class
    
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
                    label = normalize_class_name(row[label_idx])
                    
                    # Only include target classes
                    if label not in target_classes:
                        continue
                    
                    coords = [float(row[i]) for i in range(63)]
                    samples_by_class[label].append(coords)
                except (ValueError, IndexError):
                    continue
    except Exception as e:
        print(f"   Error reading {filepath}: {e}")
    
    return samples_by_class


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


def euclidean_distance(a, b):
    return np.sqrt(np.sum((np.array(a) - np.array(b)) ** 2))


def confidence_from_distance(dist):
    return np.exp(-dist / 15.0)


def train_and_evaluate(samples_by_class, min_samples=3):
    """Train centroid model and evaluate accuracy."""
    print("\n🧠 Training focused centroid model...")
    
    # Filter classes with minimum samples
    valid_classes = {k: v for k, v in samples_by_class.items() if len(v) >= min_samples}
    print(f"   Classes with >= {min_samples} samples: {len(valid_classes)}")
    
    # Process samples and calculate centroids
    centroids = {}
    processed_samples = {}
    
    for cls in sorted(valid_classes.keys()):
        samples = valid_classes[cls]
        processed = []
        for s in samples:
            wr = make_wrist_relative(s)
            if wr:
                processed.append(wr)
        
        if processed:
            centroid = np.mean(processed, axis=0).tolist()
            centroids[cls] = centroid
            processed_samples[cls] = processed
    
    print(f"   Final classes: {len(centroids)}")
    
    # Evaluate accuracy
    print("\n📊 Evaluating accuracy...")
    results = []
    
    for cls in centroids:
        samples = processed_samples[cls]
        centroid = centroids[cls]
        
        correct = 0
        high_conf_correct = 0
        confidences = []
        
        for sample in samples:
            # Find closest centroid
            min_dist = float('inf')
            pred_class = None
            
            for other_cls, other_centroid in centroids.items():
                dist = euclidean_distance(sample, other_centroid)
                if dist < min_dist:
                    min_dist = dist
                    pred_class = other_cls
            
            conf = confidence_from_distance(min_dist)
            confidences.append(conf)
            
            if pred_class == cls:
                correct += 1
                if conf >= 0.90:
                    high_conf_correct += 1
        
        accuracy = correct / len(samples) * 100
        high_conf_rate = high_conf_correct / len(samples) * 100
        avg_conf = np.mean(confidences) * 100
        
        results.append({
            'class': cls,
            'samples': len(samples),
            'accuracy': accuracy,
            'high_conf_rate': high_conf_rate,
            'avg_confidence': avg_conf,
        })
    
    return centroids, results


def main():
    print("=" * 70)
    print("  Focused ASL Vocabulary Model Trainer")
    print("=" * 70)
    print(f"\n   Target vocabulary: {len(TARGET_CLASSES)} signs")
    
    # Load samples for target classes only
    all_samples = defaultdict(list)
    
    for dataset_file in DATASETS:
        filepath = os.path.join(BASE_DIR, dataset_file)
        print(f"\n📂 Loading {dataset_file}...")
        samples = load_csv_dataset(filepath, TARGET_CLASSES)
        
        if samples:
            total = sum(len(v) for v in samples.values())
            print(f"   ✓ {total:,} samples, {len(samples)} target classes")
            
            for cls, coords_list in samples.items():
                all_samples[cls].extend(coords_list)
    
    total_samples = sum(len(v) for v in all_samples.values())
    print(f"\n   Total: {total_samples:,} samples across {len(all_samples)} classes")
    
    # Train and evaluate
    centroids, results = train_and_evaluate(all_samples, MIN_SAMPLES_PER_CLASS)
    
    # Sort by accuracy
    results.sort(key=lambda x: -x['accuracy'])
    
    # Report by category
    print("\n" + "=" * 70)
    print("  Accuracy by Category")
    print("=" * 70)
    
    for category, signs in TARGET_VOCABULARY.items():
        cat_results = [r for r in results if r['class'] in signs]
        if cat_results:
            avg_acc = np.mean([r['accuracy'] for r in cat_results])
            high_acc = len([r for r in cat_results if r['accuracy'] >= 90])
            print(f"\n   {category} ({len(cat_results)} signs, avg {avg_acc:.1f}% accuracy, {high_acc} with >90%):")
            for r in sorted(cat_results, key=lambda x: -x['accuracy']):
                marker = "✓" if r['accuracy'] >= 90 else "○" if r['accuracy'] >= 80 else "✗"
                print(f"      {marker} {r['class']:15} | {r['accuracy']:5.1f}% | {r['samples']:>4} samples | conf: {r['avg_confidence']:.1f}%")
    
    # Summary
    print("\n" + "=" * 70)
    print("  Summary")
    print("=" * 70)
    
    high_acc = [r for r in results if r['accuracy'] >= 90]
    med_acc = [r for r in results if 80 <= r['accuracy'] < 90]
    low_acc = [r for r in results if r['accuracy'] < 80]
    
    print(f"   Total classes: {len(results)}")
    print(f"   >90% accuracy: {len(high_acc)} ({len(high_acc)/len(results)*100:.1f}%)")
    print(f"   80-90% accuracy: {len(med_acc)} ({len(med_acc)/len(results)*100:.1f}%)")
    print(f"   <80% accuracy: {len(low_acc)} ({len(low_acc)/len(results)*100:.1f}%)")
    
    # Save model
    model_data = {
        'classes': list(centroids.keys()),
        'scaler_mean': [0.0] * 63,
        'scaler_scale': [1.0] * 63,
        'centroids': centroids,
    }
    
    print(f"\n💾 Saving model to {OUTPUT_MODEL_JSON}...")
    with open(OUTPUT_MODEL_JSON, 'w') as f:
        json.dump(model_data, f)
    
    file_size = os.path.getsize(OUTPUT_MODEL_JSON) / 1024
    print(f"   ✓ Saved ({file_size:.1f} KB)")
    
    # Missing signs
    found_classes = set(centroids.keys())
    missing = TARGET_CLASSES - found_classes
    if missing:
        print(f"\n⚠️ Missing signs (no training data): {len(missing)}")
        for s in sorted(missing):
            print(f"      {s}")
    
    print("\n" + "=" * 70)
    print("   To use in iOS app:")
    print(f"   cp ASLModelData_focused.json '../ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute/ASLModelData.json'")
    print("=" * 70)


if __name__ == "__main__":
    main()
