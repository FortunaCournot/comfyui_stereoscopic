
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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATIC_PYTHON_PATH="${SCRIPT_DIR}/../../../../python_embeded/python"

cd /c/Users/User/Videos/Chroma

KEYER_MODE="${KEYER_MODE:-opencv-hls}"

# HLS-Keyer: Mittelpunkt, Toleranz und weicher Uebergang je Kanal.
KEY_HUE_DEG="${KEY_HUE_DEG:-120}"
KEY_HUE_TOLERANCE_DEG="${KEY_HUE_TOLERANCE_DEG:-20}"
KEY_HUE_FALLOFF_DEG="${KEY_HUE_FALLOFF_DEG:-10}"
KEY_LIGHTNESS_PCT="${KEY_LIGHTNESS_PCT:-45}"
KEY_LIGHTNESS_TOLERANCE_PCT="${KEY_LIGHTNESS_TOLERANCE_PCT:-35}"
KEY_LIGHTNESS_FALLOFF_PCT="${KEY_LIGHTNESS_FALLOFF_PCT:-12}"
KEY_SATURATION_PCT="${KEY_SATURATION_PCT:-75}"
KEY_SATURATION_TOLERANCE_PCT="${KEY_SATURATION_TOLERANCE_PCT:-30}"
KEY_SATURATION_FALLOFF_PCT="${KEY_SATURATION_FALLOFF_PCT:-12}"
KEY_ALPHA_GAMMA="${KEY_ALPHA_GAMMA:-1.15}"
KEY_ALPHA_BLUR_SIGMA="${KEY_ALPHA_BLUR_SIGMA:-1.2}"
KEY_PROCESS_SCALE="${KEY_PROCESS_SCALE:-0.25}"

# FFmpeg-Fallback: schneller, aber weniger selektiv als der HLS-Keyer.
FFMPEG_KEY_COLOR="${FFMPEG_KEY_COLOR:-0x00FF00}"
FFMPEG_KEY_SIMILARITY="${FFMPEG_KEY_SIMILARITY:-0.26}"
FFMPEG_KEY_BLEND="${FFMPEG_KEY_BLEND:-0.04}"
FFMPEG_KEY_PREBLUR="${FFMPEG_KEY_PREBLUR:-1.0}"

find_python() {
	if [ -x "$STATIC_PYTHON_PATH" ]; then
		PYTHON_CMD=("$STATIC_PYTHON_PATH")
		return 0
	fi
	if [ -x "${STATIC_PYTHON_PATH}.exe" ]; then
		PYTHON_CMD=("${STATIC_PYTHON_PATH}.exe")
		return 0
	fi
	echo "[ERROR] Statischer Python-Pfad nicht gefunden: $STATIC_PYTHON_PATH" >&2
	return 1
}

build_alpha_with_hls_keyer() {
	find_python || {
		echo "[ERROR] Kein Python-Interpreter fuer den HLS-Keyer gefunden." >&2
		return 1
	}

	export KEY_HUE_DEG KEY_HUE_TOLERANCE_DEG KEY_HUE_FALLOFF_DEG
	export KEY_LIGHTNESS_PCT KEY_LIGHTNESS_TOLERANCE_PCT KEY_LIGHTNESS_FALLOFF_PCT
	export KEY_SATURATION_PCT KEY_SATURATION_TOLERANCE_PCT KEY_SATURATION_FALLOFF_PCT
	export KEY_ALPHA_GAMMA KEY_ALPHA_BLUR_SIGMA KEY_PROCESS_SCALE

	"${PYTHON_CMD[@]}" - <<'PY'
import math
import os
import sys
import time

try:
	import cv2
	import numpy as np
except Exception as exc:
	print(f"[ERROR] Der HLS-Keyer benoetigt opencv-python und numpy: {exc}", file=sys.stderr)
	sys.exit(1)


def env_float(name: str, default: float) -> float:
	value = os.environ.get(name)
	if value is None or value == "":
		return default
	return float(value)


def smooth_membership(distance, tolerance, falloff):
	if falloff <= 0:
		return (distance <= tolerance).astype(np.float32)
	edge = np.clip((distance - tolerance) / falloff, 0.0, 1.0)
	return 1.0 - (edge * edge * (3.0 - 2.0 * edge))


def format_duration(seconds: float) -> str:
	seconds = max(0, int(round(seconds)))
	hours, remainder = divmod(seconds, 3600)
	minutes, secs = divmod(remainder, 60)
	if hours > 0:
		return f"{hours:02d}:{minutes:02d}:{secs:02d}"
	return f"{minutes:02d}:{secs:02d}"


def render_progress_bar(progress: float, width: int = 28) -> str:
	progress = max(0.0, min(1.0, progress))
	filled = int(round(progress * width))
	filled = max(0, min(width, filled))
	return "#" * filled + "-" * (width - filled)


last_line_length = 0


def print_progress_line(message: str, final: bool = False) -> None:
	global last_line_length
	padded_message = message
	if len(padded_message) < last_line_length:
		padded_message = padded_message + (" " * (last_line_length - len(padded_message)))
	last_line_length = len(message)
	end = "\n" if final else ""
	print(f"\r{padded_message}", file=sys.stderr, end=end, flush=True)


h_center = env_float("KEY_HUE_DEG", 120.0) / 2.0
h_tolerance = env_float("KEY_HUE_TOLERANCE_DEG", 20.0) / 2.0
h_falloff = env_float("KEY_HUE_FALLOFF_DEG", 10.0) / 2.0
l_center = env_float("KEY_LIGHTNESS_PCT", 45.0) * 255.0 / 100.0
l_tolerance = env_float("KEY_LIGHTNESS_TOLERANCE_PCT", 35.0) * 255.0 / 100.0
l_falloff = env_float("KEY_LIGHTNESS_FALLOFF_PCT", 12.0) * 255.0 / 100.0
s_center = env_float("KEY_SATURATION_PCT", 75.0) * 255.0 / 100.0
s_tolerance = env_float("KEY_SATURATION_TOLERANCE_PCT", 30.0) * 255.0 / 100.0
s_falloff = env_float("KEY_SATURATION_FALLOFF_PCT", 12.0) * 255.0 / 100.0
alpha_gamma = max(env_float("KEY_ALPHA_GAMMA", 1.15), 0.01)
alpha_blur_sigma = max(env_float("KEY_ALPHA_BLUR_SIGMA", 1.2), 0.0)
process_scale = min(max(env_float("KEY_PROCESS_SCALE", 0.30), 0.05), 1.0)

cap = cv2.VideoCapture("input.mp4")
if not cap.isOpened():
	print("[ERROR] input.mp4 konnte nicht geoeffnet werden.", file=sys.stderr)
	sys.exit(1)

fps = cap.get(cv2.CAP_PROP_FPS) or 0.0
if fps <= 0:
	fps = 25.0

width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
process_width = max(1, int(round(width * process_scale)))
process_height = max(1, int(round(height * process_scale)))

fourcc = cv2.VideoWriter_fourcc(*"mp4v")
writer = cv2.VideoWriter("alpha.mp4", fourcc, fps, (width, height), True)
if not writer.isOpened():
	print("[ERROR] alpha.mp4 konnte nicht geschrieben werden.", file=sys.stderr)
	sys.exit(1)

kernel_size = max(3, int(math.ceil(alpha_blur_sigma * 4)) | 1) if alpha_blur_sigma > 0 else 0
processed_frames = 0
progress_step = max(1, total_frames // 100) if total_frames > 0 else max(1, int(round(fps)))
last_progress_percent = -1
last_reported_frame = 0
start_time = time.monotonic()

if total_frames > 0:
	print(f"[INFO] HLS-Keyer verarbeitet {total_frames} Frames...", file=sys.stderr)
else:
	print("[INFO] HLS-Keyer verarbeitet Frames... Gesamtzahl unbekannt.", file=sys.stderr)

if process_scale < 0.999:
	print(
		f"[INFO] HLS-Keyer rechnet auf {process_width}x{process_height} ({process_scale:.2f}x) und skaliert die Matte auf {width}x{height} hoch.",
		file=sys.stderr,
	)

while True:
	ok, frame = cap.read()
	if not ok:
		break

	processed_frames += 1
	work_frame = frame
	if process_width != width or process_height != height:
		work_frame = cv2.resize(frame, (process_width, process_height), interpolation=cv2.INTER_AREA)

	hls = cv2.cvtColor(work_frame, cv2.COLOR_BGR2HLS).astype(np.float32)
	hue = hls[:, :, 0]
	lightness = hls[:, :, 1]
	saturation = hls[:, :, 2]

	hue_distance = np.minimum(np.abs(hue - h_center), 180.0 - np.abs(hue - h_center))
	lightness_distance = np.abs(lightness - l_center)
	saturation_distance = np.abs(saturation - s_center)

	hue_weight = smooth_membership(hue_distance, h_tolerance, h_falloff)
	lightness_weight = smooth_membership(lightness_distance, l_tolerance, l_falloff)
	saturation_weight = smooth_membership(saturation_distance, s_tolerance, s_falloff)

	keyed_background = hue_weight * lightness_weight * saturation_weight
	alpha = 1.0 - keyed_background
	alpha = np.clip(alpha, 0.0, 1.0)
	alpha = np.power(alpha, alpha_gamma)

	alpha_u8 = np.clip(alpha * 255.0, 0.0, 255.0).astype(np.uint8)
	if kernel_size > 0:
		alpha_u8 = cv2.GaussianBlur(alpha_u8, (kernel_size, kernel_size), alpha_blur_sigma)
	if process_width != width or process_height != height:
		alpha_u8 = cv2.resize(alpha_u8, (width, height), interpolation=cv2.INTER_LINEAR)

	writer.write(cv2.cvtColor(alpha_u8, cv2.COLOR_GRAY2BGR))

	if processed_frames == 1 or processed_frames % progress_step == 0:
		if total_frames > 0:
			progress_percent = min(100, int((processed_frames * 100) / total_frames))
			if progress_percent != last_progress_percent:
				elapsed = time.monotonic() - start_time
				eta_seconds = (elapsed / processed_frames) * (total_frames - processed_frames) if processed_frames > 0 else 0.0
				progress_ratio = processed_frames / total_frames
				bar = render_progress_bar(progress_ratio)
				print_progress_line(
					f"[PROGRESS] HLS-Keyer: [{bar}] {progress_percent:3d}% ({processed_frames}/{total_frames} Frames, ETA {format_duration(eta_seconds)}, Laufzeit {format_duration(elapsed)})"
				)
				last_progress_percent = progress_percent
		else:
			if processed_frames - last_reported_frame >= progress_step:
				elapsed = time.monotonic() - start_time
				phase = (processed_frames // progress_step) % 28
				bar = ["-"] * 28
				bar[phase] = "#"
				print_progress_line(
					f"[PROGRESS] HLS-Keyer: [{''.join(bar)}] ???% ({processed_frames} Frames, Laufzeit {format_duration(elapsed)})"
				)
				last_reported_frame = processed_frames

cap.release()
writer.release()
total_elapsed = time.monotonic() - start_time
if total_frames > 0:
	bar = render_progress_bar(1.0)
	print_progress_line(
		f"[PROGRESS] HLS-Keyer: [{bar}] 100% ({processed_frames}/{total_frames} Frames, Laufzeit {format_duration(total_elapsed)})",
		final=True,
	)
else:
	bar = "#" * 28
	print_progress_line(
		f"[PROGRESS] HLS-Keyer: [{bar}] 100% ({processed_frames} Frames, Laufzeit {format_duration(total_elapsed)})",
		final=True,
	)
PY
}

build_alpha_with_ffmpeg_chromakey() {
	ffmpeg -y -i input.mp4 -vf "gblur=sigma=${FFMPEG_KEY_PREBLUR},chromakey=${FFMPEG_KEY_COLOR}:${FFMPEG_KEY_SIMILARITY}:${FFMPEG_KEY_BLEND},format=yuva420p,alphaextract,format=yuv420p" -c:v libx264 -crf 18 alpha.mp4
}

echo "[STEP] Erzeuge alpha.mp4 mit KEYER_MODE=${KEYER_MODE}"
case "$KEYER_MODE" in
	opencv-hls)
		build_alpha_with_hls_keyer || exit 1
		;;
	ffmpeg-chromakey)
		build_alpha_with_ffmpeg_chromakey || exit 1
		;;
	*)
		echo "[ERROR] Unbekannter KEYER_MODE: $KEYER_MODE" >&2
		echo "[ERROR] Gueltige Werte: opencv-hls, ffmpeg-chromakey" >&2
		exit 1
		;;
esac


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

