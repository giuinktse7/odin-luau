# AGENTS.md

luau can be found here: /c/Users/jonat/Documents/dev/checkouts/luau

## Code

- Keep changes focused on the task. Avoid unrelated refactors, cleanup, or removal of existing/partially implemented
  APIs.
- Prefer straightforward code over unnecessary abstraction or indirection.
- Before adding a helper, type, or abstraction, check whether the repository already has an established way to do the
  same thing.
- Preserve behavior outside the scope of the change unless intentionally modifying it.

## Search

- Prefer `rg` and `fd` for textual and file search.
- Use narrow, exact searches where possible; prefer `rg -wF` for identifiers.
- Avoid dumping large match sets or context ranges. Locate first, then inspect the relevant source directly.
- `tasks/archive/` is excluded by the repository `.ignore`; normal `rg` and `fd` searches should rely on that default
  and must not add manual archive-exclusion arguments.
- Treat `tasks/archive/` as historical material. Search it only when the user explicitly asks for archived, historical,
  or previous-plan information.
- When searching the archive, target it explicitly and override ignore rules as needed, e.g.
  `rg --no-ignore <pattern> tasks/archive/`.
- Current plans and TODOs live under `tasks/` outside `tasks/archive/`.

### Odin code navigation

- Prefer `odin-ast` for structural exploration of Odin code.
- Use `odin-ast map <path>` to understand a package or file.
- Use `odin-ast find <symbol> <paths...>` to locate declarations.
- Use `odin-ast show <file> <symbol>` to read an exact declaration.
- Use `odin-ast outline <paths...>` when signatures and nesting matter.
- Use `odin-ast AST_GREP_COMMAND [ARGS...]` for other structural queries. For example, `odin-ast run ...` forwards
  ast-grep's `run` command with the Odin configuration.
- Use `rg` instead for references, comments, strings, and filenames.
