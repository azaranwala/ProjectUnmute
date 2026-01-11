#!/usr/bin/env python3
"""
ASL Recognition Model Training Script

Trains a RandomForestClassifier on hand landmark data collected from collect_data.py.
Includes wrist-centered normalization for position-invariant recognition.

Usage:
    python3 train_model.py

Input:
    - asl_landmarks.csv: CSV file with 63 landmark features + label

Output:
    - asl_model.pkl: Trained RandomForest model
    - label_encoder.pkl: LabelEncoder for converting labels
"""

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
import joblib
import os
import sys

# Configuration
INPUT_FILE = "asl_landmarks.csv"
MODEL_FILE = "asl_model.pkl"
ENCODER_FILE = "label_encoder.pkl"
TEST_SIZE = 0.20
RANDOM_STATE = 42
LANDMARK_COUNT = 21


def load_data(filepath: str) -> tuple:
    """Load and validate the landmark data from CSV."""
    print(f"\n📂 Loading data from: {filepath}")
    
    if not os.path.exists(filepath):
        print(f"❌ Error: File not found: {filepath}")
        print("   Please run collect_data.py first to collect training data.")
        sys.exit(1)
    
    df = pd.read_csv(filepath)
    print(f"   Loaded {len(df)} samples")
    print(f"   Features: {len(df.columns) - 1} (expected: 63)")
    print(f"   Labels: {df['label'].nunique()} unique classes")
    print(f"   Classes: {sorted(df['label'].unique())}")
    
    return df


def normalize_landmarks(df: pd.DataFrame) -> pd.DataFrame:
    """
    Normalize landmarks by centering around the wrist (landmark 0).
    This makes the model position-invariant.
    
    For each sample:
    - Subtract wrist coordinates from all landmarks
    - Optionally scale by hand size (distance from wrist to middle finger MCP)
    """
    print("\n🔧 Normalizing landmarks (wrist-centered)...")
    
    # Create a copy to avoid modifying original
    df_normalized = df.copy()
    
    # Get feature columns (all except 'label')
    feature_cols = [col for col in df.columns if col != 'label']
    
    normalized_data = []
    
    for idx, row in df.iterrows():
        # Extract wrist coordinates (landmark 0)
        wrist_x = row['x0']
        wrist_y = row['y0']
        wrist_z = row['z0']
        
        # Calculate hand scale (distance from wrist to middle finger MCP - landmark 9)
        # This helps normalize for different hand sizes and distances from camera
        dx = row['x9'] - wrist_x
        dy = row['y9'] - wrist_y
        dz = row['z9'] - wrist_z
        hand_scale = np.sqrt(dx**2 + dy**2 + dz**2)
        
        # Avoid division by zero
        if hand_scale < 0.001:
            hand_scale = 1.0
        
        # Normalize each landmark
        normalized_row = {}
        for i in range(LANDMARK_COUNT):
            # Center around wrist and scale by hand size
            normalized_row[f'x{i}'] = (row[f'x{i}'] - wrist_x) / hand_scale
            normalized_row[f'y{i}'] = (row[f'y{i}'] - wrist_y) / hand_scale
            normalized_row[f'z{i}'] = (row[f'z{i}'] - wrist_z) / hand_scale
        
        normalized_row['label'] = row['label']
        normalized_data.append(normalized_row)
    
    df_normalized = pd.DataFrame(normalized_data)
    print(f"   ✓ Normalized {len(df_normalized)} samples")
    
    return df_normalized


def prepare_features_labels(df: pd.DataFrame) -> tuple:
    """Separate features and labels from the dataframe."""
    print("\n📊 Preparing features and labels...")
    
    # Features: all columns except 'label'
    feature_cols = [col for col in df.columns if col != 'label']
    X = df[feature_cols].values
    
    # Labels
    y = df['label'].values
    
    print(f"   Features shape: {X.shape}")
    print(f"   Labels shape: {y.shape}")
    
    return X, y


def encode_labels(y: np.ndarray) -> tuple:
    """Encode string labels to integers."""
    print("\n🏷️  Encoding labels...")
    
    encoder = LabelEncoder()
    y_encoded = encoder.fit_transform(y)
    
    print(f"   Classes: {list(encoder.classes_)}")
    print(f"   Encoded range: 0 to {len(encoder.classes_) - 1}")
    
    return y_encoded, encoder


def train_model(X_train: np.ndarray, y_train: np.ndarray) -> RandomForestClassifier:
    """Train a RandomForest classifier."""
    print("\n🌲 Training RandomForest classifier...")
    print("   This may take a moment...")
    
    model = RandomForestClassifier(
        n_estimators=100,          # Number of trees
        max_depth=20,              # Maximum tree depth
        min_samples_split=5,       # Minimum samples to split a node
        min_samples_leaf=2,        # Minimum samples in leaf node
        random_state=RANDOM_STATE,
        n_jobs=-1,                 # Use all CPU cores
        verbose=0
    )
    
    model.fit(X_train, y_train)
    
    print(f"   ✓ Model trained with {model.n_estimators} trees")
    
    return model


def evaluate_model(model, X_test: np.ndarray, y_test: np.ndarray, encoder: LabelEncoder):
    """Evaluate the trained model and print metrics."""
    print("\n📈 Evaluating model...")
    
    # Predictions
    y_pred = model.predict(X_test)
    
    # Accuracy
    accuracy = accuracy_score(y_test, y_pred)
    print(f"\n   Overall Accuracy: {accuracy:.4f} ({accuracy*100:.2f}%)")
    
    # Classification report
    print("\n" + "=" * 60)
    print("CLASSIFICATION REPORT")
    print("=" * 60)
    
    # Get class names for the report
    class_names = encoder.classes_
    report = classification_report(y_test, y_pred, target_names=class_names, zero_division=0)
    print(report)
    
    # Confusion matrix summary (not full matrix as it can be large)
    cm = confusion_matrix(y_test, y_pred)
    print(f"\nConfusion Matrix Shape: {cm.shape}")
    print(f"Diagonal (correct predictions): {np.diag(cm).sum()}")
    print(f"Off-diagonal (errors): {cm.sum() - np.diag(cm).sum()}")
    
    return accuracy


def save_model(model, encoder, model_path: str, encoder_path: str):
    """Save the trained model and label encoder."""
    print("\n💾 Saving model and encoder...")
    
    joblib.dump(model, model_path)
    print(f"   ✓ Model saved to: {model_path}")
    
    joblib.dump(encoder, encoder_path)
    print(f"   ✓ Label encoder saved to: {encoder_path}")


def print_feature_importance(model, top_n: int = 10):
    """Print the most important features."""
    print(f"\n🎯 Top {top_n} Most Important Features:")
    print("-" * 40)
    
    importances = model.feature_importances_
    feature_names = []
    for i in range(LANDMARK_COUNT):
        feature_names.extend([f'x{i}', f'y{i}', f'z{i}'])
    
    # Sort by importance
    indices = np.argsort(importances)[::-1]
    
    for i in range(min(top_n, len(indices))):
        idx = indices[i]
        print(f"   {i+1}. {feature_names[idx]}: {importances[idx]:.4f}")


def main():
    print("=" * 60)
    print("  ASL Recognition Model Training")
    print("=" * 60)
    
    # Load data
    df = load_data(INPUT_FILE)
    
    # Check if we have enough data
    if len(df) < 100:
        print(f"\n⚠️  Warning: Only {len(df)} samples. Consider collecting more data.")
    
    # Normalize landmarks (center around wrist)
    df_normalized = normalize_landmarks(df)
    
    # Prepare features and labels
    X, y = prepare_features_labels(df_normalized)
    
    # Encode labels
    y_encoded, encoder = encode_labels(y)
    
    # Split data (80% train, 20% test)
    print(f"\n✂️  Splitting data: {int((1-TEST_SIZE)*100)}% train, {int(TEST_SIZE*100)}% test")
    X_train, X_test, y_train, y_test = train_test_split(
        X, y_encoded, 
        test_size=TEST_SIZE, 
        random_state=RANDOM_STATE,
        stratify=y_encoded  # Ensure balanced split across classes
    )
    print(f"   Training samples: {len(X_train)}")
    print(f"   Testing samples: {len(X_test)}")
    
    # Train model
    model = train_model(X_train, y_train)
    
    # Evaluate model
    accuracy = evaluate_model(model, X_test, y_test, encoder)
    
    # Show feature importance
    print_feature_importance(model)
    
    # Save model and encoder
    save_model(model, encoder, MODEL_FILE, ENCODER_FILE)
    
    # Summary
    print("\n" + "=" * 60)
    print("  TRAINING COMPLETE")
    print("=" * 60)
    print(f"\n  📊 Final Accuracy: {accuracy*100:.2f}%")
    print(f"  📁 Model: {MODEL_FILE}")
    print(f"  📁 Encoder: {ENCODER_FILE}")
    print(f"\n  Next steps:")
    print(f"  1. Test the model with real_time_asl.py (if available)")
    print(f"  2. Collect more data if accuracy is low")
    print(f"  3. Integrate into iOS app")
    print("\n" + "=" * 60)


if __name__ == "__main__":
    main()
