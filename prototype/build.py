"""Package the editable prototype as a self-contained HTML and source ZIP."""
from pathlib import Path
import base64,json,zipfile
root=Path(__file__).resolve().parent
d=root/'dist'
def uri(path):
    mime='image/png' if path.suffix=='.png' else 'image/svg+xml'
    return 'data:'+mime+';base64,'+base64.b64encode(path.read_bytes()).decode()
assets={'assets/'+p.name:uri(p) for p in (d/'assets').iterdir() if p.suffix in ('.png','.svg')}
s=(d/'app.js').read_text()
s=s.replace("const pic=(i,v=0)=>'assets/'+CATS.indexOf(i.cat)+(['','-upper','-base'][v])+'.svg';", "const pic=(i,v=0)=>EMBEDDED_ASSETS['assets/'+CATS.indexOf(i.cat)+(['','-upper','-base'][v])+'.svg'];")
h=(d/'index.html').read_text().replace('<link rel="stylesheet" href="style.css">','<style>'+(d/'style.css').read_text()+'</style>')
for name,data in assets.items():
    s=s.replace(name,data)
    h=h.replace(name,data)
s='const EMBEDDED_ASSETS='+json.dumps(assets)+';\n'+s
h=h.replace('<script src="app.js"></script>','<script>'+s.replace('</script','<\\/script')+'</script>')
(root/'FreeDME Interactive Prototype v0.1.html').write_text(h)
with zipfile.ZipFile(root/'FreeDME Prototype Source v0.1.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file() and p.suffix!='.zip' and '__pycache__' not in p.parts:z.write(p,p.relative_to(root))
print('Standalone HTML and source ZIP updated.')
