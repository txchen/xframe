import json,statistics,math,collections
from pathlib import Path
p=Path(__file__).parent;r=json.load(open(p/'events.json'));marks=[x for x in r if 'marker'in x];merged={};order=[0,1,1,0,1,0,0,1,0,1]
for x in r:
 if 'id'in x:
  d=dict(x)
  if 'submit'not in d:d.pop('block',None)
  merged.setdefault(x['id'],{}).update(d)
frames=[]
for a,b in zip(marks,marks[1:]):
 block=int(a['block'])
 if not 0<=block<10:continue
 for f in merged.values():
  if a['marker']+3<=f.get('submit',0)<b['marker']-1 and f.get('actual',0)>0 and 'gpuEnd'in f:frames.append(dict(f,mode=order[block],block=block))
ts=sorted(x['actual']for x in frames);ref=ts[0];indices=[round((x-ref)*60)for x in ts];im=statistics.mean(indices);tm=statistics.mean(ts)
period=sum((i-im)*(t-tm)for i,t in zip(indices,ts))/sum((i-im)**2 for i in indices);origin=tm-period*im
residual=sorted(abs(t-(origin+i*period))*1000 for i,t in zip(indices,ts));print('period_ms',period*1000,'lattice_residual_p95_ms',residual[math.ceil(.95*len(residual))-1],'max',max(residual))
bins=collections.defaultdict(lambda:[[],[]])
for f in frames:
 phase=((f['arrival']-origin)%period)*1000;bins[int(phase)][f['mode']].append((f['actual']-f['arrival'])*1000)
weighted=[];out=[]
for b,(a,c)in sorted(bins.items()):
 if min(len(a),len(c))<20:continue
 diff=statistics.mean(a)-statistics.mean(c);weight=min(len(a),len(c));weighted.append((diff,weight));o=dict(arrival_phase_bin_ms=b,baseline_n=len(a),phase2_n=len(c),baseline_mean_ms=statistics.mean(a),phase2_mean_ms=statistics.mean(c),reduction_ms=diff);out.append(o);print(o)
print('common-phase weighted mean reduction',sum(d*w for d,w in weighted)/sum(w for _,w in weighted)if weighted else None)
(p/'phase-analysis.json').write_text(json.dumps(dict(period_ms=period*1000,bins=out),indent=2))
