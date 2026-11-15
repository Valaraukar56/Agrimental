# Simulateur d'equilibrage (agent equilibrage). Lancer : python tools/sim_equilibrage.py
# Modele : joueur actif 3D, debit = moveSpeed x 2 x harvestRadius, achete l'option la moins chere.
# Drones (remplacent l'ouvrier) : cycle hangar > champ (vol) > coupe > retour > vente, voir data/drones.json et balance.world.
# growTime, prix, capacite de depart et ratio de prime sont lus dans data/crops.json et data/balance.json.
import json, math, random, heapq, statistics, sys
import os; D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data") + os.sep
def load(eqcosts=None, eq=None):
    ups=[u for u in json.load(open(D+"upgrades.json",encoding="utf-8")) if not u.get('webOnly')]
    ups+=json.load(open(D+"drones.json",encoding="utf-8")); fl=json.load(open(D+"fields.json",encoding="utf-8"))
    E=eq or json.load(open(D+"equipment.json",encoding="utf-8"))
    if eqcosts:
        for e,c in zip(E,eqcosts): e['cost']=c
    return ups,fl,E
def run(ups,fields,E,maxT=3*3600,dt=0.1,GT=None,CAP0=None,BONUS=None,seed=1,K=2.0,fcosts=None):
    random.seed(seed)
    bal=json.load(open(D+"balance.json",encoding="utf-8")); crops=json.load(open(D+"crops.json",encoding="utf-8"))
    crop=crops["wheat"]; PRICE=crop["sellPrice"]
    GT=GT if GT is not None else crop["growTime"]
    CAP0=CAP0 if CAP0 is not None else bal["baseStats"]["sackCapacity"]
    BONUS=BONUS if BONUS is not None else bal["completionBonusRatio"]
    GM0=bal["baseStats"]["growTimeMult"]
    W=bal["world"]; ts=W["tileStep"]
    def layout():
        cw={1:0,2:2*W["hubHalf"],3:0}; rh={1:0,2:2*W["hubHalf"],3:0}
        for f in fields:
            c,r=f['slot']['col'],f['slot']['row']; cw[c]=max(cw[c],f['width']*ts); rh[r]=max(rh[r],f['height']*ts)
        def ctr(d,k): return 0 if k==2 else (1 if k==3 else -1)*(d[2]/2+W["fieldGap"]+d[k]/2)
        return [math.hypot(ctr(cw,f['slot']['col']),ctr(rh,f['slot']['row'])) for f in fields]
    DIST=layout()
    DB=bal["baseStats"]
    lv={u['id']:0 for u in ups}; tier=0
    F=[]
    for i,f in enumerate(fields):
        n=f['width']*f['height']; c=fcosts[i] if fcosts else f['unlockCost']
        F.append(dict(d=DIST[i],w=f['width'],h=f['height'],cost=c,n=n,un=c==0,ripe=n,heap=[]))
    def stats():
        e=E[tier]; ms=e['set'].get('moveSpeed',6); r=e['set'].get('harvestRadius',0.9)
        s=dict(y=1,cap=CAP0+e['add'].get('sackCapacity',0),gm=GM0,auto=0.0,ms=ms,r=r,dn=DB['droneCount'],ds=DB['droneSpeed'],dc=DB['droneCargo'])
        for u in ups:
            l=lv[u['id']]
            if u['op']=='add': s[{'yieldPerTile':'y','sackCapacity':'cap','autoHarvestRate':'auto','droneCount':'dn','droneCargo':'dc'}[u['stat']]]+=u['value']*l
            elif u['stat']=='droneSpeed': s['ds']*=u['value']**l
            else: s['gm']*=u['value']**l
        return s
    st=stats(); snaps=[]; drones=[]; rev=dict(p=0.0,d=0.0); money=0; sack=0; t=0; trip=0; acc=0; aacc=0; log=[]
    def harvest(fl,now):
        nonlocal money
        fl['ripe']-=1; heapq.heappush(fl['heap'],now+GT*st['gm'])
        b=0
        if fl['ripe']==0 and len(fl['heap'])==fl['n']: b=math.ceil(fl['n']*st['y']*PRICE*BONUS); money+=b
        return b
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
            harvest(fl,t); money+=st['y']*PRICE; aacc-=1
        while len(drones)<st['dn']: drones.append(dict(s='wait',tm=0,cargo=0,f=None,acc=0))
        for d in drones:
            if d['s']=='wait':
                c=[fl for fl in F if fl['un'] and fl['ripe']>0]
                if c:
                    d['f']=max(c,key=lambda fl:fl['ripe']); d['s']='out'; d['tm']=d['f']['d']/st['ds']
            elif d['s'] in('out','back'):
                d['tm']-=dt
                if d['tm']<=0:
                    if d['s']=='out': d['s']='cut'; d['acc']=0
                    else:
                        v=d['cargo']*st['y']*PRICE; money+=v; rev['d']+=v; d['cargo']=0; d['s']='wait'
            if d['s']=='cut':
                fl=d['f']; d['acc']+=DB['droneHarvestRate']*dt
                while d['acc']>=1 and fl['ripe']>0 and d['cargo']<st['dc']:
                    v=harvest(fl,t); rev['d']+=v; d['cargo']+=1; d['acc']-=1
                if d['cargo']>=st['dc'] or fl['ripe']==0:
                    d['s']='back'; d['tm']=fl['d']/st['ds']
        un=[fl for fl in F if fl['un']]
        best=max(un,key=lambda fl:fl['ripe'])
        PR=st['ms']*2*st['r']*(10/10.8)
        if trip>0:
            trip-=dt
            if trip<=0: money+=sack*PRICE; rev['p']+=sack*PRICE; sack=0
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
            st=stats(); log.append((t,p[0],p[1],p[2])); snaps.append((t,rev['p'],rev['d']))
        t+=dt
    run.snaps=snaps
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
def drones_report(log):
    dr=[round(t/60,1) for t,k,i,c in log if k=='up' and i=='drone']
    print("drones (min du 1er,3e,5e,10e)",[dr[n-1] if len(dr)>=n else None for n in (1,3,5,10)],"total",len(dr))
    ev=[x for x in log if x[1]=='eq']; lastf=max(t for t,k,i,c in log if k=='field')
    S=run.snaps; b=[0]+[x[0] for x in ev]+[lastf]
    def at(tt):
        r=[x for x in S if x[0]<=tt]; return (r[-1][1],r[-1][2]) if r else (0,0)
    for n in range(len(b)-1):
        p0,d0=at(b[n]); p1,d1=at(b[n+1]); tot=(p1-p0)+(d1-d0)
        print(f"  revenu drones phase {n}: {100*(d1-d0)/tot if tot else 0:.0f} %")
def phases(log,E):
    lastf=max(t for t,k,i,c in log if k=='field'); log=[x for x in log if x[0]<=lastf]  # phases jusqu'au dernier champ
    ts=[0]+[t for t,k,i,c in log if k=='eq']+[log[-1][0]+1]
    for n in range(len(ts)-1):
        lo,hi=ts[n],ts[n+1]; ev=[x for x in log if lo<=x[0]<hi or (n==0 and x[0]<hi)]
        if n>0: ev=[x for x in log if lo<x[0]<hi]
        g=[];p=lo
        for x in ev: g.append(x[0]-p);p=x[0]
        nf=sum(1 for x in ev if x[1]=='field'); nu=len(ev)-nf
        print(f"{E[min(n,len(E)-1)]['id']:17s} {lo/60:6.1f}->{hi/60:6.1f} min ({(hi-lo)/60:5.1f}) achats {len(ev):3d} (champs {nf}, ameli {nu}) ecart max {max(g) if g else 0:.0f}s")
if __name__=="__main__":
    ups,fl,E=load([int(x) for x in sys.argv[1].split(',')] if len(sys.argv)>1 else None)
    L=run(ups,fl,E); report(L); phases(L,E); drones_report(L)
