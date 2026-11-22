# PDF 앞쪽 몇 쪽의 본문을 UTF-8 파일로 뽑는다. Codex 앱에 함께 깔리는 Python(pypdf 포함)으로 돈다.
# 사용: python pdftext.py <pdf> <출력.txt> [최대글자=4000]
import sys
src, out = sys.argv[1], sys.argv[2]
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 4000
try:
    from pypdf import PdfReader
    r = PdfReader(src)
    if r.is_encrypted:
        r.decrypt("")
    parts = []
    for p in r.pages[:3]:
        parts.append(p.extract_text() or "")
        if sum(map(len, parts)) > limit:
            break
    text = "\n".join(parts).strip()[:limit]
except Exception as e:
    text = ""
with open(out, "w", encoding="utf-8") as f:
    f.write(text)
