"""Compile the original page content into a native UI schema, with strict translation parity."""
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
    if e.tag == 'a': return '['+text+'](action://'+e.attrs.get('id','')+')'
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
        if isinstance(e,str) or e.tag in ('svg','script','select','pre'): return None
        tag,ident=e.tag,e.attrs.get('id','')
        n={'kind':tag,'id':ident,'text':'','children':[]}
        if ident in ('verdict','efiout','ports') or tag=='table': n['kind']={'verdict':'verdict','efiout':'issues','ports':'ports'}.get(ident,'machine');return n
        if ident=='efirow': n['kind']='efiPicker';n['text']=text(e);return n
        if tag=='button':
            n['kind']='button';n['text']=text(Element('text'));n['text']=text_from_button(e)
            return n
        if tag in ('h1','p','li'):
            n['kind']='title' if tag=='h1' else 'subtitle' if 'sh' in e.attrs.get('class','').split() else 'step' if tag=='li' else 'status' if ident and not rich(e).strip() else 'text'
            if e.attrs.get('class')=='legal':n['kind']='legal'
            n['text']=text(e)
            for child in e.children:
                if not isinstance(child,str) and child.tag=='button': n['children'].append(convert(child))
                elif not isinstance(child,str) and child.tag=='span' and child.attrs.get('id'): n['children'].append({'kind':'status','id':child.attrs['id'],'text':'','children':[]})
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
def build():
    doc=source_document();expected=json.loads((ROOT/'downstream/ui-source.json').read_text())
    if doc!=expected:raise RuntimeError('Upstream page content or UI behavior changed; review native UI and translations before release')
    translations=json.loads((ROOT/'downstream/ui-zh.json').read_text())
    if set(doc['entries'])!=set(translations):raise RuntimeError('Every original page string must have exactly one translation')
    def localize(n):
        if n['text']:n['text']=translations[n['text']]
        for c in n['children']:localize(c)
    for page in doc['pages']:localize(page)
    (ROOT/'mac/Resources/native-pages.json').write_text(json.dumps(doc['pages'],ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':
    import sys
    if '--initialize' in sys.argv:
        doc=source_document();(ROOT/'downstream/ui-source.json').write_text(json.dumps(doc,indent=2)+'\n')
        for key,text in doc['entries'].items():print(key,text)
    else:build()
