# 2. The Xcode project is generated

**Status:** accepted · **Date:** 2026-03-19

## Context

The refactor took the game from 3 Swift files to 41. `project.pbxproj` is a
flat list of objects with opaque 24-character identifiers; every added file
touches four sections of it. Two branches adding files conflict, and the merge
is almost impossible to review.

Adding a file also requires the Xcode UI, which means `touch` does not work and
a file can silently fail to join the target.

## Decision

`project.pbxproj` and the shared scheme are generated from the file tree by
[`scripts/generate_xcodeproj.py`](../../scripts/generate_xcodeproj.py).

* Every `.swift` under `FlappyBird/` joins the app target; every one under
  `FlappyBirdTests/` joins the test target.
* Object IDs are `md5(identity)[:24]`, so the output is byte-for-byte stable.
* Groups mirror directories.
* `--check` verifies the checked-in project matches the files on disk.

The generated file is committed, so the project still opens in Xcode with no
extra tooling.

## Alternatives considered

**XcodeGen or Tuist.** Both are better tools, and both add a dependency
contributors must install before they can open the project. For a project with
two targets and no dependencies, a 600-line script with no runtime requirements
beyond the Python that ships with macOS was the better trade.

**Xcode 16 synchronised folder groups.** They solve exactly this problem, and
would have been the right answer for a project that could require Xcode 16+.
Raising the minimum that far for a game this small was not worth it.

## Consequences

**Good.** Adding a file is `touch` + `make xcodegen`. Merge conflicts in the
project file disappear — both branches regenerate to the same thing. CI catches
a stale project, and the pre-commit hook installed by `make bootstrap` catches it
earlier.

**Costs.** Build settings live in the script rather than in Xcode's UI, so
changing one means editing Python. Anything the script does not model — a new
target, a Swift package dependency — has to be added to it first. Both are
acceptable for a project of this size, and the script is documented and readable.
