---
name: recall
description: 지난 대화·결정·작업을 찾아야 할 때 쓴다. "지난번에 뭐라고 했지", "전에 어떻게 하기로 했더라", "저번에 한 거", "그때 그 기준 뭐였지", "그 파일 어디 있지", 그리고 반복 업무를 시작하기 전에 이전 기록을 확인할 때. 아직 정리 안 된 대화가 있으면 정리도 한다.
---

# recall — 기억 찾기와 대화 정리

기억은 세 겹이다.
- `memory/sessions/` — Codex 대화 원문 요약(사용자 말·답변). `sync.ps1`(Mac: `sync.py`)이 1시간마다 자동으로 옮긴다(AI 없이)
- `memory/daily/`·`memory/wiki/`·`memory/candidates.md` — 정리된 기억(wrap·이 스킬이 쓴다)
- `memory/index.db` — 위 전부와 `AGENTS.md`·`references/`·업무 폴더 문서를 담은 검색 색인(SQLite, 한국어 부분 검색)

## 1. 찾기
1. 최신 색인: `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/recall/scripts/sync.ps1`
   Mac: `python3 .agents/skills/recall/scripts/sync.py` (`python3`이 없거나 검색 색인 오류가 나면 Codex 런타임 Python `~/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`)
2. 검색: `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/recall/scripts/search.ps1 "검색어" -n 10`
   Mac: `python3 .agents/skills/recall/scripts/search.py "검색어" -n 10`
   - 핵심 명사 1~3개로 찾는다(3글자 이상이 잘 잡힘). 결과가 없으면 다른 표현으로 한 번 더(예: "품질보고" → "품질 보고", "불량률").
   - 대화만: `-kind memory/sessions`, 결정만: `-kind memory/wiki` (Mac도 같다)
3. 결과에 나온 파일 1~3개를 열어 읽고 답한다. 답 끝에 출처 경로를 적는다.
4. 그래도 없으면 "기록에 없다"고 말한다. 기억으로 지어내지 않는다.

## 2. 아직 정리 안 된 대화 정리 (대화 시작 때 자동)
`memory/sessions/`에서 `digested: false`인 파일이 있으면, 사용자의 첫 요청을 처리한 뒤 조용히:
1. 각 대화를 `wrap` 형식으로 `memory/daily/<그 날짜>.md`에 한 항목씩 요약(요청·한 일·결과 파일·사용자가 고친 점·다시 할 때 필요한 설명)
2. 결정·선호·교훈은 `memory/wiki/`에, 교정·반복은 `memory/candidates.md`에 반영(같은 후보 판정은 wrap 규칙)
3. 그 파일의 `digested: false` → `digested: true`
4. `sync.ps1`(Mac: `sync.py`)을 다시 돌려 색인 갱신
사용자에게는 제안할 승격 후보가 생겼을 때만 번호 선택지로 알린다.

## Linux
Mac은 위의 `Mac:` 줄을 쓴다. Linux는 같은 폴더 구조를 쓰고, 검색은 `rg -n "검색어" memory references AGENTS.md`로 대신한다.
