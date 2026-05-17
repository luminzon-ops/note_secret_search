# Chat And Model Layout Status Design

**Goal:** Fix three user-facing issues in the current Flutter app while preserving the existing AI/model business flow: (1) broken source-layout rendering on the model management page, (2) oversized recent-session rail on phone-sized chat screens, and (3) delayed perceived download-status updates after tapping download, then continue real-device verification on the Huawei phone.

**Status:** Direction approved by user. User selected the medium-refactor option where the model page is structurally reorganized, the chat page becomes responsive with a phone drawer + wide-screen sidebar, and download-status presentation is made more immediate and stage-aware.

---

## 1. Scope

This design covers exactly three product issues plus the verification work needed to prove the fixes on the authorized Huawei device.

### 1.1 In scope

1. Restructure the **model management page** so long source labels and source selectors no longer compete in a single horizontal row.
2. Reduce visual clutter and excess height in the **download/source/status portion** of each model tile.
3. Rework **`/ai/chat`** into a responsive layout:
   - phone widths: recent sessions hidden by default behind a top-left hamburger and left drawer
   - tablet / wide screens: persistent left session panel remains visible
4. Improve **download-status presentation responsiveness** so tapping download produces immediate visible feedback before first-byte progress arrives.
5. Run focused automated verification plus renewed **Huawei real-device testing** using the user-provided PIN `1234`.

### 1.2 Out of scope

1. Rewriting the underlying Dio downloader or replacing the current repository schema.
2. Changing the current AI chat orchestration or message/session persistence architecture.
3. Redesigning the global app shell or bottom navigation structure.
4. Replacing built-in model catalog data contracts.
5. Adding new model sources, new provider types, or new runtime backends.
6. Large product UX expansions unrelated to the three reported issues.

---

## 2. Current Constraints And Evidence

The current issues are real layout/state-presentation problems in otherwise working code paths. The design should preserve those working paths and only refactor the presentation boundaries that are now causing friction.

### 2.1 Model page source-layout issue is caused by horizontal width competition

The current source section in `lib/features/ai_models/presentation/model_management_page.dart` renders a `Row` with:

1. `Expanded(Text('当前下载源：...'))`
2. `DropdownButton<String>` when multiple sources exist

See `model_management_page.dart:575-603`.

For `BGE Small 中文 Embedding`, the catalog entry exposes multiple long source labels from `assets/model_catalog/built_in_catalog.json`, and the presentation formatter can append trust suffixes like ` (已签名)`. This combination creates width starvation for the left text on narrow devices, which explains:

1. near-vertical wrapping of `当前下载源...`
2. debug overflow indicators / striped artifacts
3. visually excessive vertical expansion once wrapped lines and trust explainers stack

### 2.2 Model tiles are visually overloaded

Each catalog tile currently stacks:

1. header/title
2. description
3. chips
4. deployment/runtime summary
5. `_DownloadStatusCard`
6. source row + trust explainers
7. action buttons
8. recommended source list

This all lives in a single large `Column` in `_CatalogEntryTile` (`model_management_page.dart:526-723`). `_DownloadStatusCard` itself is also a tall card with many fixed gaps and text rows (`model_management_page.dart:821-872`).

The result is not just one broken line; it is a model tile whose sub-sections are not visually separated enough for small screens.

### 2.3 Chat page width issue is caused by a permanently reserved left rail

`lib/features/ai_chat/presentation/ai_chat_page.dart` currently renders the main body as a `Row` where the first child is:

1. `SizedBox(width: 240)` for recent sessions
2. `VerticalDivider`
3. `Expanded` main chat area

See `ai_chat_page.dart:38-91`, especially `40-41` and `51-52`.

This means phone-width screens permanently sacrifice 240 px to a recent-session panel that is useful but not always actively needed.

### 2.4 Session selection logic is already decoupled from layout

The recent-session panel uses state that is already isolated from the view container:

1. `chatSessionsProvider`
2. `currentChatSessionIdProvider`
3. `chatSessionControllerProvider.selectSession(...)`

See `lib/features/ai_chat/application/chat_session_providers.dart` and `ai_chat_page.dart:103-143`.

That means the session panel can move from a persistent rail to a drawer/sidebar container without rewriting data flow.

### 2.5 Download status feels late because user-visible stages are too coarse

The current download flow already persists task state and progress, but the UI presentation mainly exposes storage-level task status (`queued`, `downloading`, `paused`, `failed`, etc.) via `_DownloadStatusCard`.

The real-device debugging showed that the app can legitimately spend time after the button tap but before meaningful visible byte progress, which creates the impression that “nothing is happening.”

The problem to solve in this slice is not necessarily replacing the downloader; it is making the **displayed state transition** more immediate and easier to understand.

---

## 3. Options Considered

### Option A — Minimal patch

Make only the smallest changes:

1. replace the source `Row` with a stacked `Column`
2. add a drawer on phones
3. lightly tweak status text

**Rejected** because it fixes the obvious breakages but leaves the model page structurally crowded and the download-state UX only marginally better.

### Option B — Medium refactor (**selected**)

1. restructure the model tile into clearer sections
2. convert chat session UI into a responsive container strategy
3. introduce stage-aware status presentation above the raw task details

**Chosen** because it directly addresses the reported issues while preserving existing business logic and keeping the implementation surface bounded.

### Option C — Full productized workspace redesign

Turn the model page into a full task center and the chat page into a more advanced workspace with broader navigation, richer animation, and deeper downloader refactors.

**Rejected** because it is outside the scope of the current issues and would delay verification.

---

## 4. Recommended Design

The recommended design keeps existing providers/repositories/runtime bridges intact and introduces a clearer UI component structure on top.

### 4.1 Model management page

Reorganize each catalog tile into four conceptual sections:

1. **Header section**
   - display name
   - chips (type/tier/RAM/size)
   - compact deployment summary
2. **Download status section**
   - current user-visible stage
   - source badge/label
   - progress bar and bytes
   - speed / timestamps
   - error block if failed
3. **Source section**
   - label: `当前下载源`
   - current source text on its own line/block
   - source dropdown below it when multiple sources exist
   - trust caption and generic trust explainer below
4. **Action section**
   - download / retry / pause / delete / activate buttons in a `Wrap`

This removes the key horizontal conflict while making the tile easier to scan on smaller screens.

### 4.2 Chat page

Adopt responsive layout branching inside `AiChatPage` itself.

1. **Phone widths**
   - the session panel is hidden by default
   - `AppBar.leading` becomes a hamburger button
   - tapping it opens a left `Drawer` containing the session list
   - selecting a session closes the drawer and keeps current selection behavior
2. **Wide widths**
   - the existing side-by-side structure remains conceptually the same
   - the session rail is retained as a persistent sidebar
   - no hamburger is shown in this mode

The key boundary is that the same session-list content should be reusable in both containers.

### 4.3 Download-status presentation

Introduce a display-oriented stage mapping layered over the raw task status so the page gives immediate feedback after a tap.

User-visible stages:

1. 未开始
2. 已发起 / 连接中
3. 下载中
4. 校验中
5. 已暂停
6. 已完成
7. 失败

The design does **not** require a brand-new persistence enum. The preferred implementation is a view-model/state-mapping layer that interprets existing task/install/runtime evidence into a more user-friendly stage description.

---

## 5. Component-Level Design

### 5.1 `lib/features/ai_models/presentation/model_management_page.dart`

Refactor `_CatalogEntryTile` so the source label and dropdown are no longer peers in one `Row`.

#### Required changes

1. Replace the current source `Row` (`575-603`) with a vertical source section.
2. Keep long source labels in a dedicated text block that can wrap normally.
3. Place the dropdown below the current source display instead of beside it.
4. Preserve trust captions and generic explainer behavior, but render them as subordinate stacked text.
5. Keep action buttons in a responsive `Wrap`, separated from the source section.

#### Recommended internal extraction

Split parts of the file into smaller private widgets such as:

1. `_CatalogEntryHeader`
2. `_ModelSourceSection`
3. `_ModelActionSection`
4. possibly a slimmer `_DownloadStatusSection` replacing or wrapping `_DownloadStatusCard`

This is not required purely for style; it reduces the risk of further layout regressions in a very large build method.

### 5.2 `lib/features/ai_models/presentation/model_presentation_formatter.dart`

Keep current label/trust semantics, but ensure the layout redesign can consume them cleanly.

No formatter contract change is required unless implementation reveals a need to split “display label” from “trust suffix label.” If that happens, the formatter may expose a more structured helper, but only if necessary.

### 5.3 `lib/features/ai_chat/presentation/ai_chat_page.dart`

Refactor page layout into a responsive branch.

#### Required behavior

1. Determine whether current width is phone-like or wide-screen.
2. On phone-like widths:
   - remove the fixed 240 px session rail from the main `Row`
   - expose hamburger in app bar
   - render sessions in drawer
3. On wide widths:
   - keep persistent sidebar model
   - continue showing session panel beside chat area

#### Required state behavior

1. Current session selection logic remains unchanged.
2. Tab selection sync remains unchanged.
3. Opening/closing the drawer must not reset chat state.

### 5.4 Chat session panel reuse

The current `_SessionListPanel` should become a reusable core content widget that can be hosted inside:

1. a drawer shell on phone
2. a sidebar shell on wide screens

In drawer mode, session selection should additionally close the drawer after invoking `selectSession(...)`.

### 5.5 Download-status mapping layer

Whether implemented inside the presentation file or via a small presentation helper, the app should derive a user-visible stage from:

1. task presence/status
2. downloaded bytes
3. installed-entry existence
4. runtime readiness / validation phase
5. failure message presence

The raw task row remains important, but the UI should present a more understandable stage than a bare storage enum alone.

---

## 6. Responsive Rules

### 6.1 Chat page breakpoint

The design intentionally does not hardcode the exact numeric threshold here; implementation should select a pragmatic Flutter breakpoint for “phone” vs “wide enough for sidebar.”

Requirements:

1. Huawei phone test target must land in drawer mode.
2. Typical tablet/desktop widths must land in sidebar mode.
3. The breakpoint should be applied only inside `AiChatPage`; do not mutate the global app shell.

### 6.2 Model page width behavior

The model page should be single-column but resilient:

1. source text wraps in its own block
2. dropdown may occupy full width or intrinsic width in a stacked section
3. action buttons wrap naturally without causing horizontal overflow

---

## 7. Error Handling

### 7.1 Download failure display

Failure should remain visible in the status section with:

1. user-readable stage = `失败`
2. current source context
3. retry affordance
4. raw error text preserved as secondary evidence

The design does not hide the technical error; it simply organizes it better.

### 7.2 Session loading failure

Session-panel failure behavior should be container-agnostic:

1. same error content in drawer mode and sidebar mode
2. failure in session list must not block the chat tab area from rendering

### 7.3 Transitional stages

If the downloader has started but no bytes have yet been received, the UI must not appear idle. The stage should communicate active work in progress even before non-zero MB display appears.

---

## 8. Testing Strategy

### 8.1 Widget tests — model page

Add or update tests to cover:

1. multi-source model entries render current source in a stacked layout
2. long current-source labels do not require side-by-side compression with dropdown
3. source dropdown remains usable
4. failure state still renders technical error text
5. action buttons continue to appear/enabled correctly per task/install/runtime state

### 8.2 Widget tests — chat page responsiveness

Add or update tests to cover:

1. phone-width render shows hamburger and hides persistent session rail
2. hamburger opens drawer containing recent sessions
3. wide-width render shows persistent session sidebar
4. selecting session from drawer still triggers session selection

### 8.3 State/presentation tests — download status

Add or update tests to cover:

1. immediate visible state change after download starts
2. stage mapping for connecting/downloading/failed/completed states
3. failure text remains visible when task fails

### 8.4 Verification commands

Before claiming completion, run at minimum:

1. relevant Flutter widget/provider tests for modified areas
2. `flutter analyze`
3. renewed Huawei device smoke flow

---

## 9. Real-Device Verification Plan

After implementation, verify on the Huawei device using PIN `1234`:

1. Unlock app successfully.
2. Open `/models`.
3. Confirm `BGE Small 中文 Embedding` no longer shows vertically stacked source text or striped overflow.
4. Confirm model tiles feel more compact and readable.
5. Trigger download and confirm visible stage changes happen promptly after tap.
6. Open `/ai/chat`.
7. Confirm phone layout shows hamburger instead of permanent left rail.
8. Open drawer and confirm `最近会话` appears there.
9. Select a session and confirm drawer closes plus chat content remains stable.
10. If network allows, continue download/install/activation checks afterward.

---

## 10. Risks And Mitigations

### Risk 1: Responsive refactor accidentally disrupts tab/session sync

**Mitigation:** Keep current providers/controllers unchanged and only move the session container.

### Risk 2: Model page becomes visually cleaner but loses important source/debug information

**Mitigation:** Do not remove trust captions or raw error text; reorganize them into subordinate stacked sections.

### Risk 3: “Faster status updates” turns into downloader refactor creep

**Mitigation:** Limit this slice to presentation-stage mapping and more immediate invalidation/display behavior unless code evidence proves a deeper bug.

---

## 11. Acceptance Criteria

This design is considered satisfied only if all of the following are true:

1. On phone-sized screens, `AiChatPage` no longer permanently reserves a 240 px left rail for recent sessions.
2. A hamburger-triggered left drawer exposes recent sessions on phone widths.
3. On wider screens, a persistent recent-session sidebar still exists.
4. On the model page, the current-source label for the BGE embedding entry no longer collapses into a near-vertical stack.
5. The model page no longer shows striped overflow caused by the current-source row under the tested scenario.
6. Download state changes become visible promptly after tapping download, even before meaningful byte progress is displayed.
7. Existing session selection, model actions, and runtime-state behaviors continue to work.
8. Automated verification passes and Huawei real-device smoke confirms the intended UI changes.
