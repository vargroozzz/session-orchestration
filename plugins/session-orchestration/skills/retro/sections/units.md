# Section: units

## Gather

`units 7 P > units.tsv 2> units.txt`, adding `units <slice days> P` for the slice after last run's end. Project scope
only: pass the brief's regexes with `--merge`/`--done`/`--post` when its commands differ from the defaults (`retro.py`
usage). Where reviewers press merge, a session's merge command never runs: write the window's task keys with
`units 7 P --keys keys.txt > /dev/null 2>&1`, then from the project root the adapter's merges for them to `merged.txt`
(`.claude/session-status-adapter yesterday <window start, epoch s> $(cat keys.txt)`), and pass `--merged merged.txt`
to both `units` calls. An adapter without `yesterday`, or a non-zero exit: leave it out and say merges count only the
ones sessions ran (`merge_ran`). Time to merge, with a GitHub host: the PR list to `prs.json` (`gh pr list --state all
--limit 1000 --json number,createdAt,mergedAt -R OWNER/REPO`), then `merges <dir> prs.json 7 OWNER/REPO P >
merges.txt` (`waste`'s `sessions.tsv` first: it reads it for $ per PR).

## Measure

$ and tokens (output + cache write + cache read) per merged PR, per finished ticket and per review posted: `units.tsv`
and its totals line, counted from the sessions' own transcripts (only commands that ran), not a tracker sweep. Time to
done: review written → posted, "merge it" → merged. Weekly $ only as context, one line.
