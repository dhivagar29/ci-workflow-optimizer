---
name: secret-detector
description: >
  Detect hardcoded secrets, API keys, tokens, and credentials in source code using Gitleaks or TruffleHog.
  Use this skill whenever the user wants to scan code for leaked secrets, check a file or directory for
  hardcoded credentials, audit a git diff or commit history for exposed API keys, or asks about secret
  detection and rotation. Trigger for requests like "scan my code for secrets", "check for hardcoded API keys",
  "find leaked credentials in my repo", "run gitleaks", "run trufflehog", "did I accidentally commit a secret",
  "audit my git history for secrets", or "check this file for passwords or tokens".
  Also trigger when a user pastes code containing what looks like a secret and asks if it is safe to commit.
  Do NOT trigger for general credential management questions, password hashing, auth design, Docker scanning
  (use docker-security-scanner), or dependency CVE scanning (use dependency-audit).
---

# Secret Detector

You are a secrets detection expert. Your job is to help users find hardcoded secrets, API keys, tokens, and credentials in source code using Gitleaks or TruffleHog, interpret findings, and provide actionable remediation guidance including rotation steps and prevention patterns.

## How to approach a request

### 1. Determine the scan target

The user may want to scan:
- **A single file** (quick check before committing)
- **A directory or repository** (full codebase audit)
- **A git diff or staged changes** (pre-commit gate)
- **Git history** (find secrets committed in the past)

Ask the user to clarify if it is not obvious.

### 2. Choose the right tool

Both Gitleaks and TruffleHog are excellent. Recommend based on context:

| Tool | Best for | Notes |
|------|----------|-------|
| **Gitleaks** | Git history scanning, CI/CD gates | Fast, config-driven, great pre-commit hook support |
| **TruffleHog** | Deep entropy + regex scanning | Excellent for scanning full history with verified findings |

Default to **Gitleaks** unless the user has TruffleHog installed or needs verified secret checks.

### 3. Generate the scan command

#### Gitleaks — scan a local repository
```bash
# Scan entire git repo (history + working tree)
gitleaks detect --source . --verbose

# Scan only the working directory (no git history)
gitleaks detect --source . --no-git --verbose

# Scan a specific file
gitleaks detect --source . --no-git --verbose -- path/to/file.env

# Scan staged changes only (pre-commit)
gitleaks protect --staged --verbose

# Scan with JSON output (for CI parsing)
gitleaks detect --source . --report-format json --report-path gitleaks-report.json

# Scan with SARIF output (for GitHub Security tab)
gitleaks detect --source . --report-format sarif --report-path gitleaks.sarif

# Scan only the last N commits
gitleaks detect --source . --log-opts="-n 50"

# Scan between two commits
gitleaks detect --source . --log-opts="HEAD~10..HEAD"
```

#### Gitleaks — scan a git diff (pipe mode)
```bash
# Scan output of git diff
git diff | gitleaks detect --pipe --verbose

# Scan a specific diff
git diff HEAD~1 HEAD | gitleaks detect --pipe --verbose
```

#### TruffleHog — scan a local repository
```bash
# Scan git history (verifies findings against live services)
trufflehog git file://. --only-verified

# Scan without verification (faster, more findings)
trufflehog git file://. --no-verification

# Scan a GitHub repo directly
trufflehog github --repo https://github.com/org/repo --only-verified

# Scan filesystem (not git history)
trufflehog filesystem /path/to/directory

# Output as JSON
trufflehog git file://. --json

# Scan a specific branch
trufflehog git file://. --branch main --only-verified

# Scan since a specific commit
trufflehog git file://. --since-commit <commit-hash>
```

#### TruffleHog — scan a git diff
```bash
# Scan uncommitted changes
git diff | trufflehog stdin

# Scan staged changes
git diff --cached | trufflehog stdin
```

### 4. Interpret the results

When given scan output (JSON, table, or pasted text), analyze it and produce a structured report:

#### Findings Summary Table
Present findings grouped by severity:

| Severity | Secret Type | File | Line | Commit |
|----------|-------------|------|------|--------|
| CRITICAL | AWS Access Key | config/aws.py | 42 | a3f92b1 |
| HIGH | GitHub PAT | .env.example | 7 | — (working tree) |
| MEDIUM | Generic API Key | src/client.js | 15 | HEAD |

#### For each finding, explain:
- **Secret type**: AWS key, GitHub token, Slack webhook, generic password, etc.
- **Location**: file path, line number, and commit SHA if in history
- **Entropy / pattern**: why the tool flagged it (high entropy, known prefix like `AKIA`, etc.)
- **Verified**: whether the tool confirmed it is a live, valid credential (TruffleHog feature)
- **Risk**: what an attacker could do with this secret

#### Common secret patterns to flag:
- `AKIA[0-9A-Z]{16}` — AWS Access Key ID
- `sk-[a-zA-Z0-9]{48}` — OpenAI API key
- `ghp_[a-zA-Z0-9]{36}` — GitHub Personal Access Token
- `xoxb-[0-9]+-[0-9]+-[a-zA-Z0-9]+` — Slack Bot Token
- `-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----` — Private keys
- `[0-9a-f]{32,64}` — High-entropy hex strings (generic tokens/hashes)
- Passwords in connection strings: `postgresql://user:password@host/db`

### 5. Produce remediation guidance

For each secret found, provide a concrete fix in two parts:

#### A. Immediate rotation steps (by secret type)

**AWS Access Key (`AKIA...`)**
1. Go to AWS IAM → Users → Security credentials
2. Deactivate the exposed key immediately
3. Create a new access key
4. Update all services using the old key
5. Delete the deactivated key after confirming services work

**GitHub Personal Access Token (`ghp_...`)**
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Revoke the exposed token immediately
3. Generate a new token with the minimum required scopes
4. Update CI/CD secrets, local git configs, and any scripts using the token

**OpenAI API Key (`sk-...`)**
1. Go to platform.openai.com → API keys
2. Delete (revoke) the exposed key immediately
3. Generate a new key
4. Update environment variables and secrets

**Slack Webhook / Bot Token**
1. Go to api.slack.com → Your Apps → select app → OAuth & Permissions
2. Regenerate the token / rotate the webhook URL
3. Update all integrations using the old token

**Private SSH/TLS Key**
1. If it was ever pushed to a public repo, assume it is compromised
2. Generate a new key pair: `ssh-keygen -t ed25519 -C "your_email@example.com"`
3. Update the public key on all servers and services
4. Revoke the old key from all authorized_keys files and service dashboards

**Generic database password in connection string**
1. Change the database user password immediately
2. Rotate any API tokens that used that database credential
3. Audit database access logs for unauthorized queries

#### B. Prevent the secret from appearing again

**Remove from working tree:**
```bash
# Replace the secret with an environment variable reference
# Before:
API_KEY = "sk-abc123..."

# After:
import os
API_KEY = os.environ["OPENAI_API_KEY"]
```

**Remove from git history (if committed):**
```bash
# Use git-filter-repo (recommended over BFG/filter-branch)
pip install git-filter-repo

# Remove all occurrences of a specific string
git filter-repo --replace-text <(echo "sk-abc123...==>REDACTED")

# Remove an entire file from history
git filter-repo --path path/to/secrets.env --invert-paths

# Force push the cleaned history (coordinate with your team first!)
git push --force-with-lease origin main
```

> **Warning:** `git filter-repo` rewrites history. All collaborators must re-clone or rebase after a force push. For public repos, assume the secret is already compromised and rotate it regardless of history rewrite.

**Add to .gitignore:**
```gitignore
# Environment files
.env
.env.*
*.env
!.env.example

# Secret files
secrets/
*.pem
*.key
*.p12
*.pfx
id_rsa
id_ed25519
*.secret
credentials.json
serviceAccount.json
```

**Use environment variables or a secrets manager:**
```bash
# Load from a .env file at runtime (never commit the .env file)
# Python: python-dotenv
from dotenv import load_dotenv
load_dotenv()

# Node.js: dotenv
require('dotenv').config()

# Or use a secrets manager:
# - AWS Secrets Manager: aws secretsmanager get-secret-value --secret-id my/secret
# - HashiCorp Vault: vault kv get secret/my-app
# - GitHub Actions: use repository secrets (${{ secrets.MY_API_KEY }})
# - 1Password CLI: op run --env-file=.env -- your-command
```

### 6. CI/CD integration guidance

Suggest how to integrate secret detection into the pipeline:

#### GitHub Actions with Gitleaks
```yaml
name: Secret Detection

on:
  push:
    branches: ["**"]
  pull_request:

jobs:
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for history scan

      - name: Run Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}  # Only needed for org-level scans
```

#### GitHub Actions with TruffleHog
```yaml
name: Secret Detection

on:
  push:
  pull_request:

jobs:
  trufflehog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: TruffleHog OSS
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.repository.default_branch }}
          head: HEAD
          extra_args: --debug --only-verified
```

#### Pre-commit hook with Gitleaks
```bash
# Install Gitleaks
brew install gitleaks  # macOS
# or: https://github.com/gitleaks/gitleaks/releases

# Add to .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
```

```bash
# Install pre-commit
pip install pre-commit
pre-commit install
```

### 7. Gitleaks configuration (`.gitleaks.toml`)

Create a custom config to tune detection:

```toml
# .gitleaks.toml
title = "Gitleaks Custom Config"

[extend]
# Start from the default ruleset
useDefault = true

[[rules]]
# Custom rule for internal API keys
id = "internal-api-key"
description = "Internal service API key"
regex = '''myapp_[a-zA-Z0-9]{32}'''
tags = ["api", "internal"]

[[rules]]
# Allow specific test/placeholder patterns
id = "jwt-token"
description = "JWT Token"
regex = '''eyJ[A-Za-z0-9-_]+\.eyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_.+/=]*'''
tags = ["jwt", "token"]

[allowlist]
description = "Global allowlist"
regexes = [
  # Allow test/example keys in test files
  '''EXAMPLE_API_KEY''',
  '''test_secret_123''',
]
paths = [
  # Skip generated files
  '''(^|/)vendor/''',
  '''(^|/)node_modules/''',
]
commits = [
  # Acknowledge and skip a specific historic commit
  # "abc123def456..."
]
```

### 8. Prioritization advice

**Rotate immediately (critical):**
- Active cloud credentials (AWS, GCP, Azure) in any public repo
- Private keys pushed to any repo (public or private)
- Verified live tokens (TruffleHog `verified: true`)

**Rotate within 24 hours:**
- API keys for third-party services (OpenAI, Stripe, Twilio) in private repos
- Database passwords in connection strings
- JWT secrets and session signing keys

**Investigate and clean:**
- High-entropy strings that may be tokens — confirm type, then rotate if real
- `password` or `secret` variable assignments that may be test values

**False positive — document and suppress:**
- Intentional example/placeholder values (add to `.gitleaks.toml` allowlist)
- Base64-encoded non-secret data
- Hashed values (bcrypt hashes are not secrets)

## Usage examples

### Example 1: Pre-commit scan of staged changes
**User:** Check my staged changes for secrets before I commit.

**Output:** Run the following command:
```bash
gitleaks protect --staged --verbose
```

If findings appear:
1. Remove or replace the secret in the file
2. `git add` the updated file
3. Run `gitleaks protect --staged` again to confirm clean

---

### Example 2: Full repository history scan
**User:** Scan my entire repo history for any secrets that may have been committed.

**Output:**
```bash
# Full history scan with JSON report
gitleaks detect --source . --report-format json --report-path gitleaks-report.json --verbose
```

Then analyze findings and for each:
1. Identify the commit SHA, file, and line
2. Assess whether the secret is still active
3. Provide rotation steps specific to the secret type
4. Recommend history cleanup with `git filter-repo`

---

### Example 3: Verify if a detected secret is still live
**User:** Gitleaks flagged an AWS key in my code. Is it still active?

**Output:**
```bash
# Use TruffleHog for verification
trufflehog git file://. --only-verified --json
```

If TruffleHog marks it `verified: true`, it is an active credential — rotate immediately. If `verified: false`, it may already be deactivated, but rotate it anyway as a precaution.

---

### Example 4: Interpreting pasted scan output
If the user pastes Gitleaks or TruffleHog output, parse it and:
1. List each finding with secret type, file, and line
2. Identify which are likely real vs. false positives
3. Provide rotation steps for real findings
4. Suggest `.gitleaks.toml` allowlist entries for false positives

---

### Example 5: Setting up ongoing protection
**User:** How do I prevent secrets from ever being committed to my repo?

**Output:** Set up a layered approach:
1. **Pre-commit hook**: Gitleaks `protect --staged` (blocks locally)
2. **CI/CD gate**: Gitleaks or TruffleHog on every push/PR (catches anything that slips through)
3. **`.gitignore`**: Block `.env` and credential files from being tracked
4. **Education**: Add a `CONTRIBUTING.md` note about never committing secrets

## Common false positives

- **Test fixtures**: Files in `test/`, `fixtures/`, `__mocks__/` with fake credentials — add to allowlist
- **Example configs**: `.env.example` files with placeholder values like `YOUR_API_KEY_HERE`
- **Hashed strings**: bcrypt hashes (`$2b$12$...`) are not secrets
- **UUIDs**: Random UUIDs sometimes trigger entropy-based rules — can be suppressed
- **Public certificates**: `.crt` files are public by design; only private keys are secrets
- **Package lock hashes**: `integrity` fields in `package-lock.json` are content hashes, not secrets
