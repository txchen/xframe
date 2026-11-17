import sys,json,collections,bisect,statistics
from pathlib import Path
sys.path.insert(0,'.build/instruments-display');from read_tables import table
root=Path('.build/av-duration-clean-probe');p=root/'trace-export';t=table('time-info',p)[0];epoch=int(t['mabs-epoch'])*125/3/1e9
raw=json.load(open(root/'events.json'));marks=[x for x in raw if 'marker'in x];frames=[x for x in raw if 'videoSurface'in x];bySurf=collections.defaultdict(list)
for f in frames:bySurf[f['videoSurface']].append(f)
acc=table('metal-io-surface-access',p);gpu=table('metal-gpu-intervals',p);sw=table('display-surface-swap',p)
reads=collections.defaultdict(set);outs=collections.defaultdict(set);writes=collections.defaultdict(set);swaps=collections.defaultdict(list);ends={}
for a in acc:
 if a['pid']!='652':continue
 sid=int(a['surface-id']);cmd=a['cmdbuffer-id'];tm=int(a['timestamp'])/1e9
 if a['access-type']=='0':reads[sid].add((tm,cmd))
 if a['access-type']=='1':outs[cmd].add(sid);writes[sid].add((tm,cmd))
for d in [reads,writes]:
 for k,v in d.items():d[k]=sorted(v)
for g in gpu:
 if g['state']=='Active':ends[g['cmdbuffer-id']]=max(ends.get(g['cmdbuffer-id'],0),(int(g['start'])+int(g['duration']))/1e9)
for s in sw:swaps[int(s['surface-id'])].append(int(s['timestamp'])/1e9)
for v in swaps.values():v.sort()
old={x['id']:x for x in json.load(open(root/'alternating-joined.json'))};joined=[];reasons=collections.Counter()
for ff in bySurf.values():
 for i,f in enumerate(ff):
  start=f['enqueue']-epoch;nextt=ff[i+1]['enqueue']-epoch if i+1<len(ff)else start+.08
  block=next((a['block']for a,b in zip(marks,marks[1:])if a['marker']-epoch+3<start<b['marker']-epoch-1),None)
  if block is None:continue
  rr=[(tm,c)for tm,c in reads[f['videoSurface']]if start<=tm<min(nextt,start+.08)]
  if not rr:reasons['no_read']+=1;continue
  rt,c=rr[0];end=ends.get(c)
  if end is None:reasons['no_gpu_end']+=1;continue
  found=[]
  for sid in outs[c]:
   times=swaps[sid];j=bisect.bisect_left(times,end)
   if j>=len(times):continue
   st=times[j]
   if st-rt>.05:continue
   if any(cc!=c and rt<tm<st for tm,cc in writes[sid]):continue
   found.append(st)
  if len(set(found))!=1:reasons['ambiguous_or_overwritten']+=1;continue
  st=found[0];o=old.get(f['id']);joined.append(dict(id=f['id'],block=block,enqueue=start,actual=st,total_ms=(st-(f['arrival']-epoch))*1000,enqueue_display_ms=(st-start)*1000,marker_difference_ms=None if o is None else (o['actual']-st)*1000))
print('joined',len(joined),'unjoined',dict(reasons))
for b in range(10):
 a=[x for x in joined if x['block']==b];d=[x['marker_difference_ms']for x in a if x['marker_difference_ms']is not None];print(b,len(a),'total',statistics.median(x['total_ms']for x in a),'enqueue',statistics.median(x['enqueue_display_ms']for x in a),'marker delta',statistics.median(d),max(map(abs,d)))
(root/'swap-joined.json').write_text(json.dumps(joined,indent=2))
