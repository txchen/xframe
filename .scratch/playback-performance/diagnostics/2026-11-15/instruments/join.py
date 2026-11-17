import sys,json,statistics,bisect
from collections import defaultdict
from read_tables import table
root=sys.argv[1] if len(sys.argv)>1 else '.build/instruments-display'
req=table('ca-client-present-request',root); acc=table('metal-io-surface-access',root);gpu=table('metal-gpu-intervals',root);swaps=table('display-surface-swap',root)
gend=defaultdict(int); reads=defaultdict(list);outputs=defaultdict(set);ss=defaultdict(list)
for g in gpu:
 if g['state']=='Active':gend[g['cmdbuffer-id']]=max(gend[g['cmdbuffer-id']],int(g['start'])+int(g['duration']))
for a in acc:
 if a['pid']=='652':
  if a['access-type']=='0':reads[a['surface-id']].append((int(a['timestamp']),a['cmdbuffer-id']))
  if a['access-type']=='1':outputs[a['cmdbuffer-id']].add(a['surface-id'])
for s in swaps:ss[s['surface-id']].append(s)
for a in reads.values():a.sort()
for a in ss.values():a.sort(key=lambda x:int(x['timestamp']))
requests_by_surface=defaultdict(list)
for r in req: requests_by_surface[r['surface-id']].append(int(r['timestamp']))
for ts in requests_by_surface.values():ts.sort()
joined=[]
for r in req:
 t=int(r['timestamp']); end=gend.get(r['cmdbuffer-id']);read=next(((at,c) for at,c in reads[r['surface-id']] if at>=t),None)
 if not end or not read:continue
 rt,cmd=read
 next_request=next((x for x in requests_by_surface[r['surface-id']] if x>t),float('inf'))
 if rt>=next_request:continue
 if rt-t>80000000 or rt<end:continue
 sw=[]
 for out in outputs[cmd]:
  s=next((x for x in ss[out] if int(x['timestamp'])>=gend.get(cmd,rt)),None)
  if s and int(s['timestamp'])-rt<40000000:
   overwritten=any(x['pid']=='652' and x['access-type']=='1' and x['surface-id']==out and x['cmdbuffer-id']!=cmd and rt<int(x['timestamp'])<int(s['timestamp']) for x in acc)
   if not overwritten:sw.append(s)
 if len(sw)!=1:continue
 st=int(sw[0]['timestamp']);we=gend.get(cmd)
 joined.append({'request_s':t/1e9,'surface':r['surface-id'],'app_gpu_end_s':end/1e9,'ws_read_s':rt/1e9,'ws_gpu_end_s':we/1e9,'swap_s':st/1e9,'app_to_ws_ms':(rt-end)/1e6,'ws_work_ms':(we-rt)/1e6,'ws_to_swap_ms':(st-we)/1e6,'post_gpu_ms':(st-end)/1e6})
def summary(rows):
 out={'n':len(rows)}
 for k in ['app_to_ws_ms','ws_work_ms','ws_to_swap_ms','post_gpu_ms']:
  x=sorted(r[k] for r in rows)
  if x:out[k]={'median':round(statistics.median(x),3),'p95':round(x[int((len(x)-1)*.95)],3),'min':round(x[0],3),'max':round(x[-1],3)}
 return out
print(json.dumps(summary(joined),indent=2));print('middle',json.dumps(summary([x for x in joined if 6<x['request_s']<12]),indent=2));print('examples',json.dumps(joined[len(joined)//2:len(joined)//2+3],indent=2))
with open(root+'/joined.json','w') as f:json.dump(joined,f,indent=2)
