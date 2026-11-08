"""Reference-table enrichment. Inputs are public wiki HTML, never player data."""
import datetime,json,re,urllib.parse
from bs4 import BeautifulSoup
BASE='https://dreamlightvalleywiki.com'
def text(cell):
    clone=BeautifulSoup(str(cell),'html.parser')
    for node in clone.select('sup.reference,.mw-editsection'):node.decompose()
    return re.sub(r'\s+',' ',clone.get_text(' ',strip=True)).strip()
def row_cells(row):return row.find_all(['td','th'],recursive=False)
def table_rows(doc):
    for table in doc.select('table'):
        rows=table.select('tr')
        if rows:yield rows,[text(c).lower() for c in row_cells(rows[0])]
def linked_name(cell):
    links=[a for a in cell.select('a[title]') if a.get_text(strip=True)]
    return links[0]['title'] if links else text(cell)
def ingredient_data(doc):
    result={}
    for rows,heads in table_rows(doc):
        if not {'name','location','sources'}.issubset(heads):continue
        for row in rows[1:]:
            cells=row_cells(row)
            if len(cells)<len(heads):continue
            name=linked_name(cells[heads.index('name')]);result[name]={'locations':text(cells[heads.index('location')]),'sources':text(cells[heads.index('sources')]),'growth':text(cells[heads.index('grow time')]) if 'grow time' in heads else 'Not grown'}
    return result
def recipe_data(doc):
    result={}
    for rows,heads in table_rows(doc):
        if not {'name','ingredients','stars'}.issubset(heads):continue
        for row in rows[1:]:
            cells=row_cells(row)
            if len(cells)<len(heads):continue
            parts=re.split(r'<br\s*/?>',str(cells[heads.index('ingredients')]),flags=re.I)
            ingredients=[text(BeautifulSoup(part,'html.parser')) for part in parts];ingredients=[p for p in ingredients if p]
            name_cell=cells[heads.index('name')]
            value={'ingredients':ingredients,'stars':text(cells[heads.index('stars')]).count('★')}
            result[linked_name(name_cell)]=value
            result.setdefault(text(name_cell),value)
    return result
def character_data(doc):
    result={};kinds={'cell_sleep':'Home','cell_eat':'Restaurant','cell_scrooge':"Scrooge's Store",'cell_exhibition':'Grand Exhibition'}
    for rows,heads in table_rows(doc):
        if not heads or heads[0]!='character':continue
        for row in rows[2:]:
            cells=row_cells(row)
            if not cells:continue
            name=linked_name(cells[0]);hours=[]
            for cell in cells[1:]:hours.extend([kinds.get(cell.get('id'),'Free / no fixed venue listed')]*int(cell.get('colspan','1')))
            if len(hours)==24:result[name]={'hours':hours,'source':BASE+'/Time','note':'Community-sourced daily schedule. Restaurant = Chez Remy or Tiana\'s Palace; quests and stations may override it.'}
    return result
MONTHS={m:i for i,m in enumerate(['January','February','March','April','May','June','July','August','September','October','November','December'],1)}
def date_range(value):
    numeric=re.findall(r'\b(\d{1,2})-(\d{1,2})-(\d{2,4})\b',value)
    if len(numeric)>=2:
        def make(v):m,d,y=map(int,v);return datetime.date(y+2000 if y<100 else y,m,d).isoformat()
        return make(numeric[0]),make(numeric[1])
    long=re.findall(r'([A-Za-z]+) (\d{1,2}), (\d{4})',value)
    if len(long)>=2:return tuple(datetime.date(int(y),MONTHS[m],int(d)).isoformat() for m,d,y in long[:2])
    return None,None
def guide_blocks(doc):
    blocks=[]
    for el in doc.select('.mw-parser-output > p,.mw-parser-output > h2,.mw-parser-output > h3,.mw-parser-output > ul,.mw-parser-output > ol,.mw-parser-output > table'):
        if el.get('id')=='infobox':continue
        if el.name=='table':
            for row in el.select('tr'):
                value=' | '.join(text(c) for c in row_cells(row))
                if value:blocks.append({'type':'p','text':value})
        else:
            value=text(el)
            if value:blocks.append({'type':el.name,'text':value})
    return blocks

def enrich(snapshot,fetch):
    records=snapshot['records'];by_title={}
    for row in records:by_title.setdefault(row['title'],[]).append(row)
    ingredients=ingredient_data(fetch('Ingredients'));recipes=recipe_data(fetch('Cooking'));characters=character_data(fetch('Time'))
    if len(ingredients)<100 or len(recipes)<400 or len(characters)<60:
        raise ValueError('Reference tables incomplete; keep the previous catalog')
    for row in records:
        details=json.loads(row['details']);labels=json.loads(row['categories']);name=row['title']
        if 'Ingredients' in labels and name in ingredients:details['ingredient']=ingredients[name];details.setdefault('fields',{})['Zones:']=ingredients[name]['locations']
        if 'Meals' in labels and name in recipes:details['recipe']=recipes[name]
        if 'Characters' in labels and name in characters:details['characterSchedule']=characters[name]
        row['details']=json.dumps(details,ensure_ascii=False)
    def upsert(title,categories,details,image=None):
        candidates=[r for r in by_title.get(title,[]) if r['id'].startswith('guide:')]
        if candidates:
            row=candidates[0];row['categories']=json.dumps(sorted(set(json.loads(row['categories'])+categories)));row['details']=json.dumps(details,ensure_ascii=False)
        else:
            row={'id':'guide:'+title,'title':title,'categories':json.dumps(categories),'image':image,'details':json.dumps(details,ensure_ascii=False)};records.append(row);by_title.setdefault(title,[]).append(row)
        if image:row['image']=image
    events_doc=fetch('Events');paths_doc=fetch('Star Path');events={}
    for gallery in events_doc.select('ul.gallery'):
        section=gallery.find_previous(['h2','h3']);group=text(section) if section else 'Events'
        for box in gallery.select('li.gallerybox'):
            link=box.select_one('.gallerytext a[title]')
            if not link:continue
            title=link['title'];dates=text(box.select_one('.gallerytext'));start,end=date_range(dates);img=box.select_one('img')
            events[title]={'type':group,'dates':dates.replace(title,'',1).strip(),'start':start,'end':end,'permanent':False,'source':BASE+'/Events','image':urllib.parse.urljoin(BASE,img['src']) if img else None}
    for rows,heads in table_rows(paths_doc):
        if not {'star path','dates'}.issubset(heads):continue
        # Expand rowspan season labels so the mini Star Path's neighbouring row still uses the correct columns.
        carried={}
        for row in rows[1:]:
            expanded=[];position=0;new_carry={}
            for cell in row_cells(row):
                while position in carried:
                    node,left=carried[position];expanded.append(node)
                    if left>1:new_carry[position]=(node,left-1)
                    position+=1
                expanded.append(cell)
                if int(cell.get('rowspan','1'))>1:new_carry[position]=(cell,int(cell['rowspan'])-1)
                position+=1
            while position in carried:
                node,left=carried[position];expanded.append(node)
                if left>1:new_carry[position]=(node,left-1)
                position+=1
            carried=new_carry
            if len(expanded)<len(heads):continue
            name=linked_name(expanded[heads.index('star path')]);dates=text(expanded[heads.index('dates')]);start,end=date_range(dates)
            previous=events.get(name,{})
            img=expanded[heads.index('star path')].select_one('img')
            events[name]={**previous,'type':'Star Path','dates':dates,'start':start,'end':end,'permanent':'permanent' in dates.lower(),'source':BASE+'/Star_Path','image':previous.get('image') or (urllib.parse.urljoin(BASE,img['src']) if img else None)}
    today=datetime.datetime.now().date()
    for title,event in events.items():
        details={'metadataVersion':2,'summary':False,'image':event.get('image'),'fields':{'Type:':event['type'],'Dates:':event['dates']},'blocks':[],'links':[],'event':event,'referenceComplete':True}
        for previous in by_title.get(title,[]):
            if previous['id'].startswith('guide:'):
                old=json.loads(previous['details']);details['blocks']=old.get('blocks',[])
        current=event['permanent'] or event['start'] and event['end'] and event['start']<=today.isoformat()<=event['end']
        if current:
            doc=fetch(title);details['blocks']=guide_blocks(doc)
        upsert(title,['Events','Star Paths'] if event['type']=='Star Path' or 'Star Path' in title else ['Events'],details,event.get('image'))
    snapshot['referenceVersion']=4
    snapshot['referenceSources']=['Ingredients','Cooking','Time','Events','Star Path']
    print('Reference enrichment:',len(ingredients),'ingredients;',len(recipes),'recipes;',len(characters),'character schedules;',len(events),'events/paths',flush=True)
    return snapshot
