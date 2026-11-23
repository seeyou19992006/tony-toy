#!/usr/bin/env python3
"""生成菜单栏（托盘）图标：等轴测魔方模板图。

模板图只保留 alpha，颜色由系统按深浅色自动反转，所以这里全画纯黑。
尺寸输出 18pt / @2x 36pt，供 NSImage(named:) 自动合并。
"""

import math
import os
import shutil
import subprocess
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "resources")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

CANVAS = 288            # 先按 16 倍大图渲染，再降采样
PHI = math.radians(32.0)
THETA = math.radians(31.0)
CA, SA = math.cos(PHI), math.sin(THETA) * math.sin(PHI)
CB, SB = math.sin(PHI), math.sin(THETA) * math.cos(PHI)
HSCALE = math.cos(THETA)

CUBE_W = 224.0          # 立方体在 288 画布上的宽度
GAP = 13.0              # 半缝宽（像素），菜单栏尺寸只表现三个面
CORNER = 0.05           # 圆角 / 块边长


def project(p):
    x, y, z = p
    return (x * CA - z * CB, x * SA + z * SB - y * HSCALE)


def cube_point(face, a, b):
    if face == "top":
        return (-0.5 + a, 0.5, -0.5 + b)
    if face == "left":
        return (a - 0.5, 0.5 - b, 0.5)
    return (0.5, 0.5 - b, a - 0.5)


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


def build_svg():
    pts = [project(cube_point(f, i / 3, j / 3))
           for f in ("top", "left", "right") for i in range(4) for j in range(4)]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    scale = CUBE_W / (max(xs) - min(xs))
    w = (max(xs) - min(xs)) * scale
    h = (max(ys) - min(ys)) * scale
    ox = (CANVAS - w) / 2
    oy = (CANVAS - h) / 2

    def tf(p):
        return ((p[0] - min(xs)) * scale + ox, (p[1] - min(ys)) * scale + oy)

    da = GAP / scale
    paths = []
    for face in ("left", "right", "top"):
        for i in range(1):
            for j in range(1):
                a0, a1 = da, 1 - da
                b0, b1 = da, 1 - da
                quad = [cube_point(face, a0, b0), cube_point(face, a1, b0),
                        cube_point(face, a1, b1), cube_point(face, a0, b1)]
                p2 = [tf(project(p)) for p in quad]
                edge = min(math.dist(p2[k], p2[(k + 1) % 4]) for k in range(4))
                paths.append(f'<path d="{rounded_path(p2, edge * CORNER)}" fill="#000000"/>')

    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
            f'viewBox="0 0 {CANVAS} {CANVAS}">{"".join(paths)}</svg>')


def main():
    svg = build_svg()
    tmp = tempfile.mkdtemp()
    try:
        svg_path = os.path.join(tmp, "status.svg")
        with open(svg_path, "w") as fh:
            fh.write(svg)
        big = os.path.join(tmp, "big.png")
        subprocess.run([
            CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--force-device-scale-factor=1", "--default-background-color=00000000",
            f"--window-size={CANVAS},{CANVAS}", f"--screenshot={big}",
            f"file://{svg_path}",
        ], check=True, capture_output=True)

        img = Image.open(big).convert("RGBA")
        for size, name in ((18, "StatusIcon.png"), (36, "StatusIcon@2x.png")):
            img.resize((size, size), Image.LANCZOS).save(os.path.join(RES, name))
            print(f"✅ {name} ({size}x{size})")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
