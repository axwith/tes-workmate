---
name: wrap
description: 기록을 남기고 지난 기록을 찾는다. 작업을 마치며 "정리해 줘", "오늘 여기까지", "끝, 기록해 둬", "wrap", "오늘 끝"이라고 할 때(기록)와 "지난번에 뭐라고 했지", "전에 어떻게 하기로 했더라", "저번에 한 거", "그때 그 기준 뭐였지", "그 파일 어디 있지"라고 할 때, 반복 업무를 시작하기 전에 이전 기록을 확인할 때(찾기) 쓴다. 자료·글을 정리하라는 뜻의 "정리해 줘"(예: "이 표 정리해 줘")에는 쓰지 않는다.
---

# wrap — 기록하기와 지난 기록 찾기

기억은 세 겹이다.
- `memory/sessions/` — Codex 대화 원문 요약(사용자 말·답변). `sync.ps1`(Mac: `sync.py`)이 1시간마다 자동으로 옮긴다(AI 없이)
- `memory/daily/`·`memory/wiki/`·`memory/candidates.md` — 정리된 기억(이 스킬이 쓴다)
- `memory/index.db` — 위 전부와 `AGENTS.md`·`references/`·업무 폴더 문서를 담은 검색 색인(SQLite, 한국어 부분 검색)

지난 일을 묻는 말이면 A(찾기), 작업을 마치는 말이면 B(기록)를 한다.

## A. 지난 기록 찾기

1. 최신 색인: `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/wrap/scripts/sync.ps1`
   Mac: `python3 .agents/skills/wrap/scripts/sync.py` (`python3`이 없거나 검색 색인 오류가 나면 Codex 런타임 Python `~/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`)
2. 검색: `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/wrap/scripts/search.ps1 "검색어" -n 10`
   Mac: `python3 .agents/skills/wrap/scripts/search.py "검색어" -n 10`
   - 핵심 명사 1~3개로 찾는다(3글자 이상이 잘 잡힘). 결과가 없으면 다른 표현으로 한 번 더(예: "품질보고" → "품질 보고", "불량률").
   - 대화만: `-kind memory/sessions`, 결정만: `-kind memory/wiki` (Mac도 같다)
3. 결과에 나온 파일 1~3개를 열어 읽고 답한다. 답 끝에 출처 경로를 적는다.
4. 그래도 없으면 "기록에 없다"고 말한다. 기억으로 지어내지 않는다.
5. Linux는 같은 폴더 구조를 쓰고, 검색은 `rg -n "검색어" memory references AGENTS.md`로 대신한다.

## B. 작업 기록

### B-1. 작업 기록 (`memory/daily/YYYY-MM-DD.md`)
이번 대화에서 끝낸 작업마다 한 항목:
```
## HH:MM 작업 제목
- 요청: (사용자 요청 한 줄)
- 한 일: 
- 쓴 자료: (경로)
- 결과: (파일 경로)
- 사용자가 고친 점: "원문 그대로" (없으면 없음)
- 다시 할 때 필요한 설명: (매번 덧붙여야 했던 것)
```

### B-2. 위키
- 사용자가 정한 것(결정) → `memory/wiki/decisions/`
- 선호(톤·형식) → `preferences/`, 업무 맥락 → `domain-context/`, 데이터 특징 → `data-patterns/`, 실수·함정 → `lessons/`
- 이미 있는 페이지면 고치고, 없으면 만든다. `memory/index.md`를 같이 고친다.

### B-3. 후보 장부 (`memory/candidates.md`)
표: `| id | 종류(규칙/스킬) | 요약 | 근거(daily 날짜#제목) | 횟수 | 상태 |`
- 이번 기록의 "사용자가 고친 점"은 규칙 후보, "다시 할 때 필요한 설명"과 반복 작업은 스킬 후보로 뽑는다.
- **같은 후보인지 판정**: 표현이 아니라 쓰임으로 본다.
  - 규칙: 같은 상황에서 같은 행동을 요구하는가
  - 스킬: 받는 자료·절차·결과물 종류가 같은가
  - 같으면 기존 줄의 횟수를 올리고 근거를 붙인다(합친 이유 한 줄). 애매하면 새 줄로 두고 `비슷함: C03`처럼 적는다.
- 횟수는 **다른 날·다른 작업**에서 나온 근거만 센다. 한 작업 안의 반복은 1회.
- 상태: `관찰`(1~2회) → `제안`(3회 이상) → `승격` / `보류`(사용자가 거절, 다시 세지 않음).

### B-4. 제안과 승격
- `제안` 상태가 있으면 사용자에게 묻는다: "이 교정이 3번 나왔습니다. 규칙으로 올릴까요?" / "이 작업을 3번 했습니다. 스킬로 만들까요?"
- 승인하면: 규칙은 `AGENTS.md` 5장에 한 줄 추가(끝에 후보 id), 스킬은 `skillers-suda` 플러그인으로 만든다(근거가 된 daily 기록과 결과 파일을 함께 넘긴다). 만든 스킬은 `AGENTS.md` 6장 표에 한 줄 추가하고, 장부 상태를 `승격 → 위치`로 바꾼다.
- 거절하면 `보류`.

### B-5. 보고
기록한 작업 수, 새 위키 수, 후보 변화(새로 생김/횟수 오름/제안)를 3줄로 알린다.

## C. 아직 정리 안 된 대화 정리 (대화 시작 때 자동)
`memory/sessions/`에서 `digested: false`인 파일이 있으면, 사용자의 첫 요청을 처리한 뒤 조용히:
1. 각 대화를 B-1 형식으로 `memory/daily/<그 날짜>.md`에 한 항목씩 요약
2. 결정·선호·교훈은 `memory/wiki/`에, 교정·반복은 `memory/candidates.md`에 반영(같은 후보 판정은 B-3 규칙)
3. 그 파일의 `digested: false` → `digested: true`
4. `sync.ps1`(Mac: `sync.py`)을 다시 돌려 색인 갱신
사용자에게는 제안할 승격 후보가 생겼을 때만 번호 선택지로 알린다.
