"""实测 App 内“生成3个写作点子”的同款 prompt（与 app/lib/main.dart 中 buildIdeaPrompt 保持一致）。"""
import os, json, requests, sys
SYS=("你是资深网文策划。根据给出的同题材榜单作品（书名+故事核），提炼当下流行元素，借鉴但绝不照搬（不得沿用原书名、人名、具体设定组合），"
"原创 3 个新的写作点子。只输出 JSON：{\"ideas\":[{\"title\":\"\",\"core\":\"\",\"protagonist\":\"\",\"goldfinger\":\"\",\"goal\":\"\",\"obstacle\":\"\",\"hook\":\"\",\"mainline\":\"\"}]}。"
"core=故事核（必填）：一段话，先明确主角、目标、阻力和故事方向。六要素：protagonist=主角与起点（是谁、什么时代地方、人生节点）；goldfinger=金手指/核心设定；"
"goal=目标与动机；obstacle=核心阻力（全书级）；hook=悬念钩子（全书谜团）；mainline=主线走向（一句话）。"
"不适用的要素必须返回空字符串\"\"：如纯爽文打怪升级、单元剧推进无全书悬念则 hook 为空；普通人无金手指则 goldfinger 为空；无全书级对手则 obstacle 为空。"
"六要素必须与故事核内容一致，不得矛盾。")
def user(genre, books): return f"题材：{genre}\n榜单作品：\n"+"\n".join(f"- 《{b['title']}》：{b.get('core') or b.get('intro','')[:100]}" for b in books[:30])
d=json.load(open("data/latest.json")); s=d["sites"][0]; g=sys.argv[1] if len(sys.argv)>1 else "玄幻"
books=[b for l in s["lists"] for b in l["books"] if b.get("genre")==g]
r=requests.post("https://api.deepseek.com/chat/completions",headers={"Authorization":"Bearer "+os.environ["DEEPSEEK_API_KEY"]},timeout=180,
  json={"model":"deepseek-chat","temperature":1.0,"response_format":{"type":"json_object"},"messages":[{"role":"system","content":SYS},{"role":"user","content":user(g,books)}]})
r.raise_for_status(); ideas=json.loads(r.json()["choices"][0]["message"]["content"])["ideas"]
print(len(ideas)); print(json.dumps(ideas[0],ensure_ascii=False,indent=1)); print([{k:bool(v) for k,v in i.items()} for i in ideas])
