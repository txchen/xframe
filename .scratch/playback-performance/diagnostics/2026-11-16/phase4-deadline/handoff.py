import json, bisect, statistics
from pathlib import Path
p=Path(__file__).parent;r=json.load(open(p/'events.json'));a={};s={};marks=[x for x in r if 'marker'in x];ticks=sorted((x['tick'],x['target'])for x in r if 'tick'in x);tt=[x[0]for x in ticks]
for x in r:
 if 'allID'in x:
  d=dict(x)
  if 'allSubmit'not in d:d.pop('block',None)
  a.setdefault(x['allID'],{}).update(d)
 if 'id'in x:
  d=dict(x)
  if 'submit'not in d:d.pop('block',None)
  s.setdefault(x['id'],{}).update(d)
allf=sorted([x for x in a.values()if 'allSubmit'in x],key=lambda x:x['allSubmit'])
print('all submissions',len(allf),'redraws',sum(x['repeat']for x in allf),'actual zero',sum(x.get('allActual',1)==0 for x in allf))
ready=[x['firstReady'] for x in r if 'firstReady'in x]
for t in ready:
 print('firstReady',t,[(round((x['allSubmit']-t)*1000,3),x['repeat'],x.get('allActual',0)-x['allSubmit'])for x in allf if t-.05<x['allSubmit']<t+.1])
for m,n in zip(marks,marks[1:]):
 b=int(m['block']);lo=m['marker'];hi=n['marker'];fs=[x for x in allf if lo<=x['allSubmit']<hi]
 if not fs:continue
 print('\nBLOCK',b,'first five')
 for x in fs[:5]:
  t=x['allSubmit'];j=bisect.bisect_right(tt,t)-1;target=ticks[j][1]if j>=0 and t-tt[j]<.002 else None
  pending=[q for q in allf if q['allSubmit']<t and q.get('allActual',0)>t]
  prev=[q for q in allf if q['allSubmit']<t]
  gap=(t-prev[-1]['allSubmit'])*1000 if prev else None
  prior=[q['allActual']for q in pending if q['allSubmit']<lo]
  print(dict(offset_ms=round((t-lo)*1000,2),gap_ms=round(gap,2)if gap else None,pending=len(pending),old_pending=len(prior),repeat=x['repeat'],target_to_actual_ms=round((x.get('allActual',0)-target)*1000,2)if target else None,old_last_minus_expected_ms=round((max(prior)-target-1/60)*1000,2)if target and prior else None))
