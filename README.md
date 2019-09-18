# Batch-Convert-FFmpeg-Multi-Option
Converts Any file to h264,AAC for ideal direct play on Plex

Hey Guys so this is a script ive been working on for a bit, it batch checks files in a particular folder if they meet my requirements of H264 VCodec AAC ACodec and no burn-in subs 

I run it on an Odroid N2 which at time of posting hasnt got HW GPU encoding so i used x264 libz, i will update once they become available.

As such instead of pushing all through a "standard template" i implimented IF functions to only fully encode files that fail both video and audio codex.

as such 

if Vcodex is equal to h264 <br>
  then check audio <br>
    if Acodex equal to AAC <br>
      then check for subs <br>
        if SubCodex is present  <br>
        remove subs copy codex<br>
        else move on <br>
    esle encode audio<br>
 else full encode <br>
 
 
 NOTE:// This Requires both files 
