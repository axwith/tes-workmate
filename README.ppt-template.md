# TES 공통 PPT 템플릿 (내부 교육용)

`@ppt-draft`가 쓰는 공통 템플릿입니다. 업무 내용은 넣지 않고 자리표시자만 둡니다.

- 생성기: `.agents/skills/ppt-draft/scripts/build_template.py`의 `Deck` 클래스. 견본 덱은 `tes-template.pptx`(16장, 모두 편집 가능한 텍스트·도형)
- 그래프: `.agents/skills/ppt-draft/scripts/charts.py`(파레토 등 PPT 차트로 어려운 그래프)
- 예시 보고서: `.agents/skills/ppt-draft/examples/수입검사_불량분석.py`(가상 수입검사 자료, 8장)
- 디자인 규칙: `.agents/skills/ppt-draft/DESIGN-GUIDE.md`
- 구조: TES IR 자료(2Q26·3Q26)와 같은 순서 — 섹션 머리말(번호·이름·로고·선) → 짧은 제목 → 패널 2~3개(차트·설명·표·그림) → 결론 띠
- 글: 제목은 핵심만 짧게, 본문 패널은 수치·비교·뜻까지 설명형으로. 저장할 때 넘침·한 단어만 떨어진 줄·견본 문구·PPTX 직접 수정을 점검
- 색: TES 네이비 `#2A3366`, TES 블루 `#0063A8`, 하늘색 `#12BDF3`, 표 머리 `#DEEBF7`, 최신 열 `#FFF1CC`
- 글꼴: 맑은 고딕(한글 줄바꿈은 어절 단위가 되도록 ko-KR 지정)
- 그림: 사진은 표지·섹션·마무리에만. 본문에는 불량 모습·장비·공정 개념처럼 보여 주는 편이 빠른 내용만 생성 이미지(`pumasi-image`)로 넣고 짧은 설명을 붙임. 아이콘은 Lucide(ISC 라이선스 `assets/icons/LICENSE-lucide.txt`)
- 로고: TES CI(`assets/tes-logo.png`). 출처 https://www.hites.co.kr/theme/tm04/html/img/a1_logo.png (회사 소개 페이지, 2026-11-23 수집)
