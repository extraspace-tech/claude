import re, sys, pathlib
plan = pathlib.Path(sys.argv[1]).read_text(); root = pathlib.Path("../CMS")
lines = plan.splitlines(); file_re = re.compile(r'`((?:Common|BL|DTOs|Mappers|Domain)/[^`]+\.cs)`')
cur=None; i=0; pending=None; applied=0
def block_at(k):
    b=[]; k+=1
    while k < len(lines) and not lines[k].startswith('```'): b.append(lines[k]); k+=1
    return "\n".join(b), k
while i < len(lines):
    ln=lines[i]; m=file_re.search(ln)
    if m and 'file' in ln.lower() or (m and ln.startswith('###')): cur=m.group(1)
    if ln.startswith('```csharp'):
        j=i-1
        while j>=0 and not lines[j].strip(): j-=1
        head=lines[j].strip(); code,end=block_at(i)
        if re.search(r'Replace:', head, re.I): pending=('replace',cur,code)
        elif re.search(r'Delete this', head, re.I):
            p=root/cur; s=p.read_text(); assert s.count(code)==1, (cur,head); p.write_text(s.replace(code,'',1)); applied+=1
        elif re.search(r'Find this exact line', head, re.I): pending=('insert_before',cur,code)
        elif head.startswith('with:') and pending and pending[0]=='replace':
            _,f,anchor=pending; p=root/f; s=p.read_text(); assert s.count(anchor)==1,(f,anchor[:60]); p.write_text(s.replace(anchor,code,1)); applied+=1; pending=None
        elif 'insert the following block immediately before it' in head and pending and pending[0]=='insert_before':
            _,f,anchor=pending; p=root/f; s=p.read_text(); assert s.count(anchor)==1,(f,anchor[:60]); p.write_text(s.replace(anchor,code+"\n"+anchor,1)); applied+=1; pending=None
        i=end
    i+=1
print("applied edits:",applied)
