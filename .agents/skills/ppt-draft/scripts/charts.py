#!/usr/bin/env python3
"""PPT 차트로 그리기 어려운 그래프를 TES 템플릿 색·글자 크기로 PNG로 그린다.

사용:
    from charts import pareto
    pareto(['치수', '도금', '스크래치', '이물'], [31, 28, 28, 16], 'reports/<주제>_그림/파레토.png', unit='건')
그린 PNG는 Deck.two_column(image=...)의 그림 패널에 넣는다.
"""
from pathlib import Path

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib import font_manager as fm  # noqa: E402

BLUE, GREY, INK, LINE = '#0063A8', '#C5CDD8', '#1F2633', '#E3E7ED'


def _korean_font():
    for name in ('Malgun Gothic', 'AppleSDGothicNeo', 'Apple SD Gothic Neo', 'NanumGothic'):
        for f in fm.findSystemFonts():
            if name.replace(' ', '').lower() in Path(f).stem.replace(' ', '').lower() or \
                    (name == 'Malgun Gothic' and 'malgun' in f.lower()):
                fm.fontManager.addfont(f)
                plt.rcParams['font.family'] = fm.FontProperties(fname=f).get_name()
                return
    plt.rcParams['axes.unicode_minus'] = False


def pareto(labels, values, out, unit='', top=None, size=(11, 8)):
    """막대(큰 값부터) + 누적 비율 선. top: 파랑으로 칠할 상위 개수(기본: 누적 80%까지)."""
    _korean_font()
    pairs = sorted(zip(labels, values), key=lambda p: -p[1])
    labels, values = [p[0] for p in pairs], [p[1] for p in pairs]
    total = sum(values)
    cum, c = [], 0
    for v in values:
        c += v
        cum.append(c / total * 100)
    if top is None:
        top = next((i + 1 for i, y in enumerate(cum) if y >= 80), len(values))
    fig, ax = plt.subplots(figsize=size, dpi=200)
    bars = ax.bar(labels, values, color=[BLUE] * top + [GREY] * (len(values) - top), width=0.55)
    for i, (r, v) in enumerate(zip(bars, values)):
        ax.text(r.get_x() + r.get_width() / 2, v + max(values) * 0.03, f'{v:,}{unit}', ha='center', va='bottom',
                fontsize=28, fontweight='bold', color=BLUE if i < top else INK)
    # 누적선은 막대 위쪽 띠에 그려 막대·값과 겹치지 않게 한다
    ax2 = ax.twinx()
    ax2.plot(labels, cum, color=INK, marker='o', ms=10, lw=2.5)
    for i, y in enumerate(cum):
        ax2.text(i, y + 6, f'{y:.0f}%', ha='center', va='bottom', fontsize=24, fontweight='bold', color=INK)
    ax2.set_ylim(-140, 118)
    ax.set_ylim(0, max(values) * 1.9)
    for a in (ax, ax2):
        for sp in a.spines.values():
            sp.set_visible(False)
        a.set_yticks([])
    ax.spines['bottom'].set_visible(True)
    ax.spines['bottom'].set_color(LINE)
    ax.tick_params(axis='x', labelsize=28, length=0, colors=INK, pad=10)
    plt.tight_layout()
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out, facecolor='white')
    plt.close(fig)
    return out
