# Agent Note: Keep the tsx source launch on link resolution

Status: implemented

English | [中文](2026-09-20-source-launch-link-resolution.zh.md)

## Problem

`pnpm dsh <profile>` runs the CLI from TypeScript source through tsx. After profile resolution defaulted to the runtime backend, the resolver mounted each plugin entry point from built `lib/`, while tsx's tsconfig `paths` map rewrote those built modules' workspace imports back to `src/`. A workspace package reached by both planes then existed as two module instances: `dsh-agent-loop` read `TOOL_RUNTIME_SCHEDULER` from the `src` copy of `dsh-tools`, but `ctx.tools` was the `lib` `ToolRuntime`, so the symbol-keyed lookup returned `undefined` and every model tool call failed with `Cannot read properties of undefined (reading 'prepare')` under the `UNKNOWN` failure code. The `web` and `headless` profiles were equally affected; only launch modes that load one plane throughout (built `lib/bin.js`, packaged executables) escaped it.

## Decision

To fix a `pnpm dsh` source launch that fails every model tool call with `Cannot read properties of undefined (reading 'prepare')`, change one file: `apps/cli/src/bin.ts` detects a TypeScript source entry in `runCli`'s profile branch and passes `resolutionMode: 'link'` to `runProfile` instead of accepting the runtime default. Link resolution materializes the same generation the runtime backend would install and then leaves resolution to native Node plus the active loader — tsx in a source launch — so a plugin entry point and its transitive workspace imports resolve to the same module instance. Apply the same change to any other launcher that boots the TypeScript source under tsx; a launch that loads `lib` throughout (built `lib/bin.js`, the Electron host, direct `runProfile` calls) needs no change.

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

Verification: a tool call reaches the tool pipeline instead of failing at `.prepare`, covered by the keyless recorded-session lane in its default `src` launch mode (`bash-tool-turn`). Where a source change is not possible, launching the built tree (`pnpm run build`, then `node apps/cli/lib/bin.js <profile>`) also avoids the mixed planes.

## Regression origin

The regression entered in `9ddef327a4` (2026-09-17, "feat: resolution mode link to runtime"), merged as PR #4471. Profile resolution modes had arrived in `6aa2e4633c` (2026-09-13) with `link` as the non-packaged default, and `c917a4e0bd` (2026-09-14) forced runtime only for pkg builds; `9ddef327a4` changed the remaining default to `runtime`.

The intent was to give ordinary Node launches the runtime backend that packaged executables and the Electron host already use: runtime startup installs one process-local, immutable package generation without materializing, updating, or retiring the fallback symlinks and proxy manifests, which otherwise persist package selections across processes and installations, need reconciliation and locking, and cannot represent a process-local change atomically ([profile resolution generations](../architecture/2026-09-09-profile-resolution-generations.md)). The change treated every non-packaged launch as plain Node, including the tsx source entry, whose tsconfig path mapping resolves plugin imports to a different plane. Before the mode work, profile boot always materialized the disk fallback and left resolution to Node plus tsx, so a workspace package stayed one module instance.

No CI gate exercises runtime resolution under tsx: `scripts/run-gates.ts` runs the recorded-session and expected-output gates with `DSH_EXAMPLE_MODE=lib`, `vitest.snapshot.config.ts` includes the Web snapshot suites only in that mode, and unit tests build a `Context` in-process through the tsconfig path map.

## Alternatives considered

**Keep runtime for source launches and disable tsx path mapping for `lib/` modules.** tsx applies the nearest `tsconfig` per importing file and exposes no per-directory opt-out, so the two planes cannot be reconciled from the launcher.

**Use `Symbol.for` for the scheduler key.** A global-registry symbol would remove this one collision but leaves the same dual-instance hazard for every other module-identity key, and hides a real plane mix instead of preventing it.

**Revert the launcher default to link for every launch.** Plain Node launches of the built tree, and packaged or Electron carriers, need runtime resolution so startup does not write or retire fallback links; the default is correct for them.

## Consequences

Source launches materialize or reuse the profile fallback links again and give up the runtime-only "no disk writes" property; in exchange a workspace package is one module instance across plugin entry points and transitive imports. Built and packaged launches are unchanged and keep runtime resolution. This is a partial exception to the [profile resolution generations](../architecture/2026-09-09-profile-resolution-generations.md) launcher default, which still selects runtime for every other plain Node caller.
