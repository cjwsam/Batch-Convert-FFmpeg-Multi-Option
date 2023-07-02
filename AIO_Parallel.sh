#!/bin/bash
#
# Adjust as needed.
SEARCH_LOCATION="PUT SEARCH DIR HERE"
LOG_FILE=""
MIN_SIZE=30M
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
    filename=$1
    SOURCE_FILE="$filename"

    uauma="no"
    fName=$(basename -- "$SOURCE_FILE")
    fExt="${fName##*.}"
    fExtLower=`echo "$fExt" | awk '{print tolower($0)}'`
    filename="${SOURCE_FILE%.*}"
    vcodex=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")
    acodex=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")
    scodex=$(ffprobe -v error -select_streams s:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")

    if [[ ($vcodex == "h264") && ($acodex == "aac") && ($scodex == "") ]]; then
        echo ""
        echo "--------------------------------------------------------"
        echo "Since this file is Done It Will be Skipped "
        echo "--------------------------------------------------------"
        echo ""
        return
    elif [[ ($vcodex == "h264") && ($acodex == "aac") && ($scodex != "") ]]; then
        echo ""
        echo "--------------------------------------------------------"
        echo "File Contains SUBS they Will be stripped "
        echo "--------------------------------------------------------"
        echo ""
        ffmpeg -hide_banner -i "$SOURCE_FILE" -y  "${filename}.en.srt"
        ffmpeg -hide_banner -i "$SOURCE_FILE" -c copy -ac 2 -movflags +faststart -sn -f mp4 -y "${filename}-Converting.mp4"
        exitCode=$?

        if [ $exitCode -eq 0 ]; then
            if [ "$DELETE_SOURCE_FILES" -eq 1 ]; then
                mv "${filename}-Converting.mp4" "${filename}.mp4"
                if [ "$fExtLower" == "mp4" ]; then
                    echo "No need to delete file "
                else
                    rm -rf "$SOURCE_FILE"
                fi
            fi
        else
            exit $exitCode
        fi
    elif [[ ($vcodex == "h264") && ($acodex != "aac") ]]; then
        echo ""
        echo "--------------------------------------------------------"
        echo "File Video is h264 but the AUDIO will be encoded to AAC"
        echo "--------------------------------------------------------"
        echo ""
        ffmpeg -hide_banner -i "$SOURCE_FILE" -y  "${filename}.en.srt"
        ffmpeg -hide_banner -i "$SOURCE_FILE" -c:v copy -c:a libfdk_aac -ac 2 -movflags +faststart -sn -f mp4 -y "${filename}-Converting.mp4"
        exitCode=$?

        if [ $exitCode -eq 0 ]; then
            if [ "$DELETE_SOURCE_FILES" -eq 1 ]; then
                mv "${filename}-Converting.mp4" "${filename}.mp4"
                if [ "$fExtLower" == "mp4" ]; then
                    echo "No need to delete file "
                else
                    rm -rf "$SOURCE_FILE"
                fi
            fi
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
        ffmpeg -hide_banner -i "$SOURCE_FILE" -y  "${filename}.en.srt"
        ffmpeg -hide_banner -i "$SOURCE_FILE" -c:v libx264 -threads 6 -tune film -acodec libfdk_aac -ac 2 -movflags +faststart -sn -f mp4 -y "${filename}-Converting.mp4"
        exitCode=$?

        if [ $exitCode -eq 0 ]; then
            if [ "$DELETE_SOURCE_FILES" -eq 1 ]; then
                mv "${filename}-Converting.mp4" "${filename}.mp4"
                if [ "$fExtLower" == "mp4" ]; then
                    echo "No need to delete file "
                else
                    rm -rf "$SOURCE_FILE"
                fi
            fi
        else
            exit $exitCode
        fi
    fi
}

# Run conversion in parallel
for filename in "${process_movies[@]}"; do
    (
        convert_file "$filename"
    ) &
done
wait

echo ""
