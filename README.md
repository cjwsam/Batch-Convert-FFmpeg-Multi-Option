# Batch-Convert-FFmpeg-Multi-Option
Converts Any file to h264,AAC for ideal direct play on Plex

Hey Guys so this is a script ive been working on for a bit, it batch checks files in a particular folder if they meet my requirements of H264 VCodec AAC ACodec and no burn-in subs 

I run it on an Odroid N2 which at time of posting hasnt got HW GPU encoding so i used x264 libz, i will update once they become available.

As such instead of pushing all through a "standard template" i implimented IF functions to only fully encode files that fail both video and audio codex.

as such 

if Vcodex is equal to h264 
  then check audio 
    if Acodex equal to AAC 
      then check for subs 
        if SubCodex is present  
        remove subs copy codex
        else move on 
    esle encode audio
 else full encode 
 
 
 NOTE:// This Requires both files 
