#!/usr/bin/env python3
"""Train ASL model with wrist-relative coordinates WITHOUT StandardScaler

The StandardScaler was amplifying small differences due to low-variance features.
This version uses raw wrist-relative coordinates for centroid matching.
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import train_test_split
from sklearn.utils import resample
import joblib
import json
import warnings
warnings.filterwarnings('ignore')

def make_wrist_relative_and_scale(X):
    """Make landmarks relative to wrist and scale by hand size.
    
    This matches the iOS preprocessing:
    1. Subtract wrist position from all landmarks
    2. Divide by max distance from wrist to any landmark
    """
    X = np.array(X, dtype=np.float64).reshape(-1, 21, 3)
    result = []
    for sample in X:
        wrist = sample[0].copy()
        relative = sample - wrist
        
        # Calculate max distance from wrist to any landmark
        max_dist = 0.0
        for i in range(21):
            dist = np.sqrt(relative[i, 0]**2 + relative[i, 1]**2 + relative[i, 2]**2)
            if dist > max_dist:
                max_dist = dist
        
        if max_dist < 0.001:
            max_dist = 1.0
        
        # Scale by hand size
        scaled = relative / max_dist
        result.append(scaled.flatten())
    return np.array(result)

print("="*60)
print("  Training ASL Model - Wrist-Relative + Scale Normalized")
print("="*60)

HIGH_PRIORITY = {'0','1','2','3','4','5','6','7','8','9',
                 'A','B','C','D','E','F','G','H','I','J','K','L','M',
                 'N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
                 'I_LOVE_YOU'}

# Load datasets
print("\n1. Loading datasets...")
datasets = []
for name, path in [
    ('WLASL', 'wlasl_landmarks.csv'),
    ('Combined', 'combined_asl_landmarks.csv'),
    ('Citizen', 'asl_citizen_landmarks.csv'),
    ('Kaggle', 'kaggle_asl_landmarks.csv'),
    ('ASL', 'asl_landmarks.csv'),
    ('Numbers', 'number_landmarks.csv')  # Mac webcam-collected numbers (compatible with iOS)
]:
    try:
        df = pd.read_csv(path)
        print(f"   ✓ {name}: {len(df)} samples")
        datasets.append((name, df))
    except Exception as e:
        print(f"   ✗ {name}: {e}")

feature_cols = [f'x{i}' if j == 0 else f'y{i}' if j == 1 else f'z{i}' 
                for i in range(21) for j in range(3)]

# Merge datasets
print("\n2. Merging datasets...")
all_dfs = []
custom_number_labels = {'0', '1', '2', '3', '4', '5', 'I_LOVE_YOU'}

for name, df in datasets:
    if 'label' in df.columns:
        cols_to_use = [c for c in feature_cols if c in df.columns] + ['label']
        if len(cols_to_use) == 64:
            df_clean = df[cols_to_use].copy()
            df_clean['label'] = df_clean['label'].astype(str).str.upper().str.strip()
            
            # For non-custom number datasets, REMOVE number samples (use only custom numbers)
            if name != 'Numbers':
                df_clean = df_clean[~df_clean['label'].isin(custom_number_labels)]
                print(f"   {name}: removed number samples, kept {len(df_clean)}")
            else:
                print(f"   {name}: keeping all {len(df_clean)} custom number samples")
            
            all_dfs.append(df_clean)

all_data = pd.concat(all_dfs, ignore_index=True)
all_data['label'] = all_data['label'].astype(str).str.upper().str.strip()

class_counts = all_data['label'].value_counts()
print(f"   Total: {len(all_data)} samples, {len(class_counts)} classes")

# Select classes
min_samples = 20
selected = set()

for sign in HIGH_PRIORITY:
    if sign in class_counts.index and class_counts[sign] >= min_samples:
        selected.add(sign)
print(f"   High priority: {len(selected)}")

useful_words = ['HELLO', 'THANKYOU', 'PLEASE', 'SORRY', 'YES', 'NO', 'HELP', 
                'STOP', 'WAIT', 'GO', 'GOOD', 'BAD', 'WANT', 'NEED', 'LIKE',
                'MOTHER', 'FATHER', 'FRIEND', 'FAMILY', 'EAT', 'DRINK', 'SLEEP',
                'WORK', 'PLAY', 'LEARN', 'HAPPY', 'SAD', 'NAME', 'WHAT',
                'WHERE', 'WHEN', 'WHO', 'WHY', 'HOW', 'NOW', 'LATER', 'BEFORE',
                'SCHOOL', 'DOCTOR', 'WRITE', 'FINISH', 'APPLE', 'PIZZA', 'THANKSGIVING']

for word in useful_words:
    if word in class_counts.index and class_counts[word] >= min_samples:
        selected.add(word)
        if len(selected) >= 80:
            break

print(f"   Total selected: {len(selected)} classes")

filtered_data = all_data[all_data['label'].isin(selected)]

print("\n3. Balancing classes...")
target_samples = 300
balanced_dfs = []
for label in selected:
    class_data = filtered_data[filtered_data['label'] == label]
    n = len(class_data)
    if n < target_samples:
        upsampled = resample(class_data, replace=True, n_samples=target_samples, random_state=42)
        balanced_dfs.append(upsampled)
    elif n > target_samples * 2:
        downsampled = resample(class_data, replace=False, n_samples=target_samples, random_state=42)
        balanced_dfs.append(downsampled)
    else:
        balanced_dfs.append(class_data)

balanced_data = pd.concat(balanced_dfs, ignore_index=True)
print(f"   Balanced: {len(balanced_data)} samples")

X_raw = balanced_data[feature_cols].values.astype(np.float32)
y = balanced_data['label'].values
X_raw = np.nan_to_num(X_raw, nan=0.0)

# Apply wrist-relative transformation (NO SCALING!)
print("\n4. Making landmarks wrist-relative (NO SCALER)...")
X_relative = make_wrist_relative_and_scale(X_raw)
print(f"   Raw range: [{X_raw.min():.3f}, {X_raw.max():.3f}]")
print(f"   Relative range: [{X_relative.min():.3f}, {X_relative.max():.3f}]")

# Encode labels
print("\n5. Encoding labels...")
encoder = LabelEncoder()
y_encoded = encoder.fit_transform(y)
print(f"   Classes: {len(encoder.classes_)}")

# Split (NO SCALING - use raw relative data)
X_train, X_test, y_train, y_test = train_test_split(
    X_relative, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
)
print(f"   Train: {len(X_train)}, Test: {len(X_test)}")

# Train RandomForest on raw relative coordinates
print("\n6. Training RandomForest (on raw wrist-relative)...")
model = RandomForestClassifier(
    n_estimators=500,
    max_depth=30,
    min_samples_split=2,
    min_samples_leaf=1,
    class_weight='balanced',
    n_jobs=-1,
    random_state=42
)
model.fit(X_train, y_train)

train_acc = model.score(X_train, y_train)
test_acc = model.score(X_test, y_test)
print(f"   Train accuracy: {train_acc*100:.1f}%")
print(f"   Test accuracy: {test_acc*100:.1f}%")

# Test numbers/letters
print("\n7. Testing number/letter accuracy...")
for category, signs in [('Numbers', [str(i) for i in range(10)]), 
                        ('Letters', list('ABCDEFGHIJKLMNOPQRSTUVWXYZ'))]:
    correct = 0
    total = 0
    for sign in signs:
        if sign not in encoder.classes_:
            continue
        mask = balanced_data['label'] == sign
        if mask.sum() == 0:
            continue
        samples_raw = balanced_data[mask][feature_cols].values[:50]
        samples_raw = np.nan_to_num(samples_raw, nan=0.0).astype(np.float32)
        samples_rel = make_wrist_relative_and_scale(samples_raw)
        preds = model.predict(samples_rel)
        label_idx = list(encoder.classes_).index(sign)
        correct += (preds == label_idx).sum()
        total += len(samples_raw)
    if total > 0:
        print(f"   {category}: {correct}/{total} = {correct/total*100:.1f}%")

# Compute centroids on RAW wrist-relative data (NO SCALING!)
print("\n8. Computing centroids (NO SCALER)...")
centroids = {}
for label in encoder.classes_:
    mask = balanced_data['label'] == label
    samples_raw = balanced_data[mask][feature_cols].values
    samples_raw = np.nan_to_num(samples_raw, nan=0.0)
    samples_rel = make_wrist_relative_and_scale(samples_raw)
    centroid = np.mean(samples_rel, axis=0)
    centroids[label] = centroid.tolist()

# Verify centroid distances
print("\n   Verifying centroid distances...")
for test_label in ['0', '1', '3', '5', 'A']:
    if test_label not in encoder.classes_:
        continue
    test_sample = balanced_data[balanced_data['label'] == test_label].iloc[0][feature_cols].values
    test_rel = make_wrist_relative_and_scale(test_sample.reshape(1, -1))[0]
    dist = np.linalg.norm(test_rel - np.array(centroids[test_label]))
    print(f"   '{test_label}' sample to '{test_label}' centroid: {dist:.3f}")

# Export for iOS - NO SCALER (use identity transform)
ios_data = {
    'classes': [str(c) for c in encoder.classes_],
    'scaler_mean': [0.0] * 63,  # Identity: mean=0
    'scaler_scale': [1.0] * 63,  # Identity: scale=1
    'centroids': centroids,
    'n_features': 63,
    'normalization': 'wrist_relative_no_scaler'
}

with open('../ASLModelData.json', 'w') as f:
    json.dump(ios_data, f)

import shutil
shutil.copy('../ASLModelData.json', '../ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute/ASLModelData.json')

print("\n" + "="*60)
print("  ✅ Training Complete - NO SCALER!")
print("="*60)
print(f"\n  Normalization: Wrist-relative (NO StandardScaler)")
print(f"  Scaler: IDENTITY (mean=0, scale=1)")
print(f"  Total Samples: {len(balanced_data)}")
print(f"  Classes: {len(encoder.classes_)}")
print(f"  Test Accuracy: {test_acc*100:.1f}%")
print("="*60)
