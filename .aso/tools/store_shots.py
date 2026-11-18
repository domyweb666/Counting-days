# -*- coding: utf-8 -*-
"""蒜日子商店展示圖合成：模擬器截圖（1206×2622）＋大標＋描述句 → 6.3 吋與 6.9 吋兩種尺寸。

跑法（在 repo 根目錄）：
    python .aso/tools/store_shots.py
版型照茄記的上架展示圖準則（E:\\茄記\\qieji-1.1\\.aso\\上架展示圖準則.md）：
整組同一個深色漸層底（色相跟 app 圖示的橄欖綠一樣，上深下淺）；每張一句兩行大標、一句描述；
第一張是主視覺大字；付費功能排最後、標「完整版」。
"""
import os
import shutil
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = r"C:\Windows\Fonts\NotoSansTC-VF.ttf"
INK = (30, 34, 14)

# 橄欖綠：跟 app 圖示的底同一個色相，上深下淺
BG_TOP, BG_BOTTOM = (20, 26, 8), (72, 86, 24)
CREAM = (249, 242, 224)      # 大標，跟圖示上的月曆紙同色
SAGE = (214, 224, 196)       # 描述句
GOLD = (232, 200, 122)       # 第二行、完整版的標，取自圖示上的蒜頭
BEZEL = (12, 15, 5)          # 手機邊框

RAW = "design/上架截圖/原圖/"
OUT = "design/上架截圖"
ICON = "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SIZES = {"6.3": (1206, 2622), "6.9": (1320, 2868)}
FULL = "完整版"

# name 檔名｜raw 截圖｜title 大標（兩行，第二行金色）｜sub 描述句｜badge 小標｜top 手機上緣（1206 寬時的 y）
# pop 把截圖裡的一塊放大、跳出手機外：(x0, y0, x1, y1, 倍率, 圓角)，座標是截圖上的像素
SHOTS = [
    dict(name="01-hero", raw="01-月曆.png", hero=True, title=["行程一眼看完"], sub="不用搬家，也不用重記",
         pills=["iCloud、Google 都讀得到", "不用註冊", "沒有廣告"]),
    dict(name="02-calendars", raw="02-管理行事曆.png", title=["iCloud、Google", "打開就在"], sub="直接讀 iPhone 行事曆原本的行程"),
    dict(name="03-list", raw="03-清單.png", title=["哪天有事", "一眼看出來"], sub="小月曆上色，下面列出接下來的事"),
    dict(name="04-lunar", raw="04-農曆節氣.png", title=["農曆、節氣", "台灣假日"], sub="格子裡都標好了"),
    dict(name="05-new", raw="05-新增行程地點.png", title=["新增行程", "地點附地圖"], sub="搜 Apple 地圖，存回 iPhone 行事曆",
         pop=(54, 1398, 1152, 1960, 1.08, 40)),
    dict(name="06-menu", raw="06-長按選單.png", title=["長按行程", "倒數、分享"], sub="置頂、取短名、加入倒數日、傳給朋友",
         pop=(228, 1468, 980, 2150, 1.2, 72)),
    dict(name="07-agenda", raw="07-時間表.png", title=["那天下午", "有沒有空"], sub="時間表、天、3 天、週檢視"),
    dict(name="08-privacy", raw="08-權限說明.png", title=["行程只留在", "你的手機"], sub="沒有帳號，也沒有自己的伺服器"),
    dict(name="09-themes", raw="09-主題藍染.png", title=["六款主題顏色", "換成你喜歡的"], sub="點一下先試看，不喜歡就換回來", badge=FULL),
    dict(name="10-styles", raw="03b-樣式頁週條.png", title=["週條、主事件", "兩種月曆樣式"], sub="付一次一直用，沒有訂閱", badge=FULL),
]


def font(size, weight=900):
    f = ImageFont.truetype(FONT, int(size))
    f.set_variation_by_axes([weight])
    return f


def fit(d, text, size, max_w, weight=900):
    """字太長就縮到放得下。"""
    f = font(size, weight)
    while d.textlength(text, font=f) > max_w:
        size -= 2
        f = font(size, weight)
    return f


def center(d, w, y, text, f, fill):
    d.text(((w - d.textlength(text, font=f)) / 2, y), text, font=f, fill=fill)


def gradient(size):
    w, h = size
    col = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        col.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    return col.resize(size)


def mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m


def pill(d, x, y, text, f, k, fill=None, outline=None, ink=CREAM):
    tw = d.textlength(text, font=f)
    pw, ph = tw + 56 * k, f.size * 1.9
    d.rounded_rectangle([x, y, x + pw, y + ph], ph / 2, fill=fill, outline=outline, width=max(2, int(3 * k)))
    d.text((x + 28 * k, y + (ph - f.size * 1.45) / 2), text, font=f, fill=ink)
    return pw


def pill_row(d, w, y, texts, f, k, gap=22, **kw):
    widths = [d.textlength(t, font=f) + 56 * k for t in texts]
    x = (w - sum(widths) - gap * k * (len(texts) - 1)) / 2
    for t in texts:
        x += pill(d, x, y, t, f, k, **kw) + gap * k


def shadow(im, box, radius, blur, alpha=140, dy=18):
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(sh).rounded_rectangle([x0, y0 + dy, x1, y1 + dy], radius, fill=(0, 0, 0, alpha))
    return Image.alpha_composite(im.convert("RGBA"), sh.filter(ImageFilter.GaussianBlur(blur))).convert("RGB")


def compose(size, raw, title, sub, badge=None, top=None, pop=None, hero=False, pills=None, name=None):
    w, h = size
    k = w / 1206
    im = gradient(size)
    d = ImageDraw.Draw(im)
    if hero:
        # 主視覺：圖示＋名字、特大字、描述句、三顆小標
        icon = Image.open(os.path.join(ROOT, ICON)).convert("RGB").resize((int(112 * k),) * 2, Image.LANCZOS)
        fn = font(64 * k, 800)
        tw = d.textlength("蒜日子", font=fn)
        x0 = (w - (icon.width + 24 * k + tw)) / 2
        y0 = int(120 * k)
        im.paste(icon, (int(x0), y0), mask(icon.size, int(26 * k)))
        d.text((x0 + icon.width + 24 * k, y0 + (icon.height - fn.size * 1.45) / 2), "蒜日子", font=fn, fill=CREAM)
        center(d, w, 270 * k, title[0], fit(d, title[0], 200 * k, w * 0.92), CREAM)
        center(d, w, 600 * k, sub, fit(d, sub, 80 * k, w * 0.9, 700), GOLD)
        pf = font(40 * k, 700)
        while sum(d.textlength(t, font=pf) + 56 * k for t in pills) + 44 * k > w * 0.94:
            pf = font(pf.size - 2, 700)
        pill_row(d, w, 770 * k, pills, pf, k, outline=SAGE, ink=CREAM)
        top = top or 960
    else:
        # 兩行大標（第二行金色）、一句描述、要的話一顆小標
        size_t = min(fit(d, t, 138 * k, w * 0.9).size for t in title)
        ft = font(size_t)
        y = 96 * k
        for i, t in enumerate(title):
            center(d, w, y, t, ft, GOLD if i == len(title) - 1 and len(title) > 1 else CREAM)
            y += size_t * 1.2
        y += 44 * k
        center(d, w, y, sub, fit(d, sub, 56 * k, w * 0.9, 500), SAGE)
        y += 110 * k
        if badge:
            pill_row(d, w, y, [badge], font(42 * k, 800), k, fill=GOLD, ink=INK)
            y += 120 * k
        top = top or (y / k + 40)
    shot = Image.open(os.path.join(ROOT, RAW, raw)).convert("RGB")
    sc = 1000 * k / shot.width            # 手機畫面放大到 1000 寬，底部出血
    pw, ph = int(shot.width * sc), int(shot.height * sc)
    x, y = (w - pw) // 2, int(top * k)
    r, b = int(92 * k), int(18 * k)
    im = shadow(im, (x - b, y - b, x + pw + b, y + ph + b), r + b, int(w * 0.025))
    ImageDraw.Draw(im).rounded_rectangle([x - b, y - b, x + pw + b, y + ph + b], r + b, fill=BEZEL)
    im.paste(shot.resize((pw, ph), Image.LANCZOS), (x, y), mask((pw, ph), r))
    if pop:
        # 把重點那一塊放大，疊在原位置上，超出手機邊框
        x0, y0, x1, y1, zoom, rad = pop
        piece = shot.crop((x0, y0, x1, y1))
        qw, qh = int(piece.width * sc * zoom), int(piece.height * sc * zoom)
        cx, cy = x + (x0 + x1) / 2 * sc, y + (y0 + y1) / 2 * sc
        qx = int(min(max(cx - qw / 2, 14 * k), w - qw - 14 * k))
        qy = int(min(cy - qh / 2, h - qh - 40 * k))
        qr = int(rad * sc * zoom)
        im = shadow(im, (qx, qy, qx + qw, qy + qh), qr, int(w * 0.022), alpha=160, dy=24)
        im.paste(piece.resize((qw, qh), Image.LANCZOS), (qx, qy), mask((qw, qh), qr))
    return im


if __name__ == "__main__":
    for label, size in SIZES.items():
        out_dir = os.path.join(ROOT, OUT, label)
        shutil.rmtree(out_dir, ignore_errors=True)
        os.makedirs(out_dir)
        for s in SHOTS:
            compose(size, **s).save(os.path.join(out_dir, s["name"] + ".jpg"), quality=93)
    # 總覽：一排五張，給人看
    W = 400
    H = int(W * 2622 / 1206)
    names = [s["name"] for s in SHOTS]
    for part, group in (("a", names[:5]), ("b", names[5:])):
        sheet = Image.new("RGB", (W * len(group) + 12 * (len(group) - 1), H), (245, 245, 245))
        for i, n in enumerate(group):
            sheet.paste(Image.open(os.path.join(ROOT, OUT, "6.3", n + ".jpg")).resize((W, H), Image.LANCZOS), (i * (W + 12), 0))
        sheet.save(os.path.join(ROOT, OUT, f"預覽總覽-{part}.jpg"), quality=90)
    print("done", len(SHOTS), "張 ×", len(SIZES))
