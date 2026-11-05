#!/bin/bash
# When scripts/restart-service.sh restarts (its wait_for_turn_gap): at once when no chat is
# mid-reply (idle); between turns, once no reply has produced anything for the gap; at the cap
# when the stream never pauses; and when the service stops answering. Runs the wait alone
# (RESTART_SERVICE_WAIT_ONLY=1) against a stand-in for the service's answers, on short timescales.
source "$(dirname "$0")/lib/test-hygiene.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d /tmp/chatterbox-test-restart-rule.XXXXXX)
export RESTART_SERVICE_WAIT_ONLY=1 RESTART_SERVICE_SUPPORT_DIR="$fixture/support"
export RESTART_SERVICE_GAP=2 RESTART_SERVICE_CAP=4 RESTART_SERVICE_GRACE=2 RESTART_SERVICE_POLL=1 RESTART_SERVICE_UNRESPONSIVE=2
export RESTART_SERVICE_STATUS_CMD="$fixture/status.sh"
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }
report="$fixture/support/Diagnostics/service-restart.txt"

# The stand-in answers "<mid-reply> <sequence>" as $fixture/mode says: idle, quiet (a reply
# mid-turn but producing nothing), streaming (a new event every time), or err.
cat > "$fixture/status.sh" <<STATUS
#!/bin/bash
case "\$(cat "$fixture/mode")" in
  idle) echo "0 41" ;;
  quiet) echo "2 41" ;;
  streaming) n=\$(( \$(cat "$fixture/count" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$fixture/count"; echo "1 \$n" ;;
  err) echo err ;;
esac
STATUS
chmod +x "$fixture/status.sh"

timed() {  # timed MODE → "RULE SECONDS"
  echo "$1" > "$fixture/mode"; rm -f "$fixture/count"
  local start end rule; start=$(date +%s)
  rule=$(scripts/restart-service.sh)
  end=$(date +%s)
  echo "$rule $(( end - start ))"
}
within() {  # within SECONDS MIN MAX
  (( $2 <= $1 && $1 <= $3 ))
}

result=$(timed idle); rule=${result% *}; took=${result##* }
[[ "$rule" == idle ]] && within "$took" 0 1 || fail "idle: got '$rule' after ${took}s"
pass "idle: no chat mid-reply, restarts at once"

result=$(timed quiet); rule=${result% *}; took=${result##* }
[[ "$rule" == "between turns" ]] && within "$took" 2 3 || fail "quiet: got '$rule' after ${took}s (wanted 'between turns' after ~${RESTART_SERVICE_GAP}s)"
pass "between turns: a reply mid-turn but producing nothing for ${RESTART_SERVICE_GAP}s"

result=$(timed streaming); rule=${result% *}; took=${result##* }
[[ "$rule" == cap ]] && within "$took" 6 8 || fail "streaming: got '$rule' after ${took}s (wanted 'cap' after ~$((RESTART_SERVICE_CAP + RESTART_SERVICE_GRACE))s)"
pass "cap: a stream that never pauses restarts at cap+grace (${took}s)"

# Streaming past the cap, then a one-poll pause: the cap fires at that pause, before the grace.
echo streaming > "$fixture/mode"; rm -f "$fixture/count"
( sleep 4.5; echo quiet > "$fixture/mode" ) &
start=$(date +%s); rule=$(scripts/restart-service.sh); took=$(( $(date +%s) - start ))
[[ "$rule" == cap ]] && within "$took" 5 6 || fail "pause after cap: got '$rule' after ${took}s (wanted 'cap' at the first pause past ${RESTART_SERVICE_CAP}s)"
pass "cap: past the cap, the first pause in the stream restarts (${took}s)"

result=$(timed err); rule=${result% *}; took=${result##* }
[[ "$rule" == unresponsive ]] && within "$took" 2 3 || fail "err: got '$rule' after ${took}s"
pass "unresponsive: a service that doesn't answer for ${RESTART_SERVICE_UNRESPONSIVE}s"

grep -q "waiting for a gap between replies: restart once no reply has produced anything for 2s, at the latest 4s from now" "$report" || fail "the report doesn't say what it waits for: $(cat "$report")"
pass "report: says what it's waiting for"
echo "All restart rule checks passed."
