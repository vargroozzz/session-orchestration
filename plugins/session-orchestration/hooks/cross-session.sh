#!/usr/bin/env bash
# UserPromptSubmit: when the incoming turn is a message from another Claude session, point the model
# at the protocol. Silent (and near-free) for every other prompt.
# Match only real deliveries: the harness wraps them as "Another Claude session sent a message:" followed
# by a <cross-session-message from=…> tag. A user prompt that merely mentions the tag doesn't match.
input=$(cat)
case "$input" in
  *'Another Claude session sent a message'*'<cross-session-message from='*)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"This turn is a message from another Claude session. Before replying, invoke the session-orchestration:orchestrating-sessions skill and follow its \"Receiving a message\" section."}}' ;;
esac
exit 0
