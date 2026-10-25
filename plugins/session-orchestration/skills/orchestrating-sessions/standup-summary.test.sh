#!/bin/bash
# Self-test of standup-summary (against a stub claude): cache per day, a session's moving text doesn't rerun it.
bash "$(dirname "$0")/standup-summary" --self-test && echo ok
