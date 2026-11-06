"""Generate editable diagrams.net pages and matching SVG/PNG ER diagrams locally."""
from pathlib import Path
from math import ceil, hypot
import json, re, html, heapq
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
SPEC = HERE / 'model-definition.json'
S = json.loads(SPEC.read_text(encoding='utf-8'))
SQL = (HERE.parents[1] / 'src/main/resources/db/migration/V1__initial_schema.sql').read_text(encoding='utf-8')
FONT = 'C:/Windows/Fonts/malgun.ttf'
BOLD = 'C:/Windows/Fonts/malgunbd.ttf'
FONTS = {n: ImageFont.truetype(FONT, n) for n in (16, 18, 20, 22, 24, 32)}
BF = {n: ImageFont.truetype(BOLD, n) for n in (20, 22, 24, 32)}
TABLES = {}
for name, body in re.findall(r'CREATE TABLE\s+(\w+)\s*\((.*?)\n\);', SQL, re.S | re.I):
    cols = {}
    for line in body.splitlines():
        m = re.match(r'\s*(\w+)\s+(VARCHAR\(\d+\)|CHAR\(\d+\)|DECIMAL\(\d+,\s*\d+\)|BIGINT|INTEGER|DATE|TIMESTAMP)', line, re.I)
        if m:
            cols[m[1].upper()] = m[2].upper().replace(' ', '')
    TABLES[name.upper()] = cols
N = {}
for row in S['entities']:
    N[row[0]] = dict(name=row[0], physical=row[1], fields=[], group='staff')
    for raw in row[4].split(';'):
        a = raw.split('/')
        N[row[0]]['fields'].append(dict(name=a[0], col=a[1], pk=len(a)>4 and a[4]=='P', fk=False))
INHERIT = []
for parent, discriminator, subtypes in S['subtypes']:
    pkey = S['primary_keys'][parent][0]
    source = next(a for a in N[parent]['fields'] if a['name']==pkey)
    for name, physical, code, attrs in subtypes:
        N[name] = dict(name=name, physical=physical, fields=[dict(name=pkey, col=source['col'], pk=True, fk=True)], group='staff', subtype=True, code=code)
        if attrs:
            for raw in attrs.split(';'):
                a=raw.split('/')
                N[name]['fields'].append(dict(name=a[0], col=a[1], pk=False, fk=False))
        INHERIT.append((parent,name,discriminator+'='+code,'inherit',False))
REL=[]
for row in S['relations']:
    parent, child, pk, fk, col, name = row[:6]
    field=next((a for a in N[child]['fields'] if a['col']==col),None)
    if field is None:
        field=dict(name=fk,col=col,pk=child=='평가상세',fk=True)
        N[child]['fields'].append(field)
    field['fk']=True
    REL.append((parent,child,name,'relation',len(row)>7 and row[7]))
for name,node in N.items():
    if name in ['프로젝트평가','고객평가','PM평가','동료평가','평가항목','평가상세']:
        node['group']='evaluation'
    if name in ['휴가종류','휴가정책','휴가신청','연차부여내역','연차사용내역']:
        node['group']='leave'
    for a in node['fields']:
        a['nullable']=a['name'] in S['nullable_attributes'].get(name,[])
        a['type']=TABLES.get(node['physical'],{}).get(a['col'],'')
        # Additive extensions carry precise physical metadata independently of SQL generation order.
        metadata=next((m for m in S.get('entity_metadata',{}).get(name,{}).get('columns',[]) if m['physical_name']==a['col']),None)
        if metadata:
            a['nullable']=metadata['nullable']
            a['type']=metadata['data_type']
    node['fields'].sort(key=lambda a:(not a['pk'],not a['fk']))
COLORS={'staff':('#e8f1ff','#315d92'),'evaluation':('#f0eaff','#70519b'),'leave':('#e5f5ee','#34735b')}
GRID=20
W=420

def pos_grid(names, pitch_x=660, pitch_y=620):
    return {name:(80+c*pitch_x,160+r*pitch_y) for name,c,r in names}

PAGES=[
 dict(key='00_overview',title='통합 ERD 개요',overview=True,width=4260,height=2740,
      positions=pos_grid([
       ('권한',0,0),('사원권한',1,0),('사원',2,0),('발주처경쟁관계',3,0),('발주처',4,0),('고객담당자',5,0),
       ('기술',0,1),('직원보유기술',1,1),('개발직원',2,1),('비개발직원',3,1),('프로젝트',4,1),
       ('외부경력이력',1,2),('프로젝트참여',2,2),('직무수행이력',3,2),('직무',4,2),
       ('휴가종류',0,3),('휴가정책',1,3),('휴가신청',2,3),('프로젝트평가',3,3),('평가항목',4,3),('평가상세',5,3),
       ('연차부여내역',1,4),('연차사용내역',2,4),('고객평가',3,4),('PM평가',4,4),('동료평가',5,4)],660,480),
      notes=['루트 엔터티 21개 + 하위 유형 5개 / 일반 관계 28개 + 상속 5개. 개요는 PK·FK, 신규 경쟁관계는 전체 속성·CHECK를 표시합니다.',
             '사원 DEV/NONDEV, 평가 CUSTOMER/PM/PEER는 각각 완전배타입니다. 상속별 1 : 0..1, 각 상위 레코드는 정확히 한 하위 유형을 가집니다.']),
 dict(key='01_staff_project',title='직원 · 프로젝트 · 기술',overview=False,width=2680,height=2700,
      positions=pos_grid([('권한',0,0),('사원권한',1,0),('사원',2,0),('비개발직원',3,0),
         ('기술',0,1),('직원보유기술',1,1),('개발직원',2,1),('외부경력이력',3,1),
         ('발주처',0,2),('프로젝트',1,2),('프로젝트참여',2,2),('직무수행이력',3,2),('고객담당자',0,3),('발주처경쟁관계',1,3),('직무',2,3)]),
      notes=['사원 유형은 DEV / NONDEV 중 정확히 하나입니다. 개발직원만 프로젝트참여·기술·외부경력을 가집니다.',
             'UNIQUE: 로그인ID, (사번·권한번호), (프로젝트번호·참여사번), (사번·기술번호). 실제 투입·직무와 과거 시점은 직무수행이력으로 조회합니다.']),
 dict(key='02_evaluation',title='프로젝트 평가 · 고객 의뢰 및 보고',overview=False,width=2020,height=2740,
      positions=pos_grid([('발주처',0,0),('고객담당자',1,0),('프로젝트',2,0),
         ('평가항목',0,1),('프로젝트평가',1,1),('프로젝트참여',2,1),
         ('고객평가',0,2),('PM평가',1,2),('동료평가',2,2),('평가상세',1,3)]),
      notes=['고객 / PM / 동료 평가는 완전배타입니다. 평가상세 PK = (평가번호, 항목번호). 평가 완료 시 평가일과 필수 항목을 검증합니다.',
             '앱 트랜잭션: 평가자·피평가자의 같은 프로젝트 여부, PM 직무 적격성, 고객담당자의 발주처 일치, 동료의 자기 평가 금지를 검사합니다.']),
 dict(key='03_leave',title='휴가 신청 · 정책 · 연차 원장',overview=False,width=2680,height=2220,
      positions=pos_grid([('사원',0,0),('휴가정책',2,0),('휴가종류',3,0),
         ('휴가신청',1,1),('연차부여내역',0,2),('연차사용내역',1,2)],660,640),
      notes=['처리자사번은 대기 중 NULL 허용(0..1)입니다. 한도단위 DAY/HOUR/MINUTE와 별도로 신청·부여·사용 원장은 모두 분 단위입니다.',
             '승인·차감은 동일 트랜잭션, 동일 사원·유효기간·잔여량을 검사합니다. 취소는 사용 행을 보존합니다. 프로젝트 공백은 사원·투입 기간 교차 조회로 구합니다.'])
]

def field_lines(page,node):
    competition=node['physical']=='CLIENT_COMPETITION'
    fs=[a for a in node['fields'] if not page['overview'] or competition or a['pk'] or a['fk']]
    result=[]
    for a in fs:
        key='PK/FK' if a['pk'] and a['fk'] else 'PK' if a['pk'] else 'FK' if a['fk'] else '·'
        nullable=' [NULL]' if a['nullable'] else (' [NN]' if competition else '')
        typ='' if page['overview'] and not competition else ' : '+a['type'].lower()
        result.append(f"{key}  {a['name']}{typ}{nullable}")
    if competition:
        result.extend(['CHECK CLIENT_ID_A < CLIENT_ID_B',
                       'CHECK RELEASED_ON IS NULL OR',
                       '   RELEASED_ON >= REGISTERED_ON'])
    return result

def side_anchor(rect,toward,fraction=.5):
    x,y,w,h=rect; tx,ty=toward
    dx,dy=tx-(x+w/2),ty-(y+h/2)
    if abs(dx)>abs(dy):
        side='right' if dx>0 else 'left'; q=(x+w if dx>0 else x,y+round(h*fraction/20)*20)
        return q,(q[0]+(40 if dx>0 else -40),q[1]),side
    side='bottom' if dy>0 else 'top';q=(x+round(w*fraction/20)*20,y+h if dy>0 else y)
    return q,(q[0],q[1]+(40 if dy>0 else -40)),side

def route(start,end,blocked,maxx,maxy,traffic):
    s=(round(start[0]/GRID),round(start[1]/GRID)); t=(round(end[0]/GRID),round(end[1]/GRID))
    todo=[(0,0,s[0],s[1],-1)];best={(s[0],s[1],-1):0};prev={};dest=None
    while todo:
        _,cost,x,y,d=heapq.heappop(todo);state=(x,y,d)
        if cost>best.get(state,1e30):continue
        if (x,y)==t:dest=state;break
        for nd,(dx,dy) in enumerate(((1,0),(0,1),(-1,0),(0,-1))):
            nx,ny=x+dx,y+dy
            if nx<2 or ny<6 or nx>maxx or ny>maxy or ((nx,ny) in blocked and (nx,ny) not in (s,t)):continue
            nc=cost+1+(.65 if d>=0 and d!=nd else 0)+traffic.get((nx,ny),0)*.18
            ns=(nx,ny,nd)
            if nc<best.get(ns,1e30):
                best[ns]=nc;prev[ns]=state
                heapq.heappush(todo,(nc+abs(nx-t[0])+abs(ny-t[1]),nc,nx,ny,nd))
    if dest is None:return [start,(start[0],end[1]),end]
    points=[]
    while dest in prev:
        points.append((dest[0]*GRID,dest[1]*GRID));traffic[(dest[0],dest[1])]=traffic.get((dest[0],dest[1]),0)+1;dest=prev[dest]
    points.append(start);points.reverse()
    simple=[]
    for pt in points:
        if len(simple)>=2 and ((simple[-2][0]==simple[-1][0]==pt[0]) or (simple[-2][1]==simple[-1][1]==pt[1])):simple[-1]=pt
        else:simple.append(pt)
    return simple

def build(page):
    rects={};lines={}
    for name,(x,y) in page['positions'].items():
        lines[name]=field_lines(page,N[name]);h=ceil((82+len(lines[name])*28)/20)*20
        rects[name]=(x,y,W,h)
    blocked=set()
    for x,y,w,h in rects.values():
        for gx in range((x-20)//20,(x+w+20)//20+1):
            for gy in range((y-20)//20,(y+h+20)//20+1):blocked.add((gx,gy))
    relations=[r for r in REL+INHERIT if r[0] in rects and r[1] in rects]
    endpoints={};side_counts={}
    for i,(pa,ch,name,kind,optional) in enumerate(relations):
        ar,br=rects[pa],rects[ch]
        aside=side_anchor(ar,(br[0]+br[2]/2,br[1]+br[3]/2))[2]
        bside=side_anchor(br,(ar[0]+ar[2]/2,ar[1]+ar[3]/2))[2]
        endpoints[i]=(aside,bside)
        for key in ((pa,aside),(ch,bside)):side_counts[key]=side_counts.get(key,0)+1
    used_sides={};edges=[];traffic={}
    for i,(pa,ch,name,kind,optional) in enumerate(relations):
        aside,bside=endpoints[i]
        ak,bk=(pa,aside),(ch,bside)
        used_sides[ak]=used_sides.get(ak,0)+1;used_sides[bk]=used_sides.get(bk,0)+1
        af,bf=used_sides[ak]/(side_counts[ak]+1),used_sides[bk]/(side_counts[bk]+1)
        ar,br=rects[pa],rects[ch]
        aa,ao,aside=side_anchor(ar,(br[0]+br[2]/2,br[1]+br[3]/2),af)
        ba,bo,bside=side_anchor(br,(ar[0]+ar[2]/2,ar[1]+ar[3]/2),bf)
        path=[aa]+route(ao,bo,blocked,page['width']//20-2,(page['height']-180)//20,traffic)+[ba]
        edges.append(dict(parent=pa,child=ch,name=name,kind=kind,optional=optional,points=path,aside=aside,bside=bside))
    return rects,lines,edges

def escape(s):return html.escape(str(s),quote=True)

class Canvas:
    def __init__(self,w,h):
        self.svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">', '<rect width="100%" height="100%" fill="white"/>']
        self.im=Image.new('RGB',(w,h),'white');self.d=ImageDraw.Draw(self.im)
    def line(self,pts,color='#64748b',width=2,dash=False):
        p=' '.join(f'{x},{y}' for x,y in pts); da=' stroke-dasharray="8 5"' if dash else ''
        self.svg.append(f'<polyline points="{p}" fill="none" stroke="{color}" stroke-width="{width}"{da}/>')
        if not dash:self.d.line(pts,fill=color,width=width,joint='curve')
        else:
            for (ax,ay),(bx,by) in zip(pts,pts[1:]):
                length=hypot(bx-ax,by-ay)
                if not length:continue
                ux,uy=(bx-ax)/length,(by-ay)/length
                for t in range(0,int(length),13):
                    e=min(t+8,length)
                    self.d.line([(ax+ux*t,ay+uy*t),(ax+ux*e,ay+uy*e)],fill=color,width=width)
    def rect(self,x,y,w,h,fill='white',stroke='#94a3b8',width=2):
        self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>')
        self.d.rectangle((x,y,x+w,y+h),fill=fill,outline=stroke,width=width)
    def circle(self,x,y,r,color='#64748b'):
        self.svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="white" stroke="{color}" stroke-width="2"/>');self.d.ellipse((x-r,y-r,x+r,y+r),fill='white',outline=color,width=2)
    def text(self,x,y,t,size=20,bold=False,color='#24334a'):
        weight='bold' if bold else 'normal';self.svg.append(f'<text x="{x}" y="{y+size}" font-family="Malgun Gothic,Noto Sans KR,sans-serif" font-size="{size}" font-weight="{weight}" fill="{color}">{escape(t)}</text>')
        self.d.text((x,y),t,font=BF[size] if bold else FONTS[size],fill=color)
    def marker(self,point,other,many=False,optional=False,color='#64748b'):
        x,y=point;dx,dy=other[0]-x,other[1]-y;mag=hypot(dx,dy) or 1;ux,uy=dx/mag,dy/mag;vx,vy=-uy,ux
        def q(a,b=0):return (x+ux*a+vx*b,y+uy*a+vy*b)
        if many:
            self.line([q(0,-8),q(16),q(0,8)],color);self.line([q(0),q(16)],color)
        else:self.line([q(8,-8),q(8,8)],color)
        if optional:self.circle(*q(28),5,color)
        else:self.line([q(18,-8),q(18,8)],color)

def export_page(page,mxfile):
    rects,lines,edges=build(page);c=Canvas(page['width'],page['height'])
    c.text(70,32,page['title'],32,True)
    subtitle=('SI 직원·프로젝트·평가·휴가 / 정보 차단벽 추가 2026-11-06'
              if page['key'] in ('00_overview','01_staff_project')
              else 'SI 직원·프로젝트·평가·휴가 / 확정 논리설계 2026-11-04')
    c.text(70,82,subtitle,20,color='#64748b')
    label_boxes=[]
    for edge in edges:
        color='#70519b' if edge['kind']=='inherit' else '#64748b';pts=edge['points']
        c.line(pts,color,2,edge['kind']=='inherit')
        c.marker(pts[0],pts[1],optional=edge['optional'],color=color)
        c.marker(pts[-1],pts[-2],many=edge['kind']!='inherit',optional=True,color=color)
        # Edge labels are placed on a long free route segment.
        label=edge['name']
        if edge['child']=='발주처경쟁관계':label+=' · CLIENT '+('A' if edge['name']=='경쟁기준' else 'B')
        tw=c.d.textlength(label,font=FONTS[18])+16
        segments=sorted(zip(pts,pts[1:]),key=lambda a:abs(a[0][0]-a[1][0])+abs(a[0][1]-a[1][1]),reverse=True)
        def overlap(a,b):return a[0]<b[0]+b[2] and a[0]+a[2]>b[0] and a[1]<b[1]+b[3] and a[1]+a[3]>b[1]
        selected=None
        for a,b in segments:
            if hypot(b[0]-a[0],b[1]-a[1])<80:continue
            for fraction in (.5,.32,.68):
                lx=max(35,min(a[0]+(b[0]-a[0])*fraction-tw/2,page['width']-tw-35))
                ly=a[1]+(b[1]-a[1])*fraction-12
                box=(lx-5,ly-5,tw+10,36)
                if not any(overlap(box,r) for r in list(rects.values())+label_boxes):
                    selected=(lx,ly);break
            if selected:break
        if selected:lx,ly=selected
        else:
            a,b=segments[0];lx=max(35,min((a[0]+b[0])/2-tw/2,page['width']-tw-35));ly=(a[1]+b[1])/2-12
        label_boxes.append((lx-5,ly-5,tw+10,36))
        c.rect(lx,ly,tw,26,'white','white',1);c.text(lx+8,ly+1,label,18,color=color)
        for p,o,card in [(pts[0],pts[1],'0..1' if edge['optional'] else '1'),(pts[-1],pts[-2],'0..1' if edge['kind']=='inherit' else '0..N')]:
            dx,dy=o[0]-p[0],o[1]-p[1]
            c.text(p[0]+(30 if dx>=0 else -65),p[1]+(10 if dy>=0 else -36),card,16,color=color)
    for name,(x,y,w,h) in rects.items():
        node=N[name];fill,color=COLORS[node['group']]
        c.rect(x,y,w,h,'white',color,2);c.rect(x,y,w,70,fill,color,2)
        c.text(x+14,y+8,name,22,True,color)
        c.text(x+14,y+39,node['physical'],16,color=color)
        for i,txt in enumerate(lines[name]):c.text(x+14,y+78+i*28,txt,18,color='#344256')
    ny=page['height']-138;c.rect(60,ny,page['width']-120,108,'#f7f9fc','#cbd5e1',1)
    for i,note in enumerate(page['notes']):c.text(78,ny+12+i*28,note,18)
    c.text(78,ny+72,'관계: 부모 1 / 자식 0..N  ·  빈 원 = 선택  ·  상속 점선 1 : 0..1  ·  [NULL] = 선택 속성  ·  FK 역할명은 각 테이블에 표시',18,color='#64748b')
    (HERE/(page['key']+'.svg')).write_text('\n'.join(c.svg+['</svg>']),encoding='utf-8')
    c.im.save(HERE/(page['key']+'.png'))
    diagram=ET.SubElement(mxfile,'diagram',{'id':page['key'],'name':page['title']})
    model=ET.SubElement(diagram,'mxGraphModel',{'dx':'1600','dy':'1200','grid':'1','gridSize':'20','page':'1','pageScale':'1','pageWidth':str(page['width']),'pageHeight':str(page['height']),'math':'0','shadow':'0'})
    root=ET.SubElement(model,'root');ET.SubElement(root,'mxCell',{'id':'0'});ET.SubElement(root,'mxCell',{'id':'1','parent':'0'})
    def cell(id,label,x,y,w,h,style):
        el=ET.SubElement(root,'mxCell',{'id':id,'value':label,'style':style,'vertex':'1','parent':'1'});ET.SubElement(el,'mxGeometry',{'x':str(x),'y':str(y),'width':str(w),'height':str(h),'as':'geometry'})
    cell('title',page['title'],60,25,page['width']-120,55,'text;html=1;align=left;fontSize=32;fontStyle=1;fontFamily=Malgun Gothic;')
    ids={n:'n'+str(i) for i,n in enumerate(rects)}
    for name,(x,y,w,h) in rects.items():
        node=N[name];fill,color=COLORS[node['group']]
        label='<div style="font-size:22px;font-weight:bold">'+escape(name)+'</div><div style="font-size:16px">'+escape(node['physical'])+'</div><hr>'+''.join('<div style="font-size:18px;line-height:28px">'+escape(t)+'</div>' for t in lines[name])
        cell(ids[name],label,x,y,w,h,f'rounded=0;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacing=14;fontFamily=Malgun Gothic;fillColor={fill};strokeColor={color};strokeWidth=2;')
    for i,e in enumerate(edges):
        pa,ch=e['parent'],e['child'];ar,br=rects[pa],rects[ch]
        sx,sy=(e['points'][0][0]-ar[0])/ar[2],(e['points'][0][1]-ar[1])/ar[3]
        tx,ty=(e['points'][-1][0]-br[0])/br[2],(e['points'][-1][1]-br[1])/br[3]
        end='ERzeroToOne' if e['kind']=='inherit' else 'ERzeroToMany';start='ERzeroToOne' if e['optional'] else 'ERone'
        label=e['name']+'  [ '+('0..1' if e['optional'] else '1')+' : '+('0..1' if e['kind']=='inherit' else '0..N')+' ]'
        if ch=='발주처경쟁관계':label+=' · CLIENT '+('A' if e['name']=='경쟁기준' else 'B')
        style=f'edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;fontSize=18;fontFamily=Malgun Gothic;labelBackgroundColor=#ffffff;startArrow={start};endArrow={end};startFill=0;endFill=0;strokeColor=#64748b;strokeWidth=2;exitX={sx};exitY={sy};entryX={tx};entryY={ty};'
        if e['kind']=='inherit':style+='dashed=1;strokeColor=#70519b;'
        el=ET.SubElement(root,'mxCell',{'id':'e'+str(i),'value':label,'style':style,'edge':'1','parent':'1','source':ids[pa],'target':ids[ch]})
        geo=ET.SubElement(el,'mxGeometry',{'relative':'1','as':'geometry'});arr=ET.SubElement(geo,'Array',{'as':'points'})
        for px,py in e['points'][1:-1]:ET.SubElement(arr,'mxPoint',{'x':str(px),'y':str(py)})
    cell('notes','<br>'.join(escape(x) for x in page['notes']),60,ny,page['width']-120,108,'rounded=0;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacing=12;fontSize=18;fontFamily=Malgun Gothic;fillColor=#f7f9fc;strokeColor=#cbd5e1;')
    print(page['key'],len(rects),'nodes',len(edges),'edges',flush=True)

HERE.mkdir(parents=True,exist_ok=True)
mxfile=ET.Element('mxfile',{'host':'app.diagrams.net','type':'device','version':'24.7.17','agent':'local ERD generator'})
for page in PAGES:export_page(page,mxfile)
ET.indent(mxfile,space='  ')
ET.ElementTree(mxfile).write(HERE/'SI_workforce_통합_ERD.drawio',encoding='utf-8',xml_declaration=True)
print('DONE',flush=True)
