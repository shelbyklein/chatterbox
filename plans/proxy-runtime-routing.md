# Restore proxy preference routing

Claude's proxy toggle is omitted from RuntimePreferences, so daemon sessions use direct auth. The daemon also has no awaited proxy health check before provider startup. Restore forwarding and persisted routing for ordinary chats without changing Golem direct routing, credentials, model or effort.

Flow: Settings toggles → preference projection → daemon persisted preferences → awaited proxy check → Claude process environment → EasyCLIProxy account pool.

Execution: linear, current GPT-6.1-Sol Medium session per handoff. Local plan; implementation authorized by Shelby. Readiness: pass; no visual changes. No blocking questions.

- [x] T1 Register both real proxy keys; daemon owns restart-after-turn and initial check. Check preference roundtrip and launch environment.
- [x] T2 Run isolated runtime tests and Mac build; preserve assistant direct route and disabled route.
- [ ] T3 Commit/push Core then app, install and activate only when replies idle. Verify live persisted Claude proxy setting and actual routed process; if idle gate blocks, report pending activation.

Deliverables: scoped code, regression checks, pushed commits and tested build. Rollback: prior app bundle and prior commits; do not change proxy accounts/global CLI config. Account exhaustion itself is not induced in testing.

Checks: /tmp/proxy-runtime-tests.log (all pass; live proxy health and launch environment verified without sending a model request), /tmp/proxy-routing-build.log (build passes). Core dca8b64. Account exhaustion is untested. Activation will wait for all turns idle.
