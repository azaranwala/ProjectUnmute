#!/usr/bin/env python3
"""
ASL Hand Landmark Data Collection Script

Uses MediaPipe to capture hand landmarks (21 points × 3 coordinates = 63 features)
and saves them to a CSV file for training ASL recognition models.

Usage:
    python3 collect_data.py

Controls:
    - Press 'a'-'z' to set the current label (ASL letter)
    - Press 's' to start/stop recording for the current label
    - Press 'q' to quit and save data
    - Press 'r' to reset/clear all collected data
    - Press 'c' to show current collection stats in terminal

Output:
    - asl_landmarks.csv: CSV file with 63 landmark coordinates + label column
"""

import cv2
import csv
import os
import time
import numpy as np
from datetime import datetime
from collections import defaultdict

# MediaPipe Tasks API (v0.10+)
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Configuration
SAMPLES_PER_LABEL = 500
OUTPUT_FILE = "asl_landmarks.csv"
LANDMARK_COUNT = 21
FEATURES_PER_LANDMARK = 3  # x, y, z

# 100 ASL Words/Signs to collect
ASL_WORDS = [
    # Basic Communication (1-15)
    "HELLO", "GOODBYE", "PLEASE", "THANK_YOU", "SORRY",
    "YES", "NO", "HELP", "STOP", "WAIT",
    "WELCOME", "EXCUSE_ME", "AGAIN", "SLOW", "FAST",
    # Questions (16-25)
    "WHAT", "WHERE", "WHO", "WHEN", "WHY",
    "HOW", "WHICH", "HOW_MUCH", "HOW_MANY", "CAN",
    # People (26-40)
    "ME", "YOU", "HE_SHE", "WE", "THEY",
    "FRIEND", "FAMILY", "MOTHER", "FATHER", "BABY",
    "BOY", "GIRL", "MAN", "WOMAN", "PERSON",
    # Actions (41-60)
    "EAT", "DRINK", "SLEEP", "WORK", "LEARN",
    "TEACH", "UNDERSTAND", "KNOW", "THINK", "WANT",
    "NEED", "LIKE", "LOVE", "HAVE", "GO",
    "COME", "SEE", "LOOK", "LISTEN", "SPEAK",
    # Feelings (61-75)
    "HAPPY", "SAD", "ANGRY", "SCARED", "TIRED",
    "SICK", "HUNGRY", "THIRSTY", "HOT", "COLD",
    "FINE", "NERVOUS", "EXCITED", "BORED", "PROUD",
    # Common Words (76-100)
    "GOOD", "BAD", "MORE", "LESS", "FINISHED",
    "WATER", "FOOD", "HOME", "SCHOOL", "BATHROOM",
    "NAME", "TIME", "TODAY", "TOMORROW", "YESTERDAY",
    "NOW", "LATER", "PHONE", "COMPUTER", "CAR",
    "MONEY", "BOOK", "DOCTOR", "PEACE", "THANK_YOU_ALL"
]

# CSV header: 21 landmarks × 3 coordinates (x, y, z) + label
CSV_HEADER = []
for i in range(LANDMARK_COUNT):
    CSV_HEADER.extend([f"x{i}", f"y{i}", f"z{i}"])
CSV_HEADER.append("label")


class ASLDataCollector:
    def __init__(self):
        self.data = []
        self.current_label = None
        self.is_recording = False
        self.samples_per_label = defaultdict(int)
        self.recording_start_time = None
        
    def set_label(self, label: str):
        """Set the current label for recording."""
        self.current_label = label.upper()
        print(f"\n🏷️  Label set to: {self.current_label}")
        print(f"   Samples collected: {self.samples_per_label[self.current_label]}/{SAMPLES_PER_LABEL}")
        
    def toggle_recording(self):
        """Start or stop recording for the current label."""
        if self.current_label is None:
            print("\n⚠️  Please set a label first (press 'a'-'z')")
            return
            
        self.is_recording = not self.is_recording
        
        if self.is_recording:
            self.recording_start_time = time.time()
            remaining = SAMPLES_PER_LABEL - self.samples_per_label[self.current_label]
            print(f"\n🔴 RECORDING started for '{self.current_label}' ({remaining} samples needed)")
        else:
            print(f"\n⏹️  RECORDING stopped for '{self.current_label}'")
            print(f"   Total samples: {self.samples_per_label[self.current_label]}/{SAMPLES_PER_LABEL}")
            
    def add_sample(self, landmarks) -> bool:
        """Add a sample if recording and not at limit. Returns True if sample was added."""
        if not self.is_recording or self.current_label is None:
            return False
            
        if self.samples_per_label[self.current_label] >= SAMPLES_PER_LABEL:
            print(f"\n✅ Reached {SAMPLES_PER_LABEL} samples for '{self.current_label}'!")
            self.is_recording = False
            return False
            
        # Extract landmark coordinates (works with both legacy and Tasks API)
        row = []
        for landmark in landmarks:
            row.extend([landmark.x, landmark.y, landmark.z])
        row.append(self.current_label)
        
        self.data.append(row)
        self.samples_per_label[self.current_label] += 1
        
        return True
        
    def get_stats(self) -> str:
        """Get collection statistics."""
        stats = ["\n📊 Collection Statistics:"]
        stats.append("-" * 40)
        
        total = 0
        for label in sorted(self.samples_per_label.keys()):
            count = self.samples_per_label[label]
            total += count
            progress = "✅" if count >= SAMPLES_PER_LABEL else "⏳"
            bar_len = min(20, count * 20 // SAMPLES_PER_LABEL) if SAMPLES_PER_LABEL > 0 else 0
            bar = "█" * bar_len + "░" * (20 - bar_len)
            stats.append(f"  {label}: [{bar}] {count:3d}/{SAMPLES_PER_LABEL} {progress}")
            
        stats.append("-" * 40)
        stats.append(f"  Total samples: {total}")
        stats.append(f"  Labels recorded: {len(self.samples_per_label)}/26")
        
        return "\n".join(stats)
        
    def reset_data(self):
        """Clear all collected data."""
        self.data = []
        self.samples_per_label = defaultdict(int)
        self.is_recording = False
        self.current_label = None
        print("\n🗑️  All data cleared!")
        
    def save_to_csv(self, filename: str = OUTPUT_FILE):
        """Save collected data to CSV file."""
        if not self.data:
            print("\n⚠️  No data to save!")
            return False
            
        # Backup existing file if it exists
        if os.path.exists(filename):
            backup_name = f"{filename}.backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            os.rename(filename, backup_name)
            print(f"\n📁 Backed up existing file to: {backup_name}")
            
        with open(filename, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(CSV_HEADER)
            writer.writerows(self.data)
            
        print(f"\n💾 Saved {len(self.data)} samples to: {filename}")
        print(self.get_stats())
        return True


def draw_info_overlay(frame, collector, hand_detected, current_page=0, words_per_page=10):
    """Draw information overlay on the video frame."""
    h, w = frame.shape[:2]
    
    # Semi-transparent background for left panel
    overlay = frame.copy()
    cv2.rectangle(overlay, (10, 10), (420, 180), (0, 0, 0), -1)
    
    # Word menu on right side
    total_pages = (len(ASL_WORDS) + words_per_page - 1) // words_per_page
    start_idx = current_page * words_per_page
    end_idx = min(start_idx + words_per_page, len(ASL_WORDS))
    menu_height = 30 + (end_idx - start_idx) * 22 + 30
    cv2.rectangle(overlay, (w - 220, 10), (w - 10, menu_height), (0, 0, 0), -1)
    
    cv2.addWeighted(overlay, 0.7, frame, 0.3, 0, frame)
    
    # Draw word menu
    cv2.putText(frame, f"Words ({current_page+1}/{total_pages})", (w - 210, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 0), 1)
    for i, word in enumerate(ASL_WORDS[start_idx:end_idx]):
        y_pos = 52 + i * 22
        color = (0, 255, 0) if collector.current_label == word else (200, 200, 200)
        cv2.putText(frame, f"[{i}] {word}", (w - 210, y_pos),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, color, 1)
    cv2.putText(frame, "[n]Next [p]Prev", (w - 210, menu_height - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (150, 150, 150), 1)
    
    # Status text
    y_offset = 35
    line_height = 28
    
    # Current label
    label_text = f"Label: {collector.current_label or 'None (press 0-9)'}"
    cv2.putText(frame, label_text, (20, y_offset), 
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
    y_offset += line_height
    
    # Recording status
    if collector.is_recording:
        status_color = (0, 0, 255)  # Red (BGR)
        status_text = "● RECORDING (press 's' to stop)"
    else:
        status_color = (128, 128, 128)  # Gray
        status_text = "○ Not Recording (press 's' to start)"
    cv2.putText(frame, status_text, (20, y_offset),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, status_color, 2)
    y_offset += line_height
    
    # Sample count for current label
    if collector.current_label:
        count = collector.samples_per_label[collector.current_label]
        progress_pct = min(100, count * 100 // SAMPLES_PER_LABEL)
        count_text = f"Progress: {count}/{SAMPLES_PER_LABEL} ({progress_pct}%)"
        cv2.putText(frame, count_text, (20, y_offset),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
        y_offset += line_height
        
        # Progress bar
        bar_width = 300
        bar_height = 15
        bar_x = 20
        bar_y = y_offset - 5
        filled_width = int(bar_width * count / SAMPLES_PER_LABEL)
        cv2.rectangle(frame, (bar_x, bar_y), (bar_x + bar_width, bar_y + bar_height), (50, 50, 50), -1)
        cv2.rectangle(frame, (bar_x, bar_y), (bar_x + filled_width, bar_y + bar_height), (0, 255, 0), -1)
        cv2.rectangle(frame, (bar_x, bar_y), (bar_x + bar_width, bar_y + bar_height), (255, 255, 255), 1)
        y_offset += line_height
    
    # Hand detection status
    hand_color = (0, 255, 0) if hand_detected else (0, 0, 255)
    hand_text = "✓ Hand Detected" if hand_detected else "✗ No Hand Detected"
    cv2.putText(frame, hand_text, (20, y_offset),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, hand_color, 2)
    
    # Controls hint at bottom
    controls = "Controls: [a-z] Set label | [s] Record | [c] Stats | [r] Reset | [q] Quit"
    cv2.putText(frame, controls, (10, h - 15),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 200, 200), 1)
    
    return frame


def draw_hand_landmarks(frame, hand_landmarks):
    """Draw hand landmarks and connections on frame."""
    h, w = frame.shape[:2]
    
    # Hand connections (MediaPipe standard)
    HAND_CONNECTIONS = [
        (0, 1), (1, 2), (2, 3), (3, 4),  # Thumb
        (0, 5), (5, 6), (6, 7), (7, 8),  # Index
        (0, 9), (9, 10), (10, 11), (11, 12),  # Middle
        (0, 13), (13, 14), (14, 15), (15, 16),  # Ring
        (0, 17), (17, 18), (18, 19), (19, 20),  # Pinky
        (5, 9), (9, 13), (13, 17)  # Palm
    ]
    
    # Draw connections
    for start_idx, end_idx in HAND_CONNECTIONS:
        start = hand_landmarks[start_idx]
        end = hand_landmarks[end_idx]
        start_point = (int(start.x * w), int(start.y * h))
        end_point = (int(end.x * w), int(end.y * h))
        cv2.line(frame, start_point, end_point, (0, 255, 0), 2)
    
    # Draw landmarks
    for i, landmark in enumerate(hand_landmarks):
        cx, cy = int(landmark.x * w), int(landmark.y * h)
        color = (255, 0, 0) if i == 0 else (0, 0, 255)  # Wrist is blue, others red
        cv2.circle(frame, (cx, cy), 5, color, -1)
    
    return frame


def print_word_menu(current_page=0, words_per_page=10):
    """Print the word selection menu."""
    total_pages = (len(ASL_WORDS) + words_per_page - 1) // words_per_page
    start_idx = current_page * words_per_page
    end_idx = min(start_idx + words_per_page, len(ASL_WORDS))
    
    print(f"\n📋 ASL Words (Page {current_page + 1}/{total_pages}):")
    print("-" * 40)
    for i, word in enumerate(ASL_WORDS[start_idx:end_idx]):
        key = i  # 0-9 keys
        print(f"  [{key}] {word}")
    print("-" * 40)
    print("  [n] Next page | [p] Previous page")
    return start_idx


def main():
    print("=" * 60)
    print("  ASL Hand Landmark Data Collection Tool")
    print("=" * 60)
    print("\nControls:")
    print("  • Press '0'-'9' to select ASL word from menu")
    print("  • Press 'n'/'p' for next/previous page of words")
    print("  • Press 's' to start/stop recording")
    print("  • Press 'c' to show collection statistics")
    print("  • Press 'r' to reset all data")
    print("  • Press 'q' to quit and save")
    print("\n" + "=" * 60)
    
    collector = ASLDataCollector()
    current_page = 0
    words_per_page = 10
    
    # Show initial word menu
    print_word_menu(current_page, words_per_page)
    
    # Initialize webcam
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("❌ Error: Could not open webcam!")
        return
    
    # Set camera properties for better performance
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, 30)
    
    print("\n📷 Webcam initialized. Opening window...")
    
    # Check if model file exists, download if not
    model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hand_landmarker.task')
    if not os.path.exists(model_path):
        print("\n📥 Downloading hand_landmarker.task model...")
        import urllib.request
        model_url = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
        urllib.request.urlretrieve(model_url, model_path)
        print("   ✓ Model downloaded successfully!")
    
    # Initialize MediaPipe Hand Landmarker (Tasks API v0.10+)
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        num_hands=1,
        min_hand_detection_confidence=0.7,
        min_hand_presence_confidence=0.7,
        min_tracking_confidence=0.5
    )
    detector = vision.HandLandmarker.create_from_options(options)
    
    frame_count = 0
    samples_added_this_session = 0
    
    while cap.isOpened():
        success, frame = cap.read()
        if not success:
            print("❌ Failed to read frame from webcam")
            continue
        
        # Flip frame horizontally for mirror effect
        frame = cv2.flip(frame, 1)
        
        # Convert BGR to RGB for MediaPipe
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
        # Create MediaPipe Image
        mp_image = vision.Image(image_format=vision.ImageFormat.SRGB, data=rgb_frame)
        
        # Detect hands
        detection_result = detector.detect(mp_image)
        
        hand_detected = False
        
        # Process hand landmarks if detected
        if detection_result.hand_landmarks:
            hand_detected = True
            for hand_landmarks in detection_result.hand_landmarks:
                # Draw hand landmarks on frame
                frame = draw_hand_landmarks(frame, hand_landmarks)
                
                # Add sample if recording
                if collector.add_sample(hand_landmarks):
                    samples_added_this_session += 1
                    
                    # Print progress every 50 samples
                    current_count = collector.samples_per_label[collector.current_label]
                    if current_count % 50 == 0:
                        print(f"   📈 {collector.current_label}: {current_count}/{SAMPLES_PER_LABEL} samples")
        
        # Draw info overlay
        frame = draw_info_overlay(frame, collector, hand_detected, current_page, words_per_page)
        
        # Display frame
        cv2.imshow('ASL Data Collection', frame)
        
        # Handle key presses
        key = cv2.waitKey(1) & 0xFF
        
        if key == ord('q'):
            # Quit
            print("\n👋 Quitting...")
            break
            
        elif key == ord('s'):
            # Toggle recording
            collector.toggle_recording()
            
        elif key == ord('c'):
            # Show stats
            print(collector.get_stats())
            
        elif key == ord('r'):
            # Reset data
            print("\n⚠️  Press 'y' to confirm reset, any other key to cancel")
            confirm_key = cv2.waitKey(0) & 0xFF
            if confirm_key == ord('y'):
                collector.reset_data()
                samples_added_this_session = 0
            else:
                print("Reset cancelled.")
        
        elif key == ord('n'):
            # Next page
            total_pages = (len(ASL_WORDS) + words_per_page - 1) // words_per_page
            current_page = (current_page + 1) % total_pages
            print_word_menu(current_page, words_per_page)
            
        elif key == ord('p'):
            # Previous page
            total_pages = (len(ASL_WORDS) + words_per_page - 1) // words_per_page
            current_page = (current_page - 1) % total_pages
            print_word_menu(current_page, words_per_page)
                
        elif ord('0') <= key <= ord('9'):
            # Select word from current page
            word_idx = (key - ord('0')) + (current_page * words_per_page)
            if word_idx < len(ASL_WORDS):
                collector.set_label(ASL_WORDS[word_idx])
            else:
                print(f"⚠️  Invalid selection. Press 'n' for more words.")
        
        frame_count += 1
    
    # Cleanup
    detector.close()
    cap.release()
    cv2.destroyAllWindows()
    
    # Save data
    print("\n" + "=" * 60)
    if collector.data:
        print("💾 Saving collected data...")
        collector.save_to_csv()
    else:
        print("No data collected.")
    
    print("\n✅ Done!")
    print("=" * 60)


if __name__ == "__main__":
    main()
