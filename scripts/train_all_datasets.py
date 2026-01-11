#!/usr/bin/env python3
"""Train ASL model with ALL available datasets including ASL Citizen"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split
import joblib
import json
import warnings
warnings.filterwarnings('ignore')

print("="*60)
print("  Training ASL Model with ALL Datasets")
print("="*60)

# Load all datasets
print("\n1. Loading all datasets...")

datasets = []

# WLASL dataset
try:
    wlasl = pd.read_csv('wlasl_landmarks.csv')
    print(f"   ✓ WLASL: {len(wlasl)} samples, {wlasl['label'].nunique()} classes")
    datasets.append(('WLASL', wlasl))
except Exception as e:
    print(f"   ✗ WLASL: {e}")

# Combined ASL dataset
try:
    combined = pd.read_csv('combined_asl_landmarks.csv')
    print(f"   ✓ Combined ASL: {len(combined)} samples, {combined['label'].nunique()} classes")
    datasets.append(('Combined', combined))
except Exception as e:
    print(f"   ✗ Combined ASL: {e}")

# ASL Citizen dataset (largest)
try:
    citizen = pd.read_csv('asl_citizen_landmarks.csv')
    print(f"   ✓ ASL Citizen: {len(citizen)} samples, {citizen['label'].nunique()} classes")
    datasets.append(('Citizen', citizen))
except Exception as e:
    print(f"   ✗ ASL Citizen: {e}")

# Kaggle ASL dataset
try:
    kaggle = pd.read_csv('kaggle_asl_landmarks.csv')
    print(f"   ✓ Kaggle ASL: {len(kaggle)} samples, {kaggle['label'].nunique()} classes")
    datasets.append(('Kaggle', kaggle))
except Exception as e:
    print(f"   ✗ Kaggle ASL: {e}")

# ASL Landmarks dataset
try:
    asl = pd.read_csv('asl_landmarks.csv')
    print(f"   ✓ ASL Landmarks: {len(asl)} samples, {asl['label'].nunique()} classes")
    datasets.append(('ASL', asl))
except Exception as e:
    print(f"   ✗ ASL Landmarks: {e}")

# Feature columns (63 features: 21 landmarks x 3 coordinates)
feature_cols = [f'x{i}' if j == 0 else f'y{i}' if j == 1 else f'z{i}' 
                for i in range(21) for j in range(3)]

# Standardize and merge all datasets
print("\n2. Merging datasets...")
all_dfs = []
for name, df in datasets:
    # Ensure dataset has required columns
    if 'label' in df.columns:
        # Select only the columns we need
        cols_to_use = [c for c in feature_cols if c in df.columns] + ['label']
        if len(cols_to_use) == 64:  # 63 features + label
            all_dfs.append(df[cols_to_use])
        else:
            print(f"   Warning: {name} has {len(cols_to_use)-1} features, skipping")

all_data = pd.concat(all_dfs, ignore_index=True)
print(f"   Total samples: {len(all_data)}")

# Get class distribution
class_counts = all_data['label'].value_counts()
print(f"   Unique classes: {len(class_counts)}")

# Select classes with minimum samples
min_samples = 30
eligible_classes = class_counts[class_counts >= min_samples]
top_classes = eligible_classes.head(100).index.tolist()

print(f"\n3. Selecting top 100 classes (min {min_samples} samples each)...")
print(f"   Eligible classes: {len(eligible_classes)}")
print(f"   Selected: {len(top_classes)} classes")

# Filter data
filtered_data = all_data[all_data['label'].isin(top_classes)]
print(f"   Filtered samples: {len(filtered_data)}")

# Prepare features
X = filtered_data[feature_cols].values.astype(np.float32)
y = filtered_data['label'].values
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

# Train RandomForest with balanced classes
print("\n6. Training RandomForest classifier...")
model = RandomForestClassifier(
    n_estimators=300,
    max_depth=None,
    min_samples_split=2,
    min_samples_leaf=1,
    class_weight='balanced',
    n_jobs=-1,
    random_state=42
)
model.fit(X_train, y_train)

# Evaluate
train_acc = model.score(X_train, y_train)
test_acc = model.score(X_test, y_test)
print(f"   Train accuracy: {train_acc*100:.1f}%")
print(f"   Test accuracy: {test_acc*100:.1f}%")

# Save sklearn models
print("\n7. Saving sklearn models...")
joblib.dump(model, 'asl_citizen_model.pkl')
joblib.dump(encoder, 'asl_citizen_encoder.pkl')
joblib.dump(scaler, 'asl_citizen_scaler.pkl')

# Compute centroids for iOS
print("\n8. Computing centroids for iOS...")
centroids = {}
for label in encoder.classes_:
    mask = filtered_data['label'] == label
    samples = filtered_data[mask][feature_cols].values
    samples = np.nan_to_num(samples, nan=0.0)
    scaled_samples = scaler.transform(samples)
    centroid = np.mean(scaled_samples, axis=0)
    centroids[label] = centroid.tolist()

# Export for iOS
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
print(f"\n  Total Samples Used: {len(filtered_data)}")
print(f"  Classes: {len(encoder.classes_)}")
print(f"  Test Accuracy: {test_acc*100:.1f}%")
print(f"  Saved: ASLModelData.json")
print("\n  Top 20 classes by sample count:")
for label in class_counts.head(20).index:
    if label in encoder.classes_:
        count = class_counts[label]
        print(f"    {label}: {count} samples")

print("\n  All signs included:")
signs = sorted(encoder.classes_)
for i in range(0, len(signs), 5):
    row = signs[i:i+5]
    print(f"    {', '.join(row)}")

print("\n" + "="*60)
