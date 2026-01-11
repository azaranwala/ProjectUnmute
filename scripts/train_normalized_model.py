#!/usr/bin/env python3
"""
Train ASL Model with Proper Wrist-Centered Normalization
This ensures training and real-time use the same normalization.
"""

import pandas as pd
import numpy as np
import joblib
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import accuracy_score
import warnings
warnings.filterwarnings('ignore')


def normalize_to_wrist(coords):
    """
    Normalize landmarks: center on wrist, scale by hand size.
    This must match real_time_asl.py normalization exactly.
    """
    coords = np.array(coords).reshape(21, 3)
    
    # Center on wrist (landmark 0)
    wrist = coords[0].copy()
    centered = coords - wrist
    
    # Scale by distance from wrist to middle finger MCP (landmark 9)
    hand_size = np.linalg.norm(centered[9])
    if hand_size < 0.001:
        hand_size = 1.0
    
    normalized = centered / hand_size
    return normalized.flatten()


def augment_normalized(coords, n=6):
    """Augment normalized landmarks with rotations and noise."""
    result = [coords.copy()]
    lm = coords.reshape(21, 3)
    
    for _ in range(n):
        aug = lm.copy()
        
        # Rotation around Z axis (±20 degrees)
        angle = np.random.uniform(-0.35, 0.35)  # radians
        c, s = np.cos(angle), np.sin(angle)
        rot = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
        aug = aug @ rot.T
        
        # Small scale variation
        aug *= np.random.uniform(0.9, 1.1)
        
        # Small noise
        aug += np.random.normal(0, 0.02, aug.shape)
        
        result.append(aug.flatten())
    
    return result


def main():
    print("=" * 60)
    print("  Training ASL Model with Wrist-Centered Normalization")
    print("=" * 60)
    
    # Load datasets
    print("\n📂 Loading datasets...")
    combined = pd.read_csv('combined_asl_landmarks.csv')
    wlasl = pd.read_csv('wlasl_landmarks.csv')
    all_data = pd.concat([combined, wlasl], ignore_index=True)
    
    feature_cols = [c for c in all_data.columns if c != 'label']
    X_raw = all_data[feature_cols].values
    y = all_data['label'].values
    
    print(f"   Raw samples: {len(X_raw)}, Classes: {len(set(y))}")
    
    # Normalize all samples
    print("\n🔄 Normalizing landmarks (wrist-centered)...")
    X_norm = np.array([normalize_to_wrist(x) for x in X_raw])
    
    # Check for valid samples (no NaN/inf)
    valid_mask = ~(np.isnan(X_norm).any(axis=1) | np.isinf(X_norm).any(axis=1))
    X_norm = X_norm[valid_mask]
    y = y[valid_mask]
    print(f"   Valid samples: {len(X_norm)}")
    
    # Augmentation
    print("\n🔄 Applying augmentation...")
    X_aug, y_aug = [], []
    for x, label in zip(X_norm, y):
        for ax in augment_normalized(x, n=5):
            X_aug.append(ax)
            y_aug.append(label)
    
    X = np.array(X_aug)
    y = np.array(y_aug)
    print(f"   Augmented samples: {len(X)}")
    
    # Encode labels
    encoder = LabelEncoder()
    y_enc = encoder.fit_transform(y)
    
    # Split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y_enc, test_size=0.15, random_state=42, stratify=y_enc
    )
    
    print(f"\n📊 Train: {len(X_train)}, Test: {len(X_test)}")
    print(f"   Classes: {len(encoder.classes_)}")
    
    # Train
    print("\n🧠 Training Neural Network...")
    mlp = MLPClassifier(
        hidden_layer_sizes=(512, 256, 128),
        activation='relu',
        solver='adam',
        alpha=0.0005,
        batch_size=128,
        learning_rate='adaptive',
        learning_rate_init=0.001,
        max_iter=300,
        early_stopping=True,
        validation_fraction=0.1,
        n_iter_no_change=20,
        verbose=True,
        random_state=42
    )
    mlp.fit(X_train, y_train)
    
    # Evaluate
    y_pred = mlp.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    
    y_proba = mlp.predict_proba(X_test)
    top5 = np.mean([y_test[i] in np.argsort(y_proba[i])[-5:] for i in range(len(y_test))])
    
    print(f"\n✅ Results:")
    print(f"   Top-1 Accuracy: {acc*100:.2f}%")
    print(f"   Top-5 Accuracy: {top5*100:.2f}%")
    
    # Save model (NO scaler needed - normalization is built into preprocessing)
    joblib.dump(mlp, 'asl_citizen_model.pkl')
    joblib.dump(encoder, 'asl_citizen_encoder.pkl')
    
    # Remove old scaler if exists
    import os
    if os.path.exists('asl_citizen_scaler.pkl'):
        os.remove('asl_citizen_scaler.pkl')
    
    print(f"\n💾 Model saved!")
    print(f"   Classes: {list(encoder.classes_)[:15]}...")
    
    # Per-class accuracy for top signs
    print("\n📊 Per-class accuracy (sample):")
    from collections import defaultdict
    class_correct = defaultdict(int)
    class_total = defaultdict(int)
    for true, pred in zip(y_test, y_pred):
        class_total[true] += 1
        if true == pred:
            class_correct[true] += 1
    
    class_acc = [(encoder.classes_[c], class_correct[c]/class_total[c]*100, class_total[c]) 
                 for c in class_total if class_total[c] >= 10]
    class_acc.sort(key=lambda x: x[1], reverse=True)
    
    print("\n   Top 15 best-performing classes:")
    for cls, acc, cnt in class_acc[:15]:
        print(f"   {cls}: {acc:.1f}% ({cnt} samples)")
    
    print("\n" + "=" * 60)
    print("  Training Complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
