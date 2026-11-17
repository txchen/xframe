import json,statistics,math
from pathlib import Path
p=Path('.build/av-arrival-clean-probe');r=json.load(open(p/'swap-joined.json'));out=[]
for b in range(10):
 f=[x for x in r if x['block']==b];v=sorted(x['total_ms']for x in f);t=sorted(set(x['actual']for x in f));g=[(y-x)*1000 for x,y in zip(t,t[1:])]
 o=dict(block=b,mode='AV-arrival'if b%2 else'AV-CV20.5',n=len(f),median=statistics.median(v),p95=v[math.ceil(len(v)*.95)-1],fps=(len(t)-1)/(t[-1]-t[0]),gaps25=sum(x>25 for x in g),gaps40=sum(x>40 for x in g));print(o);out.append(o)
(p/'analysis.json').write_text(json.dumps(out,indent=2))
