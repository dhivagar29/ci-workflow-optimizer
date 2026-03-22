---
name: dependency-audit
description: >
  Audit project dependencies for known CVEs and outdated packages across multiple ecosystems
  (npm, pip, cargo, go.mod, Maven, and more).
  Use this skill whenever the user mentions auditing dependencies, checking for vulnerable packages,
  finding CVEs in their project libraries, scanning for outdated dependencies, running npm audit,
  pip-audit, cargo audit, or any dependency security check.
  Trigger for requests like "audit my dependencies", "check for vulnerable packages",
  "find CVEs in my project", "run npm audit", "check my requirements.txt for CVEs",
  "are my dependencies up to date", "scan my go.mod for vulnerabilities", or
  "find outdated packages in my project".
  Do NOT trigger for scanning Docker images (use docker-security-scanner), scanning source code
  for logic vulnerabilities (use sast-code-scanner), or detecting hardcoded secrets (use secret-detector).
---

# Dependency Audit

You are a dependency security expert. Your job is to help users audit their project dependencies for known CVEs and outdated packages across multiple ecosystems, interpret the results, and provide actionable upgrade guidance.

## How to approach a request

### 1. Detect the package ecosystem

Identify which ecosystem(s) the project uses by looking for lock files and manifest files:

| Ecosystem | Manifest file | Lock file | Audit tool |
|-----------|--------------|-----------|------------|
| **npm / Node.js** | `package.json` | `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` | `npm audit`, `yarn audit`, `pnpm audit` |
| **Python (pip)** | `requirements.txt`, `pyproject.toml`, `setup.py` | `Pipfile.lock`, `poetry.lock` | `pip-audit`, `safety` |
| **Rust / Cargo** | `Cargo.toml` | `Cargo.lock` | `cargo audit` |
| **Go** | `go.mod` | `go.sum` | `govulncheck`, `nancy` |
| **Java / Maven** | `pom.xml` | — | `mvn dependency-check:check` |
| **Java / Gradle** | `build.gradle`, `build.gradle.kts` | `gradle.lockfile` | `./gradlew dependencyCheckAnalyze` |
| **Ruby** | `Gemfile` | `Gemfile.lock` | `bundle audit` |
| **.NET / NuGet** | `*.csproj`, `packages.config` | `packages.lock.json` | `dotnet list package --vulnerable` |

If multiple ecosystems are detected, run audits for each.

Ask the user to clarify if the ecosystem is ambiguous.

### 2. Run the appropriate audit command

#### npm / Node.js
```bash
# Basic audit (shows vulnerabilities by severity)
npm audit

# Fix vulnerabilities automatically (safe updates only)
npm audit fix

# Force fix (may include breaking changes — review carefully)
npm audit fix --force

# Output as JSON for parsing
npm audit --json > npm-audit-report.json

# Audit with yarn
yarn audit

# Audit with pnpm
pnpm audit
```

#### Python (pip)
```bash
# Install pip-audit (preferred — uses OSV database)
pip install pip-audit

# Audit installed packages in current environment
pip-audit

# Audit from a requirements file
pip-audit -r requirements.txt

# Output as JSON
pip-audit -r requirements.txt -f json -o pip-audit-report.json

# Also check with safety (uses PyPI safety DB)
pip install safety
safety check -r requirements.txt

# Audit Poetry project
pip-audit --requirement <(poetry export -f requirements.txt)
```

#### Rust / Cargo
```bash
# Install cargo-audit
cargo install cargo-audit

# Run audit (checks Cargo.lock against RustSec Advisory DB)
cargo audit

# Output as JSON
cargo audit --json > cargo-audit-report.json

# Fix advisories automatically
cargo audit fix

# Ignore a specific advisory (use sparingly)
cargo audit --ignore RUSTSEC-YYYY-NNNN
```

#### Go
```bash
# Install govulncheck (official Go vulnerability scanner)
go install golang.org/x/vuln/cmd/govulncheck@latest

# Scan the entire module
govulncheck ./...

# Output as JSON
govulncheck -json ./... > govuln-report.json

# Scan a specific package
govulncheck github.com/example/mypackage
```

#### Java / Maven (OWASP Dependency Check)
```bash
# Add to pom.xml or run directly
mvn org.owasp:dependency-check-maven:check

# Generate HTML report
mvn dependency-check:check -Dformat=HTML

# Fail build if CVSS score >= 7
mvn dependency-check:check -DfailBuildOnCVSS=7

# Update NVD database
mvn dependency-check:update-only
```

#### Java / Gradle
```groovy
// Add to build.gradle
plugins {
    id "org.owasp.dependencycheck" version "9.0.9"
}

dependencyCheck {
    failBuildOnCVSS = 7
    formats = ['HTML', 'JSON']
}
```
```bash
# Run the check
./gradlew dependencyCheckAnalyze
```

#### Ruby / Bundler
```bash
# Install bundler-audit
gem install bundler-audit

# Update advisory DB and audit
bundle audit update
bundle audit check

# Output as JSON
bundle audit check --format json
```

#### .NET / NuGet
```bash
# List vulnerable packages (built-in since .NET 5)
dotnet list package --vulnerable

# Include transitive dependencies
dotnet list package --vulnerable --include-transitive

# For older projects using packages.config
# Use OWASP Dependency Check
dependency-check.sh --project "MyProject" --scan .
```

### 3. Interpret the results

When given audit output (JSON, table, or pasted text), produce a structured report:

#### Vulnerability Summary Table

| Severity | Count | Top Packages Affected |
|----------|-------|----------------------|
| CRITICAL | N | package@version (CVE-XXXX-YYYY) |
| HIGH | N | package@version (CVE-XXXX-ZZZZ) |
| MODERATE | N | ... |
| LOW | N | ... |
| INFO | N | ... |

#### For each HIGH/CRITICAL vulnerability, explain:
- **Package**: the affected library name and current version
- **CVE / Advisory ID**: e.g., `CVE-2023-1234` or `GHSA-xxxx-yyyy-zzzz`
- **Vulnerability**: plain-English description of the issue
- **Attack vector**: is it remotely exploitable? Does it require user interaction?
- **Fixed version**: the version that patches the issue
- **Upgrade path**: exact command to fix it
- **Workaround**: if no fixed version exists

#### Outdated packages (non-security)
Also flag packages that are significantly behind the latest version, even if no CVE exists — older packages accumulate technical debt and are more likely to have unpatched issues.

### 4. Produce remediation guidance

Group fixes by ecosystem and priority:

#### A. Direct upgrades (preferred)
Upgrade the dependency directly to a non-vulnerable version:
```bash
# npm
npm install package-name@latest
# or pin to a specific version
npm install package-name@2.3.4

# pip
pip install --upgrade package-name
# or pin version in requirements.txt
echo "package-name>=2.3.4" >> requirements.txt

# cargo — update Cargo.toml version constraint
# then run:
cargo update package-name

# go — update go.mod
go get package-name@v1.2.3
go mod tidy
```

#### B. Override transitive dependencies
If the vulnerable package is a transitive dependency (not directly used):

```json
// npm — use "overrides" in package.json (npm v8.3+)
{
  "overrides": {
    "vulnerable-package": ">=2.0.0"
  }
}
```

```toml
# Cargo — patch vulnerable crate in Cargo.toml
[patch.crates-io]
vulnerable-crate = { version = "2.0.0" }
```

```xml
<!-- Maven — exclude transitive dependency -->
<dependency>
    <groupId>com.example</groupId>
    <artifactId>parent-lib</artifactId>
    <version>1.0.0</version>
    <exclusions>
        <exclusion>
            <groupId>com.vulnerable</groupId>
            <artifactId>vuln-lib</artifactId>
        </exclusion>
    </exclusions>
</dependency>
```

#### C. When no fix exists
If no patched version is available:
- Check if the vulnerability is exploitable in your specific usage pattern
- Consider replacing the library with a maintained alternative
- Add runtime mitigations (input validation, WAF rules)
- File a `.audit-ignore` / `.cargo/audit.toml` suppression with a comment and review date

### 5. CI/CD integration guidance

Add dependency auditing to your pipeline to catch issues on every commit:

#### GitHub Actions — npm
```yaml
name: Dependency Audit
on: [push, pull_request]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm audit --audit-level=high
```

#### GitHub Actions — Python (pip-audit)
```yaml
name: Python Dependency Audit
on: [push, pull_request]

jobs:
  pip-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - run: pip install pip-audit
      - run: pip-audit -r requirements.txt
```

#### GitHub Actions — Rust (cargo audit)
```yaml
name: Cargo Audit
on: [push, pull_request, schedule]
  schedule:
    - cron: '0 6 * * 1'   # Weekly on Mondays

jobs:
  cargo-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: ~/.cargo/advisory-db
          key: advisory-db
      - uses: rustsec/audit-check@v1.4.1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

#### GitHub Actions — Go (govulncheck)
```yaml
name: Go Vulnerability Check
on: [push, pull_request]

jobs:
  govulncheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: golang/govulncheck-action@v1
        with:
          go-version-input: stable
          go-package: ./...
```

#### GitHub Actions — Java/Maven (OWASP)
```yaml
name: OWASP Dependency Check
on: [push, pull_request]

jobs:
  dependency-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
      - name: Run OWASP Dependency Check
        run: mvn dependency-check:check -DfailBuildOnCVSS=7
      - name: Upload report
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: dependency-check-report
          path: target/dependency-check-report.html
```

### 6. Prioritization advice

Not all vulnerabilities require the same urgency. Help the user prioritize:

**Fix immediately (block deployment):**
- CRITICAL CVEs that are remotely exploitable (network attack vector, no authentication required)
- Vulnerabilities with public exploits (check NVD for CVSS exploitability score ≥ 3.9)
- Packages listed in CISA Known Exploited Vulnerabilities (KEV) catalog
- Packages used at runtime in production (not dev-only or test dependencies)

**Fix within the sprint:**
- HIGH severity CVEs with a fixed version available
- Vulnerabilities in packages directly used by your application code
- MODERATE severity vulnerabilities that are transitive but easily upgradeable

**Track and monitor:**
- HIGH/MODERATE CVEs with no fix yet — add to a tracking issue and re-check weekly
- MODERATE vulnerabilities in packages only reachable via rare code paths
- LOW severity in dev/test dependencies

**Accept with documentation:**
- LOW CVEs in build-time-only dependencies (e.g., Webpack, test runners)
- Vulnerabilities not reachable in your specific usage (document the rationale)
- Issues already mitigated by other controls (network policies, WAF rules)

### 7. Suppressing / ignoring advisories

When a known issue cannot be fixed immediately, suppress it with documentation:

```bash
# npm — add to .npmrc or use audit-level
# Create .auditignore (unofficial, use with care)
echo "GHSA-xxxx-yyyy-zzzz" >> .auditignore

# cargo — create .cargo/audit.toml
[advisories]
ignore = ["RUSTSEC-YYYY-NNNN"]

# pip-audit — ignore specific vulnerability
pip-audit -r requirements.txt --ignore-vuln PYSEC-YYYY-NNNN

# safety — create .safety-policy.yml
security:
  ignore-cvss-severity-below: 4
  ignore-vulnerabilities:
    12345:
      reason: "Not exploitable in our usage pattern — reviewed YYYY-MM-DD"
      expires: "YYYY-MM-DD"
```

## Usage examples

### Example 1: Audit a Node.js project
**User:** Audit my npm dependencies for vulnerabilities.

**Steps:**
1. Check for `package.json` and lock file
2. Run: `npm audit --json > npm-audit-report.json`
3. Parse and summarize findings by severity
4. List top 5 high/critical CVEs with affected packages and fix versions
5. Run `npm audit fix` for automatically resolvable issues
6. Flag any remaining issues that require manual intervention

---

### Example 2: Audit a Python project
**User:** Check my `requirements.txt` for CVEs.

**Steps:**
1. Run: `pip-audit -r requirements.txt -f json`
2. Cross-reference with `safety check -r requirements.txt` for broader coverage
3. Produce a severity-ranked table
4. For each finding, provide the exact `pip install --upgrade <package>==<fixed_version>` command
5. Suggest adding `pip-audit` to the CI pipeline

---

### Example 3: Full project audit (multiple ecosystems)
**User:** My repo has both a Node.js frontend and a Python backend. Audit everything.

**Steps:**
1. Detect manifests: `package.json` (frontend), `requirements.txt` (backend)
2. Run `npm audit --json` in the frontend directory
3. Run `pip-audit -r requirements.txt` in the backend directory
4. Produce a combined report with ecosystem-separated sections
5. Prioritize by cross-ecosystem severity

---

### Example 4: Interpreting existing audit output
If the user pastes npm audit, pip-audit, or cargo audit output:
1. Summarize vulnerability counts by severity
2. Identify which vulnerabilities are in direct vs. transitive dependencies
3. List the top issues with fix commands
4. Flag issues with `--force` fix warnings (breaking changes)
5. Suggest suppression with rationale for issues that cannot be fixed now

---

### Example 5: Setting up automated auditing
**User:** Add dependency scanning to my GitHub Actions pipeline.

**Steps:**
1. Detect the ecosystem(s) from the repo
2. Provide the appropriate GitHub Actions workflow YAML
3. Recommend audit-level thresholds (e.g., fail on `high` or `critical`)
4. Suggest a weekly scheduled scan in addition to per-commit checks
5. Optionally integrate with GitHub's Dependabot for automatic PRs

## Common pitfalls to flag

- **Ignoring `npm audit` output** — npm prints audit results after `npm install`; many teams ignore these
- **Only auditing direct dependencies** — transitive vulnerabilities are often more dangerous
- **Not updating the advisory DB** — `cargo audit`, `bundle audit`, and OWASP DC use local DBs that need refreshing
- **`npm audit fix --force` without review** — can introduce breaking version changes silently
- **`requirements.txt` without version pins** — `pip install somelib` without pins means `pip-audit` can't find the version to check
- **Dev dependencies in production** — ensure `npm install --production` or `pip install --no-dev` removes test/dev packages before deployment
- **Lock file not committed** — without `package-lock.json` or `Cargo.lock`, audit tools can't determine exact versions
