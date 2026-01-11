#!/usr/bin/env python3
"""Train ASL model with ALL datasets - optimized for useful signs and accuracy"""

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
print("  Training Optimized ASL Model with ALL Datasets")
print("="*60)

# Priority signs - common useful words
PRIORITY_SIGNS = {
    # Greetings
    'HELLO', 'HI', 'GOODBYE', 'BYE', 'THANKYOU', 'THANKS', 'PLEASE', 'SORRY',
    # Yes/No
    'YES', 'NO', 'OK', 'OKAY',
    # Questions
    'WHAT', 'WHAT1', 'WHERE', 'WHEN', 'WHO', 'WHY', 'HOW', 'HOW1',
    # Common words
    'HELP', 'STOP', 'WAIT', 'GO', 'COME', 'WANT', 'WANT2', 'NEED', 'LIKE',
    'GOOD', 'BAD', 'HAPPY', 'SAD', 'LOVE', 'HATE',
    # Family
    'MOTHER', 'MOM', 'FATHER', 'DAD', 'FRIEND', 'FAMILY', 'BABY',
    # Actions
    'EAT', 'DRINK', 'DRINK1', 'SLEEP', 'WORK', 'PLAY', 'LEARN', 'TEACH', 'TEACH1',
    'GIVE', 'TAKE', 'MAKE', 'WALK', 'WALK2', 'RUN', 'SIT', 'STAND', 'STAND1',
    # Time
    'NOW', 'LATER', 'BEFORE', 'AFTER', 'TODAY', 'TOMORROW', 'YESTERDAY',
    # Numbers
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    # Letters (common)
    'A', 'B', 'C', 'D', 'E', 'I', 'L', 'O', 'S', 'Y',
    # Other useful
    'NAME', 'WRITE', 'READ', 'UNDERSTAND', 'KNOW', 'THINK', 'REMEMBER',
    'HOME', 'SCHOOL', 'WATER', 'FOOD', 'BATHROOM', 'DOCTOR', 'PHONE',
    'FINISH', 'MORE', 'AGAIN', 'SAME', 'DIFFERENT',
    # From datasets
    'ACCIDENT', 'COMPUTER', 'COOL', 'APPLE', 'PIZZA', 'THANKSGIVING',
    'NOSE', 'EYES', 'NETWORK', 'SIGNATURE', 'LONGAGO', 'WILLGO'
}

# Load all datasets
print("\n1. Loading all datasets...")

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
        print(f"   ✓ {name}: {len(df)} samples, {df['label'].nunique()} classes")
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
print(f"   Total samples: {len(all_data)}")

# Normalize labels (uppercase)
all_data['label'] = all_data['label'].astype(str).str.upper().str.strip()

# Get class distribution
class_counts = all_data['label'].value_counts()
print(f"   Unique classes: {len(class_counts)}")

# Find priority signs that exist in our data
available_priority = [s for s in PRIORITY_SIGNS if s in class_counts.index]
print(f"\n3. Priority signs available: {len(available_priority)}")

# Select classes: priority signs + top by count
min_samples = 20
eligible = class_counts[class_counts >= min_samples]

# Start with priority signs
selected = set(available_priority)

# Add more classes until we reach 100
for label in eligible.index:
    if len(selected) >= 100:
        break
    selected.add(label)

selected = list(selected)[:100]
print(f"   Selected: {len(selected)} classes")

# Filter data
filtered_data = all_data[all_data['label'].isin(selected)]
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

# Train RandomForest
print("\n6. Training RandomForest classifier...")
model = RandomForestClassifier(
    n_estimators=400,
    max_depth=None,
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

# If accuracy too low, try MLP
if test_acc < 0.70:
    print("\n   Trying MLP for better accuracy...")
    from sklearn.neural_network import MLPClassifier
    
    mlp = MLPClassifier(
        hidden_layer_sizes=(512, 256, 128),
        activation='relu',
        solver='adam',
        alpha=0.0001,
        batch_size=128,
        learning_rate='adaptive',
        max_iter=500,
        early_stopping=True,
        validation_fraction=0.1,
        random_state=42
    )
    mlp.fit(X_train, y_train)
    mlp_acc = mlp.score(X_test, y_test)
    print(f"   MLP accuracy: {mlp_acc*100:.1f}%")
    
    if mlp_acc > test_acc:
        model = mlp
        test_acc = mlp_acc
        print("   Using MLP model")

# Save models
print("\n7. Saving models...")
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
print(f"\n  Total Samples: {len(filtered_data)}")
print(f"  Classes: {len(encoder.classes_)}")
print(f"  Test Accuracy: {test_acc*100:.1f}%")

# Show priority signs that made it
priority_included = [s for s in available_priority if s in encoder.classes_]
print(f"\n  Priority signs included ({len(priority_included)}):")
for i in range(0, len(priority_included), 6):
    row = priority_included[i:i+6]
    print(f"    {', '.join(row)}")

print("\n  All signs:")
signs = sorted(encoder.classes_)
for i in range(0, len(signs), 6):
    row = signs[i:i+6]
    print(f"    {', '.join(row)}")

print("\n" + "="*60)
