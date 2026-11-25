# Section: features

## Gather

`usage 30 > usage.tsv` and `events 30 > events30.tsv`.

## Measure

Each `unused` row of `usage.tsv` (0 uses in 30 days, there all window) is a candidate to drop or merge: at most one
proposal listing them, never a removal on the run's own say. Pane buttons show `-` under `telemetry: off`
(setting-up-coordination, Config; the default `full` and `local` log them): say so, and judge them not at all.
`block`, `refuse`, `relay`, `error` and the `wake poll-failed`/`gave-up` rows (telemetry `full`; `wake wake` is a
watcher's normal wake, counted, not a fault) are the plugin's faults: count them in `waste`, and a row that grew since
last run (a hook line, a --flag, an exit code) is a fix to propose. `fold-SECTION` (a section's title pressed to one
line), `unfold-SECTION` (pressed open) and `card-SECTION` (a row opened there) say which pane sections the user opens
and which never: report them. A section folded and never unfolded is one nobody reads (a candidate for `hidden` in
config pane.sections).
