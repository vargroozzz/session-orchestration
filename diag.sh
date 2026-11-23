#!/usr/bin/env bash
# Temporary CI diagnostic: every shell suite with start/end times, so a hang names its suite.
git config --global user.email ci@example.com
git config --global user.name ci
while IFS= read -r t; do
  echo "== $(date +%T) START $t"
  bash "$t" > /tmp/suite.out 2>&1; rc=$?
  echo "== $(date +%T) END rc=$rc $t"; [ $rc = 0 ] || tail -5 /tmp/suite.out
done < <(git ls-files '*.test.sh')
