#!/usr/bin/env python3
"""Train ASL model with priority for numbers and letters - better balanced"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.utils import resample
import joblib
import json
import warnings
warnings.filterwarnings('ignore')

print("="*60)
print("  Training ASL Model - Numbers & Letters Priority")
print("="*60)

# High priority signs - numbers and letters MUST work well
HIGH_PRIORITY = {'0','1','2','3','4','5','6','7','8','9',
                 'A','B','C','D','E','F','G','H','I','J','K','L','M',
                 'N','O','P','Q','R','S','T','U','V','W','X','Y','Z'}

# Load datasets
print("\n1. Loading datasets...")
datasets = []
for name, path in [
    ('WLASL', 'wlasl_landmarks.csv'),
    ('Combined', 'combined_asl_landmarks.csv'),
    ('Citizen', 'asl_citizen_landmarks.csv'),
    ('Kaggle', 'kaggle_asl_landmarks.csv'),
    ('ASL', 'asl_landmarks.csv')
]:
    try:
        df = pd.read_csv(path)
        print(f"   ✓ {name}: {len(df)} samples")
        datasets.append((name, df))
    except Exception as e:
        print(f"   ✗ {name}: {e}")

# Feature columns
feature_cols = [f'x{i}' if j == 0 else f'y{i}' if j == 1 else f'z{i}' 
                for i in range(21) for j in range(3)]

# Merge datasets
print("\n2. Merging and balancing datasets...")
all_dfs = []
for name, df in datasets:
    if 'label' in df.columns:
        cols_to_use = [c for c in feature_cols if c in df.columns] + ['label']
        if len(cols_to_use) == 64:
            all_dfs.append(df[cols_to_use])

all_data = pd.concat(all_dfs, ignore_index=True)
all_data['label'] = all_data['label'].astype(str).str.upper().str.strip()

# Get class counts
class_counts = all_data['label'].value_counts()
print(f"   Total: {len(all_data)} samples, {len(class_counts)} classes")

# Select classes: all numbers/letters + top words
min_samples = 20
selected = set()

# Add all high priority signs that exist
for sign in HIGH_PRIORITY:
    if sign in class_counts.index and class_counts[sign] >= min_samples:
        selected.add(sign)
print(f"   High priority (numbers/letters): {len(selected)}")

# Add useful words until we reach 80 total
useful_words = ['HELLO', 'THANKYOU', 'PLEASE', 'SORRY', 'YES', 'NO', 'HELP', 
                'STOP', 'WAIT', 'GO', 'GOOD', 'BAD', 'WANT', 'NEED', 'LIKE',
                'MOTHER', 'FATHER', 'FRIEND', 'FAMILY', 'EAT', 'DRINK', 'SLEEP',
                'WORK', 'PLAY', 'LEARN', 'HAPPY', 'SAD', 'LOVE', 'NAME', 'WHAT',
                'WHERE', 'WHEN', 'WHO', 'WHY', 'HOW', 'NOW', 'LATER', 'BEFORE',
                'SCHOOL', 'HOME', 'WATER', 'FOOD', 'DOCTOR', 'WRITE', 'READ',
                'FINISH', 'MORE', 'AGAIN', 'APPLE', 'PIZZA', 'THANKSGIVING']

for word in useful_words:
    if word in class_counts.index and class_counts[word] >= min_samples:
        selected.add(word)
        if len(selected) >= 80:
            break

print(f"   Total selected: {len(selected)} classes")

# Filter data
filtered_data = all_data[all_data['label'].isin(selected)]

# BALANCE CLASSES: Upsample minority classes, downsample majority
print("\n3. Balancing class sizes...")
target_samples = 300  # Target samples per class

balanced_dfs = []
for label in selected:
    class_data = filtered_data[filtered_data['label'] == label]
    n = len(class_data)
    
    if n < target_samples:
        # Upsample (especially important for numbers)
        upsampled = resample(class_data, replace=True, n_samples=target_samples, random_state=42)
        balanced_dfs.append(upsampled)
    elif n > target_samples * 2:
        # Downsample very large classes
        downsampled = resample(class_data, replace=False, n_samples=target_samples, random_state=42)
        balanced_dfs.append(downsampled)
    else:
        balanced_dfs.append(class_data)

balanced_data = pd.concat(balanced_dfs, ignore_index=True)
print(f"   Balanced samples: {len(balanced_data)}")

# Prepare features
X = balanced_data[feature_cols].values.astype(np.float32)
y = balanced_data['label'].values
X = np.nan_to_num(X, nan=0.0)

# Encode labels
print("\n4. Encoding labels...")
encoder = LabelEncoder()
y_encoded = encoder.fit_transform(y)
print(f"   Classes: {len(encoder.classes_)}")

# Scale features
print("\n5. Scaling features...")
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# Split data
X_train, X_test, y_train, y_test = train_test_split(
    X_scaled, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
)
print(f"   Train: {len(X_train)}, Test: {len(X_test)}")

# Train RandomForest
print("\n6. Training RandomForest classifier...")
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

# Test number accuracy specifically
print("\n7. Testing number/letter accuracy...")
numbers = [str(i) for i in range(10)]
letters = list('ABCDEFGHIJKLMNOPQRSTUVWXYZ')

for category, signs in [('Numbers', numbers), ('Letters', letters)]:
    correct = 0
    total = 0
    for sign in signs:
        if sign not in encoder.classes_:
            continue
        mask = balanced_data['label'] == sign
        if mask.sum() == 0:
            continue
        samples = balanced_data[mask][feature_cols].values[:50]
        samples = np.nan_to_num(samples, nan=0.0).astype(np.float32)
        scaled = scaler.transform(samples)
        preds = model.predict(scaled)
        label_idx = list(encoder.classes_).index(sign)
        correct += (preds == label_idx).sum()
        total += len(samples)
    if total > 0:
        print(f"   {category}: {correct}/{total} = {correct/total*100:.1f}%")

# Save models
print("\n8. Saving models...")
joblib.dump(model, 'asl_citizen_model.pkl')
joblib.dump(encoder, 'asl_citizen_encoder.pkl')
joblib.dump(scaler, 'asl_citizen_scaler.pkl')

# Compute centroids for iOS (using ORIGINAL balanced data, not scaled)
print("\n9. Computing centroids for iOS...")
centroids = {}
for label in encoder.classes_:
    mask = balanced_data['label'] == label
    samples = balanced_data[mask][feature_cols].values
    samples = np.nan_to_num(samples, nan=0.0)
    scaled_samples = scaler.transform(samples)
    centroid = np.mean(scaled_samples, axis=0)
    centroids[label] = centroid.tolist()

ios_data = {
    'classes': [str(c) for c in encoder.classes_],
    'scaler_mean': scaler.mean_.tolist(),
    'scaler_scale': scaler.scale_.tolist(),
    'centroids': centroids,
    'n_features': 63
}

with open('../ASLModelData.json', 'w') as f:
    json.dump(ios_data, f)

import shutil
shutil.copy('../ASLModelData.json', '../ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute/ASLModelData.json')

print("\n" + "="*60)
print("  ✅ Training Complete!")
print("="*60)
print(f"\n  Total Samples: {len(balanced_data)}")
print(f"  Classes: {len(encoder.classes_)}")
print(f"  Test Accuracy: {test_acc*100:.1f}%")

# Show all numbers/letters included
nums_included = [s for s in encoder.classes_ if s in HIGH_PRIORITY]
print(f"\n  Numbers/Letters included ({len(nums_included)}):")
print(f"    {', '.join(sorted(nums_included))}")

words_included = [s for s in encoder.classes_ if s not in HIGH_PRIORITY]
print(f"\n  Words included ({len(words_included)}):")
for i in range(0, len(words_included), 6):
    row = sorted(words_included)[i:i+6]
    print(f"    {', '.join(row)}")

print("\n" + "="*60)
