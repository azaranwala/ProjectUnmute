#!/usr/bin/env python3
"""
ASL Citizen Dataset Downloader and Processor

Downloads the Microsoft ASL Citizen dataset and extracts hand landmarks
using MediaPipe for training ASL recognition models.

Dataset: https://www.microsoft.com/en-us/research/project/asl-citizen/
- 84,000 videos
- 2,700 distinct signs
- ~13GB compressed

Usage:
    python3 download_asl_citizen.py
"""

import os
import sys
import zipfile
import urllib.request
import json
import csv
from pathlib import Path

# Configuration
DATASET_URL = "https://download.microsoft.com/download/b/8/8/b88c0bae-e6c1-43e1-8726-98cf5af36ca4/ASL_Citizen.zip"
DATASET_DIR = "asl_citizen_dataset"
DATASET_ZIP = "ASL_Citizen.zip"
OUTPUT_CSV = "asl_citizen_landmarks.csv"


def download_progress(count, block_size, total_size):
    """Show download progress."""
    percent = int(count * block_size * 100 / total_size)
    mb_downloaded = count * block_size / (1024 * 1024)
    mb_total = total_size / (1024 * 1024)
    sys.stdout.write(f"\r   Downloading: {percent}% ({mb_downloaded:.1f}/{mb_total:.1f} MB)")
    sys.stdout.flush()


def download_dataset():
    """Download the ASL Citizen dataset."""
    if os.path.exists(DATASET_ZIP):
        print(f"✓ Dataset zip already exists: {DATASET_ZIP}")
        return True
    
    print(f"\n📥 Downloading ASL Citizen dataset (~13GB)...")
    print(f"   URL: {DATASET_URL}")
    print(f"   This may take 30-60 minutes depending on your connection.\n")
    
    try:
        urllib.request.urlretrieve(DATASET_URL, DATASET_ZIP, download_progress)
        print(f"\n✓ Download complete: {DATASET_ZIP}")
        return True
    except Exception as e:
        print(f"\n❌ Download failed: {e}")
        return False


def extract_dataset():
    """Extract the dataset zip file."""
    if os.path.exists(DATASET_DIR) and os.listdir(DATASET_DIR):
        print(f"✓ Dataset already extracted: {DATASET_DIR}/")
        return True
    
    if not os.path.exists(DATASET_ZIP):
        print(f"❌ Dataset zip not found: {DATASET_ZIP}")
        return False
    
    print(f"\n📦 Extracting dataset...")
    try:
        with zipfile.ZipFile(DATASET_ZIP, 'r') as zip_ref:
            zip_ref.extractall(DATASET_DIR)
        print(f"✓ Extraction complete: {DATASET_DIR}/")
        return True
    except Exception as e:
        print(f"❌ Extraction failed: {e}")
        return False


def explore_dataset():
    """Explore the dataset structure."""
    print(f"\n🔍 Exploring dataset structure...")
    
    dataset_path = Path(DATASET_DIR)
    
    # Find all directories
    dirs = [d for d in dataset_path.rglob("*") if d.is_dir()]
    print(f"   Found {len(dirs)} directories")
    
    # Find all video files
    video_extensions = ['.mp4', '.avi', '.mov', '.webm']
    videos = []
    for ext in video_extensions:
        videos.extend(list(dataset_path.rglob(f"*{ext}")))
    print(f"   Found {len(videos)} video files")
    
    # Find metadata/label files
    json_files = list(dataset_path.rglob("*.json"))
    csv_files = list(dataset_path.rglob("*.csv"))
    txt_files = list(dataset_path.rglob("*.txt"))
    
    print(f"   Found {len(json_files)} JSON files")
    print(f"   Found {len(csv_files)} CSV files")
    print(f"   Found {len(txt_files)} TXT files")
    
    # Show sample structure
    print(f"\n   Sample files:")
    all_files = list(dataset_path.rglob("*"))[:20]
    for f in all_files:
        if f.is_file():
            print(f"      {f.relative_to(dataset_path)}")
    
    return videos, json_files, csv_files


def main():
    print("=" * 60)
    print("  ASL Citizen Dataset Downloader")
    print("=" * 60)
    print("\nDataset Info:")
    print("  • 84,000 videos of ASL signs")
    print("  • 2,700 distinct sign classes")
    print("  • ~13GB compressed")
    print("  • Source: Microsoft Research")
    print("\n" + "=" * 60)
    
    # Step 1: Download
    print("\n[Step 1/3] Download Dataset")
    if not download_dataset():
        print("\n⚠️  To download manually, run:")
        print(f"   wget {DATASET_URL}")
        return
    
    # Step 2: Extract
    print("\n[Step 2/3] Extract Dataset")
    if not extract_dataset():
        return
    
    # Step 3: Explore
    print("\n[Step 3/3] Explore Dataset")
    videos, json_files, csv_files = explore_dataset()
    
    print("\n" + "=" * 60)
    print("  Download Complete!")
    print("=" * 60)
    print("\nNext step: Run the landmark extraction script:")
    print("  python3 process_asl_citizen.py")
    print("\n" + "=" * 60)


if __name__ == "__main__":
    main()
