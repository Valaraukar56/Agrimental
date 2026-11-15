# Simulateur d'equilibrage (agent equilibrage). Lancer : python tools/sim_equilibrage.py
# Modele : joueur actif 3D, debit = moveSpeed x 2 x harvestRadius, achete l'option la moins chere.
# Attention : growTime (GT) et capacite de depart (CAP0) sont en parametres de run(), pas relus des JSON.
import json, math, random, heapq, statistics, sys
import os; D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data") + os.sep
def load(eqcosts=None, eq=None):
    ups=json.load(open(D+"upgrades.json",encoding="utf-8")); fl=json.load(open(D+"fields.json",encoding="utf-8"))
    E=eq or json.load(open(D+"equipment.json",encoding="utf-8"))
    if eqcosts:
        for e,c in zip(E,eqcosts): e['cost']=c
    return ups,fl,E
def run(ups,fields,E,maxT=3*3600,dt=0.1,GT=40,CAP0=30,BONUS=.5,seed=1,K=2.0,fcosts=None):
    random.seed(seed)
    lv={u['id']:0 for u in ups}; tier=0
    F=[]
    for i,f in enumerate(fields):
        n=f['width']*f['height']; c=fcosts[i] if fcosts else f['unlockCost']
        F.append(dict(w=f['width'],h=f['height'],cost=c,n=n,un=c==0,ripe=n,heap=[]))
    def stats():
        e=E[tier]; ms=e['set'].get('moveSpeed',6); r=e['set'].get('harvestRadius',0.9)
        s=dict(y=1,cap=CAP0+e['add'].get('sackCapacity',0),gm=1.0,auto=0.0,ms=ms,r=r)
        for u in ups:
            l=lv[u['id']]
            if u['op']=='add': s[{'yieldPerTile':'y','sackCapacity':'cap','autoHarvestRate':'auto'}[u['stat']]]+=u['value']*l
            else: s['gm']*=u['value']**l
        return s
    st=stats(); money=0; sack=0; t=0; trip=0; acc=0; aacc=0; log=[]
    def harvest(fl,now):
        nonlocal money
        fl['ripe']-=1; heapq.heappush(fl['heap'],now+GT*st['gm'])
        if fl['ripe']==0 and len(fl['heap'])==fl['n']: money+=math.ceil(fl['n']*st['y']*BONUS)
    while t<maxT:
        for fl in F:
            if fl['un']:
                h=fl['heap']
                while h and h[0]<=t: heapq.heappop(h); fl['ripe']+=1
        aacc+=st['auto']*dt
        while aacc>=1:
            c=[fl for fl in F if fl['un'] and fl['ripe']>0]
            if not c: aacc=0;break
            w=sum(fl['ripe'] for fl in c); r=random.uniform(0,w)
            for fl in c:
                r-=fl['ripe']
                if r<=0:break
            harvest(fl,t); money+=st['y']; aacc-=1
        un=[fl for fl in F if fl['un']]
        best=max(un,key=lambda fl:fl['ripe'])
        PR=st['ms']*2*st['r']*(10/10.8)
        if trip>0:
            trip-=dt
            if trip<=0: money+=sack; sack=0
        else:
            dens=best['ripe']/best['n']
            if sack>0 and (sack>=st['cap'] or dens<0.05):
                trip=2*(8+max(best['w'],best['h'])/2)/st['ms']; acc=0
            elif best['ripe']>0:
                acc+=PR*min(1,K*dens)*dt
                while acc>=1 and best['ripe']>0 and sack<st['cap']:
                    harvest(best,t); sack+=min(st['y'],st['cap']-sack); acc-=1
                if acc>=1: acc=0
        while True:
            op=[]
            for u in ups:
                if u['maxLevel'] is None or lv[u['id']]<u['maxLevel']:
                    op.append(('up',u['id'],math.ceil(u['baseCost']*u['costGrowth']**lv[u['id']])))
            for i,fl in enumerate(F):
                if not fl['un']: op.append(('field',i+1,fl['cost']))
            if tier+1<len(E): op.append(('eq',E[tier+1]['id'],E[tier+1]['cost']))
            p=min(op,key=lambda o:o[2])
            if p[2]>money: break
            money-=p[2]
            if p[0]=='up': lv[p[1]]+=1
            elif p[0]=='field': F[p[1]-1]['un']=True
            else: tier+=1
            st=stats(); log.append((t,p[0],p[1],p[2]))
        t+=dt
    return log
def report(log,full=False):
    prev=0;gaps=[]
    for x in log: gaps.append(x[0]-prev);prev=x[0]
    print("first",round(log[0][0]),"s")
    print("champs",[(i,round(t/60,1)) for t,k,i,c in log if k=='field'])
    print("equip",[(i,round(t/60,1)) for t,k,i,c in log if k=='eq'])
    for lo,hi in [(0,600),(600,1800),(1800,3600),(3600,7200),(7200,10800)]:
        g=[gaps[n] for n,x in enumerate(log) if lo<=x[0]<hi]
        if g: print(f"gaps {lo//60}-{hi//60} n={len(g)} med {statistics.median(g):.0f} max {max(g):.0f}")
if __name__=="__main__":
    ups,fl,E=load([int(x) for x in sys.argv[1].split(',')] if len(sys.argv)>1 else None)
    report(run(ups,fl,E))
