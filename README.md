# novel-rank 六站小说榜单 · 故事核
每天北京时间 16:00 由 GitHub Actions 抓取起点/纵横/七猫/晋江/飞卢/番茄的月票/新书/人气榜前10，调用 AI 生成“故事核”，写入 `data/latest.json`（归档在 `data/archive/`）。APK 由“构建APK”工作流自动发布到 Releases。

## 配置
Settings → Secrets and variables → Actions：
- Secret `AI_API_KEY`（必填才有故事核，默认 DeepSeek）
- 可选 Variables：`AI_BASE_URL`（默认 https://api.deepseek.com）、`AI_MODEL`（默认 deepseek-flash），任何 OpenAI 兼容接口均可。

本地：`pip install -r requirements.txt && AI_API_KEY=xxx python scraper/main.py [qidian zongheng ...]`
