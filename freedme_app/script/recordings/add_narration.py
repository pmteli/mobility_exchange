"""Add local synthetic narration to the verified recordings without changing picture timing."""
import json, subprocess, hashlib, wave, array, os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
source=Path(os.environ.get('RECORDING_OUTPUT', str(ROOT/'output/rails-demo')))
output=Path(os.environ.get('NARRATION_OUTPUT', str(ROOT/'output/rails-demo-narrated')))
texts=json.loads(Path(__file__).with_name('narration-text.json').read_text())
timelines=json.loads((output/'caption-timings.json').read_text())
only=set(filter(None,os.environ.get('ONLY_NARRATION','').split(',')))
items=json.loads((source/'manifest.json').read_text())
previous={i['slug']:i for i in json.loads((output/'manifest.json').read_text())} if (output/'manifest.json').exists() else {}
items=[previous.get(i['slug'],i) if only and i['slug'] not in only else i for i in items]
(output/'audio').mkdir(parents=True,exist_ok=True)
def seconds(path):
 return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(path)]))
def vtt_time(t):
 ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02}.{ms%1000:03}'
for item in items:
 slug=item['slug']
 if only and slug not in only: continue
 duration=seconds(source/(slug+'.mp4'))
 audio=array.array('h',[0])*int((duration+.1)*24000)
 selected=[];last_end=0
 cues=timelines[slug]
 for index,cue in enumerate(cues):
  caption=cue['caption']
  if caption.startswith('Enter the simulated SMS code') or caption.startswith('Scenario complete'):continue
  text=texts.get(caption)
  if not text:raise ValueError('Missing narration: '+caption)
  stem=hashlib.sha256(text.encode()).hexdigest()[:16]
  aiff=output/'audio'/(stem+'.aiff');wav=aiff.with_suffix('.wav')
  if not aiff.exists():subprocess.run(['say','-v','Samantha','-r','165','-o',str(aiff),text],check=True)
  if not wav.exists():subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(aiff),'-ar','24000','-ac','1','-c:a','pcm_s16le',str(wav)],check=True)
  with wave.open(str(wav),'rb') as f:
   samples=array.array('h');samples.frombytes(f.readframes(f.getnframes()))
  length=len(samples)/24000
  start=max(cue['time']+.15,last_end+.3)
  # Keep narration close to the visible action, never overlapping another voice.
  next_role=next((c['time'] for c in cues[index+1:] if c['caption'].startswith('Sign in as ')),duration)
  if start-cue['time']>2.5 or start+length>min(duration-.15,next_role+.1):
   continue
  offset=round(start*24000)
  audio[offset:offset+len(samples)]=samples
  selected.append({'start':round(start,3),'end':round(start+length,3),'text':text,'caption':caption})
  last_end=start+length
 wav=output/(slug+'-narration.wav')
 with wave.open(str(wav),'wb') as f:
  f.setnchannels(1);f.setsampwidth(2);f.setframerate(24000);f.writeframes(audio.tobytes())
 subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(source/(slug+'.mp4')),'-i',str(wav),'-map','0:v:0','-map','1:a:0','-c:v','copy','-c:a','aac','-b:a','128k','-af','loudnorm=I=-18:TP=-2:LRA=7','-t',str(duration),'-movflags','+faststart',str(output/(slug+'.mp4'))],check=True)
 vtt='WEBVTT\n\n'+''.join(f'{vtt_time(c["start"])} --> {vtt_time(c["end"])}\n{c["text"]}\n\n' for c in selected)
 (output/(slug+'.vtt')).write_text(vtt)
 (output/(slug+'-transcript.txt')).write_text(item['title']+'\n\n'+'\n'.join(f'{vtt_time(c["start"])}  {c["text"]}' for c in selected)+'\n')
 item.update(narrated=True,narrationVoice='Samantha (computer-generated)',narrationCues=selected)
 print(slug,len(selected),'spoken cues',flush=True)
(output/'manifest.json').write_text(json.dumps(items,indent=2))
