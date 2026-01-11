#!/usr/bin/env python3
"""Train ASL model with wrist-centered normalization for position-invariant detection"""

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

def normalize_wrist_centered(X):
    """
    Normalize landmarks: center on wrist, scale by hand size.
    Input: (N, 63) array of raw landmarks
    Output: (N, 63) array of normalized landmarks
    """
    X = X.reshape(-1, 21, 3)
    result = []
    
    for sample in X:
        wrist = sample[0]  # Landmark 0 is wrist
        middle_mcp = sample[9]  # Landmark 9 is middle finger MCP
        
        # Calculate hand scale (distance from wrist to middle MCP)
        hand_scale = np.linalg.norm(middle_mcp - wrist)
        if hand_scale < 0.001:
            hand_scale = 1.0
        
        # Center on wrist and scale
        normalized = (sample - wrist) / hand_scale
        result.append(normalized.flatten())
    
    return np.array(result)

print("="*60)
print("  Training ASL Model - Wrist-Centered Normalization")
print("="*60)

# High priority signs
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
print("\n2. Merging datasets...")
all_dfs = []
for name, df in datasets:
    if 'label' in df.columns:
        cols_to_use = [c for c in feature_cols if c in df.columns] + ['label']
        if len(cols_to_use) == 64:
            all_dfs.append(df[cols_to_use])

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

# Filter and balance
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

# Get raw features
X_raw = balanced_data[feature_cols].values.astype(np.float32)
y = balanced_data['label'].values
X_raw = np.nan_to_num(X_raw, nan=0.0)

# Apply wrist-centered normalization
print("\n4. Applying wrist-centered normalization...")
X_normalized = normalize_wrist_centered(X_raw)
print(f"   Normalized range: [{X_normalized.min():.2f}, {X_normalized.max():.2f}]")

# Encode labels
print("\n5. Encoding labels...")
encoder = LabelEncoder()
y_encoded = encoder.fit_transform(y)
print(f"   Classes: {len(encoder.classes_)}")

# Scale normalized features
print("\n6. Scaling features...")
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_normalized)

# Split
X_train, X_test, y_train, y_test = train_test_split(
    X_scaled, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
)
print(f"   Train: {len(X_train)}, Test: {len(X_test)}")

# Train
print("\n7. Training RandomForest...")
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
print("\n8. Testing number/letter accuracy...")
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
        samples_raw = balanced_data[mask][feature_cols].values[:50]
        samples_raw = np.nan_to_num(samples_raw, nan=0.0).astype(np.float32)
        samples_norm = normalize_wrist_centered(samples_raw)
        scaled = scaler.transform(samples_norm)
        preds = model.predict(scaled)
        label_idx = list(encoder.classes_).index(sign)
        correct += (preds == label_idx).sum()
        total += len(samples_raw)
    if total > 0:
        print(f"   {category}: {correct}/{total} = {correct/total*100:.1f}%")

# Save
print("\n9. Saving models...")
joblib.dump(model, 'asl_citizen_model.pkl')
joblib.dump(encoder, 'asl_citizen_encoder.pkl')
joblib.dump(scaler, 'asl_citizen_scaler.pkl')

# Compute centroids
print("\n10. Computing centroids for iOS...")
centroids = {}
for label in encoder.classes_:
    mask = balanced_data['label'] == label
    samples_raw = balanced_data[mask][feature_cols].values
    samples_raw = np.nan_to_num(samples_raw, nan=0.0)
    samples_norm = normalize_wrist_centered(samples_raw)
    scaled_samples = scaler.transform(samples_norm)
    centroid = np.mean(scaled_samples, axis=0)
    centroids[label] = centroid.tolist()

ios_data = {
    'classes': [str(c) for c in encoder.classes_],
    'scaler_mean': scaler.mean_.tolist(),
    'scaler_scale': scaler.scale_.tolist(),
    'centroids': centroids,
    'n_features': 63,
    'normalization': 'wrist_centered'  # Flag to indicate normalization type
}

with open('../ASLModelData.json', 'w') as f:
    json.dump(ios_data, f)

import shutil
shutil.copy('../ASLModelData.json', '../ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute/ASLModelData.json')

print("\n" + "="*60)
print("  ✅ Training Complete!")
print("="*60)
print(f"\n  Normalization: WRIST-CENTERED")
print(f"  Total Samples: {len(balanced_data)}")
print(f"  Classes: {len(encoder.classes_)}")
print(f"  Test Accuracy: {test_acc*100:.1f}%")

nums_included = [s for s in encoder.classes_ if s in HIGH_PRIORITY]
print(f"\n  Numbers/Letters ({len(nums_included)}): {', '.join(sorted(nums_included))}")
print("="*60)
