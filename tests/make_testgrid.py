import numpy as np
import cv2

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

if __name__ == "__main__":
    img = make_grid_image()
    # Side-by-side (SBS) LR: horizontal duplizieren
    sbs = np.concatenate([img, img], axis=1)
    cv2.imwrite("testgrid_3840x2196_SBS_LR.png", sbs)

    # --- VR180 Fisheye-Transformation ---


    # Kosinus-Stauchung mit Winkelberechnung
    def cosinus_fisheye_transform(src, spacing=512, deg_per_step=15):
        import math
        h, w = src.shape[:2]
        dst = np.full_like(src, 255)
        cx = w // 2
        cy = h // 2
        yy, xx = np.indices((h, w))
        gx = (xx - cx) / spacing
        gy = (yy - cy) / spacing
        angle_x = gx * deg_per_step
        angle_y = gy * deg_per_step
        fix_angle = 2 * deg_per_step
        zoom_x = 1.0 / abs(np.cos(np.deg2rad(fix_angle)))
        # Vertikale Stauchung zusätzlich mit 9/16 multiplizieren
        zoom_y = (1.0 / abs(np.cos(np.deg2rad(fix_angle)))) * (16/9)
        src_x = cx + (xx - cx) * zoom_x * np.abs(np.cos(np.deg2rad(angle_x)))
        src_y = cy + (yy - cy) * zoom_y * np.abs(np.cos(np.deg2rad(angle_y)))
        map_x = src_x.astype(np.float32)
        map_y = src_y.astype(np.float32)
        dst = cv2.remap(src, map_x, map_y, interpolation=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        return dst, gx, gy

    # --- Kosinus-Fisheye-Transformation ---
    spacing = 512
    deg_per_step = 15
    img_fish, _, _ = cosinus_fisheye_transform(img, spacing=spacing, deg_per_step=deg_per_step)
    sbs_fish = np.concatenate([img_fish, img_fish], axis=1)
    cv2.imwrite("testgrid_3840x2196_LR_180.png", sbs_fish)
