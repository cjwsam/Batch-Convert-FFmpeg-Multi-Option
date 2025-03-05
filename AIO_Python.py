#!/usr/bin/env python3
import os
import subprocess
import hashlib
import logging
import json
from pathlib import Path
from datetime import datetime
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed
from uuid import uuid4  # Used for generating unique temporary filenames

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger(__name__)

# Try to import langdetect for subtitle language detection
try:
    from langdetect import detect, LangDetectException
    LANGDETECT_AVAILABLE = True
except ImportError:
    LANGDETECT_AVAILABLE = False
    logger.warning("langdetect not available. Skipping language detection.")

# External tool paths
FFMPEG = "ffmpeg"
FFPROBE = "ffprobe"

# Directory to scan (update this to your video directory)
DIRECTORIES = [r"F:\TV"]

# Paths for tracking processed files and hashes
PROCESSED_LIST_PATH = Path("processed.txt")
HASHES_DB_PATH = Path("hashes_db.txt")

# Recognized text-based subtitle codecs
TEXT_CODECS = {
    "subrip": "srt",
    "ass": "ass",
    "ssa": "ass",
    "mov_text": "srt",
    "webvtt": "srt"
}

# Configuration options
SKIP_4K_OR_HDR = True
CONVERSION_TIMEOUT = 1800  # 30 minutes
MAX_WORKERS = 2

# Utility Functions
def load_processed_list() -> set:
    if not PROCESSED_LIST_PATH.is_file():
        return set()
    with PROCESSED_LIST_PATH.open("r", encoding="utf-8") as f:
        return {line.strip() for line in f if line.strip()}

def save_processed_list(processed_set: set):
    with PROCESSED_LIST_PATH.open("w", encoding="utf-8") as f:
        for item in sorted(processed_set):
            f.write(item + "\n")

def load_hash_db() -> set:
    if not HASHES_DB_PATH.is_file():
        return set()
    with HASHES_DB_PATH.open("r", encoding="utf-8") as f:
        return {line.strip() for line in f if line.strip()}

def save_hash_db(hash_set: set):
    with HASHES_DB_PATH.open("w", encoding="utf-8") as f:
        for h in sorted(hash_set):
            f.write(h + "\n")

def compute_file_hash(file: Path, chunk_size: int = 8192, max_bytes: int = 1024*1024) -> str:
    hash_sha256 = hashlib.sha256()
    with file.open("rb") as f:
        for chunk in iter(lambda: f.read(chunk_size), b""):
            hash_sha256.update(chunk)
            if f.tell() >= max_bytes:
                break
    return hash_sha256.hexdigest()

def get_temp_conversion_filename(video_file: Path) -> Path:
    """
    Generate a unique temporary filename for the conversion process.
    This uses a descriptive pattern with a formatted timestamp and a unique ID.
    """
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    unique_id = uuid4().hex[:8]  # 8-character unique identifier
    return video_file.parent / f"{video_file.stem}_converted_{timestamp}_{unique_id}.mp4"

def cleanup_temp_files(video_file: Path):
    """Delete temporary conversion files using the new naming scheme."""
    temp_pattern = video_file.parent / f"{video_file.stem}_converted_*.mp4"
    for temp_file in video_file.parent.glob(temp_pattern.name):
        try:
            temp_file.unlink()
            logger.info("Deleted temporary file: %s", temp_file)
        except Exception as e:
            logger.warning("Failed to delete temporary file %s: %s", temp_file, e)

def maybe_guess_srt_language(srt_file: Path):
    if not LANGDETECT_AVAILABLE or not srt_file.is_file():
        return
    text = srt_file.read_text(encoding="utf-8", errors="ignore")
    if len(text.strip()) < 20:
        return
    try:
        guessed = detect(text).lower()
        if guessed != "en":
            new_name = f"{srt_file.stem}.{guessed}.srt"
            new_path = srt_file.with_name(new_name)
            if not new_path.exists():
                srt_file.rename(new_path)
                logger.info("Renamed %s to %s (detected: %s)", srt_file.name, new_name, guessed)
    except Exception as e:
        logger.warning("Language detection failed for %s: %s", srt_file.name, e)

def run_ffprobe(stream_type: str, file: Path) -> dict:
    cmd = [
        FFPROBE, "-v", "error", "-select_streams", stream_type,
        "-show_entries", "stream=codec_type,codec_name,width,height,color_transfer,pix_fmt,tags",
        "-of", "json", str(file)
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return json.loads(result.stdout) if result.returncode == 0 else {}

def check_video_info(file: Path) -> dict:
    info = {
        "video_codec": "unknown",
        "audio_codec": "unknown",
        "text_sub_tracks": [],
        "image_sub_tracks": [],
        "width": 0,
        "height": 0,
        "color_transfer": "",
        "pix_fmt": ""
    }
    video_info = run_ffprobe("v", file)
    if video_info.get("streams"):
        stream = video_info["streams"][0]
        info["video_codec"] = stream.get("codec_name", "unknown")
        info["width"] = int(stream.get("width", 0))
        info["height"] = int(stream.get("height", 0))
        info["color_transfer"] = stream.get("color_transfer", "")
        info["pix_fmt"] = stream.get("pix_fmt", "")

    audio_info = run_ffprobe("a", file)
    if audio_info.get("streams"):
        info["audio_codec"] = audio_info["streams"][0].get("codec_name", "unknown")

    subtitle_info = run_ffprobe("s", file)
    if subtitle_info.get("streams"):
        for idx, stream in enumerate(subtitle_info["streams"]):
            codec_name = stream.get("codec_name", "unknown")
            lang_tag = stream.get("tags", {}).get("language", "")
            if codec_name in TEXT_CODECS:
                info["text_sub_tracks"].append((idx, codec_name, lang_tag))
            elif codec_name == "hdmv_pgs_subtitle":
                info["image_sub_tracks"].append((idx, codec_name, lang_tag))
    return info

def is_4k_or_hdr(width: int, height: int, color_transfer: str) -> bool:
    if width >= 3840 and height >= 2160:
        return True
    hdr_indicators = {"smpte2084", "arib-std-b67", "pq"}
    return color_transfer in hdr_indicators

def convert_to_mp4(src: Path, dst: Path, info: dict) -> bool:
    video_codec = info["video_codec"]
    audio_codec = info["audio_codec"]
    pix_fmt = info["pix_fmt"]
    filter_args = ["-vf", "format=yuv420p"] if "10" in pix_fmt else []

    # GPU encoding
    gpu_cmd = [
        FFMPEG, "-hide_banner", "-y", "-hwaccel", "cuda",
        "-i", str(src), *filter_args,
        "-c:v", "h264_nvenc", "-preset", "p5", "-cq", "20", "-pix_fmt", "yuv420p"
    ]
    if audio_codec in {"aac", "mp3", "ac3"}:
        gpu_cmd += ["-c:a", "copy"]
    else:
        gpu_cmd += ["-c:a", "aac", "-b:a", "192k"]
    gpu_cmd += ["-f", "mp4", str(dst)]

    try:
        result = subprocess.run(gpu_cmd, capture_output=True, text=True, timeout=CONVERSION_TIMEOUT)
        if result.returncode == 0 and dst.exists():
            return True
    except subprocess.TimeoutExpired:
        logger.error("GPU conversion timed out for %s", src.name)
        return False

    # CPU fallback
    cpu_cmd = [
        FFMPEG, "-hide_banner", "-y", "-i", str(src), *filter_args,
        "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p"
    ]
    if audio_codec in {"aac", "mp3", "ac3"}:
        cpu_cmd += ["-c:a", "copy"]
    else:
        cpu_cmd += ["-c:a", "aac", "-b:a", "192k"]
    cpu_cmd += ["-f", "mp4", str(dst)]

    try:
        result = subprocess.run(cpu_cmd, capture_output=True, text=True, timeout=CONVERSION_TIMEOUT)
        return result.returncode == 0 and dst.exists()
    except subprocess.TimeoutExpired:
        logger.error("CPU conversion timed out for %s", src.name)
        return False

def extract_text_subs_if_any(video_file: Path, text_sub_tracks: list):
    for track_index, codec, lang_tag in text_sub_tracks:
        out_name = f"{video_file.stem}.{lang_tag or f'track{track_index}'}.srt"
        out_path = video_file.with_name(out_name)
        if out_path.exists():
            continue
        cmd = [FFMPEG, "-hide_banner", "-y", "-i", str(video_file), "-map", f"0:{track_index}", "-c:s", "srt", str(out_path)]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode == 0 and out_path.exists() and out_path.stat().st_size > 0:
            logger.info("Extracted subtitle to %s", out_path.name)
            if not lang_tag and LANGDETECT_AVAILABLE:
                maybe_guess_srt_language(out_path)
        else:
            logger.warning("Subtitle extraction failed for track %s", track_index)

def extract_image_subs_if_any(video_file: Path, image_sub_tracks: list):
    for track_index, codec, lang_tag in image_sub_tracks:
        out_name = f"{video_file.stem}.{lang_tag or f'track{track_index}'}.sup"
        out_path = video_file.with_name(out_name)
        if out_path.exists():
            continue
        cmd = [FFMPEG, "-hide_banner", "-y", "-i", str(video_file), "-map", f"0:{track_index}", str(out_path)]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode == 0 and out_path.exists() and out_path.stat().st_size > 0:
            logger.info("Extracted image subtitle to %s. Use OCR to convert to SRT if needed.", out_path.name)

def process_video(video_file: Path, idx: int, total: int, processed_set: set, processed_hashes: set):
    original_path_str = str(video_file.resolve())
    if original_path_str in processed_set:
        logger.info("[%d/%d] SKIP (already processed): %s", idx, total, video_file.name)
        return

    # Clean up temporary files using the updated naming scheme
    cleanup_temp_files(video_file)

    file_hash = compute_file_hash(video_file)
    if file_hash and file_hash in processed_hashes:
        logger.info("[%d/%d] Duplicate detected: %s. Removing.", idx, total, video_file.name)
        video_file.unlink()
        processed_set.add(original_path_str)
        return
    if file_hash:
        processed_hashes.add(file_hash)

    logger.info("[%d/%d] Processing: %s", idx, total, video_file.name)
    info = check_video_info(video_file)
    if info["video_codec"] == "unknown" and info["audio_codec"] == "unknown":
        logger.warning("No valid streams in %s", video_file.name)
        processed_set.add(original_path_str)
        return

    if SKIP_4K_OR_HDR and is_4k_or_hdr(info["width"], info["height"], info["color_transfer"]):
        logger.info("Detected 4K/HDR in %s. Skipping.", video_file.name)
        processed_set.add(original_path_str)
        return

    final_file = video_file
    if (info["video_codec"] == "h264" and info["audio_codec"] in {"aac", "mp3", "ac3"} and
        video_file.suffix.lower() == ".mp4"):
        logger.info("File %s is already optimized.", video_file.name)
    else:
        # Use the new temporary filename generator
        temp_mp4_path = get_temp_conversion_filename(video_file)
        if convert_to_mp4(video_file, temp_mp4_path, info):
            video_file.unlink()  # Delete original file
            final_file = video_file.with_suffix('.mp4')
            temp_mp4_path.rename(final_file)
            logger.info("Converted to %s", final_file.name)
        else:
            logger.error("Conversion failed for %s", video_file.name)
            processed_set.add(original_path_str)
            return
        info = check_video_info(final_file)

    if info["text_sub_tracks"]:
        extract_text_subs_if_any(final_file, info["text_sub_tracks"])
    if info["image_sub_tracks"]:
        extract_image_subs_if_any(final_file, info["image_sub_tracks"])

    processed_set.add(original_path_str)
    processed_set.add(str(final_file.resolve()))

def scan_video_files(directories: list) -> list:
    video_exts = {".mkv", ".mp4", ".avi", ".mov", ".flv", ".wmv"}
    video_files = []
    for directory in directories:
        base_path = Path(directory)
        for ext in video_exts:
            video_files.extend(base_path.rglob(f"*{ext}"))
    return sorted(video_files)

def main():
    logger.info("Starting video processing...")
    all_videos = scan_video_files(DIRECTORIES)
    if not all_videos:
        logger.info("No video files found.")
        return
    logger.info("Found %d video files.", len(all_videos))

    processed_set = load_processed_list()
    processed_hashes = load_hash_db()

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {
            executor.submit(process_video, video_file, i, len(all_videos), processed_set, processed_hashes): video_file
            for i, video_file in enumerate(all_videos, 1)
        }
        for future in tqdm(as_completed(futures), total=len(futures), desc="Processing videos"):
            future.result()

    save_processed_list(processed_set)
    save_hash_db(processed_hashes)
    logger.info("Processing complete.")

if __name__ == "__main__":
    main()
