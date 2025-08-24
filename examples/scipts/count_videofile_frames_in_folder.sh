#!/bin/bash

if test $# -ne 1; then echo "Usage: $0 videofolder"; exit 1; fi

cd $1
FILES=`find . -maxdepth 1 -name "*.mp4"`

for f in $FILES; do
    ffprobe -i $f -show_streams -hide_banner >out.txt 2>/dev/null
    frames=`grep -m 1 nb_frames out.txt`
    rm out.txt
    echo "$frames""	""${f##*/}"
done
