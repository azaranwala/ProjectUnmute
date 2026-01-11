#!/usr/bin/env python3
"""
ASL Citizen Model Training Script

Trains a RandomForest classifier on landmarks extracted from ASL Citizen dataset.

Usage:
    python3 train_asl_citizen.py

Input:
    - asl_citizen_landmarks.csv (from process_asl_citizen.py)

Output:
    - asl_citizen_model.pkl
    - asl_citizen_encoder.pkl
"""

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report, accuracy_score, confusion_matrix
import joblib
import os
import sys

# Configuration
INPUT_FILE = "asl_citizen_landmarks.csv"
MODEL_FILE = "asl_citizen_model.pkl"
ENCODER_FILE = "asl_citizen_encoder.pkl"
TEST_SIZE = 0.20
RANDOM_STATE = 42
LANDMARK_COUNT = 21

# Model hyperparameters (optimized for large dataset)
N_ESTIMATORS = 200
MAX_DEPTH = 30
MIN_SAMPLES_SPLIT = 5
MIN_SAMPLES_LEAF = 2


def load_data(filepath: str):
    """Load the landmark data from CSV."""
    print(f"\n📂 Loading data from: {filepath}")
    
    if not os.path.exists(filepath):
        print(f"❌ Error: File not found: {filepath}")
        print("   Please run process_asl_citizen.py first.")
        sys.exit(1)
    
    df = pd.read_csv(filepath)
    
    print(f"   Loaded {len(df)} samples")
    print(f"   Features: {len(df.columns) - 1}")
    print(f"   Labels: {df['label'].nunique()} unique classes")
    
    # Show class distribution
    print(f"\n   Top 10 classes by sample count:")
    class_counts = df['label'].value_counts()
    for i, (label, count) in enumerate(class_counts.head(10).items()):
        print(f"      {i+1}. {label}: {count} samples")
    
    return df


def normalize_landmarks(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize landmarks by centering around wrist."""
    print("\n🔧 Normalizing landmarks (wrist-centered)...")
    
    df_normalized = df.copy()
    feature_cols = [col for col in df.columns if col != 'label']
    
    normalized_data = []
    
    for idx, row in df.iterrows():
        # Wrist coordinates (landmark 0)
        wrist_x = row['x0']
        wrist_y = row['y0']
        wrist_z = row['z0']
        
        # Hand scale (wrist to middle finger MCP)
        dx = row['x9'] - wrist_x
        dy = row['y9'] - wrist_y
        dz = row['z9'] - wrist_z
        hand_scale = np.sqrt(dx**2 + dy**2 + dz**2)
        
        if hand_scale < 0.001:
            hand_scale = 1.0
        
        # Normalize
        normalized_row = {}
        for i in range(LANDMARK_COUNT):
            normalized_row[f'x{i}'] = (row[f'x{i}'] - wrist_x) / hand_scale
            normalized_row[f'y{i}'] = (row[f'y{i}'] - wrist_y) / hand_scale
            normalized_row[f'z{i}'] = (row[f'z{i}'] - wrist_z) / hand_scale
        
        normalized_row['label'] = row['label']
        normalized_data.append(normalized_row)
        
        # Progress
        if (idx + 1) % 10000 == 0:
            print(f"      Processed {idx + 1}/{len(df)} samples...")
    
    df_normalized = pd.DataFrame(normalized_data)
    print(f"   ✓ Normalized {len(df_normalized)} samples")
    
    return df_normalized


def prepare_data(df: pd.DataFrame):
    """Prepare features and labels."""
    print("\n📊 Preparing features and labels...")
    
    feature_cols = [col for col in df.columns if col != 'label']
    X = df[feature_cols].values
    y = df['label'].values
    
    print(f"   Features shape: {X.shape}")
    print(f"   Labels shape: {y.shape}")
    
    return X, y


def encode_labels(y: np.ndarray):
    """Encode string labels to integers."""
    print("\n🏷️  Encoding labels...")
    
    encoder = LabelEncoder()
    y_encoded = encoder.fit_transform(y)
    
    print(f"   Classes: {len(encoder.classes_)}")
    print(f"   Sample classes: {list(encoder.classes_[:10])}...")
    
    return y_encoded, encoder


def train_model(X_train: np.ndarray, y_train: np.ndarray):
    """Train RandomForest classifier."""
    print("\n🌲 Training RandomForest classifier...")
    print(f"   Estimators: {N_ESTIMATORS}")
    print(f"   Max depth: {MAX_DEPTH}")
    print(f"   Training samples: {len(X_train)}")
    print("   This may take several minutes for large datasets...\n")
    
    model = RandomForestClassifier(
        n_estimators=N_ESTIMATORS,
        max_depth=MAX_DEPTH,
        min_samples_split=MIN_SAMPLES_SPLIT,
        min_samples_leaf=MIN_SAMPLES_LEAF,
        random_state=RANDOM_STATE,
        n_jobs=-1,
        verbose=1
    )
    
    model.fit(X_train, y_train)
    
    print(f"\n   ✓ Model trained with {model.n_estimators} trees")
    
    return model


def evaluate_model(model, X_test: np.ndarray, y_test: np.ndarray, encoder: LabelEncoder):
    """Evaluate the trained model."""
    print("\n📈 Evaluating model...")
    
    y_pred = model.predict(X_test)
    
    # Overall accuracy
    accuracy = accuracy_score(y_test, y_pred)
    print(f"\n   Overall Accuracy: {accuracy:.4f} ({accuracy*100:.2f}%)")
    
    # Top-5 accuracy (important for large vocab)
    y_proba = model.predict_proba(X_test)
    top5_correct = 0
    for i, (true_label, proba) in enumerate(zip(y_test, y_proba)):
        top5_indices = np.argsort(proba)[-5:]
        if true_label in top5_indices:
            top5_correct += 1
    top5_accuracy = top5_correct / len(y_test)
    print(f"   Top-5 Accuracy: {top5_accuracy:.4f} ({top5_accuracy*100:.2f}%)")
    
    # Classification report (truncated for large vocab)
    print("\n" + "=" * 60)
    print("CLASSIFICATION REPORT (Summary)")
    print("=" * 60)
    
    if len(encoder.classes_) <= 20:
        print(classification_report(y_test, y_pred, target_names=encoder.classes_, zero_division=0))
    else:
        # For large vocab, show macro/weighted averages only
        report = classification_report(y_test, y_pred, output_dict=True, zero_division=0)
        print(f"\n   Macro Avg Precision: {report['macro avg']['precision']:.4f}")
        print(f"   Macro Avg Recall: {report['macro avg']['recall']:.4f}")
        print(f"   Macro Avg F1-Score: {report['macro avg']['f1-score']:.4f}")
        print(f"\n   Weighted Avg Precision: {report['weighted avg']['precision']:.4f}")
        print(f"   Weighted Avg Recall: {report['weighted avg']['recall']:.4f}")
        print(f"   Weighted Avg F1-Score: {report['weighted avg']['f1-score']:.4f}")
    
    # Confusion matrix summary
    cm = confusion_matrix(y_test, y_pred)
    print(f"\n   Confusion Matrix: {cm.shape[0]}x{cm.shape[1]}")
    print(f"   Correct predictions: {np.diag(cm).sum()}")
    print(f"   Incorrect predictions: {cm.sum() - np.diag(cm).sum()}")
    
    return accuracy, top5_accuracy


def save_model(model, encoder, model_path: str, encoder_path: str):
    """Save model and encoder."""
    print("\n💾 Saving model and encoder...")
    
    joblib.dump(model, model_path)
    print(f"   ✓ Model saved: {model_path}")
    
    joblib.dump(encoder, encoder_path)
    print(f"   ✓ Encoder saved: {encoder_path}")


def main():
    print("=" * 60)
    print("  ASL Citizen Model Training")
    print("=" * 60)
    
    # Load data
    df = load_data(INPUT_FILE)
    
    # Check minimum samples
    if len(df) < 100:
        print(f"\n⚠️  Warning: Only {len(df)} samples. Consider processing more videos.")
    
    # Normalize
    df_normalized = normalize_landmarks(df)
    
    # Prepare data
    X, y = prepare_data(df_normalized)
    
    # Encode labels
    y_encoded, encoder = encode_labels(y)
    
    # Split data
    print(f"\n✂️  Splitting data: {int((1-TEST_SIZE)*100)}% train, {int(TEST_SIZE*100)}% test")
    X_train, X_test, y_train, y_test = train_test_split(
        X, y_encoded,
        test_size=TEST_SIZE,
        random_state=RANDOM_STATE,
        stratify=y_encoded
    )
    print(f"   Training: {len(X_train)} samples")
    print(f"   Testing: {len(X_test)} samples")
    
    # Train
    model = train_model(X_train, y_train)
    
    # Evaluate
    accuracy, top5_accuracy = evaluate_model(model, X_test, y_test, encoder)
    
    # Save
    save_model(model, encoder, MODEL_FILE, ENCODER_FILE)
    
    # Summary
    print("\n" + "=" * 60)
    print("  TRAINING COMPLETE")
    print("=" * 60)
    print(f"\n   📊 Top-1 Accuracy: {accuracy*100:.2f}%")
    print(f"   📊 Top-5 Accuracy: {top5_accuracy*100:.2f}%")
    print(f"   📁 Model: {MODEL_FILE}")
    print(f"   📁 Encoder: {ENCODER_FILE}")
    print(f"   🏷️  Classes: {len(encoder.classes_)}")
    print(f"\n   Test with: python3 real_time_asl.py --model {MODEL_FILE}")
    print("\n" + "=" * 60)


if __name__ == "__main__":
    main()
