# Build the Mac app once per shipment

The real Mac ship script builds, pushes, then calls an installer that builds the same target again. Share the build/install steps so shipping builds once, commits and pushes successfully, then installs those exact artifacts. Keep standalone installation and Dev identities unchanged.

```mermaid
flowchart LR
 A[Ship guards and source check] --> B[Lock DerivedData]
 B --> C[Build once and verify signature]
 C --> D[Commit staged changes and push]
 D --> E[Install and reopen]
 E --> F[Release DerivedData lock]
```

Success criteria: sandbox behavioral tests prove exactly one build for ship and standalone install; build/signature/push failures never install; the DerivedData lock spans build through copy and releases on failure; app arguments and environment scrubbing remain compatible. Existing build pressure/cache regressions pass.

- [x] M1 Share real Mac build/install operations and protect artifacts throughout shipping. Acceptance: sandbox command order and failure tests pass; no public skip-build path.
- [x] M2 Run focused build-lock/install/selector checks, document and commit/push tooling. Acceptance: tests pass, mapping covers changed scripts, main contains only this task's scoped files.

Deliverables: shell helpers, behavioral fixtures, test map and this plan committed/pushed on main. No actual app install/restart, phone build, TestFlight, routine configuration or source UI changes. Dev remains separate. The requested Recent section is subsequent work.

Verification: scripts/test-mac-install.sh, scripts/test-build-lock.sh, scripts/test-tests-for.sh, scripts/check-sources.sh, shell syntax and diff checks. Fixtures intercept all installation/system commands and never touch /Applications. Existing full-suite blockers remain recorded separately; no broad native run for this tooling change. Rollback: revert the scoped commit; no installed app or persistent data changes occur during this work.

Work preparation: Shelby explicitly requested implementation now. Linear, one executor because build/ship/install form one small flow. Model: current session; exact model/effort unavailable. Readiness: pass R1-R13. Open questions: none. Tracking: https://github.com/shelbyklein/chatterbox/issues/57.

Validation: four behavioral tests (nine shipment/install scenarios) pass with the real build-lock/cache wrapper and intercepted system commands. They prove one build, cache/job flags, push-before-copy, artifact lock coverage through verification/open, cleanup after success and build/signature/commit/push failures, guard behavior, argument forwarding and clean launch environment. All build-lock regressions, simulator-hygiene regressions, selector regressions (including ten Git fixtures), check-sources and shell/diff checks pass. No native app build, /Applications mutation or service restart occurred. The two delivery entry points now share Bash, avoiding zsh's missing EXIT cleanup on errexit within nested functions; the build wrapper remains tested in both shells. Dev install is unchanged because it already builds once.

Delivery: tooling on main, no app installation required. Issue remains open pending user acceptance. Removing the second xcodebuild invocation is verified; no claim of a measured end-to-end wall-clock speedup is made because no real shipment was run for tooling.
