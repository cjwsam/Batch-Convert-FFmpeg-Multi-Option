#!/bin/bash
#
# Adjust as needed.
SEARCH_LOCATION="/nas/TV"
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

for filename in "${process_movies[@]}"; do :

    count=$((count + 1))
    taskpercent=$((count*100/total))
    shortName="${filename##*/}"

    prog "$taskpercent" $shortName...
 /nas/CONVERT/ConvertAutomated.sh "$filename"
    exitCode=$?

    if [ $exitCode -eq 0 ]; then

        prog "$taskpercent" ""

    fi

done

echo ""

 

