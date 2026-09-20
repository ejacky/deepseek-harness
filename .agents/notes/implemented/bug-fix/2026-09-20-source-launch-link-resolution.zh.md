# Agent Note: 让 tsx 源码启动保留 link 解析

Status: implemented

[English](2026-09-20-source-launch-link-resolution.md) | 中文

## 问题

`pnpm dsh <profile>` 通过 tsx 从 TypeScript 源码运行 CLI。profile 解析改为默认使用 runtime 后端后，解析器会从构建产物 `lib/` 挂载每个插件入口，而 tsx 的 tsconfig `paths` 映射又把这些已构建模块对工作区包的导入改回 `src/`。于是同一个工作区包同时以两个模块实例存在：`dsh-agent-loop` 从 `dsh-tools` 的 `src` 副本读取 `TOOL_RUNTIME_SCHEDULER`，而 `ctx.tools` 却是 `lib` 的 `ToolRuntime` 实例，导致以该符号为键的查找返回 `undefined`，每次模型工具调用都以 `Cannot read properties of undefined (reading 'prepare')` 失败，并以 `UNKNOWN` 失败码上报。`web` 与 `headless` profile 同样受影响；只有全程加载单一平面（构建版 `lib/bin.js`、打包可执行文件）的启动方式不受影响。

## 决策

修复 `pnpm dsh` 源码启动下每次模型工具调用都报 `Cannot read properties of undefined (reading 'prepare')` 的方法只改一个文件：`apps/cli/src/bin.ts` 在 `runCli` 的 profile 分支检测 TypeScript 源码入口，并向 `runProfile` 传入 `resolutionMode: 'link'`，而不是沿用 runtime 默认值。link 解析会物化 runtime 后端本会安装的同一份 generation，然后把解析交给原生 Node 与当前生效的加载器——源码启动下即 tsx——因此插件入口与其传递的工作区导入都解析到同一个模块实例。其他同样以 tsx 启动 TypeScript 源码的 launcher 照此修改；全程加载 `lib` 的启动（构建版 `lib/bin.js`、Electron Host、直接调用 `runProfile`）无需改动。

```diff
 import { reportStartupFailure } from './startup-diagnostics.ts'

+// The repository script runs this entry through tsx, whose tsconfig `paths`
+// map resolves a built plugin module's workspace imports back to `src`. Runtime
+// package resolution loads plugin entry points from built `lib`, so a package
+// reached by both planes would exist as two module instances and lose symbol
+// identity. A source launch therefore keeps the native link backend; a plain
+// Node launch of the bundled bin keeps the runtime default.
+const sourceLaunch = fileURLToPath(import.meta.url).endsWith('.ts')
+
@@
         await runProfile({
           environment: loadLayeredEnv('dsh'),
           profile: invocation.profile,
           fromDefaultProfile: invocation.fromDefaultProfile,
           patchFiles: invocation.patches,
           args: invocation.args,
+          ...(sourceLaunch ? { resolutionMode: 'link' as const } : {}),
         })
```

验证：工具调用能进入工具流水线，而不是在 `.prepare` 处失败；无密钥录像会话通道在其默认 `src` 启动模式下的 `bash-tool-turn` 覆盖这一点。无法改动源码时，改跑构建树（`pnpm run build`，然后 `node apps/cli/lib/bin.js <profile>`）同样能避免平面混用。

## 引入来源

该回归由 `9ddef327a4`（2026-09-17，"feat: resolution mode link to runtime"）引入，并以 PR #4471 合入。解析模式在 `6aa2e4633c`（2026-09-13）引入，非 pkg 默认值为 `link`；`c917a4e0bd`（2026-09-14）只对 pkg 构建强制 runtime；`9ddef327a4` 把剩余默认值改为 `runtime`。

其目的是让普通 Node 启动获得打包可执行文件与 Electron Host 已在使用的 runtime 后端：runtime 启动只安装一份进程内不可变的包 generation，不物化、更新或退休 fallback symlink 与代理 manifest，而后者会让选包结果跨进程和安装版本持续存在，需要协调与加锁，也无法原子表示进程内变更（[profile 解析 generation](../architecture/2026-09-09-profile-resolution-generations.zh.md)）。该改动把所有非 pkg 启动都当作普通 Node，其中包含 tsx 源码入口——而它的 tsconfig 路径映射会把插件导入解析到另一个平面。在模式工作之前，profile 启动始终物化磁盘 fallback，并把解析交给 Node 加 tsx，因此同一个工作区包只有一个模块实例。

没有任何 CI 门禁覆盖 tsx 下的 runtime 解析：`scripts/run-gates.ts` 以 `DSH_EXAMPLE_MODE=lib` 运行录像会话与 expected-output 门禁，`vitest.snapshot.config.ts` 仅在该模式下纳入 Web 快照套件，单元测试则在进程内通过 tsconfig 路径映射构建 `Context`。

## 考虑的替代方案

**源码启动继续用 runtime，并禁止 tsx 对 `lib/` 模块做路径映射。** tsx 按导入文件的最近 `tsconfig` 生效，且没有按目录关闭的开关，因此无法从 launcher 侧调和这两个平面。

**把调度器键改为 `Symbol.for`。** 全局注册表符号能消除这一处冲突，但会为所有其他模块标识键保留同样的双实例隐患，而且只是掩盖真实的平面混用，而非阻止它。

**把所有启动方式的默认值改回 link。** 构建树的纯 Node 启动、打包或 Electron 载体需要 runtime 解析，以避免启动时写入或清理 fallback 链接；对它们而言该默认值是正确的。

## 后果

源码启动会再次物化或复用 profile fallback 链接，并放弃 runtime 独有的“不写磁盘”特性；换来的是工作区包在插件入口与其传递导入之间只有一个模块实例。构建与打包启动不变，继续使用 runtime 解析。这是对 [profile 解析 generation](../architecture/2026-09-09-profile-resolution-generations.zh.md) launcher 默认值的部分例外，该默认值对其他所有纯 Node 调用方仍然选择 runtime。
