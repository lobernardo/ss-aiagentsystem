# Pre-Harness Runbook

## Goal

Prepare `lobernardo/ss-aiagentsystem` on top of the current Chatwoot `develop` branch, then let the human operator run bc-harness.

No production provider is activated in this runbook.

## 1. Local clone

```bash
cd /home/leonardool/projetos
git clone https://github.com/lobernardo/ss-aiagentsystem.git
cd ss-aiagentsystem
```

Inspect first:

```bash
git status --short
git branch --show-current
git remote -v
```

## 2. Import Chatwoot upstream into a bootstrap branch

Run:

```bash
bash scripts/bootstrap-chatwoot-upstream.sh
```

The script:

- requires a clean worktree;
- verifies the expected repository origin;
- preserves the planning-only history in `planning/pre-chatwoot-import`;
- adds/updates `upstream=https://github.com/chatwoot/chatwoot.git`;
- fetches `upstream/develop`;
- creates `bootstrap/chatwoot-base` directly from upstream history;
- overlays this repository's `.spec/`, `docs/`, `scripts/` and project README;
- records the exact upstream baseline;
- does **not** replace `main`;
- does **not** push automatically;
- does **not** connect any production provider.

Inspect the result:

```bash
git status --short
git branch --show-current
git log --oneline -5
git remote -v
```

Then push only after verifying:

```bash
git push -u origin bootstrap/chatwoot-base
```

## 3. Do not configure production secrets

At this point do not add:

- real Meta access token/app secret;
- real ScanSolo WhatsApp number;
- production OpenAI key;
- production Make webhook/callback secret;
- real proposal API credentials;
- production SMTP credentials unless needed later for staging;
- final production DNS.

Use local/test/mock values only.

## 4. Start Claude Code from the imported Chatwoot branch

```bash
cd /home/leonardool/projetos/ss-aiagentsystem
git switch bootstrap/chatwoot-base
claude
```

Inside Claude Code:

```text
/bc-harness:ai-context
```

The command must inspect the actual imported Chatwoot code. Do not plan before context generation is complete.

## 5. Plan

Then run:

```text
/bc-harness:plan ".spec/inputs/scansolo-chatwoot-platform.md"
```

## 6. Human review before execution

Review all generated artifacts:

- `SPEC.md`
- `PLAN.md`
- `PHASES.md`

Every phase/task must have:

- identifier;
- clear title;
- Acceptance criteria;
- Tests with actual repository path/command;
- explicit dependency order;
- no hidden production activation.

Reject/revise the plan if it attempts to:

- copy Chatwoot `enterprise/` implementation;
- recreate native conversations/contacts/messages;
- use labels alone as the authoritative sales pipeline;
- put waiting/follow-up timing inside the language model;
- expose URLs/tokens/secrets to the model;
- connect real Meta/OpenAI/Make during implementation;
- deploy or migrate production automatically;
- disable the current ScanSolo Lexus runtime before final cutover.

## 7. Executor decision

Do not copy the Lexus Laravel/Sail `scripts/ralph.sh` blindly.

Chatwoot is a Rails/Vue project. After `/ai-context`, inspect the actual Chatwoot commands for:

- Rails/RSpec tests;
- frontend tests;
- lint/format;
- build;
- database setup/migrations;
- Docker development environment.

Only then create/adapt a repository-local hardened executor with the same safety properties:

- feature branch required;
- refuse `main`/default production branch execution;
- external validation of tests;
- no partial commit after failed phase;
- resumable phase state;
- plan-integrity validation;
- no production side effects.

## 8. Stop point

The pre-harness preparation is complete when:

- Chatwoot upstream is present on `bootstrap/chatwoot-base`;
- the ScanSolo planning overlay is present;
- `/bc-harness:ai-context` has been run;
- `/bc-harness:plan` has generated SPEC/PLAN/PHASES;
- the human has not yet authorized production activation.
