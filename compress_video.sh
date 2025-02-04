#!/bin/bash

#=============================================================================
#
#    FILE: compress_video.sh
#
#    USAGE:
#       compress_video.sh [-e EXTENSION] [-s SOURCE] [-d DESTINATION] [-b BITRATE] [-a AUDIO_OPTIONS]
#                          -e EXTENSION      Specify the file extension to filter on source. Eg: -e mkv'
#                          -s SOURCE         Specify the source folder to compress from. Eg: /mnt/myvideos'
#                          -d DESTINATION    Specify the destination folder to compress to. Note that files will not be overwritten. Eg: /mnt/converted'
#                          -b BITRATE        Specify the video bitrate quality in kbps. Eg: -b 2000'
#                          -a AUDIO_OPTIONS  Specify audio re-encoding options. Eg: -a "192 6ch" for AAC 5.1 at 192 kbps'
#
#    DESCRIPTION: This script compresses videos to x265 (HEVC) from one location to another recursively without overwriting the destination.
#                 It also allows re-encoding all audio streams to a specified format (e.g., AAC 5.1 at 192 kbps).
#
#          BUGS: Report bugs to Dead Laurin via Github:
#                https://github.com/DeadLaurin/CompressVideo/issues
#
#=============================================================================

function usage()
{
    echo "Usage: $(basename $0) [-e EXTENSION] [-s SOURCE] [-d DESTINATION] [-b BITRATE] [-a AUDIO_OPTIONS]" 2>&1
    echo '    -e EXTENSION      Specify the file extension to filter on source. Eg: -e mkv'
    echo '    -s SOURCE         Specify the source folder to compress from. Eg: /mnt/myvideos'
    echo '    -d DESTINATION    Specify the destination folder to compress to. Note that files will not be overwritten. Eg: /mnt/converted'
    echo '    -b BITRATE        Specify the video bitrate quality in kbps. Eg: -b 2000'
    echo '    -a AUDIO_OPTIONS  Specify audio re-encoding options. Eg: -a "192 6ch" for AAC 5.1 at 192 kbps'
    exit 1
}

unset -v extension
unset -v source
unset -v destination
unset -v bitrate
unset -v audio_options

if [[ ${#} -eq 0 ]]; then
    usage
fi

function draw_line()
{
    local width=$(tput cols)
    for (( x = 0; x < "$width"; ++x )); do echo -e -n "\e[1;32m-"; done
    echo -e "\e[0m"
}

optstring=":e:s:d:b:a:"

bitrate=2000

while getopts ${optstring} arg; do
  case "${arg}" in
    e)
        extension=${OPTARG}
        ;;
    s)
        source=$OPTARG
        ;;
    d)
        destination=$OPTARG
        ;;
    b)
        bitrate=$OPTARG
        ;;
    a)
        audio_options=$OPTARG
        ;;
    :)
        echo "$0: Must supply an argument to -$OPTARG." >&2
        exit 1
        ;;
    ?)
        echo "Invalid option: -${OPTARG}."
        exit 2
        ;;
  esac
done

if [ -z "$extension" ]; then
    echo "Extension argument is required!"
    usage
fi
if [ -z "$source" ]; then
    echo "Source argument is required!"
    usage
fi
if [ -z "$destination" ]; then
    echo "Destination argument is required!"
    usage
fi

shopt -s globstar

for i in "$source"/**/*."$extension"; do
    relative_path="${i#$source}"

    if [[ -f "$destination$relative_path" ]]; then
        echo -e "\e[1;33mDestination file exists: $destination$relative_path"
        continue
    fi

    codex=$(ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$i")

    if [ "${codex//$'\r'/}" = "hevc" ]; then
        echo -e "\e[1;33mSource file is already HEVC encoded : $i"
        continue
    fi

    width=$(ffprobe -loglevel error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$i")
    height=$(ffprobe -loglevel error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$i")

    draw_line
    frames=$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$i")
    echo -e "Compressing \e[1;32m""$i""\e[0m with size \e[1;31m" $width "x" $height "\e[0m and with \e[1;31m" $frames "\e[0m frames to file \e[1;34m""$destination""""$relative_path""\e[0m"
    draw_line

    mkdir -p "$destination""$(dirname "$relative_path")"

    ffmpeg_opts="-c:v libx265 -vtag hvc1 -b:v ${bitrate}k"

    if [ -n "$audio_options" ]; then
        audio_bitrate=$(echo "$audio_options" | awk '{print $1}')
        audio_channels=$(echo "$audio_options" | awk '{print $2}' | sed 's/ch//')

        if ! [[ "$audio_channels" =~ ^[0-9]+$ ]]; then
            echo "Invalid audio channels: $audio_channels"
            exit 1
        fi

        ffmpeg_audio_opts="-c:a aac -b:a ${audio_bitrate}k -ac ${audio_channels}"
    else
        ffmpeg_audio_opts="-c:a copy"
    fi

    nice ffmpeg -stats -hide_banner -loglevel error -i "$i" \
        ${ffmpeg_opts} \
        -map 0:v -map 0:a -map 0:s? \
        ${ffmpeg_audio_opts} \
        -c:s copy \
        "$destination$relative_path"
done
