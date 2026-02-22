# Batch-Convert-FFmpeg-Multi-Option

Batch convert video files to H.264 video / AAC audio in MP4 containers for optimal direct play on Plex Media Server. The tool intelligently detects each file's current codecs and only re-encodes what is necessary, saving significant time on large libraries.

## What It Does

Rather than blindly re-encoding every file, the converter inspects each video and takes the most efficient path:

1. **Already H.264/AAC with no subtitles** -- Skips the file entirely (no work needed).
2. **H.264/AAC but has embedded subtitles** -- Extracts subtitles to external `.srt` files and remuxes without re-encoding.
3. **H.264 video but non-AAC audio** -- Copies the video stream and only re-encodes the audio to AAC.
4. **Non-H.264 video** -- Performs a full re-encode of both video (to H.264) and audio (to AAC).

Embedded subtitles are extracted to external files before being stripped from the container. The result is a clean MP4 file that Plex can direct play without transcoding.

## Scripts

| Script | Description |
|---|---|
| `ConvertAutomated.sh` | Converts a **single** video file. Can be used standalone or called by the batch script. |
| `BatchConvertAutomated.sh` | Finds all video files in a directory and converts them **sequentially**, showing a progress bar. Calls `ConvertAutomated.sh` for each file. |
| `AIO_Parallel.sh` | **All-in-one parallel** bash script. Self-contained (does not call external scripts). Converts multiple files simultaneously with a configurable concurrency limit (`MAX_JOBS`). |
| `AIO_Python.py` | **Python version** with advanced features: GPU-accelerated encoding (NVIDIA NVENC with CPU fallback), duplicate detection via file hashing, processed-file tracking, 4K/HDR skip logic, subtitle language detection, and thread-safe parallel processing. |

## Prerequisites

- **FFmpeg** and **ffprobe** must be installed and available on your `PATH`.
  - On Debian/Ubuntu: `sudo apt install ffmpeg`
  - On macOS (Homebrew): `brew install ffmpeg`
  - On Windows: Download from [ffmpeg.org](https://ffmpeg.org/download.html) and add to your PATH.
- The bash scripts use `libfdk_aac` for AAC encoding. If your FFmpeg build does not include it, replace `libfdk_aac` with `aac` in the scripts.
- **Python script only:** Python 3.7+ with the `tqdm` package (`pip install tqdm`). Optional: `langdetect` for automatic subtitle language detection (`pip install langdetect`).
- **Python script (GPU encoding):** An NVIDIA GPU with NVENC support and FFmpeg compiled with `--enable-nvenc`. The script automatically falls back to CPU encoding if GPU encoding fails.

## Usage

### Single File

```bash
./ConvertAutomated.sh "/path/to/movie.mkv"
```

### Batch (Sequential)

1. Edit `BatchConvertAutomated.sh` and set `SEARCH_LOCATION` to your media directory.
2. Run:

```bash
./BatchConvertAutomated.sh
```

### Batch (Parallel - Bash)

1. Edit `AIO_Parallel.sh` and set `SEARCH_LOCATION` to your media directory.
2. Optionally adjust `MAX_JOBS` (default: 2) based on your CPU and RAM.
3. Run:

```bash
./AIO_Parallel.sh
```

### Batch (Python)

1. Edit `AIO_Python.py` and set `DIRECTORIES` to a list of your media directories.
2. Optionally adjust `MAX_WORKERS`, `CONVERSION_TIMEOUT`, and `SKIP_4K_OR_HDR`.
3. Run:

```bash
python3 AIO_Python.py
```

## Supported Input Formats

The bash scripts search for files with these extensions (configurable via `FILE_EXTENSIONS`):

- `.mp4`, `.avi`, `.m4v`, `.mpg`, `.mpeg`, `.mkv`, `.ts`

The Python script searches for:

- `.mkv`, `.mp4`, `.avi`, `.mov`, `.flv`, `.wmv`

## Configuration Options

### Bash Scripts

| Variable | Default | Description |
|---|---|---|
| `SEARCH_LOCATION` | *(must be set)* | Root directory to scan for video files. |
| `MIN_SIZE` | `30M` | Minimum file size to process (skips small files). |
| `DELETE_SOURCE_FILES` | `1` | Set to `0` to keep original files after conversion. |
| `FILE_EXTENSIONS` | *(see script)* | Array of file extensions to search for. |
| `MAX_JOBS` | `2` | (Parallel script only) Maximum concurrent conversions. |

### Python Script

| Variable | Default | Description |
|---|---|---|
| `DIRECTORIES` | `[r"F:\TV"]` | List of directories to scan. |
| `MAX_WORKERS` | `2` | Maximum concurrent conversion threads. |
| `CONVERSION_TIMEOUT` | `1800` | Timeout per file in seconds (30 minutes). |
| `SKIP_4K_OR_HDR` | `True` | Skip 4K and HDR content to avoid quality loss. |
| `PROCESSED_LIST_PATH` | `processed.txt` | File tracking already-processed videos. |
| `HASHES_DB_PATH` | `hashes_db.txt` | File tracking content hashes for duplicate detection. |

## Safety Warnings

**This tool is destructive by default.** When `DELETE_SOURCE_FILES` is set to `1` (the default), original video files are permanently deleted after successful conversion. There is no undo.

Before running on your media library:

1. **Back up your files** or test on a small set of copies first.
2. Set `DELETE_SOURCE_FILES=0` if you want to keep originals.
3. Verify that your FFmpeg build supports the required encoders (`libfdk_aac` or `aac`, `libx264`, and optionally `h264_nvenc`).
4. Ensure you have sufficient disk space for temporary conversion files (the converted file is written alongside the original before the original is deleted).

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
