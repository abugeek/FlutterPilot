# 21 · Merge PR #133 and Sync Baseline

**Goal:** Integrate task 20 (CI desktop test parity) into `main`, update local branch tracking, and verify the fully integrated baseline.

## Steps
1. Merge PR #133 into `main`:
   `gh pr merge 133 --merge`
2. Switch to `main` and pull:
   `git checkout main && git pull origin main`
3. Delete branch `ci/windows-matrix`.
4. Verify tests and analyze:
   - `cd packages/flutterpilot_server && dart test` (all 737 pass)
   - `cd packages/flutterpilot_cli && dart test` (all 84 pass)
   - `dart analyze` across all 4 packages (0 errors).
