#!/bin/bash
#
# ConvertAutomated.sh - Single file video converter
#
# Converts a single video file to H.264/AAC MP4 format for Plex direct play.
# Called by BatchConvertAutomated.sh for each file in a batch, or can be
# used standalone for individual file conversion.
#
# Usage: ./ConvertAutomated.sh "/path/to/video.mkv"
#
# WARNING: When DELETE_SOURCE_FILES=1, the original file is permanently deleted
# after successful conversion. Back up your media before running this script.

DEFAULT_LANGUAGE="eng"
DELETE_SOURCE_FILES=1 # Set to 0 to disable deleting of the original media

################################################################################################

SOURCE_FILE="$1"

if [ -z "$SOURCE_FILE" ] || [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: Please provide a valid file path as the first argument."
    echo "Usage: $0 /path/to/video.mkv"
    exit 1
fi

fName=$(basename -- "$SOURCE_FILE")
fExt="${fName##*.}"
fExtLower=$(echo "$fExt" | awk '{print tolower($0)}')
filename="${SOURCE_FILE%.*}"
vcodex=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")
acodex=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")
scodex=$(ffprobe -v error -select_streams s:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")


if [[ ($vcodex == "h264") && ($acodex == "aac") && ($scodex == "") ]]; then

    echo ""
    echo "--------------------------------------------------------"
    echo "File already optimized, skipping: $fName"
    echo "--------------------------------------------------------"
    echo ""

    exit 0

elif [[ ($vcodex == "h264") && ($acodex == "aac") && ($scodex != "") ]]; then

    echo ""
    echo "--------------------------------------------------------"
    echo "File contains subtitles, they will be extracted and stripped"
    echo "--------------------------------------------------------"
    echo ""

    ffmpeg -hide_banner -i "$SOURCE_FILE" -y "${filename}.en.srt"
    ffmpeg -hide_banner -i "$SOURCE_FILE" -c copy -ac 2 -movflags +faststart -sn -f mp4 -y "${filename}-Converting.mp4"
    exitCode=$?

    if [ $exitCode -eq 0 ]; then
        if [ "$DELETE_SOURCE_FILES" -eq 1 ]; then
            mv "${filename}-Converting.mp4" "${filename}.mp4"
            if [ "$fExtLower" != "mp4" ]; then
                rm -f "$SOURCE_FILE"
            fi
        fi

        exit 0
    else
        exit $exitCode
    fi

elif [[ ($vcodex == "h264") && ($acodex != "aac") ]]; then

    echo ""
    echo "--------------------------------------------------------"
    echo "File video is H.264 but audio will be re-encoded to AAC"
    echo "--------------------------------------------------------"
    echo ""

    ffmpeg -hide_banner -i "$SOURCE_FILE" -y "${filename}.en.srt"
    ffmpeg -hide_banner -i "$SOURCE_FILE" -c:v copy -c:a libfdk_aac -ac 2 -movflags +faststart -sn -f mp4 -y "${filename}-Converting.mp4"
    exitCode=$?

    if [ $exitCode -eq 0 ]; then
        if [ "$DELETE_SOURCE_FILES" -eq 1 ]; then
            mv "${filename}-Converting.mp4" "${filename}.mp4"
            if [ "$fExtLower" != "mp4" ]; then
                rm -f "$SOURCE_FILE"
            fi
        fi
        exit 0
    else
        exit $exitCode
    fi

elif [[ ($vcodex != "h264") && ($vcodex != "hevc") ]]; then

    echo ""
    echo "----------------------------------------------------"
    echo "File requires FULL encoding *THIS WILL TAKE A WHILE*"
    echo "----------------------------------------------------"
    echo ""

    # Change this to your full encoding preferences
    ffmpeg -hide_banner -i "$SOURCE_FILE" -y "${filename}.en.srt"
    ffmpeg -hide_banner -i "$SOURCE_FILE" -c:v libx264 -threads 6 -tune film -acodec libfdk_aac -ac 2 -movflags +faststart -sn -f mp4 -y "${filename}-Converting.mp4"
    exitCode=$?

    if [ $exitCode -eq 0 ]; then
        if [ "$DELETE_SOURCE_FILES" -eq 1 ]; then
            mv "${filename}-Converting.mp4" "${filename}.mp4"
            if [ "$fExtLower" != "mp4" ]; then
                rm -f "$SOURCE_FILE"
            fi
        fi

        exit 0
    else
        exit $exitCode
    fi

fi
