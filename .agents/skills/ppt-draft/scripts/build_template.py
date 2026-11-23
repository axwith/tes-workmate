#!/usr/bin/env python3
"""TES 내부용 공통 PPT 템플릿(편집 가능). 디자인 규칙은 DESIGN-GUIDE.md.

TES IR 장표의 정보 구조(섹션 머리말 · 짧은 소제목 · 패널 2~3개에 차트·설명·표 · 아래 결론 띠)를
그대로 쓰고, 정렬·여백·글자 위계·패널 모양을 정리했다.
  - 머리말: 섹션 번호(하늘색)+섹션 이름(네이비), 오른쪽 로고, 아래 가는 선.
  - 제목: 그 장의 핵심만 짧게 한 줄(26pt 네이비). 설명·수치는 패널 안 본문에 자세히.
  - 본문: 흰 패널(가는 테두리) 안에 패널 제목 + 내용. 12열 그리드, 여백 64px, 간격 24px.
  - 결론 띠: 숫자가 있는 장 아래 네이비 띠에 결론 한 문장.
  - 바닥: 출처(왼쪽), 쪽번호(오른쪽).

사용: python3 build_template.py <출력.pptx> [--assets <assets 폴더>]
"""
import argparse
from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Emu, Pt

# ---- 색 ----
INK = RGBColor(0x1F, 0x26, 0x33)        # 본문
MUTED = RGBColor(0x5F, 0x67, 0x75)      # 보조 글
FAINT = RGBColor(0x9C, 0xA3, 0xAF)      # 출처·쪽번호
LINE = RGBColor(0xD6, 0xDE, 0xEA)       # 패널 테두리·표 선
HAIR = RGBColor(0xE6, 0xEB, 0xF2)       # 옅은 선
PANEL = RGBColor(0xF5, 0xF8, 0xFC)      # 옅은 패널 면
GREY = RGBColor(0xC5, 0xCD, 0xD8)       # 비교 계열 막대
NAVY = RGBColor(0x2A, 0x33, 0x66)       # TES 네이비 — 머리말·띠·패널 제목
BLUE = RGBColor(0x00, 0x63, 0xA8)       # TES 블루 — 강조 계열
BLUE_SOFT = RGBColor(0xDE, 0xEB, 0xF7)  # 표 머리·강조 면 (TES IR 표 색)
SKY = RGBColor(0x12, 0xBD, 0xF3)        # TES 하늘색 — 섹션 번호
RULE = RGBColor(0xBD, 0xD7, 0xEE)       # 머리말 아래 선 (TES IR)
HL = RGBColor(0xFF, 0xF1, 0xCC)         # 표 최신 열 (TES IR 노랑)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
FONT = '맑은 고딕'

# ---- 그리드 (1920×1080, 1px = 0.5pt) ----
W, H = 1920, 1080
M = 64
GUT = 24
COLW = (W - 2 * M - 11 * GUT) / 12
HEAD_Y, TITLE_Y, BODY_Y = 40, 150, 250
BAND_Y, BAND_H = 892, 72          # 결론 띠
FOOT_Y = 1000
BODY_BOTTOM = BAND_Y - 24         # 띠가 있을 때 본문 아래 끝
BODY_BOTTOM_FULL = FOOT_Y - 32    # 띠가 없을 때


def px(v):
    return Emu(int(v * 6350))


def col(i, span=1):
    """12열 그리드의 i번째 열(0부터) x좌표와 span 폭."""
    x = M + i * (COLW + GUT)
    return x, span * COLW + (span - 1) * GUT


def _char_w(ch, size_px):
    """글자 하나의 대략 폭(px). 한글·한자 1.0, 영문·숫자 0.58, 공백 0.3, 기호 0.4."""
    o = ord(ch)
    if ch == ' ':
        return size_px * 0.3
    if o >= 0x1100:
        return size_px * 1.0
    if ch.isalnum():
        return size_px * 0.58
    return size_px * 0.4


def count_lines(value, w, size_pt, bold=False, report=None):
    """단어 단위 줄바꿈을 흉내 내 줄 수를 센다(PowerPoint 렌더와 ±1 이내).
    report 리스트를 주면 자동 줄바꿈 뒤 끝줄이 너무 짧은 경우(한 단어만 떨어짐)를 적는다."""
    size_px = size_pt * 2 * (1.05 if bold else 1.0)
    total = 0
    for para in (value if isinstance(value, list) else [value]):
        for chunk in str(para).split('\n'):
            n, cur = 1, 0.0
            for word in chunk.split(' '):
                ww = sum(_char_w(c, size_px) for c in word)
                sp = _char_w(' ', size_px) if cur else 0
                if cur and cur + sp + ww > w:
                    n, cur = n + 1, ww
                else:
                    cur += sp + ww
            if n > 1 and cur < w * 0.3 and report is not None:
                report.append(chunk)
            total += n
    return total


# 템플릿 견본 문구. 초안에 남아 있으면 save()가 경고한다.
PLACEHOLDERS = ('입력하세요', '한 줄로', '두 줄로', '세 줄로', '섹션 이름', '섹션 제목', '패널 제목', '요점 제목',
                '지표 이름', '할 일을', '하는 일을', '주요 일정', '0,000', '00%', '자리', '핵심을 짧게')


class Deck:
    def __init__(self, assets):
        a = Path(assets)
        self.prs = Presentation()
        self.prs.slide_width = px(W)
        self.prs.slide_height = px(H)
        self.logo = a / 'tes-logo.png'
        self.icons = a / 'icons'
        self.img = {k: a / f'{k}.png' for k in ('cover-photo', 'wafer', 'section-bg', 'closing-photo')}
        self.page = 0
        self.section = ('01', '섹션 이름')
        self.source = '출처: 출처를 입력하세요  |  원자료: 파일 경로'   # 덱 전체 기본 출처
        self.warnings = []

    # ---------- 기본 요소 ----------
    def slide(self):
        s = self.prs.slides.add_slide(self.prs.slide_layouts[6])
        self.page += 1
        return s

    def box(self, s, x, y, w, h, fill, shape=MSO_SHAPE.RECTANGLE, line=None, radius=None):
        r = s.shapes.add_shape(shape, px(x), px(y), px(w), px(h))
        if fill is None:
            r.fill.background()
        else:
            r.fill.solid()
            r.fill.fore_color.rgb = fill
        if line is None:
            r.line.fill.background()
        else:
            r.line.color.rgb = line
            r.line.width = Pt(0.75)
        if radius is not None and shape == MSO_SHAPE.ROUNDED_RECTANGLE:
            r.adjustments[0] = radius
        r.shadow.inherit = False
        return r

    def text(self, s, value, x, y, w, h, size, color=INK, bold=False, align=PP_ALIGN.LEFT,
             anchor=MSO_ANCHOR.TOP, spacing=1.2, runs=None, wrap=True, lines=None, what='글'):
        if lines and value:
            short = []
            if count_lines(value, w, size, bold, short) > lines:
                self.warnings.append(f'{self.page}장 {what} {lines}줄 넘침: "{value}"')
            elif short:
                self.warnings.append(f'{self.page}장 {what} 끝줄에 한 단어만 떨어짐(줄이거나 \\n으로 직접 나누기): "{value}"')
        tb = s.shapes.add_textbox(px(x), px(y), px(w), px(h))
        tf = tb.text_frame
        tf.word_wrap = wrap
        tf.vertical_anchor = anchor
        tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
        paras = value if isinstance(value, list) else [value]
        for i, line in enumerate(paras):
            p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
            p.alignment = align
            p.line_spacing = spacing
            for txt, c, b in (runs if (runs and i == 0) else [(line, color, bold)]):
                r = p.add_run()
                r.text = txt
                r.font.name = FONT
                r.font.size = Pt(size)
                r.font.bold = b
                r.font.color.rgb = c
                r.font._rPr.set('lang', 'ko-KR')
        return tb

    def hline(self, s, x1, x2, y, color=HAIR, width=0.75):
        c = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, px(x1), px(y), px(x2), px(y))
        c.line.color.rgb = color
        c.line.width = Pt(width)
        return c

    def picture(self, s, key, x, y, w, h, crop=None):
        f = self.img.get(key)
        if not f or not f.exists():
            self.box(s, x, y, w, h, PANEL)
            return None
        pic = s.shapes.add_picture(str(f), px(x), px(y), px(w), px(h))
        for k, v in (crop or {}).items():
            setattr(pic, f'crop_{k}', v)
        return pic

    def fit_image(self, s, path, x, y, w, h):
        """비율을 지켜 (x, y, w, h) 칸 안에 가운데 맞춘다."""
        pic = s.shapes.add_picture(str(path), px(x), px(y), width=px(w))
        if pic.height > px(h):
            ratio = px(h) / pic.height
            pic.height = px(h)
            pic.width = int(pic.width * ratio)
            pic.left = px(x) + (px(w) - pic.width) // 2
        else:
            pic.top = px(y) + (px(h) - pic.height) // 2
        return pic

    def logo_at(self, s, x, y, w):
        if self.logo.exists():
            s.shapes.add_picture(str(self.logo), px(x), px(y), width=px(w))

    def icon_at(self, s, name, x, y, size):
        f = self.icons / f'{name}.png'
        if f.exists():
            s.shapes.add_picture(str(f), px(x), px(y), width=px(size))

    # ---------- 본문 장의 공통 틀 ----------
    def frame(self, s, title, sub=None, source: str | None = ''):
        no, name = self.section
        # 머리말: 섹션 번호 + 섹션 이름, 오른쪽 로고, 아래 선 (TES IR 구조)
        self.text(s, '', M, HEAD_Y, 1400, 60, 26, runs=[(f'{no} ', SKY, True), (name, NAVY, True)],
                  anchor=MSO_ANCHOR.MIDDLE)
        self.logo_at(s, W - M - 118, HEAD_Y - 6, 118)
        self.hline(s, M, W - M, 120, RULE, 1.5)
        # 제목: 핵심만 한 줄
        self.text(s, title, M, TITLE_Y, W - 2 * M - 640, 50, 26, NAVY, True, anchor=MSO_ANCHOR.MIDDLE,
                  lines=1, what='제목')
        if sub:  # 지표 정의·기간·단위는 제목 오른쪽 끝에 작게
            self.text(s, sub, W - M - 620, TITLE_Y, 620, 50, 14, MUTED, align=PP_ALIGN.RIGHT,
                      anchor=MSO_ANCHOR.MIDDLE, lines=1, what='지표 정의')
        # 바닥: 출처(왼쪽), 쪽번호(오른쪽)
        source = self.source if source == '' else source
        if source:
            self.text(s, source, M, FOOT_Y + 24, 1500, 30, 11, FAINT)
        self.text(s, f'{self.page}', W - M - 60, FOOT_Y + 24, 60, 30, 11, FAINT, align=PP_ALIGN.RIGHT)

    def band(self, s, msg):
        """숫자가 있는 장 아래 결론 띠(TES IR 방식, 네이비)."""
        self.box(s, M, BAND_Y, W - 2 * M, BAND_H, NAVY, MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.12)
        self.text(s, msg, M + 32, BAND_Y, W - 2 * M - 64, BAND_H, 20, WHITE, True, anchor=MSO_ANCHOR.MIDDLE,
                  lines=1, what='결론 띠')

    def panel(self, s, x, y, w, h, head=None, fill=WHITE):
        """흰 패널 + 패널 제목(네이비 굵게, 왼쪽 파란 막대). 내용 시작 y를 돌려준다."""
        self.box(s, x, y, w, h, fill, MSO_SHAPE.ROUNDED_RECTANGLE, line=LINE, radius=0.03)
        if not head:
            return y + 28
        self.box(s, x + 28, y + 28, 6, 30, BLUE)
        self.text(s, head, x + 46, y + 24, w - 74, 40, 20, NAVY, True, anchor=MSO_ANCHOR.MIDDLE,
                  lines=1, what='패널 제목')
        return y + 84

    def bullets(self, s, points, x, y, w, size=18, gap=20, numbered=False, max_lines=3, what='설명'):
        """설명 항목. 각 항목은 max_lines줄까지. 다음 항목 y를 실제 줄 수에 맞춰 내린다."""
        line_h = size * 2 * 1.3
        for i, p in enumerate(points):
            n = min(count_lines(p, w - 40, size), max_lines)
            if numbered:
                self.box(s, x, y + 3, 28, 28, BLUE, MSO_SHAPE.OVAL)
                self.text(s, str(i + 1), x, y + 3, 28, 28, 13, WHITE, True, PP_ALIGN.CENTER, MSO_ANCHOR.MIDDLE)
            else:
                self.box(s, x + 6, y + line_h / 2 - 4, 8, 8, BLUE)
            self.text(s, p, x + 40, y, w - 40, n * line_h + 4, size, INK, spacing=1.3,
                      lines=max_lines, what=what)
            y += n * line_h + gap
        return y

    # ================= 장표 =================
    def cover(self, title='보고서 제목을\n입력하세요', subtitle='보고 대상 또는 목적',
              meta='부서명  ·  작성자  ·  2026. 00. 00.', style='photo'):
        """표지. 제목은 보고서 이름(기간+대상+보고 종류). style='photo'(기본) 또는 'wafer'."""
        s = self.slide()
        if style == 'wafer':
            self.picture(s, 'wafer', 1180, 120, 740, 860, {'left': 0.63, 'top': 0.08, 'bottom': 0.12})
        else:
            self.picture(s, 'cover-photo', 1060, 0, 860, H)
            self.box(s, 1060, 0, 380, H, WHITE, MSO_SHAPE.RIGHT_TRIANGLE)
        self.logo_at(s, M + 32, 80, 150)
        self.text(s, title, M + 32, 250, 940, 380, 48, NAVY, True, anchor=MSO_ANCHOR.BOTTOM, spacing=1.1,
                  lines=2, what='표지 제목')
        self.box(s, M + 32, 656, 860, 3, NAVY)
        self.text(s, subtitle, M + 32, 680, 880, 110, 24, MUTED, spacing=1.3, lines=2, what='표지 부제')
        self.text(s, meta, M + 32, 940, 900, 40, 16, MUTED)
        return s

    def agenda(self, items=None, current=None):
        """목차. current: 지금 섹션 번호(1부터)를 주면 그 항목만 강조."""
        items = items or ['첫 번째 장 제목', '두 번째 장 제목', '세 번째 장 제목', '네 번째 장 제목']
        s = self.slide()
        self.box(s, 0, 0, 640, H, NAVY)
        self.text(s, 'CONTENTS', M + 32, 140, 520, 80, 40, WHITE, True)
        self.text(s, '목차', M + 32, 240, 520, 50, 22, RGBColor(0xC9, 0xD6, 0xEE))
        self.box(s, M + 34, 316, 64, 5, SKY)
        self.box(s, M + 20, 900, 174, 104, WHITE, MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.1)
        self.logo_at(s, M + 32, 912, 150)
        n = len(items[:6])
        rowh = 120
        top = (H - n * rowh) / 2
        x2, w2 = 760, W - 760 - M - 40
        for i, item in enumerate(items[:6]):
            y = top + i * rowh
            on = current == i + 1
            dim = current is not None and not on
            self.text(s, f'{i + 1:02d}', x2, y, 120, rowh, 34, SKY if not dim else GREY, True,
                      anchor=MSO_ANCHOR.MIDDLE)
            self.text(s, item, x2 + 130, y, w2 - 130, rowh, 28, MUTED if dim else NAVY, True,
                      anchor=MSO_ANCHOR.MIDDLE, lines=1, what='목차')
            self.hline(s, x2, x2 + w2, y + rowh, HAIR)
        return s

    def section_divider(self, no='01', title='섹션 제목', desc='이 섹션에서 다룰 내용을 한 줄로'):
        self.section = (no, title)
        s = self.slide()
        self.picture(s, 'section-bg', 0, 0, W, H)
        self.text(s, no, M + 32, 470, 300, 110, 80, SKY, True)
        self.text(s, title, M + 32, 600, 1400, 120, 56, WHITE, True, lines=1, what='섹션 제목')
        self.box(s, M + 34, 730, 64, 5, WHITE)
        self.text(s, desc, M + 32, 760, 1300, 50, 22, RGBColor(0xC9, 0xD6, 0xEE), lines=1, what='섹션 설명')
        return s

    def chart(self, title='핵심을 짧게', sub='지표 정의 · 단위 · 기간', labels=None, values=None,
              highlight=-1, chart_head='차트 제목', points=None, points_head='주요 내용', unit='',
              band='결론 한 줄로'):
        """왼쪽 차트 패널(8열) + 오른쪽 설명 패널(4열) + 아래 결론 띠 (TES IR 15쪽 구조).
        highlight: 파랑으로 강조할 막대 위치(나머지 회색). points=[]이면 차트만 넓게."""
        from pptx.chart.data import CategoryChartData
        from pptx.enum.chart import XL_CHART_TYPE, XL_LABEL_POSITION
        labels = labels or ['1월', '2월', '3월', '4월', '5월', '6월']
        values = values or [42, 48, 51, 55, 60, 72]
        points = ['설명을 두세 줄로 씁니다. 수치와 비교 대상, 그 뜻까지 적습니다.'] * 3 if points is None else points
        hi = highlight % len(values)
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        span = 8 if points else 12
        x, w = col(0, span)
        cy = self.panel(s, x, BODY_Y, w, bottom - BODY_Y, chart_head)
        data = CategoryChartData()
        data.categories = labels
        data.add_series('값', values)
        gf = s.shapes.add_chart(XL_CHART_TYPE.COLUMN_CLUSTERED, px(x + 40), px(cy), px(w - 80),  # type: ignore[arg-type]
                                px(bottom - cy - 28), data)
        ch = gf.chart  # type: ignore[attr-defined]
        ch.has_legend = False
        ch.has_title = False
        ch.font.name = FONT
        ch.font.size = Pt(14)
        ch.font.color.rgb = MUTED
        plot = ch.plots[0]
        plot.gap_width = 70
        plot.has_data_labels = True
        dl = plot.data_labels
        dl.font.size = Pt(16)
        dl.font.bold = True
        dl.font.color.rgb = INK
        dl.position = XL_LABEL_POSITION.OUTSIDE_END
        if unit:
            dl.number_format = f'0.00"{unit}"' if any(isinstance(v, float) for v in values) else f'#,##0"{unit}"'
            dl.number_format_is_linked = False
        ser = plot.series[0]
        ser.format.fill.solid()
        ser.format.fill.fore_color.rgb = GREY
        pt = ser.points[hi]
        pt.format.fill.solid()
        pt.format.fill.fore_color.rgb = BLUE
        ch.value_axis.visible = False
        ch.value_axis.has_major_gridlines = False
        ca = ch.category_axis
        ca.format.line.color.rgb = LINE
        ca.tick_labels.font.size = Pt(16)
        ca.tick_labels.font.color.rgb = INK
        if points:
            x2, w2 = col(8, 4)
            py = self.panel(s, x2, BODY_Y, w2, bottom - BODY_Y, points_head)
            self.bullets(s, points, x2 + 28, py + 8, w2 - 56, numbered=True, max_lines=4, gap=28)
        if band:
            self.band(s, band)
        return s

    def kpi(self, title='핵심을 짧게', sub='기간 · 기준', items=None, highlight=0, points=None,
            points_head='수치 해석', band='결론 한 줄로'):
        """핵심 수치 카드 3~4개(위) + 해석 패널(아래) + 결론 띠 (TES IR 18쪽 개선).
        items: (지표 이름, 값, 증감) 튜플."""
        items = items or [('지표 이름', '0,000', '+0.0% 전년 대비')] * 4
        points = points if points is not None else ['수치가 뜻하는 것을 설명합니다. 비교 대상과 이유를 함께 적습니다.'] * 2
        s = self.slide()
        self.frame(s, title, sub)
        n = len(items[:4])
        cw = (W - 2 * M - (n - 1) * GUT) / n
        ch_ = 250
        for i, (label, value, delta) in enumerate(items[:4]):
            x = M + i * (cw + GUT)
            on = i == highlight
            self.box(s, x, BODY_Y, cw, ch_, BLUE_SOFT if on else WHITE, MSO_SHAPE.ROUNDED_RECTANGLE,
                     line=None if on else LINE, radius=0.05)
            self.text(s, label, x + 32, BODY_Y + 28, cw - 64, 36, 18, NAVY if on else MUTED, True,
                      lines=1, what='지표 이름')
            self.text(s, value, x + 32, BODY_Y + 70, cw - 64, 96, 44, BLUE if on else INK, True, wrap=False)
            self.text(s, delta, x + 32, BODY_Y + 190, cw - 64, 36, 18, BLUE if on else MUTED, True,
                      lines=1, what='증감')
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        py0 = BODY_Y + ch_ + GUT
        if points:
            py = self.panel(s, M, py0, W - 2 * M, bottom - py0, points_head)
            half = (len(points) + 1) // 2
            cw2 = (W - 2 * M - 56 - 48) / 2
            self.bullets(s, points[:half], M + 28, py, cw2, max_lines=2)
            if points[half:]:
                self.bullets(s, points[half:], M + 28 + cw2 + 48, py, cw2, max_lines=2)
        if band:
            self.band(s, band)
        return s

    def table(self, title='핵심을 짧게', sub='(단위: 입력)', header=None, rows=None, hl_col=3, total_row=True,
              table_head='표 제목', notes=None, notes_head='주요 내용', band='결론 한 줄로'):
        """왼쪽 표 패널(8열) + 오른쪽 설명 패널(4열) + 결론 띠 (TES IR 20쪽 개선).
        hl_col: 노랑으로 채울 최신 열 번호. notes=[]이면 표만 넓게."""
        header = header or ['구분', '기간 1', '기간 2', '기간 3', '증감']
        rows = rows or [['항목'] + ['0,000'] * 3 + ['+0%'] for _ in range(4)] + [['합계'] + ['0,000'] * 3 + ['+0%']]
        notes = ['표에서 봐야 할 변화를 설명합니다. 어느 행·열이 왜 중요한지 적습니다.'] * 2 if notes is None else notes
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        span = 8 if notes else 12
        x0, w0 = col(0, span)
        ty = self.panel(s, x0, BODY_Y, w0, bottom - BODY_Y, table_head)
        nc = len(header)
        tx, tw = x0 + 28, w0 - 56
        lw = tw * 0.26
        cw = (tw - lw) / (nc - 1)
        rh = min(64, (bottom - ty - 28) / (len(rows) + 1))
        xs = [tx] + [tx + lw + i * cw for i in range(nc - 1)]
        ws = [lw] + [cw] * (nc - 1)
        self.box(s, tx, ty, tw, rh, BLUE_SOFT)
        self.box(s, xs[hl_col], ty, ws[hl_col], rh * (len(rows) + 1), HL)
        for c, h in enumerate(header):
            self.text(s, h, xs[c] + 14, ty, ws[c] - 28, rh, 17, NAVY, True,
                      PP_ALIGN.LEFT if c == 0 else PP_ALIGN.RIGHT, MSO_ANCHOR.MIDDLE, lines=1, what='표 머리')
        for r, row in enumerate(rows):
            y = ty + rh * (r + 1)
            last = total_row and r == len(rows) - 1
            if last:
                self.hline(s, tx, tx + tw, y, NAVY, 1.25)
            for c, v in enumerate(row):
                self.text(s, v, xs[c] + 14, y, ws[c] - 28, rh, 17, INK, last or c == 0,
                          PP_ALIGN.LEFT if c == 0 else PP_ALIGN.RIGHT, MSO_ANCHOR.MIDDLE, lines=1, what='표 칸')
            if not last:
                self.hline(s, tx, tx + tw, y + rh, HAIR)
        if notes:
            x2, w2 = col(8, 4)
            py = self.panel(s, x2, BODY_Y, w2, bottom - BODY_Y, notes_head)
            self.bullets(s, notes, x2 + 28, py + 8, w2 - 56, numbered=True, max_lines=4, gap=28)
        if band:
            self.band(s, band)
        return s

    def two_column(self, title='핵심을 짧게', sub=None, points=None, points_head='주요 내용', image=None,
                   image_head='그림 제목', caption='그림 설명', band='결론 한 줄로'):
        """왼쪽 설명 패널(5열) + 오른쪽 그림 패널(7열, 그래프 PNG·도식·사진) + 결론 띠."""
        points = points or ['설명을 두세 줄로 씁니다. 수치와 비교 대상, 그 뜻까지 적습니다.'] * 3
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        x, w = col(0, 5)
        py = self.panel(s, x, BODY_Y, w, bottom - BODY_Y, points_head)
        self.bullets(s, points, x + 28, py + 8, w - 56, numbered=True, max_lines=4, gap=28)
        x2, w2 = col(5, 7)
        iy = self.panel(s, x2, BODY_Y, w2, bottom - BODY_Y, image_head)
        ih = bottom - iy - 70
        if image and Path(image).exists():
            self.fit_image(s, image, x2 + 28, iy, w2 - 56, ih)
        else:
            self.box(s, x2 + 28, iy, w2 - 56, ih, PANEL)
            self.text(s, '그래프·도식·사진 자리', x2 + 28, iy, w2 - 56, ih, 18, FAINT, align=PP_ALIGN.CENTER,
                      anchor=MSO_ANCHOR.MIDDLE)
        self.text(s, caption, x2 + 28, bottom - 56, w2 - 56, 30, 14, MUTED, lines=1, what='그림 설명')
        if band:
            self.band(s, band)
        return s

    def image_pair(self, title='핵심을 짧게', sub=None, left=None, right=None, band='결론 한 줄로'):
        """그림 패널 두 개를 나란히(예: 왼쪽 생성 이미지로 '무엇인지', 오른쪽 그래프로 '얼마나').
        left·right: (패널 제목, PNG 경로, 그림 설명 한 줄, [짧은 설명 1~2개]).
        그림만 두지 말고 그림 아래에 무엇을 봐야 하는지 짧게 설명한다."""
        left = left or ('왼쪽 그림 제목', None, '그림 설명', ['그림에서 봐야 할 점을 한두 줄로 씁니다.'])
        right = right or ('오른쪽 그림 제목', None, '그림 설명', ['그림에서 봐야 할 점을 한두 줄로 씁니다.'])
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        for i, (head, image, caption, *rest) in enumerate((left, right)):
            desc = rest[0] if rest else []
            x, w = col(i * 6, 6)
            iy = self.panel(s, x, BODY_Y, w, bottom - BODY_Y, head)
            dh = sum(min(count_lines(d, w - 96, 17), 2) * 44 + 12 for d in desc)
            ih = bottom - iy - 28 - dh
            if desc:
                self.bullets(s, desc, x + 28, iy + ih + 16, w - 56, size=17, gap=12, max_lines=2)
            if image and Path(image).exists():
                self.fit_image(s, image, x + 28, iy, w - 56, ih)
            else:
                self.box(s, x + 28, iy, w - 56, ih, PANEL)
                self.text(s, '그래프·도식·사진 자리', x + 28, iy, w - 56, ih, 18, FAINT, align=PP_ALIGN.CENTER,
                          anchor=MSO_ANCHOR.MIDDLE)
            # 그림 설명은 패널 제목 줄 오른쪽에 작게(그림 자리를 넓게 쓰기 위해)
            self.text(s, caption, x + w / 2, BODY_Y + 24, w / 2 - 28, 40, 13, MUTED, align=PP_ALIGN.RIGHT,
                      anchor=MSO_ANCHOR.MIDDLE, lines=1, what='그림 설명')
        if band:
            self.band(s, band)
        return s

    def two_panels(self, title='핵심을 짧게', sub=None, left=None, right=None, band='결론 한 줄로'):
        """패널 두 개를 나란히(TES IR 19쪽 '실적 / 향후 전망' 구조).
        left·right: (패널 제목, [설명 항목…])."""
        left = left or ('왼쪽 패널 제목', ['설명을 두 줄로 씁니다. 수치와 비교 대상, 그 뜻까지 적습니다.'] * 3)
        right = right or ('오른쪽 패널 제목', ['설명을 두 줄로 씁니다. 수치와 비교 대상, 그 뜻까지 적습니다.'] * 3)
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        for i, (head, pts) in enumerate((left, right)):
            x, w = col(i * 6, 6)
            py = self.panel(s, x, BODY_Y, w, bottom - BODY_Y, head)
            self.bullets(s, pts, x + 28, py + 8, w - 56, max_lines=3, gap=24)
        if band:
            self.band(s, band)
        return s

    def statement(self, title='핵심을 짧게', sub=None, points=None, points_head='확인 내용', big='00%',
                  big_label='큰 숫자 이름', big_detail=None, band=None):
        """왼쪽 번호 설명 패널(8열) + 오른쪽 핵심 수치 카드(4열)."""
        points = points or ['설명을 두 줄로 씁니다. 수치와 비교 대상, 그 뜻까지 적습니다.'] * 3
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        x, w = col(0, 8)
        py = self.panel(s, x, BODY_Y, w, bottom - BODY_Y, points_head)
        self.bullets(s, points, x + 28, py + 12, w - 56, numbered=True, max_lines=3, gap=36)
        x2, w2 = col(8, 4)
        self.box(s, x2, BODY_Y, w2, bottom - BODY_Y, BLUE_SOFT, MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.03)
        self.text(s, big_label, x2 + 40, BODY_Y + 56, w2 - 80, 40, 20, NAVY, True, lines=1, what='큰 숫자 이름')
        self.text(s, big, x2 + 40, BODY_Y + 110, w2 - 80, 160, 88, BLUE, True, wrap=False)
        if big_detail:
            self.hline(s, x2 + 40, x2 + w2 - 40, BODY_Y + 300, RULE, 1)
            self.text(s, big_detail, x2 + 40, BODY_Y + 330, w2 - 80, 220, 18, INK, spacing=1.4,
                      lines=5, what='큰 숫자 설명')
        if band:
            self.band(s, band)
        return s

    def three_points(self, title='핵심을 짧게', sub=None, items=None, icons=None, band=None):
        """카드 3개: 아이콘 + 요점 제목 + 설명 3~5줄."""
        items = items or [('요점 제목', '요점을 세 줄 안으로 설명합니다. 근거 수치와 그 뜻을 함께 적습니다.')] * 3
        icons = icons or ['target', 'chart-column', 'circle-check']
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        for i, (head, body) in enumerate(items[:3]):
            x, w = col(i * 4, 4)
            self.box(s, x, BODY_Y, w, bottom - BODY_Y, WHITE, MSO_SHAPE.ROUNDED_RECTANGLE, line=LINE, radius=0.03)
            self.box(s, x + 36, BODY_Y + 44, 96, 96, BLUE_SOFT, MSO_SHAPE.OVAL)
            self.icon_at(s, icons[i % len(icons)], x + 60, BODY_Y + 68, 48)
            self.text(s, f'0{i + 1}', x + w - 100, BODY_Y + 44, 64, 40, 20, SKY, True, PP_ALIGN.RIGHT)
            self.text(s, head, x + 36, BODY_Y + 168, w - 72, 50, 24, NAVY, True, lines=1, what='요점 제목')
            self.hline(s, x + 36, x + w - 36, BODY_Y + 232, HAIR)
            self.text(s, body, x + 36, BODY_Y + 256, w - 72, bottom - BODY_Y - 290, 18, INK, spacing=1.4,
                      lines=6, what='요점 설명')
        if band:
            self.band(s, band)
        return s

    def process(self, title='핵심을 짧게', sub=None, steps=None, active=1, band=None):
        """단계 화살표 + 단계별 설명. active: 지금 단계(0부터)."""
        steps = steps or [(f'{i}단계', '이 단계에서 하는 일을 두세 줄로 씁니다.') for i in range(1, 5)]
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        n = len(steps)
        w = (W - 2 * M - (n - 1) * 12) / n
        for i, (head, body) in enumerate(steps):
            x = M + i * (w + 12)
            on = i == active
            shape = MSO_SHAPE.PENTAGON if i == 0 else MSO_SHAPE.CHEVRON
            self.box(s, x, BODY_Y, w + 30 if i < n - 1 else w, 90,
                     BLUE if on else (NAVY if i < active else BLUE_SOFT), shape)
            self.text(s, head, x + 48, BODY_Y, w - 70, 90, 22, WHITE if i <= active else NAVY, True,
                      anchor=MSO_ANCHOR.MIDDLE, lines=1, what='단계 이름')
            self.box(s, x, BODY_Y + 112, w, bottom - BODY_Y - 112, WHITE if on else PANEL,
                     MSO_SHAPE.ROUNDED_RECTANGLE, line=BLUE if on else LINE, radius=0.04)
            self.text(s, body, x + 28, BODY_Y + 140, w - 56, bottom - BODY_Y - 160, 18, INK, spacing=1.4,
                      lines=8, what='단계 설명')
        if band:
            self.band(s, band)
        return s

    def timeline(self, title='핵심을 짧게', sub=None, points=None, current=2, band=None):
        """일정 막대 + 시점별 설명 카드. points: (날짜, 제목, 설명). current: 지금 시점(0부터)."""
        points = points or [(f'2026.{m:02d}', '주요 일정', '내용을 두세 줄로 씁니다.') for m in (1, 4, 7, 10)]
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        n = len(points)
        w = (W - 2 * M - (n - 1) * GUT) / n
        y = BODY_Y + 50
        self.hline(s, M, W - M, y, LINE, 3)
        self.hline(s, M, M + (w + GUT) * current + 14, y, BLUE, 3)
        for i, (date, head, body) in enumerate(points):
            x = M + i * (w + GUT)
            on = i == current
            self.box(s, x, y - 14, 28, 28, BLUE if i <= current else WHITE, MSO_SHAPE.OVAL,
                     None if i <= current else GREY)
            self.text(s, date, x + 44, y - 26, w - 44, 50, 22, BLUE if on else NAVY, True, anchor=MSO_ANCHOR.MIDDLE)
            cy = y + 50
            self.box(s, x, cy, w, bottom - cy, BLUE_SOFT if on else WHITE, MSO_SHAPE.ROUNDED_RECTANGLE,
                     line=None if on else LINE, radius=0.04)
            self.text(s, head, x + 28, cy + 24, w - 56, 40, 20, NAVY, True, lines=1, what='일정 제목')
            self.text(s, body, x + 28, cy + 76, w - 56, bottom - cy - 96, 17, INK, spacing=1.4, lines=7,
                      what='일정 설명')
        if band:
            self.band(s, band)
        return s

    def comparison(self, title='핵심을 짧게', sub=None, left=None, right=None, heads=('지금', '바꾼 뒤'), band=None):
        """전후 비교 패널 두 개. 오른쪽(바꾼 뒤)이 강조된다."""
        left = left or ['기존 방식을 한두 줄로 설명합니다.'] * 3
        right = right or ['바뀐 방식을 한두 줄로 설명합니다.'] * 3
        s = self.slide()
        self.frame(s, title, sub)
        bottom = BODY_BOTTOM if band else BODY_BOTTOM_FULL
        for i, (head, items) in enumerate(((heads[0], left), (heads[1], right))):
            x, w = col(i * 6, 6)
            on = i == 1
            self.box(s, x, BODY_Y, w, bottom - BODY_Y, WHITE, MSO_SHAPE.ROUNDED_RECTANGLE, line=LINE, radius=0.03)
            self.box(s, x, BODY_Y, w, 64, BLUE if on else GREY, MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.2)
            self.box(s, x, BODY_Y + 32, w, 32, BLUE if on else GREY)
            self.text(s, head, x + 32, BODY_Y, w - 64, 64, 22, WHITE, True, anchor=MSO_ANCHOR.MIDDLE,
                      lines=1, what='비교 제목')
            self.bullets(s, items, x + 32, BODY_Y + 96, w - 64, max_lines=3, gap=28, what='비교 항목')
        if band:
            self.band(s, band)
        return s

    def conclusion(self, title='결론 및 다음 단계', message='핵심 결론을 한 문장으로', findings=None, rows=None):
        """위: 결론 띠, 왼쪽: 확인한 내용 요약, 오른쪽: 다음 단계 표(할 일·담당·기한)."""
        findings = findings or ['보고서에서 확인한 내용을 두 줄로 요약합니다.'] * 3
        rows = rows or [('할 일을 한 줄로', '담당', '기한')] * 3
        s = self.slide()
        self.frame(s, title, source=None)
        self.box(s, M, BODY_Y, W - 2 * M, 80, NAVY, MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.12)
        self.text(s, message, M + 36, BODY_Y, W - 2 * M - 72, 80, 22, WHITE, True, anchor=MSO_ANCHOR.MIDDLE,
                  lines=1, what='핵심 결론')
        top = BODY_Y + 80 + GUT
        bottom = BODY_BOTTOM_FULL
        x, w = col(0, 5)
        py = self.panel(s, x, top, w, bottom - top, '확인한 내용')
        self.bullets(s, findings, x + 28, py + 4, w - 56, max_lines=3, gap=24)
        x2, w2 = col(5, 7)
        ty = self.panel(s, x2, top, w2, bottom - top, '다음 단계')
        cols = [(x2 + 28, w2 - 56 - 380, '할 일'), (x2 + w2 - 28 - 380, 170, '담당'), (x2 + w2 - 28 - 210, 210, '기한')]
        self.box(s, x2 + 28, ty, w2 - 56, 48, BLUE_SOFT)
        for cx, cw, h in cols:
            self.text(s, h, cx + 14, ty, cw - 28, 48, 16, NAVY, True, anchor=MSO_ANCHOR.MIDDLE)
        for r, row in enumerate(rows[:4]):
            y = ty + 48 + r * 108
            for c, ((cx, cw, _), v) in enumerate(zip(cols, row)):
                self.text(s, v, cx + 14, y, cw - 28, 108, 18, INK, anchor=MSO_ANCHOR.MIDDLE, spacing=1.2,
                          lines=2 if c == 0 else 1, what='다음 단계')
            self.hline(s, x2 + 28, x2 + w2 - 28, y + 108, HAIR)
        return s

    def closing(self, title='감사합니다', sub='질문과 의견은 아래로 보내 주세요', meta='담당 부서  ·  연락처'):
        s = self.slide()
        self.picture(s, 'closing-photo', 760, 0, W - 760, H)
        self.box(s, 0, 0, 760, H, NAVY)
        self.box(s, M + 32, 400, 64, 6, SKY)
        self.text(s, title, M + 32, 420, 600, 120, 56, WHITE, True)
        self.text(s, sub, M + 32, 560, 560, 90, 22, RGBColor(0xC9, 0xD6, 0xEE), spacing=1.3,
                  lines=2, what='마무리 문구')
        self.text(s, meta, M + 32, 730, 560, 40, 16, WHITE, True)
        self.box(s, M + 20, 900, 174, 104, WHITE, MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.1)
        self.logo_at(s, M + 32, 912, 150)
        return s

    # ---------- 점검·저장 ----------
    def check(self):
        """넘치는 글과 남은 견본 문구를 모은다. 초안은 0건이어야 한다."""
        found = list(self.warnings)
        for i, sl in enumerate(self.prs.slides, 1):
            for sh in sl.shapes:
                if sh.has_text_frame:  # type: ignore[attr-defined]
                    t = sh.text_frame.text  # type: ignore[attr-defined]
                    runs = [r for p in sh.text_frame.paragraphs for r in p.runs if r.text.strip()]  # type: ignore[attr-defined]
                    if any(r.font.size is None for r in runs):
                        found.append(f'{i}장 서식 없는 글(PPTX를 직접 고친 흔적, 스크립트에서 고쳐 다시 생성): "{t[:40]}"')
                    for ph in PLACEHOLDERS:
                        if ph in t:
                            found.append(f'{i}장 견본 문구 남음: "{t}"')
                            break
        return found

    def save(self, out, check=True):
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        self.prs.save(out)
        if check:
            found = self.check()
            print(f'점검: 고칠 곳 {len(found)}건')
            for f in found:
                print('  -', f)
            return found
        return []


def build(out, assets):
    d = Deck(assets)
    d.cover()
    d.agenda()
    d.section_divider()
    d.chart()
    d.kpi()
    d.table()
    d.two_column()
    d.image_pair()
    d.two_panels()
    d.statement()
    d.three_points()
    d.process()
    d.timeline()
    d.comparison()
    d.conclusion()
    d.closing()
    d.save(out, check=False)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('output')
    ap.add_argument('--assets', default=str(Path(__file__).resolve().parent.parent / 'assets'))
    a = ap.parse_args()
    build(a.output, a.assets)
