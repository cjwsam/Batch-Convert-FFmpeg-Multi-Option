#!/bin/bash
#
# AIO_Parallel.sh - Batch video converter with parallel processing
#
# Converts video files to H.264/AAC MP4 format for optimal Plex direct play.
# Runs multiple conversions in parallel (controlled by MAX_JOBS).
#
# WARNING: When DELETE_SOURCE_FILES=1, original files are permanently deleted
# after successful conversion. Back up your media before running this script.

# Adjust as needed.
SEARCH_LOCATION="PUT SEARCH DIR HERE"
LOG_FILE=""
MIN_SIZE=30M
MAX_JOBS=2  # Maximum number of parallel conversions (adjust based on CPU/RAM)
FILE_EXTENSIONS=(
    "mp4"
    "avi"
    "m4v"
    "mpg"
    "mpeg"
    "mkv"
    "ts"
)

DEFAULT_LANGUAGE="eng"
DELETE_SOURCE_FILES=1 # Set to 0 to disable deleting of the original media

# No need to edit below here.
################################################################################################

# Progress bar function
prog() {
    local w=50 p=$1;  shift
    printf -v dots "%*s" "$(( $p*$w/100 ))" ""; dots=${dots// /#};
    printf "\r\e[K|%-*s| %3d %% %s" "$w" "$dots" "$p" "$*";
}

NAME_ARGS=""
for i in "${FILE_EXTENSIONS[@]}"; do :
    if [[ -z "${NAME_ARGS// }" ]]; then
        NAME_ARGS="$i"
    else
        NAME_ARGS="$NAME_ARGS|$i"
    fi
done

echo -e "++ Bulk Processing ++\n--------------------------------\n"
echo "Building file list - please be patient..."


SEARCH_COMMAND="find $SEARCH_LOCATION -type f -size +$MIN_SIZE -regextype posix-egrep -regex \".*\\.($NAME_ARGS)\$\" -print0"

process_movies=()
while IFS=  read -r -d $'\0'; do
    process_movies+=("$REPLY")
done < <(eval $SEARCH_COMMAND | sort -z )

count=0
total=`echo ${#process_movies[@]}`
echo -e "\nProcessing results:"

RED='\033[0;31m'
NC='\033[0m' # No Color

if [ "$total" -gt "100" ]; then
    SLOW_COMMENT="(this will take a while)"
fi
echo "Converting $total files $SLOW_COMMENT..."

# Function to convert a single file
convert_file() {
    local SOURCE_FILE="$1"

    local fName
    fName=$(basename -- "$SOURCE_FILE")
    local fExt="${fName##*.}"
    local fExtLower
    fExtLower=$(echo "$fExt" | awk '{print tolower($0)}')
    local filename="${SOURCE_FILE%.*}"
    local vcodex acodex scodex exitCode
    vcodex=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")
    acodex=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")
    scodex=$(ffprobe -v error -select_streams s:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")

    if [[ ($vcodex == "h264") && ($acodex == "aac") && ($scodex == "") ]]; then
        echo ""
        echo "--------------------------------------------------------"
        echo "File already optimized, skipping: $fName"
        echo "--------------------------------------------------------"
        echo ""
        return 0
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
        else
            return $exitCode
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
        else
            return $exitCode
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
        else
            return $exitCode
        fi
    fi
}

# Run conversion in parallel with controlled concurrency
for filename in "${process_movies[@]}"; do
    # Wait if we have reached the maximum number of parallel jobs
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do
        sleep 1
    done

    (
        convert_file "$filename"
    ) &
done
wait

echo ""
