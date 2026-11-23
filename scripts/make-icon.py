#!/usr/bin/env python3
"""生成 TonyToy 应用图标（魔方）。

投影：观察者位于右前上方（PHI=32° 绕 Y 轴，THETA=31° 俯角）的正交投影，
两个斜轴角度不对称，比严格等轴测更接近相机实拍，且不会出现棱线退化。

三个面各 9 块，块间缝隙露出深色塑料骨架，每块带渐变模拟塑料表面。

用法:
    python3 scripts/make-icon.py               # 默认紫底撞色
    python3 scripts/make-icon.py --theme charcoal
    python3 scripts/make-icon.py --png
"""

import math
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "resources")
ICNS_PATH = os.path.join(RESOURCES, "AppIcon.icns")
SVG_PATH = os.path.join(RESOURCES, "AppIcon.svg")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

W = 1024
CUBE = 390.0

PHI = math.radians(32.0)
THETA = math.radians(31.0)
CA = math.cos(PHI)
SA = math.sin(THETA) * math.sin(PHI)
CB = math.sin(PHI)
SB = math.sin(THETA) * math.cos(PHI)
HSCALE = math.cos(THETA)

GAP = 5.8
CORNER = 0.12

PALETTE = {
    "W": ("#F5F1E8", "#CFC7B7"),
    "R": ("#BF4A38", "#8E3325"),
    "B": ("#305F9C", "#1F416B"),
    "Y": ("#EDC244", "#BE951F"),
    "O": ("#D97B39", "#A85820"),
    "G": ("#3E8A64", "#2A6349"),
}

THEMES = {
    "plum": {
        "base": ("#7C4FA6", "#43256A"),
        "faces": {"top": "W", "left": "O", "right": "G"},
    },
    "charcoal": {
        "base": ("#40382F", "#1E1A16"),
        "faces": {"top": "W", "left": "R", "right": "B"},
    },
    "coral": {
        "base": ("#E0703E", "#A63914"),
        "faces": {"top": "W", "left": "O", "right": "R"},
    },
}

ICONSET = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]


def hex_mix(a, b, t):
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02X}" for x, y in zip(ca, cb))


def project(p):
    x, y, z = p
    return (x * CA - z * CB, x * SA + z * SB - y * HSCALE)


def cube_point(face, a, b):
    if face == "top":
        return (-0.5 + a, 0.5, -0.5 + b)
    if face == "left":
        return (a - 0.5, 0.5 - b, 0.5)
    return (0.5, 0.5 - b, a - 0.5)


def make_transform():
    pts = [project(cube_point(f, i / 3, j / 3))
           for f in ("top", "left", "right") for i in range(4) for j in range(4)]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    scale = min(700.0 / (max(xs) - min(xs)), 752.0 / (max(ys) - min(ys)))
    ox = 512 - (min(xs) + max(xs)) / 2 * scale
    oy = 498 - (min(ys) + max(ys)) / 2 * scale
    return (lambda p: (p[0] * scale + ox, p[1] * scale + oy)), scale


def rounded_path(pts, r):
    n = len(pts)
    segs = []
    for i in range(n):
        prev, cur, nxt = pts[i - 1], pts[i], pts[(i + 1) % n]
        ax, ay = cur[0] - prev[0], cur[1] - prev[1]
        bx, by = nxt[0] - cur[0], nxt[1] - cur[1]
        la = math.hypot(ax, ay) or 1e-6
        lb = math.hypot(bx, by) or 1e-6
        rr = min(r, la * 0.42, lb * 0.42)
        segs.append(((cur[0] - ax / la * rr, cur[1] - ay / la * rr), cur,
                     (cur[0] + bx / lb * rr, cur[1] + by / lb * rr)))

    f = lambda p: f"{p[0]:.2f},{p[1]:.2f}"
    d = [f"M {f(segs[0][2])}"]
    for i in range(1, n):
        d.append(f"L {f(segs[i][0])} Q {f(segs[i][1])} {f(segs[i][2])}")
    d.append(f"L {f(segs[0][0])} Q {f(segs[0][1])} {f(segs[0][2])} Z")
    return " ".join(d)


def poly(pts, fill):
    d = " ".join(f"{x:.2f},{y:.2f}" for x, y in pts)
    return f'<polygon points="{d}" fill="{fill}"/>'


def squircle(cx, cy, r, n=5.0, steps=720):
    exp = 2.0 / n
    pts = []
    for k in range(steps):
        t = 2 * math.pi * k / steps
        ct, st = math.cos(t), math.sin(t)
        pts.append(f"{cx + r * math.copysign(abs(ct) ** exp, ct):.2f} "
                   f"{cy + r * math.copysign(abs(st) ** exp, st):.2f}")
    return "M" + " L".join(pts) + " Z"


def face_cells(face, tf, key, scale):
    da = GAP / scale
    out = []
    for i in range(3):
        for j in range(3):
            a0, a1 = i / 3 + da, (i + 1) / 3 - da
            b0, b1 = j / 3 + da, (j + 1) / 3 - da
            quad = [cube_point(face, a0, b0), cube_point(face, a1, b0),
                    cube_point(face, a1, b1), cube_point(face, a0, b1)]
            p2 = [tf(project(p)) for p in quad]
            edge = min(math.dist(p2[k], p2[(k + 1) % 4]) for k in range(4))
            out.append(f'<path d="{rounded_path(p2, edge * CORNER)}" fill="url(#c{key})"/>')
    return "\n    ".join(out)


def face_outline(face, tf):
    return [tf(project(cube_point(face, a, b)))
            for a, b in ((0, 0), (1, 0), (1, 1), (0, 1))]


def build_svg(theme):
    tf, scale = make_transform()
    base_hi, base_lo = theme["base"]
    faces = theme["faces"]
    body = "#241C16"

    def grad(id_, stops):
        s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{op}"/>'
                    for o, c, op in stops)
        return f'<linearGradient id="{id_}" x1="0" y1="0" x2="0.35" y2="1">{s}</linearGradient>'

    defs = (
        f'<linearGradient id="base" x1="0" y1="0" x2="0.55" y2="1">'
        f'<stop offset="0" stop-color="{base_hi}"/>'
        f'<stop offset="1" stop-color="{base_lo}"/></linearGradient>'
        + grad("shTop", [(0, "#ffffff", 0.14), (0.5, "#ffffff", 0.02), (1, "#000000", 0.08)])
        + grad("shLeft", [(0, "#ffffff", 0.06), (1, "#000000", 0.16)])
        + grad("shRight", [(0, "#ffffff", 0.04), (1, "#000000", 0.22)])
        + "".join(
            f'<linearGradient id="c{k}" x1="0.05" y1="0" x2="0.8" y2="1">'
            f'<stop offset="0" stop-color="{v[0]}"/>'
            f'<stop offset="1" stop-color="{hex_mix(v[0], v[1], 0.55)}"/>'
            f'</linearGradient>' for k, v in PALETTE.items())
        + '<filter id="soft" x="-70%" y="-70%" width="240%" height="240%">'
          '<feGaussianBlur stdDeviation="28"/></filter>'
        + f'<clipPath id="sq"><path d="{squircle(512, 512, 512)}"/></clipPath>'
    )

    outlines = {f: face_outline(f, tf) for f in ("top", "left", "right")}
    skeleton = "".join(poly(outlines[f], body) for f in ("left", "right", "top"))

    layers = [
        skeleton,
        face_cells("left", tf, faces["left"], scale),
        poly(outlines["left"], "url(#shLeft)"),
        face_cells("right", tf, faces["right"], scale),
        poly(outlines["right"], "url(#shRight)"),
        face_cells("top", tf, faces["top"], scale),
        poly(outlines["top"], "url(#shTop)"),
    ]

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" viewBox="0 0 {W} {W}">
  <defs>{defs}</defs>
  <path d="{squircle(512, 512, 512)}" fill="url(#base)"/>
  <g clip-path="url(#sq)">
    <ellipse cx="512" cy="878" rx="286" ry="32" fill="#000000" opacity="0.26" filter="url(#soft)"/>
  </g>
  {"".join(layers)}
</svg>
'''


def render_png(svg_text, out_png):
    tmp = tempfile.mkdtemp()
    try:
        svg_file = os.path.join(tmp, "icon.svg")
        with open(svg_file, "w") as fh:
            fh.write(svg_text)
        if os.path.exists(CHROME):
            subprocess.run([
                CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                "--force-device-scale-factor=1", "--default-background-color=00000000",
                f"--window-size={W},{W}", f"--screenshot={out_png}", f"file://{svg_file}",
            ], check=True, capture_output=True)
        else:
            subprocess.run(["qlmanage", "-t", "-s", str(W), "-o", tmp, svg_file],
                           check=True, capture_output=True)
            shutil.move(os.path.join(tmp, "icon.svg.png"), out_png)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    theme_name = "plum"
    only_png = "--png" in sys.argv
    for i, arg in enumerate(sys.argv):
        if arg == "--theme" and i + 1 < len(sys.argv):
            theme_name = sys.argv[i + 1]
    if theme_name not in THEMES:
        sys.exit(f"未知配色: {theme_name}（可选: {', '.join(THEMES)}）")

    svg_text = build_svg(THEMES[theme_name])
    tmp = tempfile.mkdtemp()
    try:
        master = os.path.join(tmp, "master.png")
        render_png(svg_text, master)
        img = Image.open(master).convert("RGBA")

        if only_png:
            out = os.path.join(tmp, "preview.png")
            img.save(out)
            print(out)
            return

        with open(SVG_PATH, "w") as fh:
            fh.write(svg_text)

        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset, exist_ok=True)
        for size, name in ICONSET:
            img.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, name))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", ICNS_PATH], check=True)
        print(f"✅ {ICNS_PATH}  (theme={theme_name})")
        print(f"✅ {SVG_PATH}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
