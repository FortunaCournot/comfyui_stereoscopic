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
