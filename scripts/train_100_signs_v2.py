#!/usr/bin/env python3
"""Train ASL model with 100 signs - improved with augmentation"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split
import joblib
import json

print("="*60)
print("  Training ASL Model with 100 Signs (with Augmentation)")
print("="*60)

# Load datasets
print("\n1. Loading datasets...")
wlasl = pd.read_csv('wlasl_landmarks.csv')
combined = pd.read_csv('combined_asl_landmarks.csv')

# Standardize column names
feature_cols = [f'x{i}' if j == 0 else f'y{i}' if j == 1 else f'z{i}' 
                for i in range(21) for j in range(3)]

wlasl = wlasl[feature_cols + ['label']]
combined = combined[feature_cols + ['label']]

# Merge datasets
print("\n2. Merging datasets...")
all_data = pd.concat([wlasl, combined], ignore_index=True)

# Select top 100 classes with most samples
class_counts = all_data['label'].value_counts()
min_samples = 20
eligible_classes = class_counts[class_counts >= min_samples]
top_100 = eligible_classes.head(100).index.tolist()

print(f"   Selected {len(top_100)} classes")

filtered_data = all_data[all_data['label'].isin(top_100)]
print(f"   Base samples: {len(filtered_data)}")

# Data augmentation function
def augment_sample(sample, n_augments=5):
    """Generate augmented versions of a sample"""
    augmented = []
    for _ in range(n_augments):
        aug = sample.copy()
        
        # Add small noise
        noise = np.random.normal(0, 0.02, len(aug))
        aug = aug + noise
        
        # Random scaling (0.9 to 1.1)
        scale = np.random.uniform(0.9, 1.1)
        aug = aug * scale
        
        # Random translation
        tx = np.random.uniform(-0.05, 0.05)
        ty = np.random.uniform(-0.05, 0.05)
        for i in range(21):
            aug[i*3] += tx     # x
            aug[i*3 + 1] += ty # y
        
        augmented.append(aug)
    return augmented

# Apply augmentation
print("\n3. Augmenting data...")
X_list = []
y_list = []

for label in top_100:
    samples = filtered_data[filtered_data['label'] == label][feature_cols].values
    samples = np.nan_to_num(samples, nan=0.0)
    
    for sample in samples:
        X_list.append(sample)
        y_list.append(label)
        
        # Add augmented samples
        for aug_sample in augment_sample(sample, n_augments=3):
            X_list.append(aug_sample)
            y_list.append(label)

X = np.array(X_list, dtype=np.float32)
y = np.array(y_list)
print(f"   Augmented samples: {len(X)}")

# Encode labels
print("\n4. Encoding labels...")
encoder = LabelEncoder()
y_encoded = encoder.fit_transform(y)

# Scale features
print("\n5. Scaling features...")
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# Split data
X_train, X_test, y_train, y_test = train_test_split(
    X_scaled, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
)
print(f"   Train: {len(X_train)}, Test: {len(X_test)}")

# Train RandomForest with more trees
print("\n6. Training RandomForest classifier...")
model = RandomForestClassifier(
    n_estimators=200,
    max_depth=30,
    min_samples_split=3,
    min_samples_leaf=1,
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
    mask = y == label
    samples = X[mask]
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

# Copy to iOS project
import shutil
shutil.copy('../ASLModelData.json', '../ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute/ASLModelData.json')

print("\n" + "="*60)
print("  ✅ Training Complete!")
print("="*60)
print(f"\n  Model: {len(encoder.classes_)} signs")
print(f"  Test Accuracy: {test_acc*100:.1f}%")
print(f"  Saved: ASLModelData.json")
print("\n  Signs included:")

signs = sorted(encoder.classes_)
for i in range(0, len(signs), 5):
    row = signs[i:i+5]
    print(f"    {', '.join(row)}")

print("\n" + "="*60)
