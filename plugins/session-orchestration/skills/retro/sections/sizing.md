# Section: sizing

## Gather

`chunks 7 > chunks.tsv` and `trial > trial.tsv` when the usage log has chunk lines; `kinds 7 > kinds.tsv` when it has
start lines. Exit 2 with `unmeasured: WHY` on stderr (no usage log, or one starting after the window's end) is no
measurement: write that line in the report, never a zero.

## Measure

The `ratio` per kind (median act/est) from `chunks.tsv`, and a new size multiplier for a kind whose median strays past
1.0 ± 0.3; `trial.tsv`'s arms week over week against last run's; from `kinds.tsv`, cost per start and done share per
kind beside last run's, and a plan.models change for a kind that costs more than the next kind up or reaches done less
than the one below it, or escalates in more than one start in four (its default is too low).
