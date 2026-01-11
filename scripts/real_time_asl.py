#!/usr/bin/env python3
"""
Real-Time ASL Recognition Script

Uses the trained RandomForest model to recognize ASL signs from webcam feed.
Displays predictions with confidence scores in real-time.

Usage:
    python3 real_time_asl.py                                    # Use default model
    python3 real_time_asl.py --model asl_citizen_model.pkl      # Use ASL Citizen model

Requirements:
    - asl_model.pkl OR asl_citizen_model.pkl (trained model)
    - label_encoder.pkl OR asl_citizen_encoder.pkl (label encoder)
    - hand_landmarker.task (MediaPipe model, auto-downloaded)
"""

import cv2
import numpy as np
import os
import sys
import argparse
import joblib
from collections import deque

# MediaPipe Tasks API
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Configuration
DEFAULT_MODEL_FILE = "asl_model.pkl"
DEFAULT_ENCODER_FILE = "label_encoder.pkl"
ASL_CITIZEN_MODEL = "asl_citizen_model.pkl"
ASL_CITIZEN_ENCODER = "asl_citizen_encoder.pkl"
PREDICTION_HISTORY_SIZE = 7  # Smooth predictions over N frames
CONFIDENCE_THRESHOLD = 0.4  # Minimum confidence to display prediction (lower for 100 classes)
LANDMARK_COUNT = 21


SCALER_FILE = "asl_citizen_scaler.pkl"

def load_model(model_file, encoder_file):
    """Load the trained model, label encoder, and scaler."""
    if not os.path.exists(model_file):
        print(f"❌ Error: Model file not found: {model_file}")
        print("   Please run train_model.py or train_asl_citizen.py first.")
        sys.exit(1)
        
    if not os.path.exists(encoder_file):
        print(f"❌ Error: Encoder file not found: {encoder_file}")
        print("   Please run train_model.py or train_asl_citizen.py first.")
        sys.exit(1)
    
    print(f"📂 Loading model from: {model_file}")
    model = joblib.load(model_file)
    
    print(f"📂 Loading encoder from: {encoder_file}")
    encoder = joblib.load(encoder_file)
    
    # Load scaler if exists
    scaler = None
    if os.path.exists(SCALER_FILE):
        print(f"📂 Loading scaler from: {SCALER_FILE}")
        scaler = joblib.load(SCALER_FILE)
        print("   ✓ Using advanced features with scaler")
    
    num_classes = len(encoder.classes_)
    if num_classes <= 26:
        print(f"   ✓ Model loaded with {num_classes} classes: {list(encoder.classes_)}")
    else:
        print(f"   ✓ Model loaded with {num_classes} classes")
        print(f"   Sample classes: {list(encoder.classes_[:10])}...")
    
    return model, encoder, scaler


def normalize_landmarks(landmarks) -> np.ndarray:
    """
    Normalize landmarks: center on wrist, scale by hand size.
    This must match training normalization exactly.
    """
    # Extract coordinates
    coords = []
    for lm in landmarks:
        coords.extend([lm.x, lm.y, lm.z])
    coords = np.array(coords, dtype=np.float64).reshape(21, 3)
    
    # Center on wrist (landmark 0)
    wrist = coords[0].copy()
    centered = coords - wrist
    
    # Scale by distance from wrist to middle finger MCP (landmark 9)
    hand_size = np.linalg.norm(centered[9])
    if hand_size < 0.001:
        hand_size = 1.0
    
    normalized = centered / hand_size
    
    # Clip extreme values and replace NaN/inf
    normalized = np.clip(normalized, -10, 10)
    normalized = np.nan_to_num(normalized, nan=0.0, posinf=10.0, neginf=-10.0)
    
    return normalized.flatten().reshape(1, -1)


def extract_advanced_features(coords: np.ndarray) -> np.ndarray:
    """
    Extract advanced features from hand landmarks (must match training).
    Input: 63 values (21 landmarks x 3 coords)
    Output: Enhanced feature vector with angles, distances, ratios
    """
    coords = coords.flatten()
    landmarks = coords.reshape(21, 3)
    
    features = []
    
    # 1. Original normalized coordinates (63 features)
    wrist = landmarks[0]
    for i in range(21):
        diff = landmarks[i] - wrist
        features.extend(diff.tolist())
    
    # 2. Fingertip to wrist distances (5 features)
    fingertips = [4, 8, 12, 16, 20]
    for tip_idx in fingertips:
        dist = np.linalg.norm(landmarks[tip_idx] - wrist)
        features.append(dist)
    
    # 3. Fingertip to fingertip distances (10 features)
    for i, tip1 in enumerate(fingertips):
        for tip2 in fingertips[i+1:]:
            dist = np.linalg.norm(landmarks[tip1] - landmarks[tip2])
            features.append(dist)
    
    # 4. Finger curl ratios (5 features)
    finger_bases = [1, 5, 9, 13, 17]
    finger_mids = [2, 6, 10, 14, 18]
    for i, (tip, base, mid) in enumerate(zip(fingertips, finger_bases, finger_mids)):
        tip_to_base = np.linalg.norm(landmarks[tip] - landmarks[base])
        full_length = (np.linalg.norm(landmarks[mid] - landmarks[base]) + 
                       np.linalg.norm(landmarks[tip] - landmarks[mid]))
        curl_ratio = tip_to_base / (full_length + 0.0001)
        features.append(curl_ratio)
    
    # 5. Palm orientation (3 features)
    palm_vec1 = landmarks[5] - landmarks[0]
    palm_vec2 = landmarks[17] - landmarks[0]
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
    
    return np.array(features).reshape(1, -1)


def draw_hand_landmarks(frame, hand_landmarks):
    """Draw hand landmarks and connections on frame."""
    h, w = frame.shape[:2]
    
    HAND_CONNECTIONS = [
        (0, 1), (1, 2), (2, 3), (3, 4),
        (0, 5), (5, 6), (6, 7), (7, 8),
        (0, 9), (9, 10), (10, 11), (11, 12),
        (0, 13), (13, 14), (14, 15), (15, 16),
        (0, 17), (17, 18), (18, 19), (19, 20),
        (5, 9), (9, 13), (13, 17)
    ]
    
    for start_idx, end_idx in HAND_CONNECTIONS:
        start = hand_landmarks[start_idx]
        end = hand_landmarks[end_idx]
        start_point = (int(start.x * w), int(start.y * h))
        end_point = (int(end.x * w), int(end.y * h))
        cv2.line(frame, start_point, end_point, (0, 255, 0), 2)
    
    for i, landmark in enumerate(hand_landmarks):
        cx, cy = int(landmark.x * w), int(landmark.y * h)
        color = (255, 0, 0) if i == 0 else (0, 0, 255)
        cv2.circle(frame, (cx, cy), 5, color, -1)
    
    return frame


def draw_prediction_overlay(frame, prediction, confidence, prediction_history, top_predictions=None, 
                            hand_confidence=None, raw_confidence=None):
    """Draw prediction info on frame with detailed confidence levels."""
    h, w = frame.shape[:2]
    
    # Background - wider for longer sign names
    overlay = frame.copy()
    cv2.rectangle(overlay, (10, 10), (w - 10, 160), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.7, frame, 0.3, 0, frame)
    
    # Prediction
    if prediction and confidence >= CONFIDENCE_THRESHOLD:
        # Adjust font size based on text length
        font_scale = 2.0 if len(prediction) <= 5 else (1.5 if len(prediction) <= 10 else 1.0)
        cv2.putText(frame, prediction, (20, 55),
                    cv2.FONT_HERSHEY_SIMPLEX, font_scale, (0, 255, 0), 3)
        
        # Confidence bars section
        y_bar = 75
        
        # Model confidence bar (raw prediction confidence)
        if raw_confidence is not None:
            cv2.putText(frame, "Model:", (20, y_bar + 3),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, (200, 200, 200), 1)
            bar_width = int(120 * raw_confidence)
            color = (0, 255, 0) if raw_confidence > 0.5 else ((0, 255, 255) if raw_confidence > 0.3 else (0, 165, 255))
            cv2.rectangle(frame, (70, y_bar - 10), (190, y_bar), (50, 50, 50), -1)
            cv2.rectangle(frame, (70, y_bar - 10), (70 + bar_width, y_bar), color, -1)
            cv2.putText(frame, f"{raw_confidence*100:.1f}%", (195, y_bar),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
        
        # Smoothed confidence bar
        y_bar += 18
        cv2.putText(frame, "Smooth:", (20, y_bar + 3),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, (200, 200, 200), 1)
        bar_width = int(120 * confidence)
        color = (0, 255, 0) if confidence > 0.5 else ((0, 255, 255) if confidence > 0.3 else (0, 165, 255))
        cv2.rectangle(frame, (70, y_bar - 10), (190, y_bar), (50, 50, 50), -1)
        cv2.rectangle(frame, (70, y_bar - 10), (70 + bar_width, y_bar), color, -1)
        cv2.putText(frame, f"{confidence*100:.1f}%", (195, y_bar),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
        
        # Hand detection confidence
        if hand_confidence is not None:
            y_bar += 18
            cv2.putText(frame, "Hand:", (20, y_bar + 3),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, (200, 200, 200), 1)
            bar_width = int(120 * hand_confidence)
            cv2.rectangle(frame, (70, y_bar - 10), (190, y_bar), (50, 50, 50), -1)
            cv2.rectangle(frame, (70, y_bar - 10), (70 + bar_width, y_bar), (255, 200, 0), -1)
            cv2.putText(frame, f"{hand_confidence*100:.1f}%", (195, y_bar),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
        
        # Show top 5 predictions on right side
        if top_predictions:
            cv2.putText(frame, "Top 5 Predictions:", (w - 200, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 0), 1)
            for i, (pred, prob) in enumerate(top_predictions[:5]):
                y_pos = 50 + i * 20
                # Highlight if it's the current prediction
                color = (0, 255, 0) if pred == prediction else (180, 180, 180)
                bar_w = int(80 * prob)
                cv2.rectangle(frame, (w - 200, y_pos - 2), (w - 120, y_pos + 10), (40, 40, 40), -1)
                cv2.rectangle(frame, (w - 200, y_pos - 2), (w - 200 + bar_w, y_pos + 10), color, -1)
                # Truncate long names
                disp_name = pred[:8] + ".." if len(pred) > 10 else pred
                cv2.putText(frame, f"{disp_name}", (w - 115, y_pos + 8),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.35, color, 1)
                cv2.putText(frame, f"{prob*100:.0f}%", (w - 45, y_pos + 8),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.35, (255, 255, 255), 1)
    else:
        cv2.putText(frame, "Show ASL sign...", (20, 70),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (200, 200, 200), 2)
        if hand_confidence is not None:
            cv2.putText(frame, f"Hand detected: {hand_confidence*100:.0f}%", (20, 100),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 200, 0), 1)
    
    # Prediction history (smoothed)
    if prediction_history:
        history_list = list(prediction_history)[-5:]
        history_text = "Recent: " + " | ".join(history_list)
        # Truncate if too long
        if len(history_text) > 60:
            history_text = history_text[:57] + "..."
        cv2.putText(frame, history_text, (10, h - 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
    
    # Controls
    cv2.putText(frame, "Press 'q' to quit | 'c' to clear history", (10, h - 15),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (150, 150, 150), 1)
    
    return frame


def get_smoothed_prediction(predictions_buffer):
    """Get the most common prediction from recent frames."""
    if not predictions_buffer:
        return None, 0.0
    
    # Count occurrences
    from collections import Counter
    counts = Counter(predictions_buffer)
    most_common = counts.most_common(1)[0]
    
    # Confidence based on consistency
    confidence = most_common[1] / len(predictions_buffer)
    
    return most_common[0], confidence


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Real-Time ASL Recognition')
    parser.add_argument('--model', type=str, default=None,
                        help='Path to model file (default: auto-detect)')
    parser.add_argument('--encoder', type=str, default=None,
                        help='Path to encoder file (default: auto-detect)')
    return parser.parse_args()


def main():
    args = parse_args()
    
    print("=" * 60)
    print("  Real-Time ASL Recognition")
    print("=" * 60)
    
    # Determine which model to use
    if args.model:
        model_file = args.model
        # Auto-detect encoder if not specified
        if args.encoder:
            encoder_file = args.encoder
        elif 'citizen' in args.model.lower():
            encoder_file = ASL_CITIZEN_ENCODER
        else:
            encoder_file = DEFAULT_ENCODER_FILE
    elif os.path.exists(ASL_CITIZEN_MODEL):
        # Prefer ASL Citizen model if available
        print("\n🔍 Found ASL Citizen model, using it by default.")
        model_file = ASL_CITIZEN_MODEL
        encoder_file = ASL_CITIZEN_ENCODER
    elif os.path.exists(DEFAULT_MODEL_FILE):
        model_file = DEFAULT_MODEL_FILE
        encoder_file = DEFAULT_ENCODER_FILE
    else:
        print("❌ No model found. Please train a model first.")
        print("   Run: python3 train_model.py")
        print("   Or:  python3 train_asl_citizen.py")
        sys.exit(1)
    
    # Load model
    model, encoder, scaler = load_model(model_file, encoder_file)
    num_classes = len(encoder.classes_)
    
    # Initialize webcam
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("❌ Error: Could not open webcam!")
        print("   Please grant camera permission in System Preferences.")
        return
    
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, 30)
    
    print("\n📷 Webcam initialized.")
    
    # Check/download MediaPipe model
    model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hand_landmarker.task')
    if not os.path.exists(model_path):
        print("\n📥 Downloading hand_landmarker.task model...")
        import urllib.request
        model_url = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
        urllib.request.urlretrieve(model_url, model_path)
        print("   ✓ Model downloaded!")
    
    # Initialize MediaPipe Hand Landmarker
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        num_hands=1,
        min_hand_detection_confidence=0.7,
        min_hand_presence_confidence=0.7,
        min_tracking_confidence=0.5
    )
    detector = vision.HandLandmarker.create_from_options(options)
    
    print("\n🚀 Starting real-time recognition...")
    print("   Show ASL hand signs to the camera!")
    print("\n" + "=" * 60)
    
    # Prediction smoothing buffer
    predictions_buffer = deque(maxlen=PREDICTION_HISTORY_SIZE)
    prediction_history = deque(maxlen=20)
    last_stable_prediction = None
    
    while cap.isOpened():
        success, frame = cap.read()
        if not success:
            continue
        
        frame = cv2.flip(frame, 1)
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
        detection_result = detector.detect(mp_image)
        
        current_prediction = None
        current_confidence = 0.0
        hand_confidence = None
        raw_confidence = None
        top_predictions = None
        
        if detection_result.hand_landmarks:
            # Get hand detection confidence if available
            if detection_result.handedness:
                hand_confidence = detection_result.handedness[0][0].score
            
            for hand_landmarks in detection_result.hand_landmarks:
                # Draw landmarks
                frame = draw_hand_landmarks(frame, hand_landmarks)
                
                # Normalize and extract features
                basic_features = normalize_landmarks(hand_landmarks)
                
                # Use scaler if available
                if scaler is not None:
                    features = scaler.transform(basic_features)
                else:
                    features = basic_features
                
                # Get prediction probabilities
                proba = model.predict_proba(features)[0]
                pred_idx = np.argmax(proba)
                confidence = proba[pred_idx]
                raw_confidence = confidence  # Store raw model confidence
                
                # Get top 5 predictions for display
                top_indices = np.argsort(proba)[-5:][::-1]
                top_predictions = [(encoder.classes_[i], proba[i]) for i in top_indices]
                
                if confidence >= CONFIDENCE_THRESHOLD:
                    prediction = encoder.classes_[pred_idx]
                    predictions_buffer.append(prediction)
                    
                    # Get smoothed prediction
                    current_prediction, smooth_conf = get_smoothed_prediction(predictions_buffer)
                    current_confidence = confidence * smooth_conf
                    
                    # Add to history if stable and different from last
                    stability_threshold = 0.5 if num_classes > 50 else 0.6
                    if current_prediction != last_stable_prediction and smooth_conf > stability_threshold:
                        prediction_history.append(current_prediction)
                        last_stable_prediction = current_prediction
                        print(f"   🔤 Detected: {current_prediction} ({confidence*100:.1f}%)")
        else:
            predictions_buffer.clear()
        
        # Draw overlay with all confidence levels
        frame = draw_prediction_overlay(frame, current_prediction, current_confidence, prediction_history, 
                                        top_predictions, hand_confidence, raw_confidence)
        
        cv2.imshow('ASL Recognition', frame)
        
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('c'):
            prediction_history.clear()
            last_stable_prediction = None
            print("   🗑️ History cleared")
    
    detector.close()
    cap.release()
    cv2.destroyAllWindows()
    
    print("\n✅ Done!")
    print("=" * 60)


if __name__ == "__main__":
    main()
