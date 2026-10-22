# Publishing to GitHub

Everything below runs from the repository root — the folder containing
`CONSTITUTION.md`, `code/`, `packages/` and `specs/`.

---

## 1. Check what will be committed

Build artefacts must not go in. `.gitignore` at the repository root already
excludes them, but verify before the first commit:

```bash
git status --short
```

You should **not** see any of:

```
packages/fsdabridge.Rcheck/       created by R CMD check
packages/fsdabridge_0.1.0.tar.gz  created by R CMD build
__pycache__/                      Python bytecode
fsda-venv/  .venv/                the virtualenv
.Rhistory  .RData                 R session leftovers
```

If any appear, they were committed before `.gitignore` existed. Remove them from
tracking without deleting the files:

```bash
git rm -r --cached packages/fsdabridge.Rcheck
git rm --cached packages/fsdabridge_0.1.0.tar.gz
```

## 2. Check the gold references are included

These eight files are the agreement gate. Without them the gate rewrites its
references instead of comparing, and stops being a gate:

```bash
git status --short packages/fsdabridge/data-raw/reference/
ls packages/fsdabridge/data-raw/reference/
```

Eight `.rds` files should be listed. If `git status` ignores them — some R
`.gitignore` templates exclude `*.rds` — force them in:

```bash
git add -f packages/fsdabridge/data-raw/reference/
```

## 3. Commit

```bash
git add packages/fsdabridge .gitignore README.md
git commit -m "R package: generic FSDA facade, agreement gate, CI"
```

If the project follows `CONSTITUTION.md` section 6 ("commits reference the spec
number"), use the spec number instead once one exists for this package.

## 4. Push

On an existing repository:

```bash
git push origin main
```

On a new one — create the repository on GitHub first, empty, then:

```bash
git remote add origin https://github.com/<org>/FSDA-bridge.git
git branch -M main
git push -u origin main
```

## 5. CI runs by itself

`packages/fsdabridge/.github/workflows/R-CMD-check.yaml` triggers on pushes to
`main` and `group2/cran`, and on pull requests to either.

**One thing to know:** GitHub only runs workflows found in `.github/workflows/`
**at the repository root**. This one sits inside the package directory, which is
where it belongs for a multi-package repository but is not where GitHub looks.
Either move it:

```bash
mkdir -p .github/workflows
git mv packages/fsdabridge/.github/workflows/R-CMD-check.yaml \
       .github/workflows/fsdabridge-check.yaml
```

or copy it there. The `working-directory: packages/fsdabridge` lines inside it
are already correct for a root-level workflow, so nothing in the file changes.

Then check the **Actions** tab after pushing. The run does two things: `R CMD
check` on Linux and Windows with no MATLAB present, and a checksum comparison
between the bundled `engine.py` and the shared one.

It runs at `error-on: note`, so a single NOTE fails the build. That is
deliberate — the package currently has none.

## 6. Make the package installable from GitHub

Nothing to configure. Once pushed, anyone can install it:

```r
remotes::install_github("<org>/FSDA-bridge", subdir = "packages/fsdabridge")
```

They will still need MATLAB, FSDA and a matching `matlabengine` to make any
actual call — see the package README.

---

## Optional: a release

If the group wants a tagged version:

```bash
git tag -a fsdabridge-v0.1.0 -m "fsdabridge 0.1.0"
git push origin fsdabridge-v0.1.0
```

Then on GitHub: **Releases → Draft a new release**, pick the tag, and paste
`packages/fsdabridge/NEWS.md` as the description.

The tag is prefixed because the repository holds more than one package —
`pyfsda` has its own version line.

---

## Optional: r-universe

`R CMD check --as-cran` is clean, but CRAN is unlikely to accept a package
requiring MATLAB, since its functionality cannot be tested on CRAN's machines.
r-universe has no such constraint and gives a CRAN-like install:

1. Create a repository called `<org>.r-universe.dev`
2. Add a `packages.json` file to it:

```json
[
  {
    "package": "fsdabridge",
    "url": "https://github.com/<org>/FSDA-bridge",
    "subdir": "packages/fsdabridge"
  }
]
```

r-universe picks it up within a few hours and builds it. Users then install
with:

```r
install.packages("fsdabridge", repos = "https://<org>.r-universe.dev")
```

---

## Before pushing — a short checklist

```bash
cd packages/fsdabridge

R CMD INSTALL .
Rscript -e "library(fsdabridge); testthat::test_dir('tests/testthat')"

cd ..
R CMD build fsdabridge
R CMD check --as-cran --no-manual fsdabridge_0.1.0.tar.gz
rm -rf fsdabridge.Rcheck fsdabridge_0.1.0.tar.gz     # do not commit these
```

`R CMD build` should print no warnings, and the check should end `Status: OK`.

`--no-manual` skips the PDF manual, which needs a LaTeX installation. Drop the
flag if you have one.

To run the live layer and the agreement gate as well, set `FSDA_DEV_VENV` first
and see the package README.
