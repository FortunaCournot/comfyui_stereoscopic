import numpy as np
import cv2
import glob
import os
import time

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


def cosinus_fisheye_transform(src, spacing=512, deg_per_step=15):
    import math
    h, w = src.shape[:2]
    aspect = w / h
    dst = np.full_like(src, 255)
    cx = w // 2
    cy = h // 2
    yy, xx = np.indices((h, w))
    gx = (xx - cx) / spacing
    gy = (yy - cy) / spacing
    angle_x = gx * deg_per_step
    angle_y = gy * deg_per_step
    fix_angle = 4 * deg_per_step
    # Zoomfaktor für Benutzer
    user_zoom = 1.0  # <--- Hier anpassen für mehr/weniger Zoom
    # horizontales Stretching linear: 16:9 -> 1.0, 4:3 > 1, Portrait < 1
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
    dst = cv2.remap(src, map_x, map_y, interpolation=cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    return dst, gx, gy

if __name__ == "__main__":
    # Alte Testbilder im aktuellen Verzeichnis löschen
    for f in glob.glob(os.path.join(os.path.dirname(__file__), "testgrid_*_RANDOM*.png")):
        try:
            os.remove(f)
        except Exception:
            pass
    ts = int(time.time())

    # --- 9:16 Testbilder (Portrait) ---
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

    img916 = make_grid_image_916()
    sbs916 = np.concatenate([img916, img916], axis=1)
    cv2.imwrite(f"testgrid_{width916}x{height916}_RANDOM{ts}_SBS_LR.png", sbs916)
    img916_fish, _, _ = cosinus_fisheye_transform(img916, spacing=spacing916, deg_per_step=15)
    sbs916_fish = np.concatenate([img916_fish, img916_fish], axis=1)
    mid_col916 = sbs916_fish.shape[1] // 2
    sbs916_fish[:, mid_col916] = 0
    cv2.imwrite(f"testgrid_{width916}x{height916}_RANDOM{ts}_LR_180.png", sbs916_fish)

    img = make_grid_image()
    sbs = np.concatenate([img, img], axis=1)
    cv2.imwrite(f"testgrid_3840x2196_RANDOM{ts}_SBS_LR.png", sbs)
    spacing = 512
    deg_per_step = 15
    img_fish, _, _ = cosinus_fisheye_transform(img, spacing=spacing, deg_per_step=deg_per_step)
    sbs_fish = np.concatenate([img_fish, img_fish], axis=1)
    # Mittelachse explizit auf schwarz setzen
    mid_col = sbs_fish.shape[1] // 2
    sbs_fish[:, mid_col] = 0
    cv2.imwrite(f"testgrid_3840x2196_RANDOM{ts}_LR_180.png", sbs_fish)

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
    cv2.imwrite(f"testgrid_{width43}x{height43}_RANDOM{ts}_SBS_LR.png", sbs43)
    # Fisheye für 4:3 (gleiche Transformation wie zuvor)
    img43_fish, _, _ = cosinus_fisheye_transform(img43, spacing=spacing43, deg_per_step=15)
    sbs43_fish = np.concatenate([img43_fish, img43_fish], axis=1)
    # Mittelachse explizit auf schwarz setzen
    mid_col43 = sbs43_fish.shape[1] // 2
    sbs43_fish[:, mid_col43] = 0
    cv2.imwrite(f"testgrid_{width43}x{height43}_RANDOM{ts}_LR_180.png", sbs43_fish)
