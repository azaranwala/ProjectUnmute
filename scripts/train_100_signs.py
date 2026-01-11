#!/usr/bin/env python3
"""Train ASL model with 100 signs for iOS integration"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split
import joblib
import json

print("="*60)
print("  Training ASL Model with 100 Signs")
print("="*60)

# Load datasets
print("\n1. Loading datasets...")
wlasl = pd.read_csv('wlasl_landmarks.csv')
combined = pd.read_csv('combined_asl_landmarks.csv')

print(f"   WLASL: {len(wlasl)} samples, {wlasl['label'].nunique()} classes")
print(f"   Combined: {len(combined)} samples, {combined['label'].nunique()} classes")

# Standardize column names (use first 63 features + label)
feature_cols = [f'x{i}' if j == 0 else f'y{i}' if j == 1 else f'z{i}' 
                for i in range(21) for j in range(3)]

# Ensure both datasets have same columns
wlasl = wlasl[feature_cols + ['label']]
combined = combined[feature_cols + ['label']]

# Merge datasets
print("\n2. Merging datasets...")
all_data = pd.concat([wlasl, combined], ignore_index=True)
print(f"   Total: {len(all_data)} samples")

# Count samples per class
class_counts = all_data['label'].value_counts()
print(f"   Unique classes: {len(class_counts)}")

# Select top 100 classes with most samples (minimum 20 samples each)
min_samples = 20
eligible_classes = class_counts[class_counts >= min_samples]
top_100 = eligible_classes.head(100).index.tolist()

print(f"\n3. Selecting top 100 signs (min {min_samples} samples each)...")
print(f"   Selected {len(top_100)} classes")

# Filter data to top 100 classes
filtered_data = all_data[all_data['label'].isin(top_100)]
print(f"   Filtered samples: {len(filtered_data)}")

# Prepare features and labels
X = filtered_data[feature_cols].values.astype(np.float32)
y = filtered_data['label'].values

# Handle NaN values
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
    n_estimators=100,
    max_depth=20,
    min_samples_split=5,
    min_samples_leaf=2,
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

# Compute centroids for iOS template matching
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

# Copy to iOS project
import shutil
shutil.copy('../ASLModelData.json', '../ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute/ASLModelData.json')

print("\n" + "="*60)
print("  ✅ Training Complete!")
print("="*60)
print(f"\n  Model: {len(encoder.classes_)} signs")
print(f"  Accuracy: {test_acc*100:.1f}%")
print(f"  Saved: ASLModelData.json")
print("\n  Signs included:")

# Print all signs in a nice format
signs = sorted(encoder.classes_)
for i in range(0, len(signs), 5):
    row = signs[i:i+5]
    print(f"    {', '.join(row)}")

print("\n" + "="*60)
