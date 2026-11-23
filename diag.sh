#!/usr/bin/env bash
# Temporary CI diagnostic: approved-action.test.sh with each check named as it starts, and timed.
h=$PWD/plugins/session-orchestration/hooks
sed -e "5s#.*#here=$h#" -e 's/^check() { got=\$(run "\$1");/check() { local t0=$SECONDS; echo "START $3"; got=$(run "$1"); [ $((SECONDS - t0)) -ge 2 ] \&\& echo "SLOW $((SECONDS - t0))s: $3";/' "$h/approved-action.test.sh" > /tmp/timed.test.sh
bash /tmp/timed.test.sh
