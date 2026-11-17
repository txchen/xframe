import json,statistics,math
from pathlib import Path
p=Path(__file__).parent
r=json.loads((p/'events.json').read_text());marks=[x for x in r if 'marker'in x];fs={}
for x in r:
 if 'id'in x:fs.setdefault(x['id'],{}).update(x)
def dist(v):
 v=sorted(v)
 return dict(median=statistics.median(v),p95=v[math.ceil(.95*len(v))-1],min=v[0],max=v[-1]) if v else None
out=[]
for m,n in zip(marks,marks[1:]):
 b=int(m['block']);lo=m['marker']+3;hi=n['marker']-1
 if b<0:continue
 allf=[f for f in fs.values() if f.get('block')==b and lo<=f.get('submit',0)<hi]
 f=[f for f in allf if f.get('actual',0)>0 and 'gpuEnd'in f]
 a=dict(block=b,mode='scheduled-target' if b%2 else 'immediate-present',samples=len(f),missing=len(allf)-len(f),errors=sum(x.get('error',0) for x in allf),size=list(set((x['width'],x['height']) for x in allf)),drops=sum('drop'in x and lo<=x['time']<hi for x in r))
 for name,start,end in [('input_wait','arrival','picked'),('drawable_wait','acquire','ready'),('gpu_queue','submit','gpuStart'),('gpu','gpuStart','gpuEnd'),('display','gpuEnd','actual'),('total','arrival','actual')]:
  a[name]=dist([(x[end]-x[start])*1000 for x in f])
 ts=sorted(x['actual'] for x in fs.values() if lo<=x.get('actual',0)<hi)
 gaps=[(y-x)*1000 for x,y in zip(ts,ts[1:])];a['fps']=len(ts)/(hi-lo);a['gaps25']=sum(g>25 for g in gaps)
 out.append(a)
 print(b,a['mode'],len(f),'fps',round(a['fps'],2),'gaps',a['gaps25'],'drop',a['drops'],'wait',round(a['input_wait']['median'],2),'drawable',round(a['drawable_wait']['median'],2),'gpu',round(a['gpu']['median'],3),'display',round(a['display']['median'],2),'total',round(a['total']['median'],2),'p95',round(a['total']['p95'],2))
(p/'analysis.json').write_text(json.dumps(out,indent=2))
print('errors',sum(x.get('error',0) for x in r),'zero actual',sum(x.get('actual',1)==0 for x in r),'acquire failure',sum(x.get('acquireFailure',0) for x in r),'busy',sum(x.get('busy',0) for x in r))
