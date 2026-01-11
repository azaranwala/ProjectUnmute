#!/usr/bin/env python3
"""
Import WLASL videos into AvatarAssets folder.

Reads WLASL_v0.3.json to map glosses to video IDs,
then copies matching videos to AvatarAssets with proper names.
"""

import os
import sys
import shutil
import json
from pathlib import Path

# Target glosses we want videos for
TARGET_GLOSSES = {
    # Greetings
    "hello", "hi", "goodbye", "bye",
    # Polite
    "thank you", "please", "sorry", "excuse",
    # Yes/No
    "yes", "no", "maybe", "ok",
    # Actions
    "help", "stop", "wait", "go", "come", "sit", "stand",
    # Feelings
    "happy", "sad", "angry", "tired", "sick", "hurt", "pain",
    # Needs
    "water", "food", "hungry", "thirsty", "bathroom", "eat", "drink",
    # Questions
    "what", "where", "when", "why", "who", "how", "which",
    # Family
    "mother", "father", "family", "friend", "brother", "sister",
    # Common words
    "want", "need", "like", "love", "know", "understand",
    "good", "bad", "fine", "cool", "hot", "cold",
    "more", "again", "finish", "done", "now", "later",
    "name", "work", "school", "home", "doctor",
    "open", "close", "big", "small", "all",
    # Time
    "morning", "night", "day", "week", "year", "today", "tomorrow",
    # Colors
    "red", "blue", "green", "yellow", "black", "white", "orange", "pink", "purple", "brown",
    # Numbers
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
}

def main():
    # Paths
    wlasl_path = Path("/Users/zaranwala/Downloads/WLASLVideoFiles")
    json_path = wlasl_path / "WLASL_v0.3.json"
    videos_path = wlasl_path / "videos"
    
    project_root = Path(__file__).parent.parent
    avatar_assets = project_root / "ProjectUnmute" / "Resources" / "AvatarAssets"
    
    print(f"WLASL source: {wlasl_path}")
    print(f"Output folder: {avatar_assets}")
    print()
    
    # Create output folder
    avatar_assets.mkdir(parents=True, exist_ok=True)
    
    # Load JSON
    print("Loading WLASL_v0.3.json...")
    with open(json_path, "r") as f:
        wlasl_data = json.load(f)
    print(f"Loaded {len(wlasl_data)} glosses")
    
    # Get list of available video files
    available_videos = set()
    for video_file in videos_path.glob("*.mp4"):
        available_videos.add(video_file.stem)
    print(f"Found {len(available_videos)} video files in videos/")
    print()
    
    # Build gloss -> video_id mapping
    gloss_to_video = {}
    for entry in wlasl_data:
        gloss = entry.get("gloss", "").lower()
        instances = entry.get("instances", [])
        
        # Find first available video for this gloss
        for instance in instances:
            video_id = instance.get("video_id", "")
            if video_id in available_videos:
                gloss_to_video[gloss] = video_id
                break
    
    print(f"Mapped {len(gloss_to_video)} glosses to available videos")
    print()
    
    # Copy matching videos
    copied = 0
    copied_list = []
    missing = []
    
    for target in sorted(TARGET_GLOSSES):
        target_lower = target.lower().replace(" ", "")
        
        # Try exact match
        video_id = gloss_to_video.get(target_lower)
        
        # Try without spaces
        if not video_id:
            for gloss, vid in gloss_to_video.items():
                if target_lower == gloss.replace(" ", ""):
                    video_id = vid
                    break
        
        # Try partial match
        if not video_id:
            for gloss, vid in gloss_to_video.items():
                if target_lower in gloss or gloss in target_lower:
                    video_id = vid
                    break
        
        if not video_id:
            missing.append(target)
            continue
        
        # Copy video
        src = videos_path / f"{video_id}.mp4"
        dst_name = target.lower().replace(" ", "_") + ".mp4"
        dst = avatar_assets / dst_name
        
        if src.exists():
            print(f"  ✓ {target:15} -> {dst_name} (from {video_id}.mp4)")
            shutil.copy2(src, dst)
            copied += 1
            copied_list.append(target)
        else:
            missing.append(target)
    
    print()
    print(f"{'='*50}")
    print(f"Copied {copied} videos to AvatarAssets")
    
    if missing:
        print(f"\nMissing ({len(missing)}):")
        for m in missing:
            print(f"  - {m}")
    
    # Write manifest
    manifest_path = avatar_assets / "manifest.json"
    manifest = {
        "source": "WLASL v0.3",
        "count": copied,
        "glosses": sorted(copied_list),
        "missing": sorted(missing)
    }
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"\nManifest written to: {manifest_path}")
    
    # List all available glosses
    all_glosses_path = avatar_assets / "_all_available_glosses.txt"
    with open(all_glosses_path, "w") as f:
        for gloss in sorted(gloss_to_video.keys()):
            f.write(f"{gloss}\n")
    print(f"All glosses written to: {all_glosses_path}")

if __name__ == "__main__":
    main()
