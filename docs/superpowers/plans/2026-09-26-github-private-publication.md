# FlyingSnowfluff GitHub Private Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a privacy-clean, reproducible source repository and v1.4.4 downloadable release to the private GitHub repository `aswqp/FlyingSnowfluff`.

**Architecture:** The Git repository contains source, required art assets, tests, scripts, and human-readable documentation. Generated builds, local backups, per-frame QA captures, installed state, and credentials remain outside Git; downloadable binaries are attached to the annotated `v1.4.4` GitHub Release with SHA-256 verification.

**Tech Stack:** Swift 6.1/AppKit, Swift Package Manager, zsh, Node.js 22+ with sharp 0.35.4 for optional asset regeneration, Git, GitHub private repository and GitHub Releases.

## Global Constraints

- Repository visibility must remain private.
- Repository root is `work/flying-snowfluff/`; do not upload the enclosing Codex workspace.
- Runtime remains offline Swift/AppKit with no telemetry, microphone, prompt-body collection, or new network dependency.
- Do not commit user hooks, trust records, settings, socket files, installed applications, historical recovery archives, build caches, or per-frame QA captures.
- No tracked file may exceed GitHub's 100 MiB per-file limit.
- Use v1.4.4/build 9 without changing character art, behavior, hooks mapping, or installed state.
- Release artifacts use the already verified v1.4.4 deliverables and must be re-hashed before upload.

---

### Task 1: Repository safety contract

**Files:**
- Create: `.gitignore`
- Create: `scripts/verify_repository.sh`
- Create: `Tests/Integration/repository_contract.sh`

**Interfaces:**
- Consumes: repository working tree and Git index.
- Produces: a fail-closed command that verifies required metadata, ignored local state, file-size limits, personal paths, and credential-like patterns.

- [ ] **Step 1: Add the failing repository contract test**

The test requires `.gitignore`, `README.md`, `VERSION`, `CHANGELOG.md`, `NOTICE.md`, and `scripts/verify_repository.sh`, then invokes the verifier.

- [ ] **Step 2: Run the test and confirm RED**

Run: `zsh Tests/Integration/repository_contract.sh`

Expected: non-zero with missing repository metadata or verifier.

- [ ] **Step 3: Add exact ignore rules and verifier**

Ignore `.build*`, `dist/`, `work/`, `.superpowers/`, `Resources/v3/qa/preview-frames/`, `Resources/v3/qa/runtime/`, Finder metadata, IDE caches, and outer workspace outputs. The verifier must reject files over 100 MiB and matches for private-key headers, GitHub token formats, the current developer's absolute home path, temporary screenshot paths, real socket suffixes, or committed hook data.

- [ ] **Step 4: Run the contract and confirm GREEN**

Run: `zsh Tests/Integration/repository_contract.sh`

Expected: `PASS: repository publication contract`.

### Task 2: Portable build and installation paths

**Files:**
- Modify: `scripts/build_release.sh`
- Modify: `scripts/build_assets.sh`
- Modify: `scripts/asset_pipeline_contract.test.cjs`
- Modify: `scripts/install_local.sh`
- Modify: `scripts/install_local_core.sh`
- Modify: `Tests/Integration/install_local_transaction.sh`
- Delete from publication set: `toolchain/hide-duplicate-swiftbridging.json`
- Create: `package.json`

**Interfaces:**
- Consumes: project root and optional `OUTPUT_DIR`, `NODE_BIN`, `NODE_MODULES` environment variables.
- Produces: `dist/FlyingSnowfluff.app` and archives by default; optional deterministic asset regeneration through local Node dependencies.

- [ ] **Step 1: Extend the repository contract with path-portability assertions**

Assert there are no current-developer absolute home references in committed build/install scripts, and that Release output defaults to `dist/`.

- [ ] **Step 2: Confirm the portability assertion fails**

Run: `zsh Tests/Integration/repository_contract.sh`

Expected: failure listing the current hard-coded VFS overlay or Node runtime paths.

- [ ] **Step 3: Implement portable path discovery**

Remove the obsolete user-specific VFS overlay from Release compilation. Set `OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"`; rotate older artifacts under `dist/.backups`. Resolve Node from `NODE_BIN` or PATH and resolve sharp from `NODE_MODULES` or repository `node_modules`. Pass the artifact directory explicitly into the transactional installer.

- [ ] **Step 4: Run shell syntax, installer, asset and portability tests**

Run:

```zsh
zsh -n scripts/*.sh Tests/Integration/*.sh
zsh Tests/Integration/install_local_transaction.sh
npm run test:assets
zsh Tests/Integration/repository_contract.sh
```

Expected: all commands exit 0.

### Task 3: Reader-facing project documentation

**Files:**
- Create: `README.md`
- Create: `VERSION`
- Create: `CHANGELOG.md`
- Create: `NOTICE.md`
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/BUILD.md`
- Create: `docs/releases/v1.4.4.md`
- Modify: historical `docs/superpowers/` files only if they are selected for publication; otherwise leave them ignored.

**Interfaces:**
- Consumes: verified project behavior and v1.4.4 artifacts.
- Produces: quick download instructions, source build instructions, privacy/IP boundaries, architecture map, verification commands, and release notes.

- [ ] **Step 1: Write README quick paths**

Document Release download, Finder right-click opening for non-notarized builds, SHA-256 validation, source build, test commands, Codex hooks trust, and private-repository access requirements.

- [ ] **Step 2: Add version, changelog, notice, architecture and build guide**

Record v1.4.4/build 9, macOS 15+/Apple Silicon/Swift 6.1, ad-hoc signing boundaries, separate code/character-IP terms, and the local socket privacy contract.

- [ ] **Step 3: Run documentation and repository contracts**

Run: `zsh Tests/Integration/installation_guide.sh && zsh Tests/Integration/repository_contract.sh`

Expected: both print PASS.

### Task 4: Full local verification and clean-clone proof

**Files:**
- Verify: all tracked project files
- Generate outside Git: `dist/`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: evidence that the committed tree builds and tests without relying on ignored local state.

- [ ] **Step 1: Run core and asset tests**

Run SwiftPM's 40 tests, dialogue harness, repository contract, lively asset tests, and installer transaction tests.

- [ ] **Step 2: Run AppKit harnesses**

Run `LivelyRenderingHarness`, `AppRenderingHarness fallback`, and `AppBehaviorHarness`.

- [ ] **Step 3: Build Release into `dist/` and validate**

Run `zsh scripts/build_release.sh`, `codesign --verify --deep --strict dist/FlyingSnowfluff.app`, `unzip -t` for all ZIP files, and validate the external `.sha256` from inside `dist/`.

- [ ] **Step 4: Re-run from a fresh local clone**

Clone the local repository to `/private/tmp`, run `swift test`, repository contract, and Release build there. Any dependency on ignored files is a failure.

### Task 5: Git history, private remote and v1.4.4 Release

**Files:**
- Track: the safety-approved source tree
- Attach to GitHub Release: artifacts listed in the design spec

**Interfaces:**
- Consumes: verified clean local commits, annotated tag, existing v1.4.4 outputs.
- Produces: private `aswqp/FlyingSnowfluff`, pushed `main`, pushed annotated `v1.4.4`, and a GitHub Release whose assets match local hashes.

- [ ] **Step 1: Audit the exact Git index**

Run `git status --short`, `git diff --cached --check`, `git ls-files`, file-size audit, sensitive-pattern scan, and `git check-ignore` for excluded paths.

- [ ] **Step 2: Create focused commits and tag**

Use Conventional Commits, then create `git tag -a v1.4.4 -F docs/releases/v1.4.4.md`.

- [ ] **Step 3: Create the GitHub repository as private**

Create only `aswqp/FlyingSnowfluff`, verify the owner, name, and visibility before pushing, and set `origin` to `git@github.com:aswqp/FlyingSnowfluff.git`.

- [ ] **Step 4: Push main and tag, then publish assets**

Push `main` and `v1.4.4`; create a GitHub Release using `docs/releases/v1.4.4.md` and upload the verified artifacts without replacing unrelated remote content.

- [ ] **Step 5: Verify remote state**

Confirm private visibility, remote default branch, commit SHA, annotated tag type, Release asset list/sizes, and downloaded asset SHA-256. Report local completion separately from remote publication if any remote gate fails.
