---
name: vorssaint-feature-pr
description: >-
  Use this skill whenever a task adds or changes a Vorssaint feature, bug fix,
  implementation plan, tests, or pull request. It enforces one resource per
  branch, an isolated worktree for AI implementation, native macOS architecture,
  TCC validation, privacy, and verified delivery.
---

# Vorssaint feature workflow

Apply this skill before planning, editing code, writing tests, or preparing a PR
for Vorssaint. The project is a native Swift/AppKit macOS application. Preserve
its small dependency-free architecture and reuse existing mechanisms before
introducing new abstractions.

## Mandatory branch gate

Every resource that will produce implementation work receives its own branch and
worktree. Never implement a new resource in `main`, in another feature branch, or
in a shared checkout. Do not use `stash`, `reset`, destructive checkout, or
discard commands to make an occupied checkout appear clean.

Before editing, run:

```sh
git branch --show-current
git status --short --branch
git remote -v
git log -1 --oneline
```

Record these values in the PRD/story/handoff:

- `resource_slug`;
- target branch, normally `feat/<slug>`;
- dedicated worktree path;
- base (`upstream/main` for an independent feature, or the declared dependency
  head for a follow-up);
- dependency and whether the PR is independent or dependent;
- the single objective of the branch.

Stop if the current branch, worktree, base, or dependency does not match the
handoff. A PR must contain one resource unless the user explicitly approves a
combined PR. Do not push, force-push, or open a PR without explicit permission.

For this Menu Bar Manager follow-up, use:

- branch: `feat/menu-bar-manager-followup`;
- worktree: `/Users/ruansantana/Documents/DeepAgent/vorssaint-utils-menu-bar-manager`;
- dependency: PR #360, the canonical Menu Bar Organizer MVP;
- handoff: `_bmad-output/implementation-artifacts/ai-handoff-menu-bar-manager.md`.

## Discovery before implementation

Read the project map at `.agents/skills/vorssaint-feature-pr/references/project-map.md`
when it exists, then inspect the current source rather than trusting file names
from a plan. Search open issues and pull requests for the same topic. For this
feature, do not duplicate PR #360 and do not start integration until its actual
provider and API contract are confirmed.

Use the Ice project only as a product-behavior reference. Do not copy its code,
types, names, assets, text, architecture, `AXSwift`, or other dependencies.
Reimplement behavior with the existing Vorssaint/AppKit/ApplicationServices
patterns.

## Scope discipline

Keep independent objectives in separate branches and PRs. For a complete feature,
inspect and reuse the existing equivalents of:

- `FeatureCatalog`, `Defaults`, `FeatureRuntime`;
- permissions and `PermissionRow`;
- native services and idempotent `syncWithPreferences()` teardown;
- Settings, Command Bar, localization and backup;
- `Tests/MetricsTests.swift` and the project build scripts.

Keep pure normalization, ranking, sanitization, migration, and state decisions in
testable Core code. Keep AppKit, window, event monitor, Accessibility, and timer
coordination in Services. Do not import SwiftUI from services.

## Permission and privacy gate

Create a TCC matrix before code: operation, permission/entitlement, request point,
denied behavior, and Developer-bundle manual test. Check `Permissions.shared` and
existing permission UI before creating a new path.

The Developer bundle (`com.vorssaint.utils.dev`) has separate TCC consent. Gate
global services before starting them, show an actionable explanation when denied,
re-evaluate on foreground, and tear down idempotently when revoked. Never fail
silently. Keep secrets out of UserDefaults, source, logs, fixtures, and docs.

For the Menu Bar Manager follow-up, macOS 27+ must remain inert with preferences
preserved until its provider is separately designed and verified. Do not request
Screen Recording for this organizer MVP.

## Verification and handoff

Write Given/When/Then acceptance criteria, edge cases, a Code Map, ordered tasks,
and manual TCC/hardware limitations. For code changes, run proportionally:

```sh
swift build
./build.sh --test
./build/Vorssaint --selftest
./build.sh --dev
./build.sh
./build.sh --dev --install
git diff --check
git diff --stat upstream/main...HEAD
git log --oneline upstream/main..HEAD
```

Do not claim Accessibility, notch, Spaces, multiple monitors, hardware, network,
or real app interaction was tested unless it was actually tested. Report branch,
base, dependency, commit, files, tests, build variant, manual gaps, permissions,
and deferred scope when handing work back.
