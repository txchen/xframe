import sys,json,collections,statistics,math
from pathlib import Path
sys.path.insert(0,'.build/instruments-display');from read_tables import table
root=Path('.build/av-duration-probe');p=root/'trace-export';t=table('time-info',p)[0];epoch=int(t['mabs-epoch'])*125/3/1e9
acc=table('metal-io-surface-access',p);reads=collections.defaultdict(set)
for a in acc:
 if a['pid']=='652' and a['access-type']=='0':reads[int(a['surface-id'])].add((int(a['timestamp'])/1e9,a['cmdbuffer-id']))
m={}
for x in json.load(open(root/'events.json')):
 if 'id'in x:m.setdefault(x['id'],{}).update(x)
bycmd=collections.defaultdict(list)
for x in m.values():
 if x.get('actual',0)<=0 or 'markerSurface'not in x:continue
 start=x['submit']-epoch;end=x['actual']-epoch
 if not 1<start<160:continue
 rr=[(s,c) for s,c in reads[x['markerSurface']] if start<=s<end]
 if len(set(c for s,c in rr))!=1:continue
 bycmd[rr[0][1]].append((end,rr[0][0]))
frames=[x for x in m.values() if 'videoSurface'in x];bySurf=collections.defaultdict(list)
for f in frames:bySurf[f['videoSurface']].append(f)
joined=[]
for ff in bySurf.values():
 for f,n in zip(ff,ff[1:]):
  start=f['enqueue']-epoch;nexttime=n['enqueue']-epoch
  if not 1<start<160:continue
  rr=sorted((s,c) for s,c in reads[f['videoSurface']] if start<=s<min(nexttime,start+.08))
  if not rr:continue
  s,c=rr[0];marks=bycmd[c]
  if len(marks)!=1:continue
  end,mread=marks[0]
  joined.append(dict(id=f['id'],enqueue=start,ws_read=s,actual=end,total_ms=(end-(f['arrival']-epoch))*1000,enqueue_display_ms=(end-start)*1000,enqueue_to_ws_ms=(s-start)*1000,ws_to_actual_ms=(end-s)*1000))
print('unambiguous marker commands',sum(len(x)==1 for x in bycmd.values()),'joined video',len(joined))
for k in ['total_ms','enqueue_display_ms','enqueue_to_ws_ms','ws_to_actual_ms']:
 a=sorted(x[k] for x in joined)
 if a:print(k,dict(median=statistics.median(a),p95=a[math.ceil(.95*len(a))-1],min=min(a),max=max(a)))
(root/'alternating-joined.json').write_text(json.dumps(joined,indent=2))

raw=json.load(open(root/'events.json'));marks=[x for x in raw if 'marker'in x];out=[]
for first,last in zip(marks,marks[1:]):
 b=int(first['block']);lo=first['marker']-epoch+3;hi=last['marker']-epoch-1
 if b>=10:continue
 if True:
  f=[x for x in joined if lo<=x['enqueue']<hi];values=[x['total_ms'] for x in f];ts=sorted(set(x['actual'] for x in f));submitted=[x for x in frames if lo<=x['enqueue']-epoch<hi]
 else:
  f=[x for x in m.values() if lo<=x.get('baselineSubmit',0)-epoch<hi and x.get('baselineActual',0)>0];values=[(x['baselineActual']-x['arrival'])*1000 for x in f];ts=sorted(set(x['baselineActual']-epoch for x in f));submitted=f
 gaps=[(y-x)*1000 for x,y in zip(ts,ts[1:])];values.sort()
 a=dict(block=b,mode='invalid-duration' if b%2 else 'fixed-duration',n=len(f),submitted=len(submitted),median=statistics.median(values) if values else None,p95=values[math.ceil(.95*len(values))-1] if values else None,fps=(len(ts)-1)/(ts[-1]-ts[0]) if len(ts)>1 else 0,gaps25=sum(g>25 for g in gaps),gaps40=sum(g>40 for g in gaps))
 out.append(a);print(a)
(root/'alternating-analysis.json').write_text(json.dumps(out,indent=2))
for first,last in zip(marks,marks[1:]):
 b=int(first['block'])
 if b>=10:continue
 lo=first['marker']-epoch+3;hi=last['marker']-epoch-1;reasons=collections.Counter()
 for ff in bySurf.values():
  for f,n in zip(ff,ff[1:]):
   start=f['enqueue']-epoch;nexttime=n['enqueue']-epoch
   if not lo<=start<hi:continue
   rr=sorted((s,c) for s,c in reads[f['videoSurface']] if start<=s<min(nexttime,start+.08))
   if not rr:reasons['no_ws_read']+=1
   elif not bycmd[rr[0][1]]:reasons['no_unambiguous_marker']+=1
   elif len(bycmd[rr[0][1]])!=1:reasons['multiple_marker_match']+=1
   else:reasons['matched']+=1
 print('coverage',b,dict(reasons))
