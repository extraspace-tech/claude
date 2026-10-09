import re, sys, pathlib
plan = pathlib.Path(sys.argv[1]).read_text()
root = pathlib.Path("../CMS")
lines = plan.splitlines()
current_file = None; results=[]; i=0
file_re = re.compile(r'`((?:Common|BL|DTOs|Mappers|Domain)/[^`]+\.cs)`')
while i < len(lines):
    ln = lines[i]
    m = file_re.search(ln)
    if m and ('File `' in ln or ln.startswith('File ') or ln.startswith('###') or ln.startswith('10') or ln.startswith('6') or ln.startswith('8') or 'file' in ln.lower()):
        current_file = m.group(1)
    if ln.startswith('```csharp'):
        # classify by the nearest non-empty line above
        j=i-1
        while j>=0 and not lines[j].strip(): j-=1
        head = lines[j].strip()
        block=[]; i+=1
        while i < len(lines) and not lines[i].startswith('```'):
            block.append(lines[i]); i+=1
        code = "\n".join(block)
        kind = 'anchor' if re.search(r'(Replace:|Delete this|Find this exact line)', head, re.I) else ('new' if head.startswith('with:') or 'insert the following' in head else 'other')
        if kind=='anchor':
            src = (root/current_file).read_text()
            n = src.count(code)
            results.append((current_file, head[:40], n))
    i+=1
bad=[r for r in results if r[2]!=1]
for r in results: print(("OK " if r[2]==1 else "FAIL"), r[2], r[0], '|', r[1])
print(f"\n{len(results)} anchors, {len(bad)} failing")
sys.exit(1 if bad else 0)
