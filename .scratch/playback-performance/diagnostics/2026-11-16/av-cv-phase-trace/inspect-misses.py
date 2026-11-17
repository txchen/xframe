exec(open('.build/av-cv-phase-probe/analyze.py').read().split("print('unambiguous")[0])
joined_ids={x['id'] for x in joined};raw=json.load(open(root/'events.json'));marks=[x for x in raw if 'marker'in x];frames.sort(key=lambda x:x['enqueue']);ticks=sorted(x['tick']for x in raw if 'tick'in x)
import bisect
for i,f in enumerate(frames):
 t=f['enqueue']-epoch
 if f['id']in joined_ids:continue
 block=next((a['block'] for a,b in zip(marks,marks[1:]) if a['marker']-epoch+3<t<b['marker']-epoch-1),None)
 if block is None:continue
 prev=frames[i-1];n=frames[i+1] if i+1<len(frames) else f
 idx=bisect.bisect_right(ticks,f['enqueue'])-1
 print('miss',block,f['id'],'trace',round(t,4),'age',round((f['enqueue']-f['arrival'])*1000,2),'gaps',round((f['enqueue']-prev['enqueue'])*1000,2),round((n['enqueue']-f['enqueue'])*1000,2),'tick',round((ticks[idx]-ticks[idx-1])*1000,2), 'surface',f['videoSurface'])
