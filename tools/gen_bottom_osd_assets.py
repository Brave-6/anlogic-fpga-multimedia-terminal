# -*- coding: utf-8 -*-
"""OSD横条 + 滚动通知条 目标效果示例图
布局规范（内容安全区 y≤428）：
  - 滚动通知条 y=432..454（22px，半透明黑 α148，左侧固定标签章 + 滚动文字 14px）
  - OSD状态横条 y=456..480（24px，实心藏青 #1C2C4E，三组信息：亮度块/显示模式/运行状态+页码）
  - 亮度调节临时指示器 y=384..424 居中（20px粗体，2秒自动隐藏）
"""
import os
import shutil
import pymupdf
from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(BASE, "assets", "osd_bottom_20261008")
OUT = os.path.join(ASSETS, "preview")
TF_OUT = os.path.join(ASSETS, "tf_pages")
os.makedirs(OUT, exist_ok=True)
os.makedirs(TF_OUT, exist_ok=True)
W, H = 640, 480

NAVY = (28, 44, 78)
BLUE = (31, 78, 156)
REDCHIP = (146, 12, 19)
GREEN = (86, 214, 104)
AMBER = (255, 196, 0)

MSYH = "C:/Windows/Fonts/msyh.ttc"
MSYHBD = "C:/Windows/Fonts/msyhbd.ttc"

def F(path, size, index=0):
    return ImageFont.truetype(path, size, index=index)

# ---------- 基础素材（与 gen_bmp.py 同源） ----------
def load_logo(target_w):
    doc = pymupdf.open(os.path.join(ASSETS, "anlogic_logo.svg"))
    pix = doc[0].get_pixmap(matrix=pymupdf.Matrix(8, 8), alpha=True)
    img = Image.frombytes("RGBA", (pix.width, pix.height), pix.samples)
    img = img.crop(img.getbbox())
    r = target_w / img.width
    return img.resize((target_w, round(img.height * r)), Image.LANCZOS)

def vgrad(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img

def dgrad(w, h, c1, c2):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x + y) / (w + h - 2)
            px[x, y] = tuple(round(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img

def hazard_strip(img, y0, h=12):
    d = ImageDraw.Draw(img)
    d.rectangle([0, y0, W, y0 + h], fill=(26, 26, 26))
    step = 26
    for x in range(-h * 2, W + h * 2, step):
        d.polygon([(x, y0 + h), (x + h, y0 + h), (x + 2 * h, y0), (x + h, y0)], fill=(255, 196, 0))

def warn_triangle(img, cx, cy, size):
    d = ImageDraw.Draw(img)
    pts = [(cx, cy - size * 0.58), (cx + size * 0.62, cy + size * 0.42), (cx - size * 0.62, cy + size * 0.42)]
    d.polygon(pts, fill=(255, 196, 0))
    lw = max(3, size // 14)
    d.line([(cx, cy - size * 0.22), (cx, cy + size * 0.13)], fill=(90, 8, 10), width=lw)
    r = lw * 0.9
    d.ellipse([cx - r, cy + size * 0.20 - r, cx + r, cy + size * 0.20 + r], fill=(90, 8, 10))

# ---------- 页面基图（无静态页脚，底部50px让位给动态层） ----------
def page_p2():
    img = Image.new("RGB", (W, H), (244, 246, 250))
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, 0, W, 88], fill=(31, 78, 156))
    d.text((36, 44), "园区通知", font=F(MSYHBD, 38), fill=(255, 255, 255), anchor="lm")
    d.text((W - 36, 30), "CAMPUS NOTICE", font=F(MSYH, 13), fill=(255, 255, 255, 190), anchor="rm")
    d.text((W - 36, 60), "2026-11-02  星期一", font=F(MSYH, 15), fill=(255, 255, 255), anchor="rm")
    d.rounded_rectangle([28, 116, 612, 428], radius=10, fill=(255, 255, 255), outline=(225, 230, 239), width=2)
    d.text((52, 142), "关于园区供水管道检修的通知", font=F(MSYHBD, 25), fill=(31, 41, 55), anchor="lm")
    d.text((52, 182), "发布：园区物业管理处    2026-11-02 09:30", font=F(MSYH, 14), fill=(138, 147, 166), anchor="lm")
    d.line([(52, 210), (588, 210)], fill=(237, 240, 245), width=2)
    items = [
        "检修时间：11 月 5 日（周四）09:00 – 17:00",
        "影响范围：A 座、B 座办公区域间歇停水",
        "请提前储水，检修期间请勿使用饮水设备",
    ]
    y = 244
    for it in items:
        d.ellipse([56, y - 5, 66, y + 5], fill=(31, 78, 156))
        d.text((82, y), it, font=F(MSYH, 19), fill=(51, 63, 82), anchor="lm")
        y += 50
    d.text((588, 398), "园区物业管理处", font=F(MSYH, 16), fill=(90, 107, 133), anchor="rm")
    return img

def page_p3():
    img = dgrad(W, H, (18, 59, 112), (31, 111, 178))
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([350, -150, 770, 270], fill=(255, 255, 255, 16))
    d.ellipse([-140, 340, 200, 680], fill=(255, 255, 255, 12))
    d.ellipse([430, 330, 640, 540], outline=(255, 255, 255, 60), width=3)
    d.rounded_rectangle([36, 34, 250, 66], radius=16, fill=(255, 255, 255, 42))
    d.text((143, 50), "园区活动 · CAMPUS EVENT", font=F(MSYH, 15), fill=(255, 255, 255), anchor="mm")
    d.text((48, 150), "园区科技开放日", font=F(MSYHBD, 52), fill=(255, 255, 255), anchor="lm")
    d.text((50, 218), "FPGA 创新设计大赛 · 优秀作品现场展", font=F(MSYH, 22), fill=(255, 209, 102), anchor="lm")
    d.line([(50, 262), (280, 262)], fill=(255, 209, 102), width=3)
    infos = [
        "时间：11 月 20 日 09:00 – 16:00",
        "地点：A 座一层 · 展示大厅",
        "主办：园区管委会 × 安路科技",
    ]
    y = 292
    for it in infos:
        d.rectangle([52, y - 6, 64, y + 6], fill=(255, 209, 102))
        d.text((80, y), it, font=F(MSYH, 21), fill=(255, 255, 255), anchor="lm")
        y += 38
    d.rounded_rectangle([200, 382, 440, 426], radius=22, fill=(255, 138, 61))  # 上移让位安全区
    d.text((320, 404), "欢迎莅临参观", font=F(MSYHBD, 22), fill=(255, 255, 255), anchor="mm")
    return img

def page_p4():
    img = vgrad(W, H, (192, 22, 30), (138, 14, 20))
    d = ImageDraw.Draw(img, "RGBA")
    hazard_strip(img, 0, 12)
    warn_triangle(img, 66, 84, 56)
    d.text((110, 66), "应急通知", font=F(MSYHBD, 44), fill=(255, 255, 255), anchor="lm")
    d.text((W - 36, 40), "EMERGENCY", font=F(MSYH, 15), fill=(255, 213, 213, 200), anchor="rm")
    d.text((W - 36, 66), "NOTICE", font=F(MSYH, 15), fill=(255, 213, 213, 200), anchor="rm")
    d.text((40, 168), "消防疏散演练", font=F(MSYHBD, 50), fill=(255, 255, 255), anchor="lm")
    d.line([(42, 236), (250, 236)], fill=(255, 196, 0), width=4)
    items = [
        "警报响起，立即停止手头工作",
        "沿安全通道有序撤离，切勿乘坐电梯",
        "撤至东广场集合点，按部门清点人数",
    ]
    y = 268
    for it in items:
        d.rectangle([44, y - 7, 58, y + 7], fill=(255, 196, 0))
        d.text((74, y), it, font=F(MSYH, 20), fill=(255, 255, 255), anchor="lm")
        y += 44
    d.rounded_rectangle([110, 372, 530, 418], radius=23, fill=(255, 255, 255, 240))
    d.text((320, 395), "园区应急值班（24 小时）· 内线 8888", font=F(MSYHBD, 19), fill=(179, 18, 26), anchor="mm")
    return img

# ---------- 动态层：滚动通知条 ----------
TICK_Y0, TICK_Y1 = 432, 454

def draw_ticker(img, text, offset, label="园区通知", chip=BLUE, tcol=(255, 255, 255)):
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, TICK_Y0, W, TICK_Y1], fill=(0, 0, 0, 148))
    f_label = F(MSYHBD, 12)
    lw = d.textlength(label, font=f_label)
    chip_w = int(lw) + 16
    d.rectangle([10, TICK_Y0 + 3, 10 + chip_w, TICK_Y1 - 3], fill=tuple(chip) + (255,))
    d.text((10 + chip_w / 2, (TICK_Y0 + TICK_Y1) / 2), label, font=f_label, fill=(255, 255, 255), anchor="mm")
    x0 = 10 + chip_w + 12
    f_t = F(MSYH, 14)
    unit = text + "        "
    full = unit * 2
    strip_w = int(d.textlength(full, font=f_t))
    strip = Image.new("RGBA", (strip_w + 4, TICK_Y1 - TICK_Y0), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strip)
    sd.text((2, (TICK_Y1 - TICK_Y0) / 2), full, font=f_t, fill=tuple(tcol) + (232,), anchor="lm")
    band = Image.new("RGBA", (W, TICK_Y1 - TICK_Y0), (0, 0, 0, 0))
    band.paste(strip, (x0 - offset, 0), strip)
    window = band.crop((x0, 0, W - 8, TICK_Y1 - TICK_Y0))
    img.paste(window, (x0, TICK_Y0), window)

# ---------- 动态层：OSD状态横条 ----------
BAR_Y0, BAR_Y1 = 456, 480

def draw_status_bar(img, page_str, mode="run", level=3, highlight=False):
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, BAR_Y0, W, BAR_Y1], fill=NAVY + (255,))
    ty = (BAR_Y0 + BAR_Y1) / 2
    f1 = F(MSYHBD, 13)
    f2 = F(MSYH, 12)
    # 组1：亮度
    x = 14
    d.text((x, ty), "亮度", font=f2, fill=(255, 255, 255, 200), anchor="lm")
    x += d.textlength("亮度", font=f2) + 8
    for i in range(5):
        bx = x + i * 14
        if i < level:
            d.rectangle([bx, BAR_Y0 + 6, bx + 11, BAR_Y1 - 6], fill=(255, 255, 255, 235))
        else:
            d.rectangle([bx, BAR_Y0 + 6, bx + 11, BAR_Y1 - 6], outline=(255, 255, 255, 90), width=1)
    x += 5 * 14 + 4
    if highlight:
        d.rounded_rectangle([8, BAR_Y0 + 3, x + 4, BAR_Y1 - 3], radius=4, outline=(255, 255, 255, 220), width=2)
    # 组2：显示模式（居中）
    d.text((W // 2, ty), "640×480@60Hz", font=f2, fill=(255, 255, 255, 160), anchor="mm")
    # 组3：运行状态 + 页码（右侧）
    d.text((W - 14, ty), page_str, font=f2, fill=(255, 255, 255, 200), anchor="rm")
    page_w = d.textlength(page_str, font=f2)
    if mode == "run":
        dot, label, col = GREEN, "FPGA RUN", (255, 255, 255, 200)
    else:
        dot, label, col = AMBER, "应急模式", (255, 208, 92, 235)
    lw2 = d.textlength(label, font=f2)
    d.ellipse([W - 14 - page_w - 16 - lw2 - 14, ty - 3, W - 14 - page_w - 16 - lw2 - 4, ty + 7], fill=dot)
    d.text((W - 14 - page_w - 16, ty), label, font=f2, fill=col, anchor="rm")

# ---------- 动态层：亮度调节临时指示器（2秒自动隐藏） ----------
def draw_brightness_popup(img, level=3):
    d = ImageDraw.Draw(img, "RGBA")
    f = F(MSYHBD, 20)
    label = "亮度"
    lw = d.textlength(label, font=f)
    bw, bh, gap = 16, 20, 5
    blocks_w = 5 * bw + 4 * gap
    pad = 18
    total = pad + lw + 12 + blocks_w + pad
    x0 = W // 2 - total / 2
    y0, y1 = 384, 424
    d.rounded_rectangle([x0, y0, x0 + total, y1], radius=10, fill=(0, 0, 0, 175))
    ty = (y0 + y1) / 2
    d.text((x0 + pad, ty), label, font=f, fill=(255, 255, 255), anchor="lm")
    bx = x0 + pad + lw + 12
    for i in range(5):
        if i < level:
            d.rectangle([bx, ty - bh / 2, bx + bw, ty + bh / 2], fill=(255, 255, 255, 240))
        else:
            d.rectangle([bx, ty - bh / 2, bx + bw, ty + bh / 2], outline=(255, 255, 255, 95), width=1)
        bx += bw + gap

# ---------- 生成示例图 ----------
T2 = "今日温馨提示：园区供水管道检修将于 11 月 5 日（周四）进行，请 A 座、B 座单元提前储水"
T3 = "园区科技开放日 · FPGA 创新设计大赛优秀作品展 · 时间 11 月 20 日 09:00 – 16:00 · 展位 A12 · 欢迎莅临参观"
T4 = "应急通报：消防疏散演练进行中 · 请沿安全通道有序撤离，切勿乘坐电梯 · 集合点：东广场"

imgs = {}
shutil.copyfile(os.path.join(BASE, "osd_mockups", "P1.bmp"), os.path.join(TF_OUT, "P1.bmp"))

p2 = page_p2()
p2.save(os.path.join(TF_OUT, "P2.bmp"))
img = p2.copy(); draw_ticker(img, T2, 180); draw_status_bar(img, "02/04")
img.save(os.path.join(OUT, "mockup_P2_daily_ticker.png")); imgs["P2"] = img
img.save(os.path.join(OUT, "device_preview_P2.bmp"))  # 可拷入TF卡上真机看目标效果

p3 = page_p3()
p3.save(os.path.join(TF_OUT, "P3.bmp"))
img = p3.copy(); draw_ticker(img, T3, 460); draw_status_bar(img, "03/04")
img.save(os.path.join(OUT, "mockup_P3_daily_ticker.png")); imgs["P3"] = img

p4 = page_p4()
p4.save(os.path.join(TF_OUT, "P4.bmp"))
img = p4.copy(); draw_ticker(img, T4, 40, label="应急通报", chip=REDCHIP, tcol=(255, 224, 224)); draw_status_bar(img, "04/04", mode="emergency")
img.save(os.path.join(OUT, "mockup_P4_emergency_ticker.png")); imgs["P4"] = img
img.save(os.path.join(OUT, "device_preview_P4.bmp"))

img = p2.copy(); draw_ticker(img, T2, 180); draw_status_bar(img, "02/04", highlight=True); draw_brightness_popup(img, 3)
img.save(os.path.join(OUT, "mockup_P2_brightness_adjust.png")); imgs["ADJ"] = img

detail = imgs["P3"].crop((0, 378, W, H)).resize((W * 3, (H - 378) * 3), Image.LANCZOS)
detail.save(os.path.join(OUT, "mockup_bottom_detail_3x.png"))

# ---------- 程序化QA ----------
def px(img, x, y):
    return img.getpixel((x, y))

checks = []
c = px(imgs["P2"], 5, 470); checks.append(("状态条藏青底", c, abs(c[0]-28) < 12 and abs(c[1]-44) < 12 and abs(c[2]-78) < 12))
c = px(imgs["P2"], 630, 433); base = px(p2, 630, 433); checks.append(("通知条半透明黑(带顶部无字处)", c, abs(c[0] - round(base[0]*(1-148/255))) < 12))
c = px(imgs["P2"], 12, 443); checks.append(("通知条标签章(蓝,章内左缘无字处)", c, abs(c[0]-31) < 15 and abs(c[2]-156) < 15))
c = px(imgs["P2"], 200, 470); checks.append(("状态条组间空隙仍藏青", c, abs(c[0]-28) < 12 and abs(c[2]-78) < 12))
# 亮度实心块（第一块中心）与空心块（第四块）
import math
x_lab = 14 + 24 + 8  # 近似：亮度字宽24
c_on = px(imgs["P2"], x_lab + 5, 468)
c_off = px(imgs["P2"], x_lab + 3*14 + 5, 468)
checks.append(("亮度块实/空对比", (c_on, c_off), c_on[0] > 200 and c_off[0] < 90))
c = px(imgs["P4"], 12, 443); checks.append(("应急标签章(红,章内左缘无字处)", c, c[0] > 120 and c[1] < 50))
c = px(imgs["ADJ"], 320, 390); checks.append(("临时指示器黑底", c, c[0] < 110))
ok = all(v[2] for v in checks)
for name, val, passed in checks:
    print(f"{'PASS' if passed else 'FAIL'}  {name}: {val}")
print("ALL OK" if ok else "HAS FAILURES")
for k, im in imgs.items():
    assert im.size == (W, H) and im.mode == "RGB"
print("done ->", OUT)
