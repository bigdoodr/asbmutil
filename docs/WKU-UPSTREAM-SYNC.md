# Keeping this fork in sync with upstream

This fork ([bigdoodr/asbmutil](https://github.com/bigdoodr/asbmutil)) tracks
[rodchristiansen/asbmutil](https://github.com/rodchristiansen/asbmutil). WKU's changes stay in this
repository; new upstream work arrives as a pull request, and merging that PR produces a release.

## What happens

1. **Daily**, [Upstream Sync](../.github/workflows/upstream-sync.yml) compares upstream's `main` with the
   commit recorded in `.github/upstream-sync.base`. If upstream has moved, it merges upstream's changes
   with this fork's customizations and opens (or updates) one PR from `upstream-sync/latest`.
2. **The PR shows what you need to review:** the new upstream commits and releases, every file WKU
   customizes and what became of it, and any new upstream lines that contain upstream's bundle
   identifier (so they can be rebranded).

   | Status in the PR | Meaning |
   |---|---|
   | kept | upstream didn't touch the file; the WKU change is untouched |
   | kept, merged | both changed the file, in different places; both changes are in |
   | absorbed | upstream now has the same change; nothing left to carry |
   | **conflict** | both edited the same lines. The PR is a **draft** labeled `needs-resolution`, with conflict markers committed so the diff shows where |
3. **CI builds the PR** (`ci.yml`: macOS and Linux). A conflicted or broken sync can't pass.
4. **Merge the PR.** That advances `.github/upstream-sync.base`, and the workflow tags `main` as
   `vYYYY.MM.DD.HHMM` (Central time). The tag starts the existing **Release** workflow, which builds
   the `.pkg`, `.dmg` and CLI zips and publishes the release.

If upstream publishes again before you merge, the same PR is updated in place. If you push your own
commits to `upstream-sync/latest` (for example to resolve a conflict), the daily job stops touching the
branch so your work isn't overwritten; merge or close the PR to resume. Run the workflow manually with
**force** to overwrite it anyway.

## Why it isn't a plain `git merge`

Upstream's history has been rewritten before (the same changes exist upstream and here under different
commit hashes), so git's merge-base is mid-2025 and a normal merge would conflict on nearly every file.
Instead the job does a three-way merge by **content**:

- base: the upstream commit in `.github/upstream-sync.base` (initially `c3aba6b`, whose files are
  identical to this fork before the WKU changes)
- ours: this fork's `main`
- theirs: upstream's `main`

That also means a change WKU made that upstream later makes too simply collapses into upstream's version.

## One-time setup

1. **Enable Actions** on the fork (Actions tab). GitHub turns them off on forks by default and pauses
   scheduled workflows after 60 days without repository activity.
2. **Add the `SYNC_TOKEN` secret** (Settings → Secrets and variables → Actions): a fine-grained
   personal access token limited to this repository with **Contents**, **Pull requests**, **Issues** and
   **Workflows** set to *Read and write*. The built-in `GITHUB_TOKEN` can't push upstream's
   `.github/workflows` changes, PRs it opens don't start CI, and tags it pushes don't start the Release
   workflow. (The Mac-Health-Check fork uses the same arrangement; its token is scoped to that repo, so
   this one needs its own or an expanded one.)
3. Run **Actions → Upstream Sync → Run workflow** once to open the first PR.

## Local dry run

```sh
DRY_RUN=true tools/ci-upstream-sync.sh     # pushes nothing; prints where the PR body was written
```

Needs git 2.40+ (`git merge-tree --write-tree`).

## Things to know

- Releases come from the existing `release.yml`, which builds **unsigned** artifacts. The separate
  [Signed Release](WKU-SIGNED-RELEASES.md) workflow then replaces the macOS assets with signed,
  notarized ones.
- `scripts/` is bundled into the `.pkg` as installer scripts, which is why the sync tooling lives in `tools/`.
- Upstream's `apple-api-watch.yml` arrives with the first sync and will open "Apple API changes to
  review" issues on this fork each week. Delete or disable it in the sync PR if you don't want them.
- `Sources/core/Utilities/Version.swift` is rewritten by CI and by `make`; it shows as a customization but
  never conflicts unless upstream edits it.
- If `.github/upstream-sync.base` ever points at a commit upstream no longer has, set it to the latest
  upstream commit whose files match what this fork last absorbed.
