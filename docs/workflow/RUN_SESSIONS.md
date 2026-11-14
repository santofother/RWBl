# Running sessions: your cheat sheet

Everything you need to drive Claude and Codex on Custom Chariot. Agents don't read this file.
Replace the `<...>` parts in prompts and paste. Nothing else is needed: cards hold the details.

---

## The daily loop

1. Open `docs/STATUS.md`. Pick a card marked **READY**.
2. Check the card's first line: **which AI** and **which tier** (model table in `docs/PLAN.md` §2).
3. Start a **new session in a new worktree** (how: §Starting a session).
4. Paste the **builder prompt** with the card number.
5. Wait. The agent builds, tests, writes a handoff and merges itself into `main`.
   It only asks you something if it's blocked.
6. When the STATUS row says **DONE**, archive the session. If it says **REVIEW**, run a merge session.
7. After a wave, play a build (§Playtesting). Write down what felt wrong.

Up to **3 sessions at once** (for example 2 Codex + 1 Claude).

---

## Which prompt do I need?

| Situation | Prompt | Where | Model |
|---|---|---|---|
| Build a card | Builder | new worktree | what the card says |
| STATUS row says REVIEW, or you want to merge by hand | Merge | main folder, no worktree | T4 |
| You have a question about the project | Question | main folder, no worktree | T3/T4 |
| You found a bug while playing | Fix | new worktree | T3 |
| You want to change the design | Design change | main folder, Claude | T2 |
| After a playtest | Triage | main folder, Claude | T1 |
| Old worktrees piling up | Cleanup | main folder | T4 |

---

## Prompts

### First session only (C01)
Claude Code, Opus 5.5, medium, folder `CustomChariot`, worktree **off**:
```text
You're head engineer on Custom Chariot. Read AGENTS.md, then do card docs/sessions/C01-foundation.md. There's no git repo yet; the card creates it. Only stop to ask if you're blocked.
```

### Builder
```text
You're a builder on Custom Chariot. Read AGENTS.md, then do card docs/sessions/<C05-track>.md on branch <c05-track>. Follow the card's Owns list, run the tests, write the handoff, and land it on main yourself following AGENTS.md step 8, without asking me. Only stop to ask if you're blocked.
```

### Merge
Put what to merge in the `<...>`: `branch c05-track (worktree ../cc-c05)`, `PR 12`, or `every branch whose STATUS row is REVIEW`.
```text
You're head engineer on Custom Chariot, doing a merge session. Merge into main: <what>.

For each branch, one at a time:
1. `git checkout main && git pull origin main`. For a GitHub-only branch, `git fetch origin` and use `origin/<branch>`. For a local worktree branch, use its branch name and commit nothing in that worktree.
2. Read its handoff docs/handoffs/<Cxx>.md and its STATUS.md row.
3. `git merge <branch>`. On conflicts keep both sides' intent. If unsure which side wins, stop and ask me.
4. Run tools/run_tests.sh (after new/moved files, first `$GODOT --headless --path custom-chariot --import`). All must pass. Fix only obvious merge mistakes; otherwise stop and tell me.
5. In docs/STATUS.md set the row to DONE with today's date, flip TODO rows to READY whose dependencies are now all DONE, add a merge-log line. Commit.

When all are merged and green, `git push origin main` (never force-push). Then list any "Contract change requested" items from the handoffs with your recommendation (don't change contracts yourself).
```

### Question
```text
You're the head engineer on Custom Chariot, answering a question. Make no changes unless I ask. Open only the files the question needs; docs/STATUS.md, docs/ARCHITECTURE.md and DESIGN.md are the usual starting points. Answer in under 15 lines. My question: <question>
```

### Fix
```text
Read AGENTS.md. Bug from playtest: <what happened, what you expected, which build>. Find the cause with the smallest read possible, fix it on branch fix-<short-name>, add a test if it's headless-testable, write a 5-line note in docs/handoffs/fix-<short-name>.md, commit, and land it on main following AGENTS.md step 8 without asking.
```

### Design change
```text
You're head engineer on Custom Chariot. I want to change the design: <change>. Update DESIGN.md (keep its style, short), then list which cards in docs/STATUS.md and contracts in docs/ARCHITECTURE.md this affects and what you'd change. Change cards/ARCHITECTURE only after I say yes.
```

### Triage (after a playtest)
```text
You're head engineer on Custom Chariot, doing card C15 (triage). Playtest notes: <paste notes>. Read docs/STATUS.md, docs/PLAN.md §5 and the handoffs you need. Turn bugs into Fix cards, write detailed cards for the next wave in docs/sessions/, update STATUS.md and PLAN.md. Ask me before cutting or adding features that DESIGN.md doesn't have.
```

### Cleanup worktrees
```text
List the git worktrees and branches of this repo. For every worktree whose branch is merged into main, remove the worktree and delete the local branch. Don't touch unmerged ones: list them for me instead.
```

---

## Starting a session

**Claude Code (desktop app):** New session → folder `CustomChariot` → turn the **worktree** option on → pick
model + effort in the model picker → paste the prompt. Merge/question/design sessions: worktree **off**.

**Codex (ChatGPT desktop app):** open the `CustomChariot` project → new thread in **worktree** mode → pick
model + reasoning level → paste the prompt. Merge/question sessions: run in the main folder (local mode).
Codex reads `AGENTS.md` by itself.

First time in a new worktree, the agent runs Godot's import once. That's normal and takes a minute.

---

## Merging a worktree yourself (if you ever want to)

Normally agents merge themselves. If you want to do it by hand, in Terminal:

```bash
cd /Users/santofothergill/PersonalProjects/CustomChariot
```
```bash
git checkout main && git pull origin main
```
```bash
git merge <branch-name>
```
```bash
tools/run_tests.sh
```
```bash
git push origin main
```

If `git merge` reports conflicts, don't fix them by hand: run the **Merge** prompt instead.

---

## Setup (once, after C01)

C01 creates the local git repo. Then create the GitHub repo (private) and push. With the GitHub CLI:

```bash
cd /Users/santofothergill/PersonalProjects/CustomChariot && gh repo create CustomChariot --private --source=. --push
```

From then on, builders can self-merge and you can run cards in parallel.

---

## Playtesting (new to Godot)

- **Open the project:** run Godot → Import → pick `CustomChariot/custom-chariot/project.godot`.
- **Run the game:** press **F5** (or the ▶ button top right).
- **Two players on one Mac:** menu **Debug → Customize Run Instances…** → enable multiple instances → set 2.
  F5 then opens two windows. Host in one, join `127.0.0.1` in the other.
- **Tune the chariot:** in game press **F2** (tuning panel, after C04). Move sliders, drive, press Save.
  Values go to a file the agents use. This costs zero tokens.
- **Debug overlay:** **F3** shows ping, players, connection state.
- **Two machines / Steam:** follow `docs/STEAM_EXPORT_AND_TESTING.md` (copied from LastMage in C01).
- Don't edit scenes in the editor while agents are working: they edit the same files as text.

### Writing playtest notes
One line each, in three lists. That's all triage needs.
```text
Fun: <what felt good>
Boring/confusing: <what dragged or was unclear>
Broken: <what happened> / <what you expected> / <build or date>
```

---

## When things go wrong

| Symptom | Do this |
|---|---|
| Handoff says PARTIAL | Rerun the rest of the card one tier higher (builder prompt + "continue from the handoff") |
| Agent looping on the same bug | Stop it. Ask it to write what it tried into the handoff. Start a fresh session one tier higher |
| Claude or Codex out of usage | Give its cards to the other one. Every builder card is swappable |
| Tests fail on main | Fix prompt with "tests fail on main: <output>" |
| You're unsure if something matches the design | Question prompt |
