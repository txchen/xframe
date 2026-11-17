import sys,re,json,statistics
from read_tables import table
root=sys.argv[1]
t=table('time-info',root)[0];ep=int(t['mabs-epoch']);a,b=map(int,t['timebase-info_fmt'].split('/'));factor=a/b/1e9
joined=json.load(open(root+'/joined.json')); rows=table('signposts',root); vals=[]
for r in rows:
 if r['name']!='DrawableLifetime' or r['event-type']!='End':continue
 d=dict(re.findall(r'(surfaceID|timePresentCalled|targetTimestamp|targetPresentationTimestamp|preferredLatency)=([\da-fA-F,.]+)',r['message_fmt']))
 if not d:continue
 def seconds(k):return (int(d[k].replace(',',''))-ep)*factor
 sid=str(int(d['surfaceID'],16));p=seconds('timePresentCalled')
 matched=[j for j in joined if j['surface']==sid and abs(j['request_s']-p)<.002]
 if len(matched)!=1:continue
 j=matched[0];deadline=seconds('targetTimestamp');target=seconds('targetPresentationTimestamp');end=int(r['time'])/1e9
 vals.append(dict(j,deadline_s=deadline,target_s=target,lead_ms=(deadline-p)*1000,gpu_margin_ms=(deadline-j['app_gpu_end_s'])*1000,late_ms=(j['swap_s']-target)*1000,lifetime_swap_delta_ms=(end-j['swap_s'])*1000))
for k in ['lead_ms','gpu_margin_ms','late_ms','lifetime_swap_delta_ms']:
 x=sorted(v[k] for v in vals)
 if x:print(k,'n',len(x),'median',round(statistics.median(x),4),'p95',round(x[int(.95*(len(x)-1))],4),'range',round(x[0],4),round(x[-1],4))
print('on_target',sum(abs(x['late_ms'])<1 for x in vals),'one_refresh_late',sum(abs(x['late_ms']-16.667)<1 for x in vals))
json.dump(vals,open(root+'/deadlines.json','w'),indent=2)
