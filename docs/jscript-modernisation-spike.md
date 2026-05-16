# Spike brief — modernising Wine's JavaScript engine

**Status:** proposed, not started. This is a handoff brief, not a plan.
The first real task is the spike in §7 — it produces the plan.

**Origin:** attempt 17 (running the Adobe Creative Cloud Desktop
installer under Wine, see `docs/attempt-17-cc-desktop.md`). Two walls
were fixed — the `mshtml` `FEATURE_BROWSER_EMULATION` patch and the
`lib32-nettle` 32-bit-TLS fix. The installer then reaches Adobe's
sign-in step but **stalls**: the modern React OOBE/sign-in app cannot
run inside Wine's IE-emulated script engine. That engine is the subject
of this brief.

---

## 1. The problem, precisely

Wine's `mshtml.dll` (the embedded-IE / WebBrowser control) renders the
DOM with Wine-Gecko but executes `<script>` with **Wine's own
`jscript.dll`** — an engine at roughly **ES5.1 + a few ES6 bits**
(`let`/`const`, `JSON`). It is hand-written C in Wine's `dlls/jscript/`.

Modern web apps (Adobe's OOBE included) need ES2015–ES2023: classes,
arrow functions, generators, `async`/`await`, real `Promise`, `Symbol`,
`Proxy`, `Map`/`Set`, destructuring, spread, template literals, optional
chaining, modules. `jscript` implements almost none of it.

**Evidence captured in attempt 17** (session 5 trace):

- `mshtml:ActiveScriptSite_OnScriptError` — page JS raised script errors.
- `jscript:exprval_call invoke undefined` ×4 — a thrown `TypeError`
  (calling an undefined value), the classic symptom of a missing
  builtin/feature.
- `jscript:JScriptProperty_SetProperty Unimplemented property
  70000001 / 70000002` — the app asks the engine for JS-version
  features (`SCRIPTPROP_*`); `jscript` does not implement them.
- `mshtml:HTMLDOMImplementation2_createHTMLDocument` returns `null`.
- `mshtml:HTMLWindow2_put_onerror … semi-stub`.

Net: the app's JavaScript does not run to completion; the UI parks on
"Loading". This is **in-scope (a) Wine** — not Adobe, not host config.

## 2. Goal & non-goals

**Goal:** the embedded WebBrowser in Wine's `mshtml` runs a modern
(ES2020+) JavaScript application — concretely, Adobe's CC installer
OOBE app reaches its interactive sign-in form.

**Non-goals:**
- Not required to *use* Lightroom — Lightroom already works under Wine
  (`README.md`); the CC installer is one install path among several.
  This project is a Wine improvement in its own right, valuable beyond
  attempt 17, but **it is not on the critical path to Lightroom**.
- Not a Node.js / server-JS runtime. Browser-embedded scripting only.
- Not committing to upstreaming (see §10).

## 3. Why this is a *new project*, not a continuation

`lightroom-arch` is "run Adobe apps on Arch via Wine". It *consumes*
Wine — it ships patched DLLs in `wine-patches/` and a rebuilt
`lib32-nettle` in `patches/nettle/`. Modernising the JS engine is
**general Wine source work**. It does not belong inside `lightroom-arch`.

Relationship: identical to the existing pattern. The JS-engine project
*produces* a patched Wine; `lightroom-arch` *consumes* it (drops the
built DLL into `wine-patches/`, exactly like the `mshtml` patch). The
two stay separate repos with a producer/consumer link.

## 4. Project structure — recommended

**Fork Wine.** This is Wine source code; it belongs in a Wine tree.

- Fork `gitlab.winehq.org/wine/wine` → `AndreNijman/wine` (or base the
  fork on the PhialsBasement/Proton-patched tree already used here, at
  `~/wine-build/wine-src` — decide in the spike; upstream-clean is
  better for rebasing, the Proton tree is what the prefix runs).
- Work on a branch, e.g. `feat/jscript-modern`.
- If the "replace" approach wins (§5 B), the new engine is **vendored**
  into the Wine tree — a third-party JS engine's source imported as a
  new `dll` (this is the "merge of another project" part: you import
  `quickjs-ng` source the way Wine already vendors other libraries).

**Do not** make a standalone repo holding loose patches — jscript work
is too entangled with Wine internals (COM interfaces, the DOM bridge,
the build system) to live outside the tree.

**`lightroom-arch` gets one small thing:** a pointer. When the engine
builds, its DLL is dropped into `lightroom-arch/wine-patches/` and
`install-cc-desktop.sh` installs it — same as `mshtml-i386.dll` today.

So: **a Wine fork (new project) + a vendored JS engine (merged-in
project) + a one-line consumer link from `lightroom-arch`.**

## 5. The three candidate approaches

The spike must pick one with evidence. Honest tradeoffs:

### A — Extend Wine's `jscript` to modern ECMAScript
Add classes, generators, `async`/`await`, `Promise`, `Symbol`, `Proxy`,
etc. to `dlls/jscript/`.
- ➕ Upstreamable piecemeal; no new dependency; keeps Wine's exact
  IActiveScript + `IDispatchEx` DOM bridge that already works.
- ➖ Enormous. A decade of language evolution, hand-written in C. This
  is what upstream Wine has been doing slowly for years. Not a
  finishable project for one person in a sane timeframe.

### B — Replace the engine: `quickjs-ng` behind `IActiveScript`
Wrap a modern embeddable engine (`quickjs-ng` — community fork of
Bellard's QuickJS, ES2023, small, pure C, designed to embed) in a new
DLL that implements `IActiveScript` / `IActiveScriptParse` /
`IActiveScriptProperty`, registered as the script engine for
`text/javascript`.
- ➕ Modern language support comes for free from a maintained engine.
  Tractable in scope.
- ➖ **The hard part: the DOM bridge.** Wine's `mshtml` hands the DOM
  to script as `IDispatchEx` objects (`window`, `document`, nodes).
  QuickJS has no `IDispatch` concept. You must write a bidirectional
  bridge: QuickJS exotic objects that proxy property/call access onto
  `IDispatchEx`, and expose QuickJS objects back as `IDispatchEx`.
  jscript's `IDispatchEx` bridge is the model. **This bridge is the
  whole project.** Not upstreamable as-is (Wine won't drop jscript).

### C — Route `mshtml` script to Wine-Gecko's SpiderMonkey
Wine-Gecko already embeds a JS engine (SpiderMonkey) *and* already has
native JS↔DOM bindings. Make `mshtml` use them instead of `jscript`.
- ➕ The DOM bindings already exist — potentially the least new glue.
- ➖ Wine-Gecko is frozen at 2.47.4 (Firefox-52-era, ~2017, ES2016) —
  may not be modern enough, and may not be the version installed.
  Rebuilding Wine-Gecko is its own painful toolchain. `mshtml` uses
  `jscript` instead of Gecko-JS for deep architectural reasons — undoing
  that is invasive.

**Working recommendation (spike to confirm):** lean **B**. A is
unfinishable; C depends on a frozen, possibly-too-old engine and a
nastier integration. B is bounded — the risk is concentrated in one
known place (the `IDispatchEx` bridge), which is exactly what a spike
can de-risk.

## 6. The crux to resolve first

Everything hinges on the **`IDispatchEx` ⇆ modern-engine object
bridge**. Before committing to B, the spike must prove a minimal bridge
works: a QuickJS script reading and calling one real `mshtml` DOM object
(`window.document`) through `IDispatchEx`. If that prototype is clean,
B is viable. If it is a quagmire, reconsider C.

## 7. The spike — concrete first steps (do these, in order)

1. **Reproduce in isolation.** Build a minimal HTML page that uses
   ES2020 features (classes, `async`/`await`, `Promise`, optional
   chaining) hosted in a bare Wine `WebBrowser` control — reuse the
   `wine-patches/repro-feature-browser-emulation/` harness pattern.
   Confirm it fails on stock `jscript` the same way the Adobe app does.
   This becomes the regression repro.
2. **Map the seam.** Read `dlls/jscript/` — specifically how `mshtml`
   creates the engine (`CLSID_JScript`, `IActiveScript`,
   `IActiveScriptParse`), and how `jscript` exposes/consumes host
   objects via `IDispatchEx` (`dlls/jscript/dispex.c`,
   `jsdisp`/`IWineJSDispatch`). This is the integration contract.
3. **Bridge prototype.** Stand up `quickjs-ng` in a throwaway program;
   write the minimal two-way `IDispatchEx`⇆`JSValue` bridge; drive one
   real `mshtml` DOM object from a QuickJS script. **This is the
   go/no-go gate for approach B.**
4. **Decide.** Write the verdict + the real implementation plan
   (milestones, scope, estimate) into a `docs/` file in the Wine fork.

The spike is done when step 4 exists. Only then write code beyond
prototypes.

## 8. Milestones (post-spike, if B)

- M1 — new engine DLL loads, implements `IActiveScript[Parse]`, runs
  a trivial DOM-free script from `mshtml`.
- M2 — `IDispatchEx` bridge: scripts read/write/call `window` &
  `document`; events fire.
- M3 — the ES2020 repro page (§7.1) runs green.
- M4 — the Adobe CC OOBE app reaches its interactive sign-in form.
- M5 — drop the built DLL into `lightroom-arch/wine-patches/`, wire
  `install-cc-desktop.sh`, re-run `Set-up.exe` end to end.

## 9. Risks & unknowns

- The `IDispatchEx` bridge may be deeper than it looks (prototypes,
  exotic objects, `Symbol` keys vs `DISPID`s, GC interaction between
  QuickJS's GC and COM refcounting). **Top risk.**
- `mshtml` may rely on `jscript`-specific behaviour beyond the public
  `IActiveScript` contract.
- The Adobe app may need more than ES2020 (e.g. specific DOM APIs Wine
  Gecko lacks) — fixing JS may just expose the *next* wall.
- Engine GC ⇆ COM lifetime is a classic source of crashes.
- This is large regardless of approach. Scope honestly after the spike;
  do not start M1 before §7.4 exists.

## 10. Upstreaming reality

Wine will **not** accept wholesale replacement of `jscript`. Approach B
is therefore a **long-lived fork**, not an upstream contribution.
Approach A's individual feature additions *could* upstream piecemeal but
A is unfinishable solo. Decide consciously in the spike whether the goal
is "a working fork for personal use" (fine, and the realistic answer) or
"upstream Wine" (then it must be A, and it becomes a multi-year effort).

## 11. What a fresh session needs to start

- This brief.
- `docs/attempt-17-cc-desktop.md` — "Full Set-up.exe run" section: the
  evidence, the exact failing fixmes.
- Vault: `decisions/2026-05-16-cc-installer-jscript-wall.md`.
- Wine source: `dlls/jscript/`, `dlls/mshtml/` (the script-host glue).
- `quickjs-ng` upstream.
- Decision to make first: §7. Decision after: §4 (fork base) and §5
  (approach). No production code before §7.4.
