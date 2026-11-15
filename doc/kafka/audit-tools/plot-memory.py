from pathlib import Path
import os,json,csv
root=Path('/root/shuwen/s');p=root/'.bootstrap/kafka-audit/audit-20261115'
os.environ['MPLCONFIGDIR']=str(p/'matplotlib-cache')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
fig,axes=plt.subplots(1,2,figsize=(11,4.2),constrained_layout=True)
for label,color in [('seed','#c54b35'),('canonical','#287c9f')]:
 data=json.loads((p/f'memory-524288-{label}/samples.json').read_text())
 axes[0].plot([r['seconds'] for r in data['samples']],[r['VmRSS']/1024 for r in data['samples']],label=label,color=color)
axes[0].set(title='512 KiB × 16 replay deliveries',xlabel='Process elapsed time (s)',ylabel='Native process RSS (MiB)')
axes[0].legend();axes[0].grid(alpha=.25)
sustained=p/'memory-sustained/samples.json'
if sustained.exists():
 d=json.loads(sustained.read_text());rows=d['samples']
 axes[1].plot([r['seconds']/60 for r in rows],[r['VmRSS']/1024 for r in rows],color='#287c9f',linewidth=.8)
 axes[1].set(title='Canonical: 30-minute 1 KiB replay',xlabel='Process elapsed time (minutes)',ylabel='Native process RSS (MiB)')
 axes[1].grid(alpha=.25)
 with (p/'rss-sustained.csv').open('w') as f:
  writer=csv.DictWriter(f,fieldnames=['seconds','phase','VmRSS','VmHWM','RssAnon','cpu_seconds','fd_count'],extrasaction='ignore');writer.writeheader();writer.writerows(rows)
fig.suptitle('Kafka Consumer audit — /proc native PID sampling; Java Producer excluded',fontsize=11)
fig.savefig(root/'doc/kafka/KAFKA_MEMORY_RSS.png',dpi=160)
fig.savefig(root/'doc/kafka/KAFKA_MEMORY_RSS.pdf')
