# Section: context

## Gather

`context 7 <split> P > context.tsv` (split: last run's end, so the slice after it gets its own row).

## Measure

Base context per session (first request, median) and average context per request; requests above 200K and their
excess tokens; resume forks (`fork` rows): `context.tsv`.
