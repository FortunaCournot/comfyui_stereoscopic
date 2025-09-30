#!/bin/bash

if test $# -ne 2; then echo "Usage: $0 threshold file"; exit 1; fi

ffmpeg.exe -hide_banner -y -i $2 -filter:v "select='gt(scene,$1)',showinfo" -f null - 2>&1 | grep showinfo | grep pts_time:[0-9.]* -o | grep [0-9.]* -o
