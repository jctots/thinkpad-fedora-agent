#!/usr/bin/env bash
# UserPromptSubmit hook body: warns when the session's current context size
# crosses a threshold, so a long session gets flagged before PreCompact fires
# — by the time PreCompact runs, most of the context window is already spent
# and compaction itself costs an extra LLM call on top of that.
#
# Reads the hook's stdin JSON, finds .transcript_path, and looks at the LAST
# assistant turn's usage block only — input_tokens + cache_read_input_tokens
# + cache_creation_input_tokens there approximates the context currently
# loaded, which is what predicts compaction. Summing usage across every turn
# in the transcript is wrong: cache_read_input_tokens re-counts the same
# reused context on every single turn, so a naive sum overstates real spend
# by roughly an order of magnitude on a long session (verified against a
# ~400-turn session: summed usage came out to ~12.9M tokens, of which
# ~12.4M was repeated cache_read noise, while the last turn's actual context
# size was ~203k).
#
# Threshold default (150000) sits under the standard 200k context window,
# so the warning lands before the window is nearly full, not at the edge.
# Override with SESSION_TOKEN_WARN_THRESHOLD.
#
# Usage: piped stdin JSON from the UserPromptSubmit hook, e.g.
#   echo '{"transcript_path":"/path/to/session.jsonl"}' | scripts/session-token-check.sh

set -euo pipefail

threshold="${SESSION_TOKEN_WARN_THRESHOLD:-150000}"

transcript_path="$(jq -r '.transcript_path // empty')"

if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
    exit 0
fi

context_size="$(python3 -c "
import json, sys
last_usage = None
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if d.get('type') == 'assistant':
            u = d.get('message', {}).get('usage')
            if u:
                last_usage = u
if last_usage is None:
    print(0)
else:
    print(
        last_usage.get('input_tokens', 0)
        + last_usage.get('cache_read_input_tokens', 0)
        + last_usage.get('cache_creation_input_tokens', 0)
    )
" "$transcript_path")"

if [ "$context_size" -ge "$threshold" ]; then
    printf '{"systemMessage": "Session context is at ~%s tokens (threshold %s) — consider wrapping up or starting fresh soon."}\n' \
        "$context_size" "$threshold"
fi

exit 0
