#!/usr/bin/env bash
set -euo pipefail

TARGET_REPO="lobernardo/ss-aiagentsystem"
UPSTREAM_URL="https://github.com/chatwoot/chatwoot.git"
UPSTREAM_BRANCH="develop"
WORK_BRANCH="bootstrap/chatwoot-base"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || fail "git is required"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "run this script inside the cloned ss-aiagentsystem repository"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  fail "working tree is not clean; commit/stash and inspect changes before bootstrapping"
fi

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" != *"${TARGET_REPO}"* ]]; then
  fail "origin does not look like ${TARGET_REPO}: ${ORIGIN_URL}"
fi

CURRENT_BRANCH="$(git branch --show-current)"
[[ -n "$CURRENT_BRANCH" ]] || fail "detached HEAD is not supported"

PLANNING_REF="$(git rev-parse HEAD)"
PLANNING_BRANCH="planning/pre-chatwoot-import"

echo "Planning snapshot: ${PLANNING_REF}"

git branch -f "$PLANNING_BRANCH" "$PLANNING_REF"

if git remote get-url upstream >/dev/null 2>&1; then
  git remote set-url upstream "$UPSTREAM_URL"
else
  git remote add upstream "$UPSTREAM_URL"
fi

echo "Fetching Chatwoot upstream/${UPSTREAM_BRANCH}..."
git fetch upstream "$UPSTREAM_BRANCH"
UPSTREAM_REF="$(git rev-parse "upstream/${UPSTREAM_BRANCH}")"
echo "Upstream baseline: ${UPSTREAM_REF}"

# Create a clean working branch directly from Chatwoot history.
git switch -C "$WORK_BRANCH" "$UPSTREAM_REF"

# Preserve the upstream README for maintenance/reference before overlaying the ScanSolo project README.
mkdir -p docs/upstream
git show "upstream/${UPSTREAM_BRANCH}:README.md" > docs/upstream/CHATWOOT_README.md

# Overlay only ScanSolo planning/bootstrap artifacts from the original repository history.
for path in README.md .spec docs scripts; do
  if git cat-file -e "${PLANNING_BRANCH}:${path}" 2>/dev/null; then
    git checkout "$PLANNING_BRANCH" -- "$path"
  fi
done

# Re-create the saved upstream README after restoring docs/ from the planning snapshot.
mkdir -p docs/upstream
git show "upstream/${UPSTREAM_BRANCH}:README.md" > docs/upstream/CHATWOOT_README.md

# Record the exact baseline used by this bootstrap.
cat > docs/upstream/BASELINE.md <<BASELINE
# Chatwoot Upstream Baseline

- Repository: https://github.com/chatwoot/chatwoot
- Branch: ${UPSTREAM_BRANCH}
- Commit: ${UPSTREAM_REF}
- Imported at: $(date -u +%Y-%m-%dT%H:%M:%SZ)

The `upstream` remote must remain configured for future updates.

Custom ScanSolo work must avoid deriving implementation from upstream proprietary `enterprise/` code unless a valid Enterprise license is intentionally adopted.
BASELINE

git add README.md .spec docs scripts

if git diff --cached --quiet; then
  echo "No ScanSolo overlay changes to commit."
else
  git commit -m "chore: overlay ScanSolo platform planning on Chatwoot upstream"
fi

cat <<EOF

Bootstrap complete locally.

Current branch: ${WORK_BRANCH}
Chatwoot baseline: ${UPSTREAM_REF}

Next checks:
  git status --short
  git remote -v
  git log --oneline -5

When satisfied, push the bootstrap branch (this does NOT replace main):
  git push -u origin ${WORK_BRANCH}

Then run Claude Code from this branch and execute:
  /bc-harness:ai-context
  /bc-harness:plan ".spec/inputs/scansolo-chatwoot-platform.md"

Do NOT connect production Meta/OpenAI/Make/DNS/secrets during bootstrap or harness execution.
EOF
