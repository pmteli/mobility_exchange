from pathlib import Path
import subprocess,concurrent.futures,json,re,difflib,os
os.environ.setdefault("OMP_THREAD_LIMIT","1")
project=Path(__file__).resolve().parents[3]
root=Path(os.environ.get('RECORDING_OUTPUT', str(project/'output/rails-demo'))); target=Path(os.environ.get('NARRATION_OUTPUT', str(project/'output/rails-demo-narrated')));target.mkdir(exist_ok=True)
source=Path(__file__).with_name('run.cjs').read_text()
items=json.loads((root/'manifest.json').read_text())
known=list(dict.fromkeys(re.findall(r"caption\('([^']*)'\)",source)+[i['title'] for i in items]+['Add equipment · photo upload and moderator publication']+['Sign in as '+n for n in ['Nina · Donor','David · Donor','Maya · Recipient','Alex · Recipient','Sam · Moderator']]))
def norm(t):return re.sub(r'[^a-z0-9 ]','',t.lower()).strip()
normalized=[norm(x) for x in known]
only=set(filter(None,os.environ.get("ONLY_NARRATION", "").split(",")))
result=json.loads((target/'caption-timings.json').read_text()) if (target/'caption-timings.json').exists() else {}
for item in items:
 slug=item['slug']
 if only and slug not in only: continue
 d=Path('/private/tmp/freedme-voice-cues')/slug;d.mkdir(parents=True,exist_ok=True)
 for stale in d.glob('*.png'): stale.unlink()
 subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(root/(slug+'.mp4')),'-vf','fps=1,crop=1440:50:0:950,scale=2880:100',str(d/'%04d.png')],check=True)
 def ocr(p):
  text=subprocess.run(['tesseract',str(p),'stdout','--psm','7'],capture_output=True,text=True,errors='replace').stdout.strip()
  n=norm(text);scores=[difflib.SequenceMatcher(None,n,k).ratio() for k in normalized]
  j=max(range(len(scores)),key=scores.__getitem__)
  return int(p.stem)-1,known[j] if scores[j]>.70 else None,text
 events=[];last=None
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
  for second,caption,raw in pool.map(ocr,sorted(d.glob('*.png'))):
   if caption and caption!=last:events.append({'time':second,'caption':caption});last=caption
 result[slug]=events
 (target/'caption-timings.json').write_text(json.dumps(result,indent=2))
 print(slug,len(events),'captions',flush=True)
