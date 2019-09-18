#!/bin/bash
	
DEFAULT_LANGUAGE="eng"
DELETE_SOURCE_FILES=1 # Set to 0 to disable deleting of the original media

################################################################################################

SOURCE_FILE="$1"

uauma="no"
fName=$(basename -- "$SOURCE_FILE")
fExt="${fName##*.}"
fExtLower=`echo "$fExt" | awk '{print tolower($0)}'`
filename="${SOURCE_FILE%.*}"
vcodex=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")
acodex=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")
scodex=$(ffprobe -v error -select_streams s:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${SOURCE_FILE}")
logFname="TVlog.txt"
condencedCheck="[DONE]-$fName"
while IFS= read -r line; do
if [[ $line == $condencedCheck ]] ; then
        uamaua="yes"
fi
done < "$logFname"


if [[ ($vcodex == "h264") && ($acodex == "aac") && ($scodex == "") || ($uauma == "yes") ]]; then

 echo ""   
 echo "--------------------------------------------------------"   
 echo "Since this file is Done It Will be Skipped "
 echo "--------------------------------------------------------"
 echo ""   
 exit 0

elif [[ ($vcodex == "h264") && ($acodex == "aac") && ($scodex != "") ]]; then


    echo ""   
    echo "--------------------------------------------------------"   
    echo "File Containes SUBS they Will be stripped "
    echo "--------------------------------------------------------"
    echo ""   
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
echo "[DONE]-$fName" >> /nas/CONVERT/TVlog.txt
        exit 0
    else
        exit $exitCode
    fi



elif [[ ($vcodex == "h264") && ($acodex != "aac")]]; then


    echo ""   
echo "--------------------------------------------------------"    
echo "File Video is h264 but the AUDIO will be encoded to AAC"
    echo "--------------------------------------------------------" 
echo ""   
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
echo "[DONE]-$fName" >> /nas/CONVERT/TVlog.txt
        exit 0
    else
        exit $exitCode
    fi


elif [[ ($vcodex != "h264") ]]; then

echo ""   
    echo "----------------------------------------------------"    
echo "File requires FULL encoding *THIS WILL TAKE A WHILE*"
    echo "----------------------------------------------------"
echo ""   

#Change this to ur full encoding prefs

ffmpeg -hide_banner -i "$SOURCE_FILE" -pix_fmt yuv420p -deinterlace -bsf:v "filter_units=remove_types=6" -c:v libx264 -bf 2 -coder 1 -threads 0 -preset medium -profile:v high -g 15 -tune film -acodec libfdk_aac  -ac 2 -movflags +faststart -sn -f mp4 -y "${filename}-Converting.mp4"
 
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
echo "[DONE]-$fName" >> /nas/CONVERT/TVlog.txt
        exit 0
    else
        exit $exitCode
    fi

fi

