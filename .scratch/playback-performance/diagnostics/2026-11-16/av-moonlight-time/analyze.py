import json,math,statistics,sys
from pathlib import Path
sys.path.insert(0,'.build/instruments-display');from read_tables import table
root=Path('.build/av-moonlight-time-probe');epoch=int(table('time-info',root/'trace-export')[0]['mabs-epoch'])*125/3/1e9
raw=json.load(open(root/'events.json'));marks=[x for x in raw if 'block'in x];av=json.load(open(root/'swap-joined.json'));merged={}
for x in raw:
 if 'id'in x:merged.setdefault(x['id'],{}).update(x)
results=[]
for a,b in zip(marks,marks[1:]):
 block=int(a['block']);lo=a['marker']-epoch+3;hi=b['marker']-epoch-1
 if block>=10:continue
 if block%2:
  frames=[x for x in av if x['block']==block];times=sorted(set(x['actual']for x in frames));values=sorted(x['total_ms']for x in frames);submitted=sum(lo<=x.get('enqueue',0)-epoch<hi for x in raw)
 else:
  frames=[x for x in merged.values()if lo<=x.get('baselineSubmit',0)-epoch<hi and x.get('baselineActual',0)>0];times=sorted(set(x['baselineActual']-epoch for x in frames));values=sorted((x['baselineActual']-x['arrival'])*1000 for x in frames);submitted=len(frames)
 gaps=[(y-x)*1000 for x,y in zip(times,times[1:])]
 out=dict(block=block,mode='AV-CV-no-marker' if block%2 else 'MTK',n=len(frames),submitted=submitted,median=statistics.median(values)if values else None,p95=values[math.ceil(len(values)*.95)-1]if values else None,fps=(len(times)-1)/(times[-1]-times[0])if len(times)>1 else 0,gaps25=sum(x>25 for x in gaps),gaps40=sum(x>40 for x in gaps));results.append(out);print(out)
(root/'analysis.json').write_text(json.dumps(results,indent=2))
