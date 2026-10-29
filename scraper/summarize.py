"""用 OpenAI 兼容接口为每本书生成故事核；按书缓存在 data/cache.json。无 AI_API_KEY 时跳过。"""
import os, json, hashlib, requests, time
BASE=os.environ.get("AI_BASE_URL") or "https://api.deepseek.com"
MODEL=os.environ.get("AI_MODEL") or "deepseek-chat"
KEY=os.environ.get("AI_API_KEY","")
PROMPT=("你是网文编辑。根据书名和简介，用一两句话（不超过80字）概括这本小说的“故事核”："
        "核心设定（金手指/世界观/身份）+ 主线冲突。只输出故事核本身。")
def bkey(b): return hashlib.md5((b.get("url") or b["title"]).encode()).hexdigest()
def call(b):
    msg=f"书名：{b['title']}\n作者：{b.get('author') or ''}\n简介：{(b.get('abstract_in_page') or b.get('intro') or '无')[:1200]}"
    r=requests.post(BASE.rstrip("/")+"/chat/completions",headers={"Authorization":f"Bearer {KEY}"},timeout=90,
        json={"model":MODEL,"temperature":0.3,"messages":[{"role":"system","content":PROMPT},{"role":"user","content":msg}]})
    r.raise_for_status(); return r.json()["choices"][0]["message"]["content"].strip()
def summarize(sites, cache_path):
    cache=json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    n=0
    for s in sites:
        for l in s["lists"]:
            for b in l["books"]:
                if not b.get("title"): continue
                k=bkey(b)
                if k not in cache and KEY:
                    try: cache[k]=call(b); n+=1; time.sleep(0.2)
                    except Exception as e: print("AI失败",b["title"],e)
                b["core"]=cache.get(k)
    json.dump(cache,open(cache_path,"w"),ensure_ascii=False,indent=0)
    print("新生成故事核",n,"条" if KEY else "(未配置 AI_API_KEY，已跳过)")
