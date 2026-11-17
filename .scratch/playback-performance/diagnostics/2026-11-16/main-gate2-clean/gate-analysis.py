import json,statistics
from pathlib import Path
p=Path(__file__).parent;r=json.load(open(p/'events.json'));marks=[x for x in r if'marker'in x];merged={};out=[]
for x in r:
 if'allID'in x:
  d=dict(x)
  if'allSubmit'not in d:d.pop('block',None)
  merged.setdefault(x['allID'],{}).update(d)
a=sorted([x for x in merged.values()if'allSubmit'in x],key=lambda x:x['allSubmit'])
for m,n in zip(marks,marks[1:]):
 b=int(m['block']);lo=m['marker'];hi=n['marker']
 if b<0:continue
 fs=[x for x in a if lo<=x['allSubmit']<hi];stable=[x for x in fs if lo+3<=x['allSubmit']<hi-1];delay=[(x['observedAt']-x['allActual'])*1000 for x in stable if x.get('allActual',0)>0];injections=[x['injectedRepaint']for x in r if lo<=x.get('injectedRepaint',0)<hi]
 o=dict(block=b,submissions=len(fs),max_pending=max([x['pendingCount']for x in fs],default=0),stable_max_pending=max([x['pendingCount']for x in stable],default=0),backpressure=sum(lo<=x.get('presentationBackpressure',0)<hi for x in r),stable_backpressure=sum(lo+3<=x.get('presentationBackpressure',0)<hi-1 for x in r),callback_delay_median_ms=statistics.median(delay)if delay else None,redraws=sum(x['repeat']for x in fs),injections=[x-lo for x in injections]);out.append(o);print(o)
 for t in injections:
  print(' injection neighbors',[(round((x['allSubmit']-t)*1000,3),x['repeat'],x['pendingCount'],round((x['allActual']-x['allSubmit'])*1000,2)if x.get('allActual',0)>0 else None)for x in a if t-.02<x['allSubmit']<t+.05])
(p/'gate-analysis.json').write_text(json.dumps(out,indent=2))
