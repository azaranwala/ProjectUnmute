#!/usr/bin/env python3
"""
Train Neural Network ASL Classifier

Uses MLPClassifier for better accuracy on overlapping sign classes.
Exports model weights to JSON for iOS app.
"""

import os
import json
import csv
import numpy as np
from collections import defaultdict
from sklearn.neural_network import MLPClassifier
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler, LabelEncoder
import warnings
warnings.filterwarnings('ignore')

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_MODEL_JSON = os.path.join(BASE_DIR, "../ASLModelData_nn.json")
MIN_SAMPLES_PER_CLASS = 10

# Target vocabulary
TARGET_VOCABULARY = {
    'Family': [
        'MOM', 'MOTHER', 'DAD', 'FATHER', 'BOY', 'GIRL', 'MARRY', 'BROTHER', 'SISTER',
        'GRANDMA', 'GRANDMOTHER', 'GRANDFATHER', 'AUNT', 'UNCLE', 'BABY', 'SINGLE',
        'DIVORCE', 'SEPARATE', 'FAMILY', 'SON', 'DAUGHTER', 'HUSBAND', 'WIFE', 'COUSIN'
    ],
    'Places': [
        'HOME', 'WORK', 'SCHOOL', 'STORE', 'CHURCH', 'COME', 'GO', 'CAR', 'DRIVE',
        'IN', 'OUT', 'WITH', 'HERE', 'THERE'
    ],
    'Time': [
        'DAY', 'NIGHT', 'WEEK', 'MONTH', 'YEAR', 'WILL', 'FUTURE', 'BEFORE', 'PAST',
        'TODAY', 'NOW', 'FINISH', 'DONE', 'MORNING', 'AFTERNOON', 'TOMORROW', 'YESTERDAY',
        'TIME', 'HOUR', 'MINUTE', 'SECOND', 'WAIT', 'LATE', 'EARLY'
    ],
    'Temperature': ['HOT', 'COLD', 'WARM', 'COOL'],
    'Food': [
        'PIZZA', 'MILK', 'HAMBURGER', 'HOT_DOG', 'EGG', 'APPLE', 'CHEESE', 'DRINK',
        'SPOON', 'FORK', 'CUP', 'CEREAL', 'WATER', 'CANDY', 'COOKIE', 'HUNGRY',
        'EAT', 'FOOD', 'BREAD', 'MEAT', 'FRUIT', 'VEGETABLE', 'BREAKFAST', 'LUNCH', 'DINNER'
    ],
    'Clothes': ['SHIRT', 'PANTS', 'SOCKS', 'SHOES', 'COAT', 'UNDERWEAR', 'HAT', 'DRESS'],
    'Health': [
        'WASH', 'HURT', 'BATHROOM', 'BRUSH', 'TEETH', 'SLEEP', 'NICE', 'CLEAN',
        'SICK', 'MEDICINE', 'DOCTOR', 'HOSPITAL', 'TIRED'
    ],
    'Feelings': [
        'HAPPY', 'ANGRY', 'SAD', 'SORRY', 'CRY', 'LIKE', 'GOOD', 'BAD', 'LOVE',
        'EXCITED', 'SCARED', 'WORRIED', 'PROUD', 'EMBARRASSED', 'BORED', 'SURPRISED'
    ],
    'Requests': [
        'PLEASE', 'EXCUSE', 'THANK_YOU', 'HELP', 'WHO', 'WHAT', 'WHEN', 'WHERE', 'WHY',
        'HOW', 'STOP', 'YES', 'NO', 'WANT', 'NEED', 'CAN', 'GIVE', 'TAKE', 'SHOW'
    ],
    'Amounts': ['BIG', 'TALL', 'FULL', 'MORE', 'SMALL', 'SHORT', 'EMPTY', 'LESS', 'ALL', 'SOME', 'MANY', 'FEW'],
    'Colors': ['BLUE', 'GREEN', 'YELLOW', 'RED', 'BROWN', 'ORANGE', 'GOLD', 'SILVER', 'BLACK', 'WHITE', 'PINK', 'PURPLE'],
    'Money': ['DOLLAR', 'CENT', 'COST', 'MONEY', 'BUY', 'PAY', 'FREE', 'EXPENSIVE', 'CHEAP'],
    'Animals': ['CAT', 'DOG', 'BIRD', 'HORSE', 'COW', 'SHEEP', 'PIG', 'BUG', 'FISH', 'RABBIT', 'CHICKEN'],
    'Common': [
        'HELLO', 'GOODBYE', 'NAME', 'MY', 'YOUR', 'I', 'YOU', 'HE', 'SHE', 'IT', 'WE', 'THEY',
        'THIS', 'THAT', 'AND', 'OR', 'BUT', 'NOT', 'HAVE', 'BE', 'DO', 'MAKE', 'SEE', 'LOOK',
        'THINK', 'KNOW', 'LEARN', 'TEACH', 'READ', 'WRITE', 'PLAY', 'WALK', 'RUN', 'SIT', 'STAND'
    ],
    'Numbers': ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
    'Letters': list('ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
}

TARGET_CLASSES = set()
for signs in TARGET_VOCABULARY.values():
    TARGET_CLASSES.update(signs)

DATASETS = [
    "wlasl_full_landmarks.csv",
    "asl_citizen_landmarks.csv",
    "combined_asl_landmarks.csv",
    "kaggle_asl_landmarks.csv",
    "asl_landmarks.csv",
    "number_landmarks.csv",
]

CLASS_NORMALIZATION = {
    "THANKYOU": "THANK_YOU", "THANK YOU": "THANK_YOU",
    "ILOVEYOU": "I_LOVE_YOU", "DRINK1": "DRINK", "HOW1": "HOW",
    "WHAT1": "WHAT", "WANT2": "WANT", "WALK2": "WALK", "TEACH1": "TEACH",
    "STAND1": "STAND", "GRANDPA": "GRANDFATHER", "MARRIAGE": "MARRY", "DIVORCED": "DIVORCE",
}


def normalize_class_name(name):
    name = name.strip().upper().replace(" ", "_")
    return CLASS_NORMALIZATION.get(name, name)


def make_wrist_relative(landmarks):
    if len(landmarks) != 63:
        return None
    
    wrist_x, wrist_y, wrist_z = landmarks[0], landmarks[1], landmarks[2]
    
    relative = []
    for i in range(0, len(landmarks), 3):
        relative.append(landmarks[i] - wrist_x)
        relative.append(landmarks[i+1] - wrist_y)
        relative.append(landmarks[i+2] - wrist_z)
    
    max_dist = 0.0
    for i in range(0, len(relative), 3):
        x, y, z = relative[i], relative[i+1], relative[i+2]
        dist = np.sqrt(x*x + y*y + z*z)
        if dist > max_dist:
            max_dist = dist
    
    if max_dist < 0.001:
        max_dist = 1.0
    
    return [v / max_dist for v in relative]


def load_data():
    """Load all target samples."""
    samples_by_class = defaultdict(list)
    
    for dataset_file in DATASETS:
        filepath = os.path.join(BASE_DIR, dataset_file)
        if not os.path.exists(filepath):
            continue
        
        try:
            with open(filepath, 'r') as f:
                reader = csv.reader(f)
                header = next(reader)
                
                label_idx = len(header) - 1
                for i, col in enumerate(header):
                    if col.lower() == 'label':
                        label_idx = i
                        break
                
                for row in reader:
                    if len(row) < 64:
                        continue
                    try:
                        label = normalize_class_name(row[label_idx])
                        if label not in TARGET_CLASSES:
                            continue
                        
                        coords = [float(row[i]) for i in range(63)]
                        wr = make_wrist_relative(coords)
                        if wr:
                            samples_by_class[label].append(wr)
                    except (ValueError, IndexError):
                        continue
        except Exception:
            continue
    
    return samples_by_class


def train_neural_network(samples_by_class):
    """Train MLP classifier."""
    print("\n🧠 Training neural network...")
    
    # Filter classes
    valid_classes = {k: v for k, v in samples_by_class.items() if len(v) >= MIN_SAMPLES_PER_CLASS}
    print(f"   Classes with >= {MIN_SAMPLES_PER_CLASS} samples: {len(valid_classes)}")
    
    # Prepare data
    X = []
    y = []
    for cls, samples in valid_classes.items():
        for sample in samples:
            X.append(sample)
            y.append(cls)
    
    X = np.array(X)
    y = np.array(y)
    print(f"   Total samples: {len(X)}")
    
    # Encode labels
    label_encoder = LabelEncoder()
    y_encoded = label_encoder.fit_transform(y)
    classes = label_encoder.classes_.tolist()
    
    # Scale features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X_scaled, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
    )
    
    # Train MLP with optimized architecture
    print("   Training MLP classifier...")
    mlp = MLPClassifier(
        hidden_layer_sizes=(256, 128, 64),
        activation='relu',
        solver='adam',
        alpha=0.001,
        batch_size=64,
        learning_rate='adaptive',
        learning_rate_init=0.001,
        max_iter=500,
        early_stopping=True,
        validation_fraction=0.1,
        n_iter_no_change=20,
        random_state=42,
        verbose=True
    )
    
    mlp.fit(X_train, y_train)
    
    # Evaluate
    train_acc = mlp.score(X_train, y_train) * 100
    test_acc = mlp.score(X_test, y_test) * 100
    
    print(f"\n   Training accuracy: {train_acc:.1f}%")
    print(f"   Test accuracy: {test_acc:.1f}%")
    
    # Per-class accuracy on test set
    y_pred = mlp.predict(X_test)
    
    class_results = []
    for i, cls in enumerate(classes):
        mask = y_test == i
        if mask.sum() > 0:
            cls_acc = (y_pred[mask] == y_test[mask]).mean() * 100
            cls_samples = mask.sum()
            class_results.append({
                'class': cls,
                'accuracy': cls_acc,
                'test_samples': int(cls_samples),
                'total_samples': len(valid_classes[cls])
            })
    
    return mlp, scaler, classes, class_results


def export_model(mlp, scaler, classes, output_path):
    """Export model to JSON for iOS."""
    print(f"\n💾 Exporting model to {output_path}...")
    
    # Extract MLP weights
    weights = []
    biases = []
    for i, (w, b) in enumerate(zip(mlp.coefs_, mlp.intercepts_)):
        weights.append(w.tolist())
        biases.append(b.tolist())
    
    model_data = {
        'model_type': 'mlp',
        'classes': classes,
        'scaler_mean': scaler.mean_.tolist(),
        'scaler_scale': scaler.scale_.tolist(),
        'weights': weights,
        'biases': biases,
        'activation': 'relu',
        'hidden_layers': list(mlp.hidden_layer_sizes),
    }
    
    with open(output_path, 'w') as f:
        json.dump(model_data, f)
    
    file_size = os.path.getsize(output_path) / 1024
    print(f"   ✓ Saved ({file_size:.1f} KB)")
    
    return model_data


def main():
    print("=" * 70)
    print("  Neural Network ASL Classifier")
    print("=" * 70)
    
    # Load data
    print("\n📂 Loading training data...")
    samples_by_class = load_data()
    total = sum(len(v) for v in samples_by_class.values())
    print(f"   Loaded {total:,} samples across {len(samples_by_class)} classes")
    
    # Train
    mlp, scaler, classes, results = train_neural_network(samples_by_class)
    
    # Sort by accuracy
    results.sort(key=lambda x: -x['accuracy'])
    
    # Report
    high_acc = [r for r in results if r['accuracy'] >= 90]
    med_acc = [r for r in results if 80 <= r['accuracy'] < 90]
    low_acc = [r for r in results if r['accuracy'] < 80]
    
    print("\n" + "=" * 70)
    print("  Results Summary")
    print("=" * 70)
    print(f"   Total classes: {len(results)}")
    print(f"   >90% accuracy: {len(high_acc)} ({len(high_acc)/len(results)*100:.1f}%)")
    print(f"   80-90% accuracy: {len(med_acc)} ({len(med_acc)/len(results)*100:.1f}%)")
    print(f"   <80% accuracy: {len(low_acc)} ({len(low_acc)/len(results)*100:.1f}%)")
    
    # Show high accuracy signs
    print("\n" + "=" * 70)
    print("  Signs with >90% Accuracy")
    print("=" * 70)
    for r in high_acc:
        print(f"   {r['class']:20} | {r['accuracy']:5.1f}% | {r['total_samples']:>4} samples")
    
    print("\n" + "=" * 70)
    print("  Signs with 80-90% Accuracy")
    print("=" * 70)
    for r in med_acc[:30]:
        print(f"   {r['class']:20} | {r['accuracy']:5.1f}% | {r['total_samples']:>4} samples")
    if len(med_acc) > 30:
        print(f"   ... and {len(med_acc) - 30} more")
    
    # Category breakdown
    print("\n" + "=" * 70)
    print("  Accuracy by Category")
    print("=" * 70)
    
    for category, signs in TARGET_VOCABULARY.items():
        cat_results = [r for r in results if r['class'] in signs]
        if cat_results:
            avg_acc = np.mean([r['accuracy'] for r in cat_results])
            high = len([r for r in cat_results if r['accuracy'] >= 90])
            med = len([r for r in cat_results if 80 <= r['accuracy'] < 90])
            print(f"   {category:15} | {len(cat_results):>3} signs | avg {avg_acc:5.1f}% | {high:>2} >90% | {med:>2} 80-90%")
    
    # Export
    export_model(mlp, scaler, classes, OUTPUT_MODEL_JSON)
    
    print("\n" + "=" * 70)
    print("   To use in iOS app, update ASLModelClassifier.swift to use MLP inference")
    print("=" * 70)


if __name__ == "__main__":
    main()
