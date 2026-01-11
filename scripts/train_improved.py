#!/usr/bin/env python3
"""
Improved ASL Model Training Script

Uses neural network with data augmentation and feature engineering
to achieve higher accuracy (target: 90%+).
"""

import numpy as np
import pandas as pd
import joblib
import os
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.neural_network import MLPClassifier
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.metrics import accuracy_score, classification_report
import warnings
warnings.filterwarnings('ignore')

# Configuration
INPUT_CSV = "asl_citizen_landmarks.csv"
MODEL_FILE = "asl_citizen_model.pkl"
ENCODER_FILE = "asl_citizen_encoder.pkl"
SCALER_FILE = "asl_citizen_scaler.pkl"
LANDMARK_COUNT = 21


def load_data(csv_path: str):
    """Load landmark data from CSV."""
    print(f"\n📂 Loading data from: {csv_path}")
    df = pd.read_csv(csv_path)
    print(f"   Loaded {len(df)} samples")
    print(f"   Labels: {df['label'].nunique()} unique classes")
    return df


def extract_advanced_features(coords: np.ndarray) -> np.ndarray:
    """
    Extract advanced features from hand landmarks.
    Input: 63 values (21 landmarks x 3 coords)
    Output: Enhanced feature vector with angles, distances, ratios
    """
    # Reshape to (21, 3)
    landmarks = coords.reshape(21, 3)
    
    features = []
    
    # 1. Original normalized coordinates (63 features)
    wrist = landmarks[0]
    # Normalize by wrist
    for i in range(21):
        diff = landmarks[i] - wrist
        features.extend(diff.tolist())
    
    # 2. Fingertip to wrist distances (5 features)
    fingertips = [4, 8, 12, 16, 20]  # Thumb, Index, Middle, Ring, Pinky tips
    for tip_idx in fingertips:
        dist = np.linalg.norm(landmarks[tip_idx] - wrist)
        features.append(dist)
    
    # 3. Fingertip to fingertip distances (10 features - all pairs)
    for i, tip1 in enumerate(fingertips):
        for tip2 in fingertips[i+1:]:
            dist = np.linalg.norm(landmarks[tip1] - landmarks[tip2])
            features.append(dist)
    
    # 4. Finger curl ratios (5 features)
    # Compare fingertip-MCP distance to finger length
    finger_bases = [1, 5, 9, 13, 17]  # MCP joints
    finger_mids = [2, 6, 10, 14, 18]  # PIP joints
    for i, (tip, base, mid) in enumerate(zip(fingertips, finger_bases, finger_mids)):
        tip_to_base = np.linalg.norm(landmarks[tip] - landmarks[base])
        full_length = (np.linalg.norm(landmarks[mid] - landmarks[base]) + 
                       np.linalg.norm(landmarks[tip] - landmarks[mid]))
        curl_ratio = tip_to_base / (full_length + 0.0001)
        features.append(curl_ratio)
    
    # 5. Palm orientation (3 features) - using cross product of palm vectors
    palm_vec1 = landmarks[5] - landmarks[0]  # Wrist to index MCP
    palm_vec2 = landmarks[17] - landmarks[0]  # Wrist to pinky MCP
    palm_normal = np.cross(palm_vec1, palm_vec2)
    palm_normal = palm_normal / (np.linalg.norm(palm_normal) + 0.0001)
    features.extend(palm_normal.tolist())
    
    # 6. Thumb position relative to palm (3 features)
    thumb_tip = landmarks[4]
    palm_center = (landmarks[0] + landmarks[5] + landmarks[9] + landmarks[13] + landmarks[17]) / 5
    thumb_rel = thumb_tip - palm_center
    features.extend(thumb_rel.tolist())
    
    # 7. Finger spread angles (4 features)
    for i in range(len(fingertips) - 1):
        vec1 = landmarks[fingertips[i]] - landmarks[finger_bases[i]]
        vec2 = landmarks[fingertips[i+1]] - landmarks[finger_bases[i+1]]
        cos_angle = np.dot(vec1, vec2) / (np.linalg.norm(vec1) * np.linalg.norm(vec2) + 0.0001)
        features.append(cos_angle)
    
    return np.array(features)


def augment_sample(coords: np.ndarray, num_augments: int = 8) -> list:
    """
    Augment a single sample with noise and transformations.
    More augmentation = better generalization.
    """
    augmented = [coords]  # Include original
    
    landmarks = coords.reshape(21, 3)
    
    for i in range(num_augments):
        aug = landmarks.copy()
        
        # Random noise (varying intensity)
        noise_level = 0.005 + (i * 0.002)  # 0.005 to 0.021
        noise = np.random.normal(0, noise_level, aug.shape)
        aug += noise
        
        # Random scale (0.85 to 1.15)
        scale = np.random.uniform(0.85, 1.15)
        aug *= scale
        
        # Random rotation around z-axis
        angle = np.random.uniform(-0.15, 0.15)  # radians
        cos_a, sin_a = np.cos(angle), np.sin(angle)
        rot_z = np.array([[cos_a, -sin_a, 0],
                          [sin_a, cos_a, 0],
                          [0, 0, 1]])
        aug = aug @ rot_z.T
        
        # Random rotation around x-axis (simulates viewing angle)
        if i % 2 == 0:
            angle_x = np.random.uniform(-0.1, 0.1)
            cos_x, sin_x = np.cos(angle_x), np.sin(angle_x)
            rot_x = np.array([[1, 0, 0],
                              [0, cos_x, -sin_x],
                              [0, sin_x, cos_x]])
            aug = aug @ rot_x.T
        
        # Random translation (shift)
        if i % 3 == 0:
            shift = np.random.uniform(-0.02, 0.02, 3)
            aug += shift
        
        augmented.append(aug.flatten())
    
    return augmented


def prepare_data(df: pd.DataFrame, augment: bool = True):
    """Prepare features with augmentation and advanced feature extraction."""
    print("\n🔧 Preparing features...")
    
    feature_cols = [c for c in df.columns if c != 'label']
    X_raw = df[feature_cols].values
    y_raw = df['label'].values
    
    X_features = []
    y_labels = []
    
    print("   Extracting advanced features and augmenting...")
    for i, (coords, label) in enumerate(zip(X_raw, y_raw)):
        if augment:
            augmented_samples = augment_sample(coords, num_augments=3)
        else:
            augmented_samples = [coords]
        
        for aug_coords in augmented_samples:
            features = extract_advanced_features(aug_coords)
            X_features.append(features)
            y_labels.append(label)
        
        if (i + 1) % 5000 == 0:
            print(f"      Processed {i+1}/{len(X_raw)} samples...")
    
    X = np.array(X_features)
    y = np.array(y_labels)
    
    print(f"   ✓ Generated {len(X)} samples with {X.shape[1]} features each")
    
    return X, y


def train_neural_network(X_train, y_train, X_test, y_test, encoder):
    """Train MLP neural network."""
    print("\n🧠 Training Neural Network (MLP)...")
    print(f"   Hidden layers: (256, 128, 64)")
    print(f"   Training samples: {len(X_train)}")
    
    mlp = MLPClassifier(
        hidden_layer_sizes=(512, 256, 128, 64),  # Deeper network
        activation='relu',
        solver='adam',
        alpha=0.0005,  # Less regularization
        batch_size=128,
        learning_rate='adaptive',
        learning_rate_init=0.001,
        max_iter=1000,
        early_stopping=True,
        validation_fraction=0.1,
        n_iter_no_change=30,
        verbose=True,
        random_state=42
    )
    
    mlp.fit(X_train, y_train)
    
    # Evaluate
    y_pred = mlp.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    # Top-5 accuracy
    y_proba = mlp.predict_proba(X_test)
    top5_acc = np.mean([y_test[i] in np.argsort(y_proba[i])[-5:] 
                        for i in range(len(y_test))])
    
    print(f"\n   ✓ MLP Accuracy: {accuracy*100:.2f}%")
    print(f"   ✓ MLP Top-5 Accuracy: {top5_acc*100:.2f}%")
    
    return mlp, accuracy, top5_acc


def train_ensemble(X_train, y_train, X_test, y_test, encoder):
    """Train ensemble model (RandomForest + GradientBoosting)."""
    print("\n🌲 Training Ensemble (RandomForest + GradientBoosting)...")
    
    # RandomForest with more trees
    rf = RandomForestClassifier(
        n_estimators=300,
        max_depth=None,
        min_samples_split=2,
        min_samples_leaf=1,
        max_features='sqrt',
        n_jobs=-1,
        random_state=42,
        verbose=1
    )
    
    rf.fit(X_train, y_train)
    rf_pred = rf.predict(X_test)
    rf_acc = accuracy_score(y_test, rf_pred)
    print(f"   RandomForest Accuracy: {rf_acc*100:.2f}%")
    
    # Top-5 accuracy
    rf_proba = rf.predict_proba(X_test)
    rf_top5 = np.mean([y_test[i] in np.argsort(rf_proba[i])[-5:] 
                       for i in range(len(y_test))])
    print(f"   RandomForest Top-5: {rf_top5*100:.2f}%")
    
    return rf, rf_acc, rf_top5


def main():
    print("=" * 60)
    print("  Improved ASL Model Training (Target: 90%+)")
    print("=" * 60)
    
    # Load data
    df = load_data(INPUT_CSV)
    
    # Show class distribution
    print("\n   Top 10 classes by sample count:")
    class_counts = df['label'].value_counts()
    for i, (label, count) in enumerate(class_counts.head(10).items()):
        print(f"      {i+1}. {label}: {count} samples")
    
    # Prepare features with augmentation
    X, y = prepare_data(df, augment=True)
    
    # Encode labels
    print("\n🏷️  Encoding labels...")
    encoder = LabelEncoder()
    y_encoded = encoder.fit_transform(y)
    print(f"   Classes: {len(encoder.classes_)}")
    
    # Scale features
    print("\n📊 Scaling features...")
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    
    # Split data
    print("\n✂️  Splitting data: 80% train, 20% test")
    X_train, X_test, y_train, y_test = train_test_split(
        X_scaled, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
    )
    print(f"   Training: {len(X_train)} samples")
    print(f"   Testing: {len(X_test)} samples")
    
    # Train models
    mlp, mlp_acc, mlp_top5 = train_neural_network(X_train, y_train, X_test, y_test, encoder)
    rf, rf_acc, rf_top5 = train_ensemble(X_train, y_train, X_test, y_test, encoder)
    
    # Choose best model
    print("\n" + "=" * 60)
    print("  MODEL COMPARISON")
    print("=" * 60)
    print(f"   Neural Network: {mlp_acc*100:.2f}% (Top-5: {mlp_top5*100:.2f}%)")
    print(f"   RandomForest:   {rf_acc*100:.2f}% (Top-5: {rf_top5*100:.2f}%)")
    
    if mlp_acc >= rf_acc:
        best_model = mlp
        best_acc = mlp_acc
        best_top5 = mlp_top5
        model_name = "Neural Network"
    else:
        best_model = rf
        best_acc = rf_acc
        best_top5 = rf_top5
        model_name = "RandomForest"
    
    print(f"\n   🏆 Best Model: {model_name}")
    
    # Save models
    print("\n💾 Saving model and encoder...")
    joblib.dump(best_model, MODEL_FILE)
    joblib.dump(encoder, ENCODER_FILE)
    joblib.dump(scaler, SCALER_FILE)
    print(f"   ✓ Model saved: {MODEL_FILE}")
    print(f"   ✓ Encoder saved: {ENCODER_FILE}")
    print(f"   ✓ Scaler saved: {SCALER_FILE}")
    
    # Final summary
    print("\n" + "=" * 60)
    print("  TRAINING COMPLETE")
    print("=" * 60)
    print(f"\n   📊 Top-1 Accuracy: {best_acc*100:.2f}%")
    print(f"   📊 Top-5 Accuracy: {best_top5*100:.2f}%")
    print(f"   📁 Model: {MODEL_FILE}")
    print(f"   🏷️  Classes: {len(encoder.classes_)}")
    print(f"\n   Test with: python3 real_time_asl.py")
    print("=" * 60)


if __name__ == "__main__":
    main()
