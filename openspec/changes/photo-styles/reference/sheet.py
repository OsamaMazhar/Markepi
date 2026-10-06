import sys
from PIL import Image, ImageDraw, ImageFont
out = sys.argv[1]
F = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 22)
def sheet(name, photos, looks, tileH=300):
    rows=[]
    for p in photos:
        tiles=[]
        for l in looks:
            im=Image.open(f'{out}/{p}__{l}.jpg'); im=im.resize((int(im.width*tileH/im.height),tileH))
            t=Image.new('RGB',(im.width,tileH+34),'white'); t.paste(im,(0,0))
            ImageDraw.Draw(t).text((8,tileH+6),l,fill='black',font=F); tiles.append(t)
        rows.append(tiles)
    W=max(sum(t.width+8 for t in r) for r in rows); H=sum(r[0].height+8 for r in rows)
    c=Image.new('RGB',(W,H),'white'); y=0
    for r in rows:
        x=0
        for t in r: c.paste(t,(x,y)); x+=t.width+8
        y+=r[0].height+8
    c.save(f'{out}/../sheet_{name}.jpg',quality=88); print(name,c.size)
moods=['Original','Vibrant','Natural','Luminous','Dramatic','Quiet','Cozy','Ethereal','Muted B&W','Stark B&W']
film=['Original','Portrait 400','Golden 200','Chrome 100','Velvet 50','Classic Neg','Tungsten 800','Silver 400','Faded']
und=['Original','Neutral','Cool Rose','Rose Gold','Gold','Amber','mask']
sheet('moods',['portrait','windmill','harbour','night'],moods)
sheet('film',['portrait','windmill','harbour','night'],film)
sheet('undertones',['portrait','elder'],und,tileH=420)
