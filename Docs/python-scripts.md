# Python scripts and their imports

Every script under `Scripts/` uses the standard library only. `make python-imports-audit`
(part of `make verify`) enforces it: it parses each `Scripts/**/*.py` with `ast` and refuses
any top-level import that is not in `sys.stdlib_module_names`, not a Python module tracked in
this repository, and not pinned. It prints the file and line.

## Adding a third-party package

Prefer the standard library. When a package is genuinely needed:

1. Add a line to `python_imports_allow.txt` in `Scripts/`:
   `module package==version sha256:<64 hex> licence`, for example
   `numpy numpy==2.1.0 sha256:<wheel hash> BSD-3-Clause`.
2. Add the same pin with its hash to `requirements.lock` in `Scripts/`
   (`package==version --hash=sha256:<hash>`, the `pip-compile --generate-hashes` form).

The audit fails until both agree. Once `requirements.lock` in `Scripts/` exists, the Security
workflow's `osv-scanner` step scans it alongside `Package.resolved`.
