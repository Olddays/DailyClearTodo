# 日清 DailyClear

*A cross-platform Pomodoro assistant built around one idea: close the books on today, every day.*

## Why I built this

"日清" borrows a term from bookkeeping — 日清月结, settle the books daily, close them monthly. In accounting it means no debt quietly rolls over from one day to the next; every ledger gets reconciled before the day ends, whether the numbers were good or bad.

I wanted the same discipline applied to my own task list. Most to-do apps let unfinished items drift forward indefinitely — today's leftovers become tomorrow's list, then next week's, until the list itself stops meaning anything and procrastination becomes invisible because nothing ever forces a reckoning. So the core mechanic here isn't the Pomodoro timer (that's just the execution engine) — it's the **automatic, unforgiving daily archive**. At 23:59 local time, whatever didn't get done is silently frozen into history and the slate is wiped clean, no negotiation, no "just one more reminder." The app deliberately does *not* nag about yesterday's misses beyond a single, matter-of-fact mention the next morning. The point isn't guilt — it's an honest, cumulative record of completion rates over time that you can't talk yourself out of, and a genuine fresh start every single day instead of an ever-growing backlog.

Everything else follows from that: a conversational interface so planning the day takes seconds, a Pomodoro timer that runs independent of the network/LLM so it never fails you mid-focus, and a history view that's just data, not judgment.

## Structure

- `app/` — Flutter client
- `backend/supabase/` — database migrations + Edge Functions
- `.github/workflows/` — CI (analyze/test, five-platform build matrix, Supabase deploy)

## Getting started

### Backend

The Supabase CLI is installed as an npm dependency under `backend/` (there's no global `supabase` command), so use `npx`, and run it from `backend/` (one level above `supabase/`):

```bash
cd backend
cp .env.example .env   # fill in SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY / ZHIPU_API_KEY / XFYUN_*
npx supabase link --project-ref <your-project-ref>
npx supabase db push               # apply migrations
npx supabase functions serve chat --env-file .env   # run the Edge Function locally
# or deploy to production (--use-api bundles server-side, no local Docker needed):
npx supabase secrets set --env-file .env
npx supabase functions deploy chat --use-api
npx supabase functions deploy xfyun-auth --use-api
```

`XFYUN_APP_ID` / `XFYUN_API_KEY` / `XFYUN_API_SECRET` are credentials for the mainland-China speech recognition fallback (iFlytek's streaming "语音听写" product) — register an app at [console.xfyun.cn](https://console.xfyun.cn) to get them. These values are only ever used inside the `xfyun-auth` Edge Function; the client never sees them and they never end up in the compiled app.

### Client

`SUPABASE_URL` / `SUPABASE_ANON_KEY` live in `app/.env` (gitignored) — don't hardcode them on the command line or commit them:

```bash
cd app
cp .env.example .env   # fill in SUPABASE_URL / SUPABASE_ANON_KEY
flutter pub get
./run.sh run -d linux           # equivalent to flutter run -d linux --dart-define=...
./run.sh build apk --release --obfuscate --split-debug-info=build/symbols
```

`run.sh` just turns `app/.env` into `--dart-define` flags for `flutter`; it doesn't affect plain `flutter analyze`/`flutter test` (neither needs those values).

### CI

`.github/workflows/supabase-deploy.yml` and `flutter-build-matrix.yml` need these configured under repo Settings → Secrets and variables → Actions:
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `ZHIPU_API_KEY`, `XFYUN_APP_ID`, `XFYUN_API_KEY`, `XFYUN_API_SECRET`.

`flutter-build-matrix.yml` produces release (obfuscated) builds for Android/Web/Linux/macOS/Windows/iOS and uploads them as workflow artifacts. Known limitations: Android is signed with Flutter's default debug key (fine for sideloading, not acceptable for the Play Store — bring your own release keystore for that); iOS builds with `--no-codesign` (proves it compiles, can't be installed anywhere without a real Apple signing identity); macOS/Windows builds are unsigned (macOS in particular will trip Gatekeeper on first launch without a Developer ID signature + notarization).

## Architecture notes

- "Today" and "history" share a single `tasks` table, distinguished only by `task_date` — there's no explicit "clear the list" step.
- The daily auto-archive runs entirely inside Postgres via `pg_cron`, independent of the LLM, computing each user's local 23:59 from their own timezone.
- The Pomodoro timer runs on wall-clock time client-side and writes straight to the database on completion — no round trip through the chat LLM, and no lost session if the app gets killed and restarted mid-timer.
- The LLM only handles natural-language understanding and tool calls; every state change (adding a task, logging a pomodoro, reading history) is a real database operation, with the morning-planning window for `add_task` enforced server-side. The model doesn't automatically carry forward tool results from earlier turns, so it has to re-query for a real ID before acting on it rather than inventing one from memory.
- The chat backend talks to Zhipu GLM's OpenAI-compatible endpoint (`glm-4-flash` on the free tier; `glm-4.6` needs a funded account — swap via the `CHAT_MODEL_ID` env var).
- Voice input prefers the platform's built-in `speech_to_text` (Android/iOS/macOS/Windows/Web) and falls back to iFlytek's streaming recognizer when the device looks like it's in mainland China or the system recognizer is unavailable (`xfyun_asr_service.dart` + the `record` package capture 16kHz/16-bit PCM, exchanged for a signed WebSocket URL via the `xfyun-auth` Edge Function so the credentials never reach the client); the mic button pulses with input volume while listening.

---

# 日清 DailyClear

*一个跨平台番茄工作法助手，核心理念只有一句话：每天的账，当天清。*

## 为什么做这个

"日清"这个词借自会计术语——日清月结，每天的账当天核对清楚，每月再做一次结算。在会计里，这意味着不会有债务悄悄拖到第二天：不管当天的数字好不好看，账本每天都要闭合一次。

我想把这种纪律用在自己的任务清单上。大部分待办事项 App 都放任未完成的事情无限期往后拖——今天没做完的变成明天的清单，再变成下周的清单，最后清单本身失去意义，拖延也因为从来没有真正被"结算"过而变得不可见。所以这个 App 的核心机制其实不是番茄钟本身（那只是执行引擎），而是**自动的、不留情面的每日归档**。到了当地时间 23:59，没做完的事情会被静默冻结进历史记录，白板重新擦干净，没有商量余地，也不会"再提醒你一次"。App 刻意**不会**为昨天没做完的事反复唠叨——第二天早上如实提一句就够了。这么做的目的不是制造愧疚感，而是留下一份诚实的、随时间累积的完成率记录，让你没法自己骗自己，同时保证每一天都是真正意义上的重新开始，而不是一份越滚越大的待办债务。

其他的设计都是从这一点延伸出来的：对话式界面让规划一天只需要几秒钟；番茄钟计时器完全独立于网络和 LLM 运行，专注到一半绝不会掉链子；历史页面只呈现数据，不做评判。

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

- "今天"的任务和"历史"任务共用同一张 `tasks` 表，按 `task_date` 区分，不做显式的"清空"操作。
- 每日自动归档由 Postgres 内的 `pg_cron` 定时任务驱动，完全不依赖 LLM，按用户各自时区计算本地 23:59。
- 番茄钟计时器在客户端用挂钟时间驱动，到点直接写数据库，不经过聊天 LLM 往返，App 被杀掉重开也不会丢计时。
- LLM 只做自然语言理解和工具调用，所有状态变更（加任务、记番茄钟、查历史）都落在真实数据库操作上，`add_task` 的晨间规划限制在服务端强制校验；模型每轮对话不会自动带上之前工具调用的结果，需要真实 ID 时必须先重新查询，不能凭对话记忆编造。
- Chat 后端走智谱 GLM 的 OpenAI 兼容接口（`glm-4-flash` 免费档跑通，`glm-4.6` 需要账户余额，改 `CHAT_MODEL_ID` 环境变量即可切换）。
- 语音输入优先用系统自带的 `speech_to_text`（Android/iOS/macOS/Windows/Web），检测到大陆环境或系统识别不可用时自动切到讯飞流式语音听写（`xfyun_asr_service.dart` + `record` 包采集 16kHz/16bit PCM，通过 `xfyun-auth` Edge Function 换取签名 WebSocket 地址，密钥不进客户端），录音时麦克风按钮会有跟随音量大小的动效。
