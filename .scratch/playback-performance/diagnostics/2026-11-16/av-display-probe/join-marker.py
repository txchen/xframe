import sys,json,collections,statistics,math
from pathlib import Path
sys.path.insert(0,'.build/instruments-display');from read_tables import table
root=Path('.build/av-display-probe');p=root/'marked';t=table('time-info',p)[0];epoch=int(t['mabs-epoch'])*125/3/1e9
acc=table('metal-io-surface-access',p);reads=collections.defaultdict(set)
for a in acc:
 if a['pid']=='652' and a['access-type']=='0':reads[int(a['surface-id'])].add((int(a['timestamp'])/1e9,a['cmdbuffer-id']))
m={}
for x in json.load(open(root/'marker.json')):m.setdefault(x['id'],{}).update(x)
bycmd=collections.defaultdict(list)
for x in m.values():
 if x.get('actual',0)<=0:continue
 start=x['submit']-epoch;end=x['actual']-epoch
 if not 1<start<14:continue
 rr=[(s,c) for s,c in reads[x['surface']] if start<=s<end]
 if len(set(c for s,c in rr))!=1:continue
 bycmd[rr[0][1]].append((end,rr[0][0]))
frames=json.load(open(root/'events.json'));bySurf=collections.defaultdict(list)
for f in frames:bySurf[f['surface']].append(f)
joined=[]
for ff in bySurf.values():
 for f,n in zip(ff,ff[1:]):
  start=f['enqueue']-epoch;nexttime=n['enqueue']-epoch
  if not 1<start<14:continue
  rr=sorted((s,c) for s,c in reads[f['surface']] if start<=s<min(nexttime,start+.08))
  if not rr:continue
  s,c=rr[0];marks=bycmd[c]
  if len(marks)!=1:continue
  end,mread=marks[0]
  joined.append(dict(id=f['id'],enqueue=start,ws_read=s,actual=end,total_ms=(end-start)*1000,enqueue_to_ws_ms=(s-start)*1000,ws_to_actual_ms=(end-s)*1000))
print('unambiguous marker commands',sum(len(x)==1 for x in bycmd.values()),'joined video',len(joined))
for k in ['total_ms','enqueue_to_ws_ms','ws_to_actual_ms']:
 a=sorted(x[k] for x in joined)
 if a:print(k,dict(median=statistics.median(a),p95=a[math.ceil(.95*len(a))-1],min=min(a),max=max(a)))
(root/'marker-joined.json').write_text(json.dumps(joined,indent=2))
