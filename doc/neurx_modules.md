# NeurX Multi-Module Support

The S toolchain resolves NeurX packages (`neurx.*`) for compile, link (dependency graph merge), and run.

## Module layout

NeurX declares packages as `neurx.<area>.<name>` but source files live directly under the repo root:

| Package | Source |
|---------|--------|
| `neurx.agent.runtime` | `agent/runtime.s` |
| `neurx.planner` | `task/planner.s` |
| `neurx.runtime.io` | `runtime/io/io.s` |

When the package name does not match the directory path, generate a package index (see below).

## Resolution order

1. `S_PACKAGE_INDEX` or `build/s-package-index.tsv` (exact package → path)
2. Strip `neurx.` prefix and try `path.s` / `dir/name.s` under `S_PROJECT_ROOT`
3. Workspace roots from `s.work` (`use = "..."` lines)
4. Generic dotted-path candidates

## Commands

From the NeurX repo:

```bash
export S_PROJECT_ROOT=/path/to/neurx
/path/to/s/bin/s mod index .
/path/to/s/bin/s check neurx.agent.code_agent
/path/to/s/bin/s build agent/code_agent.s -o /tmp/neurx_code_agent
/path/to/s/bin/s run agent/code_agent.s
```

Environment:

- `S_PROJECT_ROOT` — NeurX repo root (set automatically by `bin/s` when run inside the tree)
- `S_PACKAGE_INDEX` — optional override for the TSV index file
- `S_WORK_FILE` — optional multi-root workspace file

## Linking / execution

The compiler loads the full dependency graph via `use` declarations (`load_source_graph` in the backend). All reachable modules are merged into one compile unit before IR emission, so `s build` / `s run` execute the linked program, not a single file in isolation.

Regenerate the package index after adding or moving `.s` files:

```bash
s mod index .
```

Rebuild the self-hosted compiler after changing `backend_elf64.s`:

```bash
cd /path/to/s
./bin/s bootstrap src/cmd/compile/main.s
```
