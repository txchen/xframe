import json,statistics,math
from pathlib import Path
root=Path('.build/selection-probe')
r=json.loads((root/'events.json').read_text());marks=[x for x in r if 'marker'in x]; frames={}
for x in r:
 if 'id'in x:frames.setdefault(x['id'],{})[int(x['stage'])]=x
out=[]
def dist(v):
 v=sorted(v)
 return {'median':statistics.median(v),'p95':v[math.ceil(.95*len(v))-1],'mean':statistics.mean(v)} if v else None
for m,n in zip(marks,marks[1:]):
 block=int(m['block'])
 if block<0:continue
 lo=m['marker']+5;hi=n['marker']-1
 allframes=[f for f in frames.values() if 1 in f and f[1]['block']==block and lo<=f[1]['time']<hi]
 shown=[f for f in allframes if all(k in f for k in range(1,6)) and f[5]['time']>0]
 a={'block':block,'mode':'latest' if block%2 else 'fifo','seconds':hi-lo,'picked':len(allframes),'shown':len(shown),'staleAtPick':sum(f[1]['newest']>f[1]['id'] for f in allframes),'queued2':sum(f[1]['queued']>1 for f in allframes)}
 for name,fun in [('arrival_pick',lambda f:f[1]['time']-f[1]['arrival']),('drawable_wait',lambda f:f[2]['time']-f[2]['drawableBegin']),('pick_submit',lambda f:f[3]['time']-f[1]['time']),('gpu',lambda f:f[4]['time']-f[4]['gpuStart']),('display_wait',lambda f:f[5]['time']-f[4]['time']),('arrival_display',lambda f:f[5]['time']-f[1]['arrival'])]:a[name]=dist([fun(f)*1000 for f in shown])
 actual=sorted(f[5]['time'] for f in frames.values() if 5 in f and lo<=f[5]['time']<hi)
 gaps=[(b-a)*1000 for a,b in zip(actual,actual[1:])];a['outputFPS']=len(actual)/(hi-lo);a['interval']=dist(gaps);a['gaps25']=sum(g>25 for g in gaps)
 out.append(a)
(root/'analysis.json').write_text(json.dumps(out,indent=2))
for a in out:
 print(a['block'],a['mode'],'fps',round(a['outputFPS'],2),'gaps',a['gaps25'],'stale',a['staleAtPick'],'/',a['picked'], 'pick',round(a['arrival_pick']['median'],2),'drawable',round(a['drawable_wait']['p95'],3),'display',round(a['display_wait']['median'],2),'total',round(a['arrival_display']['median'],2),round(a['arrival_display']['p95'],2))
