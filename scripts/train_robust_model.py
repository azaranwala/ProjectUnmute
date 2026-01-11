#!/usr/bin/env python3
"""
Robust ASL Model Training
- Processes ALL available data from Kaggle and WLASL
- Uses advanced augmentation with rotations (±15°)
- Trains a deep neural network for accurate recognition
"""

import os
import cv2
import numpy as np
import pandas as pd
import joblib
from pathlib import Path
from collections import defaultdict
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import accuracy_score, classification_report
import warnings
warnings.filterwarnings('ignore')

# MediaPipe
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Configuration
KAGGLE_DIR = "/Users/zaranwala/Downloads/asl_dataset"
WLASL_DIR = "/Users/zaranwala/Downloads/wlasl_dataset"
LANDMARK_COUNT = 21
MIN_SAMPLES_PER_CLASS = 50  # Minimum samples needed per class


def setup_hand_landmarker():
    """Initialize MediaPipe Hand Landmarker."""
    model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hand_landmarker.task')
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        num_hands=1,
        min_hand_detection_confidence=0.3,  # Lower threshold for more detections
        min_hand_presence_confidence=0.3,
        min_tracking_confidence=0.3
    )
    return vision.HandLandmarker.create_from_options(options)


def extract_landmarks_from_image(detector, image_path):
    """Extract hand landmarks from an image."""
    try:
        image = cv2.imread(image_path)
        if image is None:
            return None
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_image)
        result = detector.detect(mp_image)
        
        if not result.hand_landmarks:
            return None
        
        landmarks = result.hand_landmarks[0]
        coords = []
        for lm in landmarks:
            coords.extend([lm.x, lm.y, lm.z])
        return coords
    except:
        return None


def extract_landmarks_from_video(detector, video_path, samples_per_video=20):
    """Extract landmarks from video frames."""
    samples = []
    cap = cv2.VideoCapture(video_path)
    
    if not cap.isOpened():
        return samples
    
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if total_frames <= 0:
        cap.release()
        return samples
    
    frame_indices = np.linspace(0, total_frames - 1, samples_per_video, dtype=int)
    
    for frame_idx in frame_indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
        ret, frame = cap.read()
        if not ret:
            continue
        
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
        
        try:
            result = detector.detect(mp_image)
            if result.hand_landmarks:
                landmarks = result.hand_landmarks[0]
                coords = [lm.x for lm in landmarks] + [lm.y for lm in landmarks] + [lm.z for lm in landmarks]
                # Reformat to x0,y0,z0,x1,y1,z1,...
                coords_formatted = []
                for i in range(21):
                    coords_formatted.extend([landmarks[i].x, landmarks[i].y, landmarks[i].z])
                samples.append(coords_formatted)
        except:
            continue
    
    cap.release()
    return samples


def augment_landmarks(coords, num_augments=10):
    """
    Apply augmentation to landmark coordinates.
    Includes rotation (±15°), scaling, noise, and translation.
    """
    augmented = [coords.copy()]
    landmarks = np.array(coords).reshape(21, 3)
    
    for _ in range(num_augments):
        aug = landmarks.copy()
        
        # Center around wrist for rotation
        wrist = aug[0].copy()
        aug = aug - wrist
        
        # Random rotation (±15 degrees)
        angle = np.random.uniform(-15, 15) * np.pi / 180
        cos_a, sin_a = np.cos(angle), np.sin(angle)
        rotation_matrix = np.array([
            [cos_a, -sin_a, 0],
            [sin_a, cos_a, 0],
            [0, 0, 1]
        ])
        aug = aug @ rotation_matrix.T
        
        # Random scale (0.85 - 1.15)
        scale = np.random.uniform(0.85, 1.15)
        aug = aug * scale
        
        # Random noise
        noise = np.random.normal(0, 0.01, aug.shape)
        aug = aug + noise
        
        # Random translation
        translation = np.random.uniform(-0.05, 0.05, 3)
        aug = aug + translation
        
        # Move back
        aug = aug + wrist
        
        augmented.append(aug.flatten().tolist())
    
    return augmented


def process_kaggle_dataset(detector):
    """Process all images from Kaggle ASL dataset."""
    print("\n📂 Processing Kaggle ASL Alphabet Dataset...")
    
    all_samples = []
    label_counts = defaultdict(int)
    
    dataset_path = Path(KAGGLE_DIR)
    
    for label_dir in sorted(dataset_path.iterdir()):
        if not label_dir.is_dir():
            continue
        
        label = label_dir.name.upper()
        if label.lower() == 'asl_dataset' or label.startswith('.'):
            continue
        
        images = list(label_dir.glob("*.jpg")) + list(label_dir.glob("*.jpeg")) + list(label_dir.glob("*.png"))
        
        for img_path in images:
            coords = extract_landmarks_from_image(detector, str(img_path))
            if coords:
                all_samples.append((coords, label))
                label_counts[label] += 1
        
        if label_counts[label] > 0:
            print(f"   {label}: {label_counts[label]} samples")
    
    print(f"   Total Kaggle samples: {len(all_samples)}")
    return all_samples


def process_wlasl_dataset(detector):
    """Process WLASL videos for word-level signs."""
    print("\n📂 Processing WLASL Dataset...")
    
    import json
    
    # Load class mappings
    class_list_path = os.path.join(WLASL_DIR, "wlasl_class_list.txt")
    json_path = os.path.join(WLASL_DIR, "nslt_100.json")
    videos_dir = os.path.join(WLASL_DIR, "videos")
    
    if not os.path.exists(class_list_path):
        print("   ⚠️ WLASL class list not found, skipping...")
        return []
    
    # Load class mapping
    class_map = {}
    with open(class_list_path, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) == 2:
                class_map[int(parts[0])] = parts[1].upper()
    
    # Load video-label mapping
    with open(json_path, 'r') as f:
        video_labels = json.load(f)
    
    # Find available videos
    video_to_label = {}
    for video_id, info in video_labels.items():
        video_path = os.path.join(videos_dir, f"{video_id}.mp4")
        if os.path.exists(video_path):
            class_id = info['action'][0]
            if class_id in class_map:
                video_to_label[video_path] = class_map[class_id]
    
    print(f"   Found {len(video_to_label)} videos")
    
    all_samples = []
    label_counts = defaultdict(int)
    processed = 0
    
    for video_path, label in video_to_label.items():
        samples = extract_landmarks_from_video(detector, video_path, samples_per_video=15)
        for coords in samples:
            all_samples.append((coords, label))
            label_counts[label] += 1
        
        processed += 1
        if processed % 100 == 0:
            print(f"   Processed {processed}/{len(video_to_label)} videos...")
    
    print(f"   Total WLASL samples: {len(all_samples)}")
    return all_samples


def main():
    print("=" * 60)
    print("  Robust ASL Model Training")
    print("=" * 60)
    
    # Initialize MediaPipe
    print("\n🔧 Initializing MediaPipe...")
    detector = setup_hand_landmarker()
    
    # Process datasets
    kaggle_samples = process_kaggle_dataset(detector)
    wlasl_samples = process_wlasl_dataset(detector)
    
    # Combine all samples
    all_samples = kaggle_samples + wlasl_samples
    print(f"\n📊 Total raw samples: {len(all_samples)}")
    
    # Count per label
    label_counts = defaultdict(int)
    for _, label in all_samples:
        label_counts[label] += 1
    
    # Filter labels with enough samples
    valid_labels = {label for label, count in label_counts.items() if count >= MIN_SAMPLES_PER_CLASS}
    print(f"   Labels with >= {MIN_SAMPLES_PER_CLASS} samples: {len(valid_labels)}")
    
    # Filter samples
    filtered_samples = [(coords, label) for coords, label in all_samples if label in valid_labels]
    print(f"   Filtered samples: {len(filtered_samples)}")
    
    # Apply augmentation
    print("\n🔄 Applying data augmentation (rotations ±15°, scaling, noise)...")
    augmented_data = []
    for coords, label in filtered_samples:
        for aug_coords in augment_landmarks(coords, num_augments=8):
            augmented_data.append((aug_coords, label))
    
    print(f"   Augmented samples: {len(augmented_data)}")
    
    # Prepare training data
    X = np.array([sample[0] for sample in augmented_data])
    y = np.array([sample[1] for sample in augmented_data])
    
    # Encode labels
    encoder = LabelEncoder()
    y_encoded = encoder.fit_transform(y)
    
    # Scale features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X_scaled, y_encoded, test_size=0.15, random_state=42, stratify=y_encoded
    )
    
    print(f"\n📊 Training set: {len(X_train)}")
    print(f"   Test set: {len(X_test)}")
    print(f"   Classes: {len(encoder.classes_)}")
    
    # Train model
    print("\n🧠 Training Deep Neural Network...")
    mlp = MLPClassifier(
        hidden_layer_sizes=(512, 256, 128, 64),
        activation='relu',
        solver='adam',
        alpha=0.0003,
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
    accuracy = accuracy_score(y_test, y_pred)
    
    y_proba = mlp.predict_proba(X_test)
    top5_acc = np.mean([y_test[i] in np.argsort(y_proba[i])[-5:] for i in range(len(y_test))])
    
    print(f"\n✅ Results:")
    print(f"   Top-1 Accuracy: {accuracy*100:.2f}%")
    print(f"   Top-5 Accuracy: {top5_acc*100:.2f}%")
    
    # Save model
    joblib.dump(mlp, 'asl_citizen_model.pkl')
    joblib.dump(encoder, 'asl_citizen_encoder.pkl')
    joblib.dump(scaler, 'asl_citizen_scaler.pkl')
    
    print(f"\n💾 Model saved!")
    print(f"   Classes: {list(encoder.classes_)[:20]}...")
    
    # Cleanup
    detector.close()
    
    print("\n" + "=" * 60)
    print("  Training Complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
