#!/usr/bin/env python3
"""TES 공개용 가상 템플릿으로 PPTX 초안을 생성한다."""
import argparse
from pathlib import Path
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN
from pptx.util import Inches, Pt

NAVY = RGBColor(15, 23, 42)
BLUE = RGBColor(29, 78, 216)
LIGHT = RGBColor(241, 245, 249)
MID = RGBColor(100, 116, 139)
WHITE = RGBColor(255, 255, 255)


def box(slide, x, y, w, h, fill=None, line=None):
    s = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    s.fill.solid(); s.fill.fore_color.rgb = fill or WHITE
    s.line.color.rgb = line or (fill or WHITE)
    return s


def text(slide, value, x, y, w, h, size=20, color=NAVY, bold=False, label=False):
    shape = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = shape.text_frame; tf.clear(); tf.word_wrap = True
    p = tf.paragraphs[0]; p.alignment = PP_ALIGN.LEFT
    r = p.add_run(); r.text = value; r.font.name = 'Arial'; r.font.size = Pt(size); r.font.bold = bold; r.font.color.rgb = color
    if label: r.font.size = Pt(9); r.font.bold = True
    return shape


def footer(slide, source='출처: 확인 필요 | 원자료: 확인 필요 | 초안, 검토 필요', align='left'):
    shape = text(slide, source, .55, 7.05, 12.2, .25, 8, MID)
    shape.text_frame.paragraphs[0].alignment = PP_ALIGN.RIGHT if align == 'right' else PP_ALIGN.LEFT


def header(slide, title, section='TES WORKMATE / DRAFT'):
    box(slide, 0, 0, 13.333, .18, NAVY)
    text(slide, section, .55, .35, 4, .2, 9, BLUE, True, True)
    text(slide, title, .55, .68, 11.8, .55, 25, NAVY, True)


def add_title(prs, title, subtitle='업무 검토 초안'):
    s = prs.slides.add_slide(prs.slide_layouts[6]); box(s, 0, 0, 13.333, 7.5, NAVY)
    text(s, 'TES', 11.7, .35, .7, .2, 9, RGBColor(147,197,253), True, True)
    # 일반화한 회로 선형 그래픽
    for i in range(5):
        line = s.shapes.add_connector(1, Inches(8.2), Inches(1.1 + i), Inches(12.5), Inches(1.1 + i))
        line.line.color.rgb = BLUE; line.line.transparency = 35
        box(s, 8.0 + i*.75, 1.0 + i*.75, .16, .16, BLUE)
    text(s, '업무 검토 자료', .75, .8, 4, .3, 12, RGBColor(147,197,253), True, True)
    text(s, title, .75, 2.25, 10.5, 1.2, 35, WHITE, True)
    text(s, subtitle, .78, 3.65, 8, .45, 17, RGBColor(203,213,225))
    text(s, 'DRAFT · 검토 필요', .78, 6.55, 4, .3, 10, RGBColor(148,163,184), True)


def add_body(prs, title, bullets, source=None):
    s = prs.slides.add_slide(prs.slide_layouts[6]); box(s, 0, 0, 13.333, 7.5, LIGHT); header(s, title)
    y = 1.55
    for b in bullets:
        box(s, .75, y+.1, .12, .12, BLUE)
        text(s, b, 1.05, y, 11.2, .55, 20, NAVY)
        y += .85
    footer(s, source or '출처: 확인 필요 | 원자료: 확인 필요 | 초안, 검토 필요')


def add_cards(prs, title, cards):
    s = prs.slides.add_slide(prs.slide_layouts[6]); box(s, 0, 0, 13.333, 7.5, LIGHT); header(s, title)
    for i, (head, body) in enumerate(cards[:3]):
        x = .75 + i*4.15; box(s, x, 1.65, 3.7, 3.8, WHITE, RGBColor(226,232,240))
        box(s, x, 1.65, 3.7, .12, BLUE)
        text(s, head, x+.28, 2.05, 3.1, .45, 18, NAVY, True)
        text(s, body, x+.28, 2.75, 3.1, 1.8, 15, MID)
    footer(s, '출처: 확인 필요 | 원자료: 확인 필요 | 초안, 검토 필요')


def build(output, title):
    prs = Presentation(); prs.slide_width = Inches(13.333); prs.slide_height = Inches(7.5)
    add_title(prs, title)
    add_body(prs, '목차', ['1. 시험 목적과 조건', '2. 결과와 핵심 근거', '3. 검토와 다음 단계'])
    add_body(prs, '시험 목적과 조건', ['목적: BKM 공정개발 평가', '조건: 막두께 균일도·Defect·장비 조건 비교', '자료 범위: 시험 원자료와 검토 기록'], '출처: 시험계획서 | 원자료: 확인 필요 | 초안, 검토 필요')
    add_cards(prs, '핵심 결과', [('막두께 균일도', '측정값과 공식, 포함 점수를 확인하세요.'), ('Defect 개선', '기준 대비 변화와 대조값을 입력하세요.'), ('장비 평가', '조건별 결과와 확인 필요 항목을 입력하세요.')])
    add_body(prs, '검토와 다음 단계', ['고객 요청과 현재 상태를 대조하세요.', '원자료의 숫자·단위·기간을 확인하세요.', '담당자 검토 후 다음 일정을 확정하세요.'])
    add_title(prs, 'Thank you', '검토 의견과 다음 일정을 남겨 주세요')
    Path(output).parent.mkdir(parents=True, exist_ok=True); prs.save(output)


if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('output'); ap.add_argument('--title', default='TES 업무 보고 초안')
    a = ap.parse_args(); build(a.output, a.title)
