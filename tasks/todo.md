# Todo: Practical Luau Embedding for Odin

## Phase 1: Reliable compiler and VM execution

- [ ] Task 1: Add the pinned Windows build/manifest workflow and correct native dependency linkage.
- [ ] Task 2: Repair the compiler/VM surface needed for protected compile, execute, callback, and cleanup workflows.
- [ ] Verify the Phase 1 workflow on actual Windows in ordinary and optimized Odin builds.

## Phase 2: Practical `require()` support

- [ ] Task 3: Bind the required Require APIs and implement root-constrained relative module loading with caching and useful errors.
- [ ] Task 4: Add protected entry scripts, `init.luau`, aliases, and a runnable UI/gameplay example.
- [ ] Verify nested modules, caching, diagnostics, independent VMs, and repeated teardown on Windows.

## Add only when needed

- [ ] Expand raw API coverage for concrete project requirements.
- [ ] Add packaged or virtual script sources if loose files no longer fit deployment.
- [ ] Add hot reload or explicit cache invalidation if the development workflow needs it.
