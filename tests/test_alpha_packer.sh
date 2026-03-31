
#!/bin/bash
# test_alpha_packer.sh
# Erzeugt ein maskiertes Alpha-Video im FullSBS-Format aus input.mp4 und alpha.mp4
# Arbeitsverzeichnis: /c/Users/User/Videos/Chroma
# Ergebnis: output_ALPHA.mp4

# Hinweis: Wenn keine portable Bash im Projekt enthalten ist, kann Git Bash aus C:\Program Files\Git\git-bash.exe verwendet werden:
# Beispiel-Aufruf:
#   "C:/Program Files/Git/git-bash.exe" tests/test_alpha_packer.sh

set -e
set -x

cd /c/Users/User/Videos/Chroma

#0. Vorbereitung: Erstelle alpha.mp4
ffmpeg -y -i input.mp4 -vf "chromakey=0x00FF00:0.30:0.0,format=yuva420p,alphaextract,format=yuv420p" -c:v libx264 -crf 18 alpha.mp4


# 1. Variablen aus input.mp4 ermitteln
echo "[STEP] Extrahiere Frame aus input.mp4"
ffmpeg -y -i input.mp4 -vf "scale=iw:ih" -frames:v 1 tmp_input.png
echo "[STEP] Ermittle Dimensionen"
width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 tmp_input.png)
height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 tmp_input.png)
qwidth=$((width / 2))
qheight=$height
radius=$((height / 4))
radius_x=$(awk "BEGIN {printf \"%.0f\", $radius * $width / $height / 2}")
rm tmp_input.png
echo "width: $width; height: $height; qwidth: $qwidth; qheight: $qheight; radius: $radius; radius_x: $radius_x"


rm -f left.mp4 right.mp4 mask.png left_masked.mov right_masked.mov mask.avi alphalayer.mov output_ALPHA.mp4

echo "[STEP] Croppe linkes Video aus alpha.mp4"
ffmpeg -y -i alpha.mp4 -vf "crop=${qwidth}:${height}:0:0" -c:v libx265 -pix_fmt yuv420p -profile:v main -movflags +faststart left.mp4 || exit 1

echo "[STEP] Croppe rechtes Video aus alpha.mp4"
ffmpeg -y -i alpha.mp4 -vf "crop=${qwidth}:${height}:${qwidth}:0" -c:v libx265 -pix_fmt yuv420p -profile:v main -movflags +faststart right.mp4 || exit 1

echo "[STEP] Erzeuge Masken-Video (Graustufen-Maske mit weißem Kreis)"
# ffmpeg -y -f lavfi -i "nullsrc=size=${qwidth}x${height}:duration=5:rate=25" -vf "geq=lum=255*lte((X-${radius})^2+(Y-${height}/2)^2\,${radius}*${radius}),format=gray" -c:v libx265 -pix_fmt yuv420p -profile:v main -movflags +faststart mask.mp4 || exit 1

# [STEP] Erzeuge Masken-Bild (Graustufen, PNG)
echo "[STEP] Erzeuge Masken-Bild (Graustufen, PNG)"
#ffmpeg -y -f lavfi -i "nullsrc=size=${qwidth}x${height}" -vf "geq=lum=255*lte((X-${radius})^2+(Y-${height}/2)^2\,${radius}*${radius}),format=gray" -frames:v 1 mask.png || exit 1
ffmpeg -y -f lavfi -i "nullsrc=size=${qwidth}x${height}" -vf "geq=lum=255*lte(((X-${qwidth}/2)^2)/(${radius_x}^2)+((Y-${height}/2)^2)/(${radius}^2)\,1),format=gray" -frames:v 1 mask.png || exit 1

echo "[STEP] Konvertiere Maske nach AVI (gray, ffv1)"

# Standard: ffv1 (gray)
#ffmpeg -y -i mask.mp4 -c:v ffv1 -pix_fmt gray mask.avi || exit 1

# Alternative: rawvideo (gray) für mplayer-Kompatibilität
#ffmpeg -y -i mask.mp4 -c:v rawvideo -pix_fmt gray mask_raw.avi || exit 1

echo "[STEP] Alphamerge links"
ffmpeg -y -i left.mp4 -i mask.png -filter_complex "[0][1]alphamerge" -c:v png -pix_fmt rgba -auto-alt-ref 0 left_masked.mov || exit 1

echo "[STEP] Alphamerge rechts"
ffmpeg -y -i right.mp4 -i mask.png -filter_complex "[0][1]alphamerge" -c:v png -pix_fmt rgba -auto-alt-ref 0 right_masked.mov || exit 1

echo "[STEP] Hstack zu FullSBS"
ffmpeg -y -i left_masked.mov -i right_masked.mov -filter_complex "hstack=inputs=2" -c:v png -pix_fmt rgba -auto-alt-ref 0 alphalayer.mov || exit 1

echo "[STEP] Überlagere alphalayer.mov auf input.mp4"
ffmpeg -y -i input.mp4 -i alphalayer.mov -filter_complex "\
[1:v]crop=iw/4:ih/2:0*iw/4:0*ih/2,scale=iw*0.8:ih*0.8[ov0]; \
[1:v]crop=iw/4:ih/2:1*iw/4:0*ih/2,scale=iw*0.8:ih*0.8[ov1]; \
[1:v]crop=iw/4:ih/2:2*iw/4:0*ih/2,scale=iw*0.8:ih*0.8[ov2]; \
[1:v]crop=iw/4:ih/2:3*iw/4:0*ih/2,scale=iw*0.8:ih*0.8[ov3]; \
[1:v]crop=iw/4:ih/2:0*iw/4:1*ih/2,scale=iw*0.8:ih*0.8[ov4]; \
[1:v]crop=iw/4:ih/2:1*iw/4:1*ih/2,scale=iw*0.8:ih*0.8[ov5]; \
[1:v]crop=iw/4:ih/2:2*iw/4:1*ih/2,scale=iw*0.8:ih*0.8[ov6]; \
[1:v]crop=iw/4:ih/2:3*iw/4:1*ih/2,scale=iw*0.8:ih*0.8[ov7]; \
[0:v][ov0]overlay=x=(0*W/4)+0.3*W:y=H-overlay_h[tmp1]; \
[tmp1][ov1]overlay=x=(1*W/4)-0.25*W:y=H-overlay_h[tmp2]; \
[tmp2][ov2]overlay=x=(2*W/4)+0.3*W:y=H-overlay_h[tmp3]; \
[tmp3][ov3]overlay=x=(3*W/4)-0.25*W:y=H-overlay_h[tmp4]; \
[tmp4][ov4]overlay=x=(0*W/4)+0.3*W:y=0[tmp5]; \
[tmp5][ov5]overlay=x=(1*W/4)-0.25*W:y=0[tmp6]; \
[tmp6][ov6]overlay=x=(2*W/4)+0.3*W:y=0[tmp7]; \
[tmp7][ov7]overlay=x=(3*W/4)-0.25*W:y=0" \
-c:v libx265 -pix_fmt yuv420p output_ALPHA.mp4 || exit 1

echo "[STEP] Aufräumen: Lösche Zwischendateien"
rm -f left.mp4 right.mp4 mask.png left_masked.mov right_masked.mov mask.avi alphalayer.mov

echo "Fertig! output_ALPHA.mp4 wurde erzeugt."

