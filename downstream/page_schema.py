"""Compile the original page content into a native UI schema, with strict translation parity."""
import difflib
import hashlib
import json
import pathlib
import re
from html.parser import HTMLParser
ROOT = pathlib.Path(__file__).resolve().parents[1]
class Element:
    def __init__(self, tag, attrs=()): self.tag, self.attrs, self.children = tag, dict(attrs), []
class Parser(HTMLParser):
    def __init__(self): super().__init__(); self.root = Element('root'); self.stack = [self.root]
    def handle_starttag(self, tag, attrs):
        e = Element(tag, attrs); self.stack[-1].children.append(e)
        if tag not in ('meta','link','br','img','input','hr'): self.stack.append(e)
    def handle_endtag(self, tag):
        for i in range(len(self.stack)-1,0,-1):
            if self.stack[i].tag == tag: self.stack = self.stack[:i]; break
    def handle_data(self, text): self.stack[-1].children.append(text)
def all_nodes(e):
    if isinstance(e,str): return
    yield e
    for c in e.children: yield from all_nodes(c)
def rich(e):
    if isinstance(e,str): return e
    if e.tag in ('svg','button','select','pre'): return ''
    text = ''.join(rich(c) for c in e.children)
    if e.tag == 'b': return '**'+text+'**'
    if e.tag == 'i': return '*'+text+'*'
    if e.tag == 'a':
        href = e.attrs.get('href', '')
        destination = href if href.startswith('https://') else 'action://' + e.attrs.get('id', '')
        return '['+text+']('+destination+')'
    return text
def source_document():
    parser=Parser(); parser.feed((ROOT/'mac/Resources/index.html').read_text())
    entries={}; count=0
    def text(e):
        nonlocal count
        s=re.sub(r'\s+',' ',rich(e)).strip()
        if not s:return ''
        count+=1; key=f't{count:03d}'; entries[key]=s; return key
    def convert(e):
        if isinstance(e,str) or e.tag in ('svg','script','pre'): return None
        tag,ident=e.tag,e.attrs.get('id','')
        n={'kind':tag,'id':ident,'text':'','children':[]}
        # A <select> keeps its options so the native UI can offer the same choice; each label is translated on its own.
        if tag=='select':
            n['kind']='picker'
            for opt in e.children:
                if not isinstance(opt,str) and opt.tag=='option':
                    value=opt.attrs.get('value','')
                    n['children'].append({'kind':'option','id':value,'text':text(opt),'children':[],'value':value})
            return n
        if ident in ('verdict','efiout','ports') or tag=='table': n['kind']={'verdict':'verdict','efiout':'issues','ports':'ports'}.get(ident,'machine');return n
        if ident=='efirow':
            n['kind']='efiPicker';n['text']=text(e)
            for child in e.children:
                if not isinstance(child,str) and child.tag in ('button','select'):
                    n['children'].append(convert(child))
            return n
        if tag=='button':
            n['kind']='button';n['text']=text(Element('text'));n['text']=text_from_button(e)
            return n
        if tag in ('h1','p','li'):
            n['kind']='title' if tag=='h1' else 'subtitle' if 'sh' in e.attrs.get('class','').split() else 'step' if tag=='li' else 'status' if ident and not rich(e).strip() else 'text'
            if e.attrs.get('class')=='legal':n['kind']='legal'
            n['text']=text(e)
            for child in e.children:
                if isinstance(child,str): continue
                if child.tag in ('button','select'):
                    n['children'].append(convert(child))
                elif child.tag=='span' and child.attrs.get('id'):
                    n['children'].append({'kind':'status','id':child.attrs['id'],'text':'','children':[]})
                elif child.tag=='label':
                    for control in all_nodes(child):
                        if control.tag=='input' and control.attrs.get('type')=='checkbox':
                            n['children'].append({'kind':'experimentalToggle','id':control.attrs.get('id',''),
                                'text':'','value':control.attrs.get('data-id',''),'children':[]})
                            break
                elif child.tag=='input' and child.attrs.get('type')=='number':
                    n['children'].append({'kind':'numberInput','id':child.attrs.get('id',''),
                        'text':'','value':child.attrs.get('value',''),'children':[]})
            return n
        if tag=='span':
            if ident:return {'kind':'status','id':ident,'text':'','children':[]}
            return None
        n['kind']='card' if 'card' in e.attrs.get('class','').split() else 'steps' if tag=='ol' else 'group'
        for child in e.children:
            c=convert(child)
            if c:n['children'].append(c)
        return n
    def text_from_button(e):
        nonlocal count
        value=re.sub(r'\s+',' ',''.join(rich(c) for c in e.children)).strip()
        count+=1;key=f't{count:03d}';entries[key]=value;return key
    pages=[]
    for e in all_nodes(parser.root):
        if e.tag=='section': pages.append({'kind':'page','id':e.attrs['id'][2:],'text':'','children':[n for c in e.children if (n:=convert(c))]})
    return {'pages':pages,'entries':entries,'script_sha256':hashlib.sha256((ROOT/'mac/Resources/app.js').read_bytes()).hexdigest()}
def preview(text, width=70):
    text = re.sub(r'\s+', ' ', text).strip()
    return text if len(text) <= width else text[:width - 1] + '…'
def opcodes(old, new):
    return difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes()
def entry_lines(expected, doc, limit=24):
    old, new = list(expected['entries'].values()), list(doc['entries'].values())
    keys, lines, budget = list(doc['entries']), [f'entries: {len(old)} -> {len(new)}'], limit
    for tag, i1, i2, j1, j2 in opcodes(old, new):
        if tag == 'equal':
            if i1 != j1: lines.append(f'  shift: old t{i1+1:03d}..t{i2:03d} -> t{j1+1:03d}..t{j2:03d} ({j1-i1:+d}); translate by position, not by text')
            continue
        lines.append('  ' + {'insert': 'added', 'delete': 'removed', 'replace': 'changed'}[tag] + f' at t{j1+1:03d}: {j2-j1} new / {i2-i1} old')
        for offset in range(j2 - j1):
            if budget <= 0: lines.append('    … truncated, see downstream/ui-source.json'); break
            budget -= 1; lines.append(f'    + {keys[j1+offset]} {preview(new[j1+offset])}')
        for offset in range(i2 - i1):
            if budget <= 0: break
            budget -= 1; lines.append(f'    - t{i1+offset+1:03d} {preview(old[i1+offset])}')
    return lines
def node_lines(expected, doc, limit=30):
    def signatures(page, entries):
        found = []
        def walk(node):
            found.append(f"{node['kind']} {node['id']} {entries.get(node['text'], node['text'])}".strip())
            for child in node['children']: walk(child)
        for node in page['children']: walk(node)
        return found
    old = {page['id']: page for page in expected['pages']}; new = {page['id']: page for page in doc['pages']}
    lines = ['pages: ' + ', '.join(old) + ' -> ' + ', '.join(new)]
    lines += [f'  - page {name}' for name in old if name not in new]
    budget = limit
    for name, page in new.items():
        before = signatures(old[name], expected['entries']) if name in old else []
        after = signatures(page, doc['entries'])
        if before == after: continue
        lines.append(f'  {name}: {len(before)} -> {len(after)} nodes')
        for tag, i1, i2, j1, j2 in opcodes(before, after):
            if tag == 'equal': continue
            lines.append('    ' + {'insert': 'added', 'delete': 'removed', 'replace': 'changed'}[tag])
            for text in after[j1:j2][:max(budget, 0)]: budget -= 1; lines.append('      + ' + preview(text))
            for text in before[i1:i2][:max(budget, 0)]: budget -= 1; lines.append('      - ' + preview(text))
            if budget <= 0: break
    return lines
def describe(expected, doc):
    """Explain a snapshot mismatch well enough to act on without opening the JSON."""
    lines = []
    if expected.get('script_sha256') != doc.get('script_sha256'):
        lines.append('app.js changed: ' + str(expected.get('script_sha256'))[:8] + ' -> ' + str(doc.get('script_sha256'))[:8] + ' (page behavior, check the native event handling)')
    return lines + entry_lines(expected, doc) + node_lines(expected, doc)
def build():
    doc=source_document();expected=json.loads((ROOT/'downstream/ui-source.json').read_text())
    if doc!=expected:raise RuntimeError('Upstream page content or UI behavior changed; review native UI and translations before release\n\n'+'\n'.join(describe(expected,doc)))
    translations=json.loads((ROOT/'downstream/ui-zh.json').read_text())
    if set(doc['entries'])!=set(translations):
        missing=sorted(set(doc['entries'])-set(translations));extra=sorted(set(translations)-set(doc['entries']))
        detail=[f'  missing {key} {preview(doc["entries"][key])}' for key in missing[:20]]
        detail+=[f'  unknown {key} (no longer in the original page)' for key in extra[:20]]
        raise RuntimeError(f'Every original page string must have exactly one translation: {len(missing)} missing, {len(extra)} unknown\n'+'\n'.join(detail))
    resources = ROOT / 'mac/Resources'
    (resources / 'native-pages.json').write_text(json.dumps(doc['pages'], indent=2) + '\n')
    for language, entries in {'en': doc['entries'], 'zh-Hans': translations}.items():
        directory = ROOT / 'mac/Localizations' / (language + '.lproj')
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'native-page-text.json').write_text(json.dumps(entries, ensure_ascii=False, indent=2) + '\n')
if __name__=='__main__':
    import sys
    if '--initialize' in sys.argv:
        doc=source_document();(ROOT/'downstream/ui-source.json').write_text(json.dumps(doc,indent=2)+'\n')
        for key,text in doc['entries'].items():print(key,text)
    else:build()
