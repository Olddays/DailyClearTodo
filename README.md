# 日清 DailyClear

跨平台（Linux / Windows / macOS / Android / iOS）番茄工作法助手。对话式 UI，智谱 GLM 驱动的意图理解 + 工具调用，Supabase 提供数据存储、鉴权和确定性的每日自动归档。语音输入优先用系统自带识别，检测到大陆环境时自动切到讯飞流式语音听写。

## 结构

- `app/` — Flutter 客户端
- `backend/supabase/` — 数据库迁移 + Edge Functions
- `.github/workflows/` — CI（analyze/test、五端构建矩阵、Supabase 部署）

## 快速开始

### 后端

Supabase CLI 是作为 npm 依赖装在 `backend/` 下的（没有全局装 `supabase` 命令），所以要用 `npx`，并且要在 `backend/` 目录（`supabase/` 子目录的上一级）执行：

```bash
cd backend
cp .env.example .env   # 填入 SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY / ZHIPU_API_KEY / XFYUN_*
npx supabase link --project-ref <your-project-ref>
npx supabase db push               # 应用 migrations
npx supabase functions serve chat --env-file .env   # 本地跑 Edge Function
# 或者部署到线上（--use-api 走服务端打包，不需要本机 Docker）：
npx supabase secrets set --env-file .env
npx supabase functions deploy chat --use-api
npx supabase functions deploy xfyun-auth --use-api
```

`XFYUN_APP_ID` / `XFYUN_API_KEY` / `XFYUN_API_SECRET` 是国内语音识别（讯飞"语音听写"流式版）的凭据，去 [console.xfyun.cn](https://console.xfyun.cn) 注册应用获取——这几个值只在 `xfyun-auth` 这个 Edge Function 里用，客户端拿不到，也不会打包进 App。

### 客户端

`SUPABASE_URL` / `SUPABASE_ANON_KEY` 放在 `app/.env`（gitignored），不要直接写进命令行或提交进仓库：

```bash
cd app
cp .env.example .env   # 填入 SUPABASE_URL / SUPABASE_ANON_KEY
flutter pub get
./run.sh run -d linux           # 等价于 flutter run -d linux --dart-define=...
./run.sh build apk --release --obfuscate --split-debug-info=build/symbols
```

`run.sh` 只是把 `app/.env` 里的值转成 `--dart-define` 参数转发给 `flutter`，本身不影响正常的 `flutter analyze`/`flutter test`（这两个不需要这些值）。

### CI

`.github/workflows/supabase-deploy.yml` 和 `flutter-build-matrix.yml` 需要在仓库 Settings → Secrets and variables → Actions 里配置：
`SUPABASE_URL`、`SUPABASE_ANON_KEY`、`SUPABASE_ACCESS_TOKEN`、`SUPABASE_PROJECT_REF`、`SUPABASE_DB_PASSWORD`、`ZHIPU_API_KEY`、`XFYUN_APP_ID`、`XFYUN_API_KEY`、`XFYUN_API_SECRET`。

`flutter-build-matrix.yml` 会给 Android/Web/Linux/macOS/Windows/iOS 六个平台出正式构建产物（release + 混淆），上传成 workflow artifacts。已知限制：Android 用的是 Flutter 默认调试签名（能装机测试，不能上架 Play Store，需要自己配置正式签名密钥）；iOS 用 `--no-codesign`（只验证编译，装不到真机，需要 Apple 开发者账号签名）；macOS/Windows 未签名（macOS 首次打开会被 Gatekeeper 拦截，需要 Developer ID 签名+公证）。

## 架构要点

详见 [/home/zkzc/.claude/plans/nifty-seeking-aho.md](../.claude/plans/nifty-seeking-aho.md)（本次实现的设计方案）。核心原则：

- "今天"的任务和"历史"任务共用同一张 `tasks` 表，按 `task_date` 区分，不做显式的"清空"操作。
- 每日自动归档由 Postgres 内的 `pg_cron` 定时任务驱动，完全不依赖 LLM，按用户各自时区计算本地 23:59。
- 番茄钟计时器在客户端用挂钟时间驱动，到点直接写数据库，不经过聊天 LLM 往返，App 被杀掉重开也不会丢计时。
- LLM 只做自然语言理解和工具调用，所有状态变更（加任务、记番茄钟、查历史）都落在真实数据库操作上，`add_task` 的晨间规划限制在服务端强制校验；模型每轮对话不会自动带上之前工具调用的结果，需要真实 ID 时必须先重新查询，不能凭对话记忆编造。
- Chat 后端走智谱 GLM 的 OpenAI 兼容接口（`glm-4-flash` 免费档跑通，`glm-4.6` 需要账户余额，改 `CHAT_MODEL_ID` 环境变量即可切换）。
- 语音输入优先用系统自带的 `speech_to_text`（Android/iOS/macOS/Windows/Web），检测到大陆环境或系统识别不可用时自动切到讯飞流式语音听写（`xfyun_asr_service.dart` + `record` 包采集 16kHz/16bit PCM，通过 `xfyun-auth` Edge Function 换取签名 WebSocket 地址，密钥不进客户端），录音时麦克风按钮会有跟随音量大小的动效。
