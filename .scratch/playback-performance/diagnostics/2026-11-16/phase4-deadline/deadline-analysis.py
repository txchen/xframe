import json,bisect,statistics,collections
from pathlib import Path
p=Path(__file__).parent;r=json.load(open(p/'events.json'));marks=[x for x in r if 'marker'in x];f={};ticks=sorted((x['tick'],x['target'])for x in r if'tick'in x);ts=[x[0]for x in ticks];results=[]
for x in r:
 if'id'in x:
  d=dict(x)
  if'submit'not in d:d.pop('block',None)
  f.setdefault(x['id'],{}).update(d)
for m,n in zip(marks,marks[1:]):
 b=int(m['block']);lo=m['marker']+3;hi=n['marker']-1
 if b<0:continue
 a=sorted([x for x in f.values()if x.get('block')==b and lo<=x.get('submit',0)<hi],key=lambda x:x['submit'])
 late=[];leads=[]
 for x in a:
  if not x.get('actual',0)>0 or 'gpuEnd'not in x:continue
  j=bisect.bisect_right(ts,x['submit'])-1
  if j<0 or x['submit']-ts[j]>.003:continue
  target=ticks[j][1];delta=(x['actual']-target)*1000;leads.append((target-x['gpuEnd'])*1000)
  if delta>25:late.append(dict(offset=x['submit']-m['marker'],submit_lead_ms=(target-x['submit'])*1000,gpu_lead_ms=(target-x['gpuEnd'])*1000,actual_delta_ms=delta))
 missed=[x for x in r if lo<=x.get('missedDeadline',0)<hi]
 o=dict(block=b,frames=len(a),missing=sum(x.get('actual',0)<=0 for x in a),late_frames=len(late),missed_deadlines=len(missed),min_gpu_lead_ms=min(leads)if leads else None,first_late=late[0]if late else None);results.append(o);print(o)
(p/'deadline-analysis.json').write_text(json.dumps(results,indent=2))
