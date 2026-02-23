import numpy as np
import cv2
import glob
import os
import time


def cap_image(img, max_dim=8192):
    h, w = img.shape[:2]
    m = max(h, w)
    if m <= max_dim:
        return img
    scale = float(max_dim) / float(m)
    new_w = max(1, int(round(w * scale)))
    new_h = max(1, int(round(h * scale)))
    return cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)

def make_grid_image():
    width, height = 3840, 2196  # 16:9
    spacing = 512
    bg = np.full((height, width, 3), 255, np.uint8)
    cx, cy = width // 2, height // 2
    # Hauptachsen
    cv2.line(bg, (cx, 0), (cx, height), (0,0,0), 5)
    cv2.line(bg, (0, cy), (width, cy), (0,0,0), 5)
    # Gitterlinien
    for dx in range(spacing, width//2+1, spacing):
        for sign in [-1, 1]:
            x = cx + sign*dx
            if 0 <= x < width:
                cv2.line(bg, (x, 0), (x, height), (128,128,128), 2)
    for dy in range(spacing, height//2+1, spacing):
        for sign in [-1, 1]:
            y = cy + sign*dy
            if 0 <= y < height:
                cv2.line(bg, (0, y), (width, y), (128,128,128), 2)
    # Koordinatenpunkte und Labels
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 1.2
    font_thick = 2
    dot_radius = 12
    for gx in range(-(cx//spacing), (width-cx)//spacing+1):
        px = cx + gx*spacing
        if not (0 <= px < width): continue
        for gy in range(-(cy//spacing), (height-cy)//spacing+1):
            py = cy + gy*spacing
            if not (0 <= py < height): continue
            color = (0,128,0) if (gx,gy)==(0,0) else (0,0,255)
            cv2.circle(bg, (px, py), dot_radius, color, -1)
            label = f"({gx},{gy})"
            tx, ty = px+18, py-18
            cv2.putText(bg, label, (tx, ty), font, font_scale, (0,0,0), font_thick, cv2.LINE_AA)
    return bg


def cosinus_fisheye_transform(src, deg_per_step=15, output_scale=1.0, debug_name=None):
    import math
    h, w = src.shape[:2]
    aspect = w / h
    # Make mapping resolution-independent:
    # Interpret the incoming `deg_per_step` as the reference value for a
    # reference height of 2196 px. Scale both `spacing` and `deg_per_step`
    # proportionally to the current image height so that results match the
    # original behavior at h==2196 but otherwise are resolution-independent.
    ref_h = 2196.0
    ref_spacing = 512.0
    ref_deg = float(deg_per_step)
    scale = float(h) / ref_h
    effective_spacing = ref_spacing * scale
    effective_deg_per_step = ref_deg * scale

    # Portrait supersampling: if the image is taller than wide (aspect < 1)
    # perform an internal upscale to increase horizontal sampling density,
    # then downscale the mapped result back to the original size. This
    # preserves geometry while improving remap quality for narrow images.
    supersample = 1
    w_up = w
    h_up = h
    if aspect < 1.0:
        candidate = int(round(1.0 / aspect))
        supersample = max(2, min(4, candidate))
        w_up = int(round(w * supersample))
        h_up = int(round(h * supersample))

    # enforce hard maximum on any working dimension
    MAX_DIM = 8192
    max_up = max(w_up, h_up)
    downscale_to_max = 1.0
    if max_up > MAX_DIM:
        downscale_to_max = float(MAX_DIM) / float(max_up)
        w_work = max(1, int(round(w_up * downscale_to_max)))
        h_work = max(1, int(round(h_up * downscale_to_max)))
    else:
        w_work = w_up
        h_work = h_up

    # choose interpolation depending on whether we're up- or downscaling
    if w_work != w or h_work != h:
        interp = cv2.INTER_CUBIC if (w_work > w or h_work > h) else cv2.INTER_AREA
        src_work = cv2.resize(src, (w_work, h_work), interpolation=interp)
    else:
        src_work = src
    # operate on working image (possibly supersampled/rescaled)
    h_work, w_work = src_work.shape[:2]
    dst_work = np.full_like(src_work, 255)
    cx = w_work // 2
    cy = h_work // 2
    yy, xx = np.indices((h_work, w_work))

    # recompute effective spacing/deg for the working resolution so mapping
    # stays consistent with the 2196px reference
    scale_work = float(h_work) / ref_h
    effective_spacing_work = ref_spacing * scale_work
    effective_deg_per_step_work = ref_deg * scale_work

    gx = (xx - cx) / effective_spacing_work
    gy = (yy - cy) / effective_spacing_work
    angle_x = gx * effective_deg_per_step_work
    angle_y = gy * effective_deg_per_step_work
    fix_angle = 4 * effective_deg_per_step_work
    # Zoomfaktor für Benutzer
    user_zoom = 1.0  # <--- Hier anpassen für mehr/weniger Zoom
    # horizontales Stretching proportional zur Abweichung vom 16:9-Referenz.
    # (16:9)/aspect — das war die zuvor funktionierende Formel.
    aspect = w / h
    aspect_169 = 16/9
    horizontal_stretch = aspect_169 / aspect
    # Horizontales Sichtfeld für 4:3 und 16:9 identisch behandeln
    zoom_x = (1.0 / abs(np.cos(np.deg2rad(fix_angle)))) * user_zoom
    zoom_y = (1.0 / abs(np.cos(np.deg2rad(fix_angle)))) * (16/9) * user_zoom
    # horizontal_stretch wirkt nur auf die horizontale Cosinus-Komponente
    src_x = cx + (xx - cx) * zoom_x * np.abs(np.cos(np.deg2rad(angle_x))) * horizontal_stretch
    src_y = cy + (yy - cy) * zoom_y * np.abs(np.cos(np.deg2rad(angle_y)))
    map_x = src_x.astype(np.float32)
    map_y = src_y.astype(np.float32)
    dst_work = cv2.remap(src_work, map_x, map_y, interpolation=cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=0)

    # resize mapped result back to original requested size if necessary
    if (w_work, h_work) != (w, h):
        # choose good resampling for the final step
        final_interp = cv2.INTER_AREA if (w < w_work or h < h_work) else cv2.INTER_CUBIC
        dst = cv2.resize(dst_work, (w, h), interpolation=final_interp)
        try:
            gx_res = cv2.resize(gx.astype(np.float32), (w, h), interpolation=cv2.INTER_LINEAR)
            gy_res = cv2.resize(gy.astype(np.float32), (w, h), interpolation=cv2.INTER_LINEAR)
        except Exception:
            gx_res, gy_res = gx, gy
        gx, gy = gx_res, gy_res
    else:
        dst = dst_work
    # optionally save pre-resize fisheye for debugging
    if debug_name is not None:
        try:
            pre_name = f"{debug_name}_pre_{dst.shape[1]}x{dst.shape[0]}.png"
            cv2.imwrite(pre_name, dst)
        except Exception:
            pass
    if output_scale != 1.0:
        new_w = int(round(dst.shape[1] * output_scale))
        new_h = int(round(dst.shape[0] * output_scale))
        dst = cv2.resize(dst, (new_w, new_h), interpolation=cv2.INTER_CUBIC)
    # optionally save post-resize fisheye for debugging
    if debug_name is not None:
        try:
            post_name = f"{debug_name}_post_{dst.shape[1]}x{dst.shape[0]}.png"
            cv2.imwrite(post_name, dst)
        except Exception:
            pass

    return dst, gx, gy

height916 = 2196
width916 = int(height916 * 9 / 16)
spacing916 = 512
def make_grid_image_916():
    bg = np.full((height916, width916, 3), 255, np.uint8)
    cx, cy = width916 // 2, height916 // 2
    # Hauptachsen
    cv2.line(bg, (cx, 0), (cx, height916), (0,0,0), 6)
    cv2.line(bg, (0, cy), (width916, cy), (0,0,0), 6)
    # Gitterlinien
    for dx in range(spacing916, width916//2+1, spacing916):
        for sign in [-1, 1]:
            x = cx + sign*dx
            if 0 <= x < width916:
                cv2.line(bg, (x, 0), (x, height916), (128,128,128), 2)
    for dy in range(spacing916, height916//2+1, spacing916):
        for sign in [-1, 1]:
            y = cy + sign*dy
            if 0 <= y < height916:
                cv2.line(bg, (0, y), (width916, y), (128,128,128), 2)
    # Koordinatenpunkte und Labels
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 1.2
    font_thick = 2
    dot_radius = 12
    for gx in range(-(cx//spacing916), (width916-cx)//spacing916+1):
        px = cx + gx*spacing916
        if not (0 <= px < width916): continue
        for gy in range(-(cy//spacing916), (height916-cy)//spacing916+1):
            py = cy + gy*spacing916
            if not (0 <= py < height916): continue
            color = (0,128,0) if (gx,gy)==(0,0) else (0,0,255)
            cv2.circle(bg, (px, py), dot_radius, color, -1)
            label = f"({gx},{gy})"
            tx, ty = px+18, py-18
            cv2.putText(bg, label, (tx, ty), font, font_scale, (0,0,0), font_thick, cv2.LINE_AA)
    return bg

if __name__ == "__main__":
    # Alte Testbilder und Debug-Images im aktuellen Verzeichnis löschen
    # remove previous generated images (testgrid_, gridbase_, debug_*)
    for pattern in [
        "testgrid_*_RANDOM*.png",
        "gridbase_*_RANDOM*.png",
        "gridbase_single_*_RANDOM*.png",
        "debug_*.png",
        "debug_*_pre_*.png",
        "debug_*_post_*.png",
        "testbear_*_RANDOM*.png",
        "testbear_native_*_RANDOM*.png",
    ]:
        for f in glob.glob(os.path.join(os.path.dirname(__file__), pattern)):
            try:
                os.remove(f)
            except Exception:
                pass
    ts = int(time.time())

    # --- 9:16 Testbilder (Portrait) ---
    img916 = make_grid_image_916()
    sbs916 = np.concatenate([img916, img916], axis=1)
    out_sbs916 = cap_image(sbs916, 8192)
    cv2.imwrite(f"gridbase_{out_sbs916.shape[1]}x{out_sbs916.shape[0]}_RANDOM{ts}_SBS_LR.png", out_sbs916)
    img916_fish, _, _ = cosinus_fisheye_transform(img916, deg_per_step=15, output_scale=2.0, debug_name=f"debug_916_{ts}")
    sbs916_fish = np.concatenate([img916_fish, img916_fish], axis=1)
    mid_col916 = sbs916_fish.shape[1] // 2
    sbs916_fish[:, mid_col916] = 0
    out_sbs916_fish = cap_image(sbs916_fish, 8192)
    cv2.imwrite(f"testgrid_{out_sbs916_fish.shape[1]}x{out_sbs916_fish.shape[0]}_RANDOM{ts}_LR_180.png", out_sbs916_fish)

    # --- 16:9 Testbilder ---
    img = make_grid_image()
    sbs = np.concatenate([img, img], axis=1)
    out_sbs = cap_image(sbs, 8192)
    cv2.imwrite(f"gridbase_{out_sbs.shape[1]}x{out_sbs.shape[0]}_RANDOM{ts}_SBS_LR.png", out_sbs)
    spacing = 512
    deg_per_step = 15
    img_fish, _, _ = cosinus_fisheye_transform(img, deg_per_step=deg_per_step, output_scale=2.0, debug_name=f"debug_169_{ts}")
    sbs_fish = np.concatenate([img_fish, img_fish], axis=1)
    # Mittelachse explizit auf schwarz setzen
    mid_col = sbs_fish.shape[1] // 2
    sbs_fish[:, mid_col] = 0
    out_sbs_fish = cap_image(sbs_fish, 8192)
    cv2.imwrite(f"testgrid_{out_sbs_fish.shape[1]}x{out_sbs_fish.shape[0]}_RANDOM{ts}_LR_180.png", out_sbs_fish)

    # --- 4:3 Testbilder (4096x3072) ---
    height43 = 2196  # gleiche Höhe wie 16:9
    width43 = int(height43 * 4 / 3)  # echtes 4:3-Verhältnis
    spacing43 = 512
    def make_grid_image_43():
        bg = np.full((height43, width43, 3), 255, np.uint8)
        cx, cy = width43 // 2, height43 // 2
        # Hauptachsen
        cv2.line(bg, (cx, 0), (cx, height43), (0,0,0), 6)
        cv2.line(bg, (0, cy), (width43, cy), (0,0,0), 6)
        # Gitterlinien
        for dx in range(spacing43, width43//2+1, spacing43):
            for sign in [-1, 1]:
                x = cx + sign*dx
                if 0 <= x < width43:
                    cv2.line(bg, (x, 0), (x, height43), (128,128,128), 2)
        for dy in range(spacing43, height43//2+1, spacing43):
            for sign in [-1, 1]:
                y = cy + sign*dy
                if 0 <= y < height43:
                    cv2.line(bg, (0, y), (width43, y), (128,128,128), 2)
        # Koordinatenpunkte und Labels
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 1.2
        font_thick = 2
        dot_radius = 12
        for gx in range(-(cx//spacing43), (width43-cx)//spacing43+1):
            px = cx + gx*spacing43
            if not (0 <= px < width43): continue
            for gy in range(-(cy//spacing43), (height43-cy)//spacing43+1):
                py = cy + gy*spacing43
                if not (0 <= py < height43): continue
                color = (0,128,0) if (gx,gy)==(0,0) else (0,0,255)
                cv2.circle(bg, (px, py), dot_radius, color, -1)
                label = f"({gx},{gy})"
                tx, ty = px+18, py-18
                cv2.putText(bg, label, (tx, ty), font, font_scale, (0,0,0), font_thick, cv2.LINE_AA)
        return bg

    img43 = make_grid_image_43()
    # SBS: echte horizontale Verdopplung
    sbs43 = np.concatenate([img43, img43], axis=1)
    out_sbs43 = cap_image(sbs43, 8192)
    cv2.imwrite(f"gridbase_{out_sbs43.shape[1]}x{out_sbs43.shape[0]}_RANDOM{ts}_SBS_LR.png", out_sbs43)
    # Fisheye für 4:3 (gleiche Transformation wie zuvor)
    img43_fish, _, _ = cosinus_fisheye_transform(img43, deg_per_step=15, output_scale=2.0, debug_name=f"debug_43_{ts}")
    sbs43_fish = np.concatenate([img43_fish, img43_fish], axis=1)
    # Mittelachse explizit auf schwarz setzen
    mid_col43 = sbs43_fish.shape[1] // 2
    sbs43_fish[:, mid_col43] = 0
    out_sbs43_fish = cap_image(sbs43_fish, 8192)
    cv2.imwrite(f"testgrid_{out_sbs43_fish.shape[1]}x{out_sbs43_fish.shape[0]}_RANDOM{ts}_LR_180.png", out_sbs43_fish)

    # --- Zusatz: fisheye-Erzeugung für input/testbear.png in nativer Auflösung ---
    tb_path = os.path.join(os.path.dirname(__file__), "input", "testbear.png")
    if os.path.exists(tb_path):
        src_tb = cv2.imread(tb_path)
        if src_tb is not None:
            tb_h, tb_w = src_tb.shape[:2]
            # Use native resolution; choose spacing proportional to height to
            # keep visual grid density similar to the standard 2196px height.
            spacing_tb = max(1, int(round(512 * (tb_h / 2196.0))))
            deg_per_step = 15

            tb_fish, _, _ = cosinus_fisheye_transform(src_tb, deg_per_step=deg_per_step, output_scale=2.0, debug_name=f"debug_testbear_native_{ts}")
            sbs_tb = np.concatenate([tb_fish, tb_fish], axis=1)
            mid_col_tb = sbs_tb.shape[1] // 2
            sbs_tb[:, mid_col_tb] = 0
            out_sbs_tb = cap_image(sbs_tb, 8192)
            cv2.imwrite(f"testbear_native_{out_sbs_tb.shape[1]}x{out_sbs_tb.shape[0]}_RANDOM{ts}_LR_180.png", out_sbs_tb)
