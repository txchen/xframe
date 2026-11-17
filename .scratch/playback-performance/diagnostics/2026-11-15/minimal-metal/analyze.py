import collections,json,re,statistics,sys
from pathlib import Path
sys.path.insert(0,'.build/instruments-display')
from read_tables import table
out={}
for name in ['root','nested','overlay','bare']:
 root='.build/minimal-metal/'+name
 rows=table('displayed-surfaces-interval',root)
 result={'display_events':len(rows),'direct':sum(x['direct-to-display']=='1' for x in rows),'reasons':dict(collections.Counter(x['detachment-reason_fmt'] or 'none' for x in rows))}
 if name!='overlay':
  t=table('time-info',root)[0];ep=int(t['mabs-epoch']);a,b=map(int,t['timebase-info_fmt'].split('/'));vs=[]
  for x in table('signposts',root):
   if x['name']=='DrawableLifetime' and x['event-type']=='End':
    m=re.search(r'targetPresentationTimestamp=([\d,]+)',x['message_fmt'])
    if m:vs.append((int(x['time'])-(int(m[1].replace(',',''))-ep)*a/b)/1e6)
  result.update(matched=len(vs),late_median_ms=statistics.median(vs),late_p95_ms=sorted(vs)[int(.95*(len(vs)-1))],one_refresh_late=sum(abs(x-16.667)<1 for x in vs))
 out[name]=result
print(json.dumps(out,indent=2))
Path('.scratch/playback-performance/diagnostics/2026-11-15/minimal-metal/results.json').write_text(json.dumps(out,indent=2))
