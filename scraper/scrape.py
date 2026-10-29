#!/usr/bin/env python3
"""六站小说榜单抓取（实测于 2026-10-29）。用法: python3 scrape.py [site]  输出 JSON 到 out/。"""
import re, json, sys, os, requests
from bs4 import BeautifulSoup
PC="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36"
M="Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile Safari/604.1"
import time
def get(u,ua=PC,enc=None,**kw):
    for i in range(3):
        try:
            r=requests.get(u,headers={"User-Agent":ua},timeout=40,**kw); r.raise_for_status(); break
        except Exception:
            if i==2: raise
            time.sleep(2)
    r.encoding=enc or 'utf-8'; return r.text
def clean(s): return re.sub(r'\s+',' ',s or '').strip()

def qidian(kind):  # 移动版 m.qidian.com，SSR 内嵌 JSON pageData.records
    t=get(f"https://m.qidian.com/rank/{kind}/",M)
    i=t.find('"records":['); arr=json.JSONDecoder().raw_decode(t[i+10:])[0]
    return [dict(rank=x.get("rankNum"),title=x["bName"],author=x.get("bAuth"),intro=x.get("desc"),cat=x.get("cat"),
                 url=f"https://book.qidian.com/info/{x['bid']}/") for x in arr[:10]]

def zongheng(rankType):  # 公开 JSON 接口
    r=requests.post("https://www.zongheng.com/api/rank/details",headers={"User-Agent":PC},
        data=dict(rankType=rankType,pageNum=1,pageSize=20,cateFineId=0,period=0),timeout=30).json()
    return [dict(rank=x["orderNo"],title=x["bookName"],author=x.get("pseudonym"),intro=clean(x.get("description")),cat=x.get("cateFineName"),
                 url=f"https://www.zongheng.com/detail/{x['bookId']}") for x in r["result"]["resultList"][:10]]

def qimao(path):  # SSR HTML
    s=BeautifulSoup(get(f"https://www.qimao.com/paihang/{path}"),"lxml"); out=[]
    for li in s.select("li.rank-list-item")[:10]:
        a=li.select_one("a.s-book-title")
        if not a: continue
        au=li.select_one('.s-book-info a[href*="/zuozhe/"]'); d=li.select_one(".s-book-intro")
        out.append(dict(rank=len(out)+1,title=clean(a.text),author=clean(au.text) if au else None,intro=clean(d.text) if d else None,url="https://www.qimao.com"+a["href"] if a["href"].startswith("/") else a["href"]))
    return out

def jjwxc(orderstr):  # GBK HTML 表格，简介在 title/tooltip 属性；站点响应慢
    s=BeautifulSoup(get(f"https://www.jjwxc.net/topten.php?orderstr={orderstr}&t=0",enc="gb18030"),"lxml"); out=[]
    for tr in s.select("tr"):
        a=tr.select_one('a[href*="onebook.php?novelid"]'); au=tr.select_one('a[href*="oneauthor.php"]')
        if not a: continue
        out.append(dict(rank=len(out)+1,title=clean(a.text),author=clean(au.text) if au else None,intro=clean(" ".join(a.get("rel")) if isinstance(a.get("rel"),list) else (a.get("rel") or a.get("title"))),
                        url="https://www.jjwxc.net/"+a["href"].lstrip("/")))
        if len(out)==10: break
    if not out:  # 新手金榜等为分频道网格布局（每频道一个 ul.list_01，无简介，需再进书页取文案）
        for box in s.select("div.box_06"):
            cat=clean(box.h5.text) if box.h5 else None
            for li in box.select("li")[:3]:
                a=li.select_one('a[href*="novelid"]'); au=li.select_one(".author")
                if a: out.append(dict(rank=len(out)+1,cat=cat,title=a.get("title") or clean(a.text),author=clean(au.text) if au else None,intro=None,url="https://www.jjwxc.net/"+a["href"]))
    return out

def faloo(code):  # GBK HTML
    s=BeautifulSoup(get(f"https://b.faloo.com/y_0_0_0_0_3_{code}_1.html",enc="gb18030"),"lxml"); out=[]
    for it in s.select(".TwoBox02_01, .TwoBox02_02, .TwoBox02"):
        a=it.select_one('h1 a[href*="b.faloo.com"], .TwoBox02_08 a, a[title]')
        if not a: continue
        title=clean(a.get("title") or a.text)
        if not title or any(o["title"]==title for o in out): continue
        au=it.select_one('a[href*="/l_"], .fs14 a, a[href*="author"]'); d=it.select_one(".TwoBox02_06, .TwoBox02_10")
        out.append(dict(rank=len(out)+1,title=title,author=clean(au.text) if au else None,intro=clean(d.text) if d else None,url="https:"+a["href"] if a["href"].startswith("//") else a["href"]))
        if len(out)==10: break
    return out

def fanqie(cat):  # SSR __INITIAL_STATE__；书名明文，简介/作者被字体加密（私有区字符）
    t=get(f"https://fanqienovel.com/rank/{cat}"); out=[]
    for m in re.finditer(r'\{"[^{}]*?"bookName":"([^"]*)"[^{}]*\}',t):
        try: o=json.loads(m.group(0))
        except Exception: continue
        bid=o.get("bookId")
        if not bid or any(x["url"].endswith(bid) for x in out): continue
        # 榜单页书名/作者/简介均为字体加密；再请求书页，<title> 与 meta description 为明文
        time.sleep(0.4)
        try: p=get(f"https://fanqienovel.com/page/{bid}")
        except Exception: p=""
        tt=re.search(r'<title>(.*?)完整版在线免费阅读',p); md=re.search(r'<meta name="description" content="番茄小说提供.*?精彩小说尽在番茄小说网。([^"]*)"',p)
        ab=re.search(r'"abstract":"((?:[^"\\]|\\.)*)"',p)
        out.append(dict(rank=o.get("currentPos"),title=tt.group(1) if tt else o["bookName"],author=None,
                        intro=md.group(1) if md else None, abstract_in_page=ab.group(1) if ab else None,
                        url=f"https://fanqienovel.com/page/{bid}"))
        if len(out)==10: break
    return out

FQ_CATS={"男频":{"都市脑洞":262,"玄幻脑洞":257,"东方仙侠":1140,"历史脑洞":272},
         "女频":{"现言脑洞":267,"古言脑洞":253,"年代":79,"豪门总裁":748}}
# 实测：/rank/{g}_1_{cat} 均为30万字以下 => 新书榜；{g}_2_{cat} => 阅读榜（g:1男频 0女频）
SITES={
 "qidian":("起点中文网",{"月票榜":(qidian,"yuepiao"),"新书榜":(qidian,"newfans"),"人气榜(阅读指数)":(qidian,"readindex")}),
 "zongheng":("纵横中文网",{"月票榜":(zongheng,1),"新书榜":(zongheng,4),"人气榜(点击)":(zongheng,5)}),
 "qimao":("七猫免费小说",{f"{gn}·{ln}":(qimao,f"{g}/{p}") for g,gn in (("boy","男生"),("girl","女生"))
          for ln,p in (("大热月榜","hot/month/"),("新书榜","new/date/"),("大热日榜","hot/date/"))}),
 "jjwxc":("晋江文学城",{"月度排行榜":(jjwxc,5),"新手金榜":(jjwxc,17),"霸王票总榜":(jjwxc,13)}),
 "faloo":("飞卢小说网",{"月票榜":(faloo,15),"新书PK榜":(faloo,66),"人气榜(月点击)":(faloo,2)}),
 "fanqie":("番茄小说",{f"{gn}·{cn}·{ln}":(fanqie,f"{1 if gn=='男频' else 0}_{t}_{cid}") for gn,cs in FQ_CATS.items()
          for cn,cid in cs.items() for ln,t in (("阅读榜",2),("新书榜",1))}),
}
def scrape_all(only=None):
    out=[]
    for key,(name,lists) in SITES.items():
        if only and key not in only: continue
        site={"key":key,"name":name,"lists":[]}
        for ln,(fn,arg) in lists.items():
            try: books=fn(arg); err=None
            except Exception as e: books=[]; err=repr(e)
            site["lists"].append({"name":ln,"books":books,"error":err})
            print(key,ln,len(books),err or "",flush=True)
        out.append(site)
    return out
