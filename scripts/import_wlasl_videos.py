#!/usr/bin/env python3
"""
Import WLASL videos into AvatarAssets folder.

Usage:
    python import_wlasl_videos.py /path/to/wlasl-processed

This script copies videos for common phrases to the AvatarAssets folder,
renaming them to match the phrase format expected by Project Unmute.
"""

import os
import sys
import shutil
import json
from pathlib import Path

# Target phrases we want videos for (matches SpeechRecognizer.swift mapping)
TARGET_GLOSSES = [
    "hello", "hi", "hey",
    "goodbye", "bye",
    "thank you", "thanks",
    "please", "sorry",
    "yes", "no", "maybe",
    "help", "stop", "wait",
    "love", 
    "good", "morning", "night",
    "how", "fine",
    "water", "food", "hungry", "thirsty",
    "bathroom", "pain", "tired",
    "happy", "sad", "angry",
    "name", "what", "where", "when", "why", "who",
    "want", "need", "like",
    "understand", "know",
    "family", "friend", "mother", "father",
    "eat", "drink", "sleep",
    "go", "come", "sit", "stand",
    "open", "close",
    "hot", "cold",
    "big", "small",
    "more", "again",
    "finish", "done",
]

def find_wlasl_structure(wlasl_path: Path):
    """Determine the structure of the WLASL dataset."""
    # Check for common structures
    if (wlasl_path / "videos").exists():
        return wlasl_path / "videos"
    if (wlasl_path / "processed").exists():
        return wlasl_path / "processed"
    # Might be flat structure with gloss folders
    return wlasl_path

def get_video_files(videos_path: Path):
    """Get all video files organized by gloss."""
    gloss_videos = {}
    
    for item in videos_path.iterdir():
        if item.is_dir():
            # Folder structure: videos/gloss_name/video.mp4
            gloss = item.name.lower().replace("_", " ")
            videos = list(item.glob("*.mp4")) + list(item.glob("*.mov"))
            if videos:
                gloss_videos[gloss] = videos[0]  # Take first video
        elif item.suffix.lower() in [".mp4", ".mov", ".m4v"]:
            # Flat structure: videos/gloss_001.mp4
            gloss = item.stem.rsplit("_", 1)[0].lower().replace("_", " ")
            if gloss not in gloss_videos:
                gloss_videos[gloss] = item
    
    return gloss_videos

def main():
    if len(sys.argv) < 2:
        print("Usage: python import_wlasl_videos.py /path/to/wlasl-processed")
        print("\nDownload WLASL from: https://www.kaggle.com/datasets/risangbaskoro/wlasl-processed")
        sys.exit(1)
    
    wlasl_path = Path(sys.argv[1])
    if not wlasl_path.exists():
        print(f"Error: Path not found: {wlasl_path}")
        sys.exit(1)
    
    # Determine output path
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    avatar_assets = project_root / "ProjectUnmute" / "Resources" / "AvatarAssets"
    
    # Create AvatarAssets if needed
    avatar_assets.mkdir(parents=True, exist_ok=True)
    
    print(f"WLASL source: {wlasl_path}")
    print(f"Output folder: {avatar_assets}")
    print()
    
    # Find videos structure
    videos_path = find_wlasl_structure(wlasl_path)
    print(f"Scanning: {videos_path}")
    
    # Get available videos
    available = get_video_files(videos_path)
    print(f"Found {len(available)} glosses in dataset")
    print()
    
    # Copy matching videos
    copied = 0
    missing = []
    
    for gloss in TARGET_GLOSSES:
        gloss_lower = gloss.lower()
        
        # Try exact match first
        if gloss_lower in available:
            src = available[gloss_lower]
        else:
            # Try variations
            found = None
            for key in available:
                if gloss_lower in key or key in gloss_lower:
                    found = available[key]
                    break
            if not found:
                missing.append(gloss)
                continue
            src = found
        
        # Output filename (underscores for spaces)
        out_name = gloss_lower.replace(" ", "_") + ".mp4"
        dst = avatar_assets / out_name
        
        print(f"  Copying: {src.name} -> {out_name}")
        shutil.copy2(src, dst)
        copied += 1
    
    print()
    print(f"Copied {copied} videos to AvatarAssets")
    
    if missing:
        print(f"\nMissing glosses ({len(missing)}):")
        for m in missing[:20]:
            print(f"  - {m}")
        if len(missing) > 20:
            print(f"  ... and {len(missing) - 20} more")
    
    # List all available glosses (for reference)
    print(f"\nAll available glosses in dataset: {len(available)}")
    glosses_file = avatar_assets / "_available_glosses.txt"
    with open(glosses_file, "w") as f:
        for gloss in sorted(available.keys()):
            f.write(f"{gloss}\n")
    print(f"Written to: {glosses_file}")

if __name__ == "__main__":
    main()
