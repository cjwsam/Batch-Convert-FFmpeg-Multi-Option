#!/bin/bash
#
# BatchConvertAutomated.sh - Batch video converter (sequential)
#
# Finds video files in SEARCH_LOCATION and converts them one at a time
# using ConvertAutomated.sh. Shows a progress bar during processing.
#
# WARNING: When DELETE_SOURCE_FILES is enabled in ConvertAutomated.sh,
# original files are permanently deleted after successful conversion.
# Back up your media before running this script.

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

# Path to the single-file conversion script (adjust if needed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERT_SCRIPT="${SCRIPT_DIR}/ConvertAutomated.sh"

# No need to edit below here.
################################################################################################

if [ ! -f "$CONVERT_SCRIPT" ]; then
    echo "Error: ConvertAutomated.sh not found at $CONVERT_SCRIPT"
    exit 1
fi

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

if [ "$total" -eq "0" ]; then
    echo "No files found to convert."
    exit 0
fi

if [ "$total" -gt "100" ]; then
    SLOW_COMMENT="(this will take a while)"
fi
echo "Converting $total files $SLOW_COMMENT..."

for filename in "${process_movies[@]}"; do :

    count=$((count + 1))
    taskpercent=$((count*100/total))
    shortName="${filename##*/}"

    prog "$taskpercent" "$shortName"...
    "$CONVERT_SCRIPT" "$filename"
    exitCode=$?

    if [ $exitCode -eq 0 ]; then
        prog "$taskpercent" ""
    fi

done

echo ""
