import json,statistics,collections
r=json.load(open('.build/deadline-probe/events.json')); frames={}
for row in r:frames.setdefault(row['id'],{}).update(row)
phases=collections.defaultdict(list)
for x in frames.values():
 if all(k in x for k in ['phase','actual','gpuEnd','submit']) and x['actual']>0 and x['gpuEnd']>0:phases[int(x['phase'])].append(x)
for p,rows in phases.items():
 rows.sort(key=lambda x:x['submit']);start=rows[0]['submit'];rows=[x for x in rows if x['submit']>start+5]
 print('phase',p,'frames',len(rows))
 if not rows:continue
 for name,a,b in [('gpu','gpuEnd','gpuStart'),('display_wait','actual','gpuEnd'),('arrival_display','actual','arrival'),('submit_lead','deadline','submit'),('gpu_margin','deadline','gpuEnd'),('actual_target','actual','target')]:
  if p==0 and name in ['submit_lead','gpu_margin','actual_target']:continue
  vals=sorted((x[a]-x[b])*1000 for x in rows)
  print(name,'median',round(statistics.median(vals),3),'p95',round(vals[int(.95*(len(vals)-1))],3))
 print('range',rows[0]['submit'],rows[-1]['submit'])
 if p:print('late>8ms',sum(x['actual']-x['target']>.008 for x in rows),'submitted_late',sum(x['submit']>x['deadline'] for x in rows))
