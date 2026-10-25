#!/usr/bin/env python3
"""Renderpolish pipeline for ext_menu (graphical formcache design).

Artifacts:
  textures/ext_menu_menu_bg.png       - main panel shell (gradient, title, close X, footer)
  textures/ext_menu_row_<i>_f<k>.png  - entrance stagger frame for row i (k = 0..ANIM-1)
  textures/ext_menu_row_<i>_set.png   - settled (fully opaque) row card
  textures/ext_menu_sw_base.png       - rhombus-free empty slot for the switch zone (uses row)
  textures/ext_menu_sw_<dir>_f<k>.png - switch knob slide frames, dir in {off_to_on, on_to_off}
  textures/ext_menu_sub_<mod>_bg.png  - module settings page shell
  textures/ext_menu_seg_sel_<i>.png   - chest_dupe mode segment selection overlays
  layout.lua                          - geometry shared with Lua (cannot drift)
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "..", "textures")
LAYOUT = os.path.join(HERE, "..", "layout.lua")
os.makedirs(TEX, exist_ok=True)

PXPU = 440
W, H = 6.55, 5.85
L = 0.35

MAIN_ROWS = [
    ("xray",       "XRay"),
    ("fullbright", "Fullbright"),
    ("no_night",   "No-Night"),
    ("chest_dupe", "ChestDupe"),
]

ANIM = 6
HDR_Y, HDR_H = 0.25, 0.68
ROW_Y0, ROW_H, ROW_SP = 1.18, 0.88, 1.02
SW_W, SW_H = 1.10, 0.55
GEAR_S = 0.52
SRC_PAD = 0.22
CLOSE_S = 0.64
TITLE_BG = (0.16, HDR_Y, 2.85, HDR_H)
SUB_W, SUB_H = 5.30, 5.85
SUB_ROW_Y0, SUB_ROW_H, SUB_ROW_SP = 1.20, 0.88, 1.02

C_PANEL_TOP = (14, 18, 26)
C_PANEL_BOT = (20, 26, 36)
C_CARD      = (25, 32, 43, 255)
C_CARD_EDGE = (37, 47, 61, 255)
C_ACCENT    = (74, 140, 235)
C_TEXT      = (216, 226, 238)
C_DIM       = (140, 152, 166)

F_REG  = "/usr/share/fonts/google-noto/NotoSans-Regular.ttf"
F_BOLD = "/usr/share/fonts/google-noto/NotoSans-Bold.ttf"

def u2px(u):
    return int(round(u * PXPU))

def ease_out_cubic(t):
    return 1 - (1 - t) ** 3

def lerp(a, b, t):
    return a + (b - a) * t

def lerp_color(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def gradient_panel(w, h, top, bot, radius):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    grad = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / h
        c = lerp_color(top, bot, t)
        gd.line([(0, y), (w, y)], fill=c + (255,))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)
    return img

def make_card(wpx, hpx, label, alpha=255, with_gear=False):
    card = Image.new("RGBA", (wpx, hpx), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle([0, 0, wpx - 1, hpx - 1], radius=22, fill=C_CARD, outline=C_CARD_EDGE, width=2)
    if alpha < 250:
        # soften all painted layers via alpha-reduced overlay
        overlay = Image.new("RGBA", (wpx, hpx), (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        if with_gear:
            _paint_gear(od, wpx - u2px(SRC_PAD + SW_W) - u2px(GEAR_S) - u2px(0.14), hpx // 2)
        f_row = ImageFont.truetype(F_REG, 52)
        od.ellipse([u2px(0.24), hpx // 2 - 5, u2px(0.24) + 10, hpx // 2 + 5], fill=(92, 150, 212, 255))
        od.text((u2px(0.46), hpx // 2 - 28), label, font=f_row, fill=tuple(list(C_TEXT[:3]) + [255]))
        r, g, b, a = overlay.split()
        a = a.point(lambda p: int(p * (alpha / 255)))
        card = Image.alpha_composite(card, Image.merge("RGBA", (r, g, b, a)))
    else:
        d.ellipse([u2px(0.24), hpx // 2 - 5, u2px(0.24) + 10, hpx // 2 + 5], fill=(92, 150, 212, 255))
        f_row = ImageFont.truetype(F_REG, 52)
        d.text((u2px(0.46), hpx // 2 - 28), label, font=f_row, fill=C_TEXT)
        if with_gear:
            _paint_gear(d, wpx - u2px(SRC_PAD + SW_W) - u2px(GEAR_S) - u2px(0.14), hpx // 2)
    return card

def _paint_gear(d, cx, cy):
    gs = int(PXPU * GEAR_S * 0.32)
    d.ellipse([cx - gs, cy - gs, cx + gs, cy + gs], outline=(152, 164, 178), width=5)
    for a in range(8):
        ang = a * math.pi / 4
        x1, y1 = cx + (gs - 2) * math.cos(ang), cy + (gs - 2) * math.sin(ang)
        x2, y2 = cx + (gs + 5) * math.cos(ang), cy + (gs + 5) * math.sin(ang)
        d.line([x1, y1, x2, y2], fill=(152, 164, 178), width=5)

def render():
    # ---------- main shell ----------
    WPX, HPX = u2px(W), u2px(H)
    img = gradient_panel(WPX, HPX, C_PANEL_TOP, C_PANEL_BOT, 24)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, WPX - 2, HPX - 2], radius=24, outline=(45, 57, 73, 255), width=2)
    tx0, ty0, tw, th = u2px(TITLE_BG[0]), u2px(TITLE_BG[1]), u2px(TITLE_BG[2]), u2px(TITLE_BG[3])
    d.rounded_rectangle([tx0, ty0, tx0 + tw, ty0 + th], radius=14,
                        fill=(28, 36, 48, 255), outline=(50, 64, 82, 255), width=2)
    d.rounded_rectangle([tx0 + 14, ty0 + 14, tx0 + 20, ty0 + th - 14], radius=3, fill=C_ACCENT)
    d.text((tx0 + 38, ty0 + 24), "Ext Menu", font=ImageFont.truetype(F_BOLD, 62), fill=(228, 236, 246))
    cx, cy = u2px(W - SRC_PAD - CLOSE_S / 2), u2px(HDR_Y + HDR_H / 2)
    s = u2px(CLOSE_S) // 2 - 18
    d.line([cx - s, cy - s, cx + s, cy + s], fill=C_DIM, width=7)
    d.line([cx + s, cy - s, cx - s, cy + s], fill=C_DIM, width=7)
    d.text((u2px(L), HPX - u2px(0.28)),
           "Click row = toggle   |   Gear = module settings",
           font=ImageFont.truetype(F_REG, 38), fill=(116, 128, 142))
    img.save(os.path.join(TEX, "ext_menu_menu_bg.png"))

    # ---------- row cards (entrance stagger + settled) ----------
    wpx, hpx = u2px(W - 2 * L), u2px(ROW_H)
    for i, (key, label) in enumerate(MAIN_ROWS):
        for k in range(ANIM):
            t = ease_out_cubic(k / (ANIM - 1))
            card = make_card(wpx, hpx, label, alpha=int(t * 255), with_gear=(k == ANIM - 1))
            card.save(os.path.join(TEX, "ext_menu_row_%d_in_f%d.png" % (i, k)))
        settled = make_card(wpx, hpx, label, alpha=255, with_gear=True)
        settled.save(os.path.join(TEX, "ext_menu_row_%d_set.png" % i))

    # ---------- switch slides ----------
    sw_w_px, sw_h_px = u2px(SW_W), u2px(SW_H)
    for direction in ("off_to_on", "on_to_off"):
        for k in range(ANIM):
            t = ease_out_cubic(k / (ANIM - 1))
            pill = Image.new("RGBA", (sw_w_px, sw_h_px), (0, 0, 0, 0))
            pd = ImageDraw.Draw(pill)
            bh = sw_h_px - 8
            col_start = (32, 40, 52) if direction == "off_to_on" else (46, 78, 120)
            col_end   = (46, 78, 120) if direction == "off_to_on" else (32, 40, 52)
            color = lerp_color(col_start, col_end, t)
            outline = lerp_color((46, 57, 72), (88, 148, 232), t) if direction == "off_to_on" \
                else lerp_color((88, 148, 232), (46, 57, 72), t)
            pd.rounded_rectangle([0, 0, sw_w_px - 1, sw_h_px - 1], radius=bh // 2,
                                 fill=color + (255,), outline=outline + (255,), width=5)
            knob_col = lerp_color((150, 160, 172), (255, 255, 255), t) if direction == "off_to_on" \
                else lerp_color((255, 255, 255), (150, 160, 172), t)
            kx_start = 6 if direction == "off_to_on" else (sw_w_px - bh - 2)
            kx_end = (sw_w_px - bh - 2) if direction == "off_to_on" else 6
            kx = int(kx_start + (kx_end - kx_start) * t)
            pd.ellipse([kx, 5, kx + bh, bh - 1], fill=knob_col + (255,))
            pill.save(os.path.join(TEX, "ext_menu_sw_%s_f%d.png" % (direction, k)))

    # ---------- subpages ----------
    SUBPAGES = [
        ("xray",       "XRay Module",       [("xray.nodes", "Node blocks")]),
        ("fullbright", "Fullbright Module", []),
        ("no_night",   "No-Night Module",   []),
        ("chest_dupe", "ChestDupe Module",  [("chest_dupe.autotake", "Auto-collect"),
                                            ("chest_dupe.log", "Log"),
                                            ("chest_dupe.hold_mode", "Hold mode")]),
    ]
    for modkey, title, rows in SUBPAGES:
        swpx, shpx = u2px(SUB_W), u2px(SUB_H)
        sub = gradient_panel(swpx, shpx, (13, 17, 24), (19, 25, 34), 24)
        sd = ImageDraw.Draw(sub)
        sd.rounded_rectangle([1, 1, swpx - 2, shpx - 2], radius=24, outline=(45, 57, 73, 255), width=2)
        # transparent blank for invisible buttons
        Image.new("RGBA", (1, 1), (0, 0, 0, 0)).save(os.path.join(TEX, "ext_menu_blank.png"))
        bx, by = u2px(0.32), u2px(0.44)
        sd.line([bx + 18, by - 4, bx - 6, by + 14], fill=C_DIM, width=7)
        sd.line([bx - 6, by + 14, bx + 18, by + 32], fill=C_DIM, width=7)
        sd.line([bx - 8, by + 14, bx + 46, by + 14], fill=C_DIM, width=7)
        sd.text((u2px(0.64), u2px(0.26)), title, font=ImageFont.truetype(F_BOLD, 54),
                fill=(226, 234, 244))
        seg_y = 0.0
        if modkey == "chest_dupe":
            seg_y = SUB_ROW_Y0
            sy_px = u2px(SUB_ROW_Y0)
            sd.rounded_rectangle([u2px(L), sy_px, u2px(SUB_W - L), sy_px + u2px(SUB_ROW_H)],
                                 radius=22, fill=C_CARD, outline=C_CARD_EDGE, width=2)
            half = (SUB_W - 2 * L) / 2
            f_seg = ImageFont.truetype(F_REG, 48)
            sd.text((u2px(L + half * 0.24), sy_px + u2px(SUB_ROW_H) // 2 - 26), "Auto",
                    font=f_seg, fill=C_TEXT)
            sd.text((u2px(L + half * 1.18), sy_px + u2px(SUB_ROW_H) // 2 - 26), "Crosshair only",
                    font=f_seg, fill=C_DIM)
            sd.line([u2px(L + half), sy_px + 10, u2px(L + half), sy_px + u2px(SUB_ROW_H) - 10],
                    fill=(44, 56, 72, 255), width=3)
        ry_base = (seg_y + SUB_ROW_H + 0.14) if modkey == "chest_dupe" else SUB_ROW_Y0
        for j, (_stg, label) in enumerate(rows):
            sy_px = u2px(ry_base + j * SUB_ROW_SP)
            sd.rounded_rectangle([u2px(L), sy_px, u2px(SUB_W - L), sy_px + u2px(SUB_ROW_H)],
                                 radius=22, fill=C_CARD, outline=C_CARD_EDGE, width=2)
            sd.ellipse([u2px(L + 0.24), sy_px + u2px(SUB_ROW_H) // 2 - 5,
                        u2px(L + 0.24) + 10, sy_px + u2px(SUB_ROW_H) // 2 + 5],
                       fill=(92, 150, 212, 255))
            f_sb = ImageFont.truetype(F_REG, 44)
            sd.text((u2px(L + 0.46), sy_px + u2px(SUB_ROW_H) // 2 - 24), label, font=f_sb,
                    fill=C_TEXT)
        info = "Gear switches module settings." if modkey == "chest_dupe" else \
               ("No additional module options." if not rows else "")
        if info:
            sd.text((u2px(L), shpx - u2px(0.28)), info, font=ImageFont.truetype(F_REG, 36),
                    fill=(116, 128, 142))
        sub.save(os.path.join(TEX, "ext_menu_sub_%s_bg.png" % modkey))
        if modkey == "chest_dupe":
            half = (SUB_W - 2 * L) / 2
            for i2, lbl in enumerate(("Auto", "Crosshair only")):
                sel = Image.new("RGBA", (u2px(half), u2px(SUB_ROW_H)), (0, 0, 0, 0))
                sed = ImageDraw.Draw(sel)
                sed.rounded_rectangle([0, 0, u2px(half) - 1, u2px(SUB_ROW_H) - 1], radius=22,
                                      fill=(40, 66, 100, 255), outline=(96, 156, 238, 255), width=3)
                sed.text((u2px(half * 0.16), u2px(SUB_ROW_H) // 2 - 26), lbl,
                         font=ImageFont.truetype(F_BOLD, 46), fill=(216, 236, 255))
                sel.save(os.path.join(TEX, "ext_menu_seg_sel_%d.png" % i2))

    # ---------- layout.lua ----------
    lines = [
        "-- Auto-generated by tools/gen_menu_bg.py — DO NOT EDIT BY HAND.",
        "local M = {}",
        "M.W, M.H = %.2f, %.2f" % (W, H),
        "M.ANIM = %d" % ANIM,
        "M.MAIN = {",
    ]
    for i, (key, _label) in enumerate(MAIN_ROWS):
        ry = ROW_Y0 + i * ROW_SP
        swx = W - L - SRC_PAD - SW_W
        gxc = W - L - SRC_PAD - SW_W - GEAR_S - 0.14
        lines.append("    { key = %r, x0 = %.2f, y = %.2f, w = %.2f, h = %.2f, "
                     "sw_x = %.2f, sw_y = %.2f, sw_w = %.2f, sw_h = %.2f, gear_x = %.2f, gear_w = %.2f }," % (
                         key, L, ry, W - 2 * L, ROW_H, swx, ry + (ROW_H - SW_H) / 2, SW_W, SW_H,
                         gxc - 0.06, GEAR_S + 0.12))
    lines.append("}")
    lines.append("M.CLOSE_X, M.CLOSE_Y, M.CLOSE_S = %.2f, %.2f, %.2f" % (W - SRC_PAD - CLOSE_S, HDR_Y, CLOSE_S))
    lines.append("M.SUB = {")
    for modkey, title, rows in SUBPAGES:
        ry_base = (SUB_ROW_Y0 + SUB_ROW_H + 0.14) if modkey == "chest_dupe" else SUB_ROW_Y0
        rls = ["{ setting = %r, x0 = %.2f, y = %.2f, w = %.2f, h = %.2f }" % (
            stg, L, ry_base + j * SUB_ROW_SP, SUB_W - 2 * L, SUB_ROW_H) for j, (stg, _l) in enumerate(rows)]
        lines.append("    %s = { title = %r, w = %.2f, h = %.2f, rows = { %s } }," % (
            ("%r" % modkey).strip("'"), title, SUB_W, SUB_H, ", ".join(rls)))
    lines.append("}")
    lines.append("return M")
    with open(LAYOUT, "w") as fh:
        fh.write("\n".join(lines) + "\n")

render()
print("OK — rendered ext_menu graphics + layout.lua")
