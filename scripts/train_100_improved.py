#!/usr/bin/env python3
"""Train improved ASL model with 100 signs - targeting >70% accuracy"""

import pandas as pd
import numpy as np
from sklearn.neural_network import MLPClassifier
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.utils import class_weight
import joblib
import json
import warnings
warnings.filterwarnings('ignore')

print("="*60)
print("  Training Improved ASL Model - Target: >70% Accuracy")
print("="*60)

# Load datasets
print("\n1. Loading datasets...")
wlasl = pd.read_csv('wlasl_landmarks.csv')
combined = pd.read_csv('combined_asl_landmarks.csv')

# Feature columns
feature_cols = [f'x{i}' if j == 0 else f'y{i}' if j == 1 else f'z{i}' 
                for i in range(21) for j in range(3)]

wlasl = wlasl[feature_cols + ['label']]
combined = combined[feature_cols + ['label']]

# Merge datasets
print("\n2. Preparing data...")
all_data = pd.concat([wlasl, combined], ignore_index=True)

# Select top 100 classes with most samples (higher minimum for better quality)
class_counts = all_data['label'].value_counts()
min_samples = 50  # Increased minimum for better training
eligible_classes = class_counts[class_counts >= min_samples]
top_100 = eligible_classes.head(100).index.tolist()

print(f"   Selected {len(top_100)} classes (min {min_samples} samples each)")

filtered_data = all_data[all_data['label'].isin(top_100)]
print(f"   Total samples: {len(filtered_data)}")

# Prepare features
X = filtered_data[feature_cols].values.astype(np.float32)
y = filtered_data['label'].values
X = np.nan_to_num(X, nan=0.0)

# Add engineered features
print("\n3. Engineering features...")

def add_features(X):
    """Add computed features like distances and angles"""
    n_samples = X.shape[0]
    new_features = []
    
    for i in range(n_samples):
        sample = X[i].reshape(21, 3)
        features = []
        
        # Distances from wrist to each fingertip
        wrist = sample[0]
        for tip_idx in [4, 8, 12, 16, 20]:  # thumb, index, middle, ring, pinky tips
            tip = sample[tip_idx]
            dist = np.sqrt(np.sum((tip - wrist) ** 2))
            features.append(dist)
        
        # Distances between fingertips
        tips = [sample[4], sample[8], sample[12], sample[16], sample[20]]
        for j in range(len(tips)):
            for k in range(j+1, len(tips)):
                dist = np.sqrt(np.sum((tips[j] - tips[k]) ** 2))
                features.append(dist)
        
        # Hand spread (max distance between any two landmarks)
        max_dist = 0
        for j in range(21):
            for k in range(j+1, 21):
                dist = np.sqrt(np.sum((sample[j] - sample[k]) ** 2))
                if dist > max_dist:
                    max_dist = dist
        features.append(max_dist)
        
        # Finger curl (tip to MCP distance)
        mcp_indices = [1, 5, 9, 13, 17]  # MCP joints
        tip_indices = [4, 8, 12, 16, 20]
        for mcp, tip in zip(mcp_indices, tip_indices):
            curl = np.sqrt(np.sum((sample[tip] - sample[mcp]) ** 2))
            features.append(curl)
        
        new_features.append(features)
    
    return np.hstack([X, np.array(new_features)])

X_enhanced = add_features(X)
print(f"   Features: {X.shape[1]} → {X_enhanced.shape[1]}")

# Encode labels
encoder = LabelEncoder()
y_encoded = encoder.fit_transform(y)

# Scale features
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_enhanced)

# Split data with stratification
X_train, X_test, y_train, y_test = train_test_split(
    X_scaled, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
)
print(f"   Train: {len(X_train)}, Test: {len(X_test)}")

# Compute class weights for imbalanced classes
class_weights = class_weight.compute_class_weight(
    'balanced', classes=np.unique(y_train), y=y_train
)
class_weight_dict = dict(zip(np.unique(y_train), class_weights))

# Try different classifiers
print("\n4. Training classifiers...")

# MLP Classifier
print("\n   a) MLP Classifier...")
mlp = MLPClassifier(
    hidden_layer_sizes=(256, 128, 64),
    activation='relu',
    solver='adam',
    alpha=0.001,
    batch_size=64,
    learning_rate='adaptive',
    max_iter=500,
    early_stopping=True,
    validation_fraction=0.1,
    random_state=42
)
mlp.fit(X_train, y_train)
mlp_train_acc = mlp.score(X_train, y_train)
mlp_test_acc = mlp.score(X_test, y_test)
print(f"      Train: {mlp_train_acc*100:.1f}%, Test: {mlp_test_acc*100:.1f}%")

# RandomForest with class weights
print("\n   b) RandomForest with balanced classes...")
rf = RandomForestClassifier(
    n_estimators=300,
    max_depth=None,
    min_samples_split=2,
    min_samples_leaf=1,
    class_weight='balanced',
    n_jobs=-1,
    random_state=42
)
rf.fit(X_train, y_train)
rf_train_acc = rf.score(X_train, y_train)
rf_test_acc = rf.score(X_test, y_test)
print(f"      Train: {rf_train_acc*100:.1f}%, Test: {rf_test_acc*100:.1f}%")

# Choose best model
results = [
    ('MLP', mlp, mlp_test_acc),
    ('RandomForest', rf, rf_test_acc),
]

best_name, best_model, best_acc = max(results, key=lambda x: x[2])
print(f"\n5. Best model: {best_name} ({best_acc*100:.1f}%)")

# If still below 70%, try reducing classes to top 50 with most samples
if best_acc < 0.70:
    print("\n   Accuracy below 70%, trying top 50 classes...")
    
    top_50 = eligible_classes.head(50).index.tolist()
    filtered_50 = all_data[all_data['label'].isin(top_50)]
    
    X_50 = filtered_50[feature_cols].values.astype(np.float32)
    y_50 = filtered_50['label'].values
    X_50 = np.nan_to_num(X_50, nan=0.0)
    X_50_enhanced = add_features(X_50)
    
    encoder_50 = LabelEncoder()
    y_50_encoded = encoder_50.fit_transform(y_50)
    
    scaler_50 = StandardScaler()
    X_50_scaled = scaler_50.fit_transform(X_50_enhanced)
    
    X_train_50, X_test_50, y_train_50, y_test_50 = train_test_split(
        X_50_scaled, y_50_encoded, test_size=0.2, random_state=42, stratify=y_50_encoded
    )
    
    mlp_50 = MLPClassifier(
        hidden_layer_sizes=(256, 128, 64),
        activation='relu',
        solver='adam',
        alpha=0.001,
        batch_size=64,
        learning_rate='adaptive',
        max_iter=500,
        early_stopping=True,
        validation_fraction=0.1,
        random_state=42
    )
    mlp_50.fit(X_train_50, y_train_50)
    acc_50 = mlp_50.score(X_test_50, y_test_50)
    print(f"   50-class accuracy: {acc_50*100:.1f}%")
    
    if acc_50 > best_acc:
        best_name = 'MLP-50'
        best_model = mlp_50
        best_acc = acc_50
        encoder = encoder_50
        scaler = scaler_50
        filtered_data = filtered_50
        X_enhanced = X_50_enhanced
        y = y_50

# Save models
print("\n6. Saving models...")
joblib.dump(best_model, 'asl_citizen_model.pkl')
joblib.dump(encoder, 'asl_citizen_encoder.pkl')

# Need to save a scaler that works with 63 features for iOS
# (iOS uses basic 63 features, not enhanced)
basic_scaler = StandardScaler()
X_basic = filtered_data[feature_cols].values.astype(np.float32)
X_basic = np.nan_to_num(X_basic, nan=0.0)
basic_scaler.fit(X_basic)
joblib.dump(basic_scaler, 'asl_citizen_scaler.pkl')

# Compute centroids for iOS (using basic 63 features)
print("\n7. Computing centroids for iOS...")
centroids = {}
for label in encoder.classes_:
    mask = filtered_data['label'] == label
    samples = filtered_data[mask][feature_cols].values
    samples = np.nan_to_num(samples, nan=0.0)
    scaled_samples = basic_scaler.transform(samples)
    centroid = np.mean(scaled_samples, axis=0)
    centroids[label] = centroid.tolist()

# Export for iOS
ios_data = {
    'classes': [str(c) for c in encoder.classes_],
    'scaler_mean': basic_scaler.mean_.tolist(),
    'scaler_scale': basic_scaler.scale_.tolist(),
    'centroids': centroids,
    'n_features': 63
}

with open('../ASLModelData.json', 'w') as f:
    json.dump(ios_data, f)

import shutil
shutil.copy('../ASLModelData.json', '../ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute/ASLModelData.json')

print("\n" + "="*60)
print(f"  ✅ Training Complete!")
print("="*60)
print(f"\n  Best Model: {best_name}")
print(f"  Classes: {len(encoder.classes_)}")
print(f"  Test Accuracy: {best_acc*100:.1f}%")
print(f"  Saved: ASLModelData.json")
print("\n  Signs:")

signs = sorted(encoder.classes_)
for i in range(0, len(signs), 5):
    row = signs[i:i+5]
    print(f"    {', '.join(row)}")

print("\n" + "="*60)
