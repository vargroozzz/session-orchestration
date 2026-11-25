# Section: protocol

## Gather

`start 7 > start.tsv` (each coordinator's Start by part, the medians last) and `loads 7 > loads.tsv` (messages, skill,
`worker.md`, card and reply loads by session kind).

## Measure

Against its targets: `start.tsv`'s median and `target` rows (per entrypoint when there are several: the app's harness
base runs ~30K above the CLI's; the base itself is the harness's, no target) and `loads.tsv`'s workers' skill loads (0
to reply: the card replaces them) and `reply_target`. Name the part furthest over.
