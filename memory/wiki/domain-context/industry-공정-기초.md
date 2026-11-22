---
title: 반도체 공정·기술 기초
category: domain-context
status: 공개자료
updated: 2026-11-22
---

# 반도체 공정·기술 기초

> 업계 공통 도메인 지식(공개 자료). "(미대조)"·"요약 기준" 표시는 원문과 맞춰 보지 못한 숫자다. 회사·고객사 내부 사정과 다를 수 있고, 사용자가 다르게 말하면 사용자 말이 우선이다.

확인일 2026-11-22

## 핵심 5줄
1. 칩은 "막을 쌓고(증착) → 남길 곳을 표시하고(포토) → 나머지를 깎고(식각) → 닦는(세정)" 순서를 수백 번 반복해 만든다. [1][3]
2. 증착은 CVD(빠름)·PECVD(저온)·ALD(느리지만 원자 단위로 고르게)·PVD(금속, 순도 높음)·에피(결정 그대로 성장)로 나뉘며, 구조가 깊고 좁아질수록 ALD 비중이 커진다. [4][5]
3. 회로가 노광 장비 한계보다 작아지면 같은 층을 여러 번 쌓고 깎는 다중 패터닝을 쓴다. EUV가 일부 단계를 줄여도 하드마스크 증착·식각은 계속 필요하다. [12][13]
4. DRAM 미세화(1a→1b→1c), NAND 적층(300단 이상), HBM(TSV·하이브리드 본딩)은 모두 웨이퍼 한 장당 증착·식각 단계 수를 늘린다. 램리서치는 3D 구조 전환으로 증착·식각 공정 강도가 약 2배로 오른다고 본다. [6]
5. 장비 품질은 균일도·파티클·처리량·가동률·MTBF로 평가하고, 고객 팹에서는 데모 → 셋업 → 양산 평가를 거쳐 양산에 들어간 뒤 PM(예방 정비)으로 유지한다. [16]

## 1. 제조 흐름 한눈에 보기
| 단계 | 하는 일 | 주요 장비 |
|---|---|---|
| 설계 | 회로를 설계하고 노광용 마스크(포토마스크)를 만든다 | 설계 소프트웨어, 마스크 노광기 |
| 웨이퍼 제조 | 실리콘 덩어리(잉곳)를 얇게 잘라 연마한다 | 단결정 성장로, 절단·연마기 |
| 산화 | 웨이퍼 표면에 절연용 산화막을 만든다 | 산화·확산로(퍼니스) |
| 포토(노광) | 감광액을 바르고 빛으로 회로 모양을 찍는다 | 트랙(도포·현상), 스캐너(ArF·EUV) |
| 식각 | 표시되지 않은 부분의 막을 깎아낸다 | 건식 식각기(플라즈마), 습식 식각기 |
| 증착·이온주입 | 얇은 막을 쌓고, 불순물을 넣어 전기적 성질을 만든다 | CVD·ALD·PVD·에피 장비, 이온주입기 |
| 금속 배선 | 소자끼리 연결하는 금속선을 만든다 | PVD, 도금, CMP(평탄화) |
| EDS(테스트) | 웨이퍼 상태에서 칩마다 전기 검사를 한다 | 프로버, 테스터 |
| 패키징 | 칩을 잘라 기판에 붙이고 보호재로 감싼다 | 다이싱·본더·몰딩 장비 |

- 위 8단계가 SK하이닉스·삼성이 설명하는 "8대 공정"이다. [1][3] 세정과 CMP는 독립 단계라기보다 거의 모든 공정 전후에 끼어 들어간다. [14]
- 증착·식각·세정 장비사는 주로 전공정(웨이퍼 위에 회로를 만드는 단계)에 장비를 공급한다. 최근에는 HBM 같은 첨단 패키징에서도 증착·식각 수요가 생긴다. [6]

## 2. 증착: 웨이퍼 위에 얇은 막을 쌓는 공정
| 방식 | 원리 | 장점 | 단점 | 주 용도 |
|---|---|---|---|---|
| CVD | 원료 기체 두 가지 이상을 넣고 열 등 에너지를 주어 웨이퍼 표면에서 반응시킨다 | 빠르고 단차피복이 좋다 | 부산물이 섞일 수 있다 | 하드마스크, 두꺼운 절연막 [5] |
| PECVD | CVD에 플라즈마를 더해 반응 에너지를 공급한다 | 비교적 낮은 온도에서 균일한 막 | 막 품질이 고온 공정보다 낮을 수 있다 | 배선층 사이 절연막, 보호막 [3] |
| ALD | 원료 A를 한 층만 흡착 → 남은 기체 제거 → 반응 기체 B 투입 → 제거, 이 순서를 반복 | 두께를 원자 단위로 조절, 깊은 구멍 안쪽까지 고르게 | 느리다 | DRAM 커패시터, 게이트 절연막, 스페이서 [4][5] |
| PVD | 금속 표적에 이온을 부딪쳐 떨어진 입자를 웨이퍼에 붙인다(스퍼터링) | 부산물이 없어 순도가 높다 | 깊은 구조 안쪽을 덮기 어렵다 | 금속 배선, 확산 방지막 [5] |
| 에피(Epitaxy) | 웨이퍼 결정 배열을 그대로 이어받아 단결정 막을 키운다 | 결함이 적은 결정층 | 고온, 표면 청정도에 민감 | GAA의 Si/SiGe 적층, SiC·GaN 전력소자 [8][10] |

- 증착 막을 평가하는 말: 균일도(웨이퍼 전체 두께가 고른가), 단차피복(구멍 위·바닥·옆벽 두께 비율, 1에 가까울수록 좋음), 갭필(빈 공간을 빈틈 없이 채우는가). [5]
- 실제로는 섞어 쓴다. 예를 들어 금속 충전은 ALD로 얇은 시작층을 깔고 CVD로 나머지를 빠르게 채운다. [4]

## 3. 식각과 세정
| 구분 | 방식 | 특징 |
|---|---|---|
| 습식 식각 | 약액에 담가 녹인다 | 빠르고 싸지만 옆으로도 깎여 미세 패턴에 불리하다 [2] |
| 건식 식각 | 플라즈마로 만든 이온·라디칼로 깎는다 | 수직으로 깎을 수 있어 현재 주력. 대표 방식은 RIE(반응성 이온 식각) [2][3] |
| ALE | 원자층 단위로 한 겹씩 깎는다 | GAA처럼 옆 방향·초미세 가공에 쓴다 [6] |

- 식각 지표: 식각률(속도), 선택비(목표 막만 깎고 다른 막은 남기는 정도), 종횡비(얼마나 깊고 좁게 파는가), 균일도. 덜 깎으면 다음 공정이 막히고, 더 깎으면 아래층이 손상된다. [2]
- 세정은 각 공정 전후로 파티클·유기물·금속 오염을 없앤다. 대표 약액은 SC1(파티클·유기물), SC2(금속), SPM(감광액 잔여물), 희석 HF(자연산화막)다. [14]
- 세정 장비 방식: 배치식은 여러 장을 약액조에 한꺼번에 담가 처리량이 많고, 매엽식은 한 장씩 돌리며 분사해 균일도가 좋고 오염 전이가 적다. 미세화가 진행될수록 매엽식 비중이 커진다. [14][15]

## 4. 하드마스크와 패터닝
- 하드마스크: 감광액만으로는 깊은 식각을 버티지 못해, 감광액 아래에 깔아 패턴을 대신 옮겨 받는 단단한 막이다. 질화막·산화막·비정질 탄소막 등을 쓰며 대부분 CVD로 쌓는다. [5][12]
- 다중 패터닝(SADP·SAQP) 순서: ① 넓은 간격으로 기둥(맨드릴)을 만든다 ② ALD로 기둥 전체에 얇은 막을 덮는다 ③ 식각으로 윗면·바닥 막을 걷어 옆벽 막만 남긴다 ④ 기둥을 제거하면 간격이 절반이 된다. 이를 한 번 더 하면(SAQP) 4분의 1이 된다. [12][13]
- 그래서 다중 패터닝 한 번마다 증착·식각 단계가 여러 개 추가된다. 장비사 입장에서는 패터닝 단계 수가 곧 장비 수요다. [13]
- EUV는 파장이 13.5nm로 짧아 한 번에 더 작은 패턴을 찍을 수 있어 다중 패터닝 일부를 줄인다. SK하이닉스는 1c DRAM에서 EUV 공정을 최적화했다고 밝혔다. [7] 다만 EUV에서도 하드마스크·식각은 필요하고, 금속산화물 감광액 같은 새 재료가 들어온다. [6]

## 5. 메모리 구조와 장비 수요
| 제품 | 지금 일어나는 변화 | 증착·식각 수요가 느는 이유 |
|---|---|---|
| DRAM | 10나노급 세대가 1x·1y·1z·1a·1b·1c 순으로 진행. SK하이닉스는 2024-08 6세대 1c DDR5 개발 발표(생산성 약 30%↑) [7] | 선폭이 줄수록 다중 패터닝·EUV층이 늘고, 커패시터가 깊어져 고종횡비 식각과 ALD가 늘어난다. 차세대 4F²·3D DRAM은 종횡비 200:1까지 거론된다 [6] |
| NAND | 셀을 위로 쌓는다. SK하이닉스 321단 양산(2024-11 TLC, 2025-08 QLC) [8] | 단수만큼 산화막·질화막을 번갈아 증착하고, 수백 층을 한 번에 뚫는 채널홀 식각(현재 약 50:1, 100:1로 진행)과 워드라인 금속 충전이 필요하다 [6][9] |
| HBM | DRAM 칩 여러 장(12~16단)을 쌓아 GPU 옆에 붙인다 [10] | 칩을 관통하는 구멍(TSV)을 식각하고 절연막·금속을 채우는 공정, 웨이퍼 뒷면 박막, 본딩 전 표면 처리가 추가된다 [6][10] |

- HBM 접합 방식: 현재 SK하이닉스는 범프로 붙이고 틈을 보호재로 채우는 MR-MUF를 쓴다. 하이브리드 본딩은 범프 없이 구리와 절연막 면을 직접 붙이는 방식으로, 16단을 넘는 높은 적층에서 후보로 검토된다. [10][11]
- 하이브리드 본딩은 표면이 원자 수준으로 평평하고 깨끗해야 해서 CMP·세정·플라즈마 표면 처리·뒷면 증착 수요를 만든다. [6][11]

## 6. 로직·전력반도체·디스플레이의 공정 차이
| 분야 | 핵심 구조 | 메모리 공정과 다른 점 |
|---|---|---|
| 로직(GAA) | 얇은 실리콘판(나노시트)을 여러 장 쌓고 게이트가 사방을 감싼다 | Si/SiGe를 번갈아 에피로 쌓고, SiGe만 골라 옆으로 깎는 선택 식각과 그 빈자리를 채우는 ALD 내부 스페이서가 핵심. 옆 방향 가공이라 ALD·ALE 비중이 크다 [6][17] |
| 전력(SiC) | 높은 전압을 견디는 탄화규소 소자 | 에피를 약 1500~1700°C에서 키우고, 이온주입을 수백°C로 데운 상태에서 하며, 활성화 열처리가 1600°C를 넘기도 한다. 웨이퍼 결함 관리가 수율을 좌우한다 [18] |
| 전력(GaN) | 실리콘 등 기판 위에 GaN 막을 키운 소자 | MOCVD로 여러 층 버퍼를 쌓아 기판과의 격자 차이(Si 기준 약 17%)로 생기는 휨·균열을 막는다. 150·200mm 실리콘 웨이퍼를 쓸 수 있어 원가가 낮다 [19] |
| 디스플레이(OLEDoS) | 실리콘 웨이퍼 회로 위에 OLED를 올린 초소형 화면(XR 기기용) | 유기물은 고진공 열증착으로 올리고, 회로를 지키기 위해 저온 공정이 필수다. 수분 차단 봉지막에 PECVD·ALD를 쓴다 [20] |

## 7. 장비 품질 지표
| 지표 | 뜻 | 확인 방법·주의 |
|---|---|---|
| 균일도 | 웨이퍼 안(WIW)·웨이퍼 간(WTW) 두께·식각량 차이 | 여러 지점을 측정해 편차를 %로 표시 [5] |
| 파티클 | 장비가 웨이퍼에 남긴 이물 개수 | 처리 전후 검사 장비로 크기별 개수를 센다. 수율 직결 [14] |
| 처리량(WPH) | 시간당 처리 웨이퍼 수 | 같은 품질 조건에서 비교해야 의미가 있다 |
| 가동률(Uptime) | 장비가 생산 가능한 상태였던 시간 비율 | SEMI E10 기준. 생산·대기·엔지니어링 시간을 합해 계산 [16] |
| MTBF | 고장 사이 평균 시간 | 분모가 생산 시간(MTBFp)인지 가동 시간(MTBFu)인지 먼저 확인 [16] |
| MTTR | 고장 후 복구까지 평균 시간 | MTBF와 함께 서비스 계약 지표로 쓴다 [16] |

## 8. 팹 운영 용어
| 용어 | 뜻 |
|---|---|
| 데모(Demo) | 고객 웨이퍼로 장비 성능을 보여 주는 시험. 장비사 데모룸이나 고객 팹에서 한다 |
| 셋업(Setup) | 장비를 고객 팹에 반입·설치하고 배관·전기·통신을 연결해 공정 조건을 맞추는 과정 |
| 양산 평가(Qual) | 고객이 정한 기준(균일도·파티클·처리량 등)을 장기간 만족하는지 검증. 통과해야 양산 라인 투입 |
| 레시피(Recipe) | 온도·압력·가스·시간 등 공정 조건 묶음 |
| PM | 예방 정비. 정해진 주기에 부품 교체·챔버 세정을 해 고장을 미리 막는다 |
| 시즈닝 | PM 후 챔버 상태를 안정시키려고 더미 웨이퍼로 공정을 미리 돌리는 작업 |

- 8절 용어는 업계에서 통용되는 설명이며, 개별 고객사마다 단계 이름과 기준이 다르다. 공식 문서 출처로는 확인하지 못했다.

## 출처
1. SK하이닉스 뉴스룸, 반도체 전공정 2편: 공정 개괄과 산화 — https://news.skhynix.co.kr/jeonginseong-column-oxidation/
2. SK하이닉스 뉴스룸, 식각 패턴을 완성하다 上·下 — https://news.skhynix.co.kr/etching-pattern-superior/ , https://news.skhynix.co.kr/etching-pattern-down/
3. Samsung Newsroom, Eight Major Steps Part 5(식각)·Part 6(증착) — https://news.samsung.com/global/eight-major-steps-to-semiconductor-fabrication-part-5-etching-a-circuit-pattern , https://news.samsung.com/global/eight-major-steps-to-semiconductor-fabrication-part-6-the-addition-of-electrical-properties
4. Lam Research, Deposition Essentials (Semi 101)·ALTUS — https://newsroom.lamresearch.com/Deposition-Essentials-Semi-101 , https://www.lamresearch.com/product/altus-product-family/
5. SK하이닉스 뉴스룸, 반도체 전공정 5편: 증착 공정 — https://news.skhynix.co.kr/jeonginseong-column-deposition/
6. Lam Research Newsroom, How Deposition and Etch Are Reshaping Chips for the AI Era — https://newsroom.lamresearch.com/how-deposition-and-etch-are-reshaping-chips-for-the-ai-era/
7. SK하이닉스 뉴스룸, 세계 최초 10나노급 6세대 1c DDR5 개발 (2024-08-29) — https://news.skhynix.co.kr/1c-ddr5-development/
8. SK하이닉스 뉴스룸, 321단 낸드 양산 돌입 / 321단 QLC 양산 — https://news.skhynix.co.kr/mass-production-of-321-layer-nand/ , https://news.skhynix.co.kr/mass-production-321-nand-qlc/
9. Lam Research, Cryogenic Etching — https://www.lamresearch.com/products/our-solutions/cryogenic-etching/
10. SK hynix Newsroom, 16-Layer HBM3E / 차세대 패키징 인터뷰 — https://news.skhynix.com/en/sk-hynix-announces-16-layer-hbm3e-at-sk-ai-summit-2024/ , https://news.skhynix.com/en/gyujei-lee-next-gen-packaging-tech-key-to-hbm-success/
11. SK hynix Newsroom, [Tech Note] Hybrid Bonding — https://news.skhynix.com/en/tech-note-series-ep2/
12. Siemens, Multi-patterning options for 5nm and below: SADP, SAQP, SALELE — https://static.sw.cdn.siemens.com/siemens-disw-assets/public/4u6CdiSMj8aj3CBiiHGUNv/en-US/Siemens-SW-Multi-patterning-options-for-5nm-and-below-WP-81862-C2.pdf
13. TEL Investors' Guide, Self-aligned multiple patterning — https://www.tel.com/ir/library/investors-guide/hq95qj0000000734-att/InvestorsGuide_E20261109_rev00.pdf
14. 삼성반도체 용어사전 세정공정 / SK하이닉스 뉴스룸 세정공정 편 — https://semiconductor.samsung.com/kr/support/tools-resources/dictionary/zero-residue-zero-contaminants-semiconductor-cleaning/ , https://news.skhynix.co.kr/quiz_wash_semiconductors/
15. 대한기계학회 뉴스레터 2025-05, 반도체 습식 세정 공정 및 장비 기술 — https://ksme.or.kr/Newsletter/202505/data/02.%ED%85%8C%EB%A7%88%EA%B8%B0%ED%9A%8D.pdf
16. SEMI E10-0422 (RAM·가동률 정의) / SEMI Compilation of Terms — https://store-us.semi.org/products/e01000-semi-e10-specification-for-definition-and-measurement-of-equipment-reliability-availability-and-maintainability-ram-and-utilization , https://www.semi.org/sites/semi.org/files/2020-02/CompilationTerms1218_0.pdf
17. Applied Materials, GAA / Why Selective Processing is Critical — https://www.appliedmaterials.com/us/en/semiconductor/markets-and-inflections/advanced-logic/gaa.html , https://www.appliedmaterials.com/us/en/blog/blog-posts/why-selective-processing-is-critical-to-the-future-of-chip-scaling.html
18. MDPI Materials 14(14):3923, Selective Doping in SiC Power Devices / MDPI Crystals 12(2):245 — https://www.mdpi.com/1996-1944/14/14/3923 , https://www.mdpi.com/2073-4352/12/2/245
19. PMC, A review on the GaN-on-Si power electronic devices — https://pmc.ncbi.nlm.nih.gov/articles/PMC11197798/
20. OLED-on-silicon microdisplays review (2025) — https://doi.org/10.1016/j.nxnano.2025.100132
