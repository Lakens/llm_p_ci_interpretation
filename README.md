# llm_p_ci_interpretation

Validation for `stat_p_ci_interpretation`, a Metacheck module (on the
`p-interpretation-check` branch of `metacheck-new`) that uses an LLM to
judge whether a sentence reporting a *p* value or confidence interval
defines or uses that statistic correctly, per 11 named misinterpretation
categories (e.g. `p_null_true`, `ci_prob_of_parameter`, `nonsig_sample`,
`nonsig_population`; see the module's own roxygen `@details` for the full
list and definitions).

## Files

- **`_p_ci_all_papers_spike_result.rds`** -- the module's raw output from
  running it on 220 papers from the psychsci corpus, via TU/e's SPIKE-1
  gateway (`vllm/best-live`, an OpenAI-compatible endpoint at
  `https://spike-gateway-runai-aiteam.inference.spike.tue.nl/v1`; at run
  time this routed to `deepseek-ai/DeepSeek-V4.1-Flash`). One list entry per
  paper: `traffic_light` (`green`/`red`/`na`/`fail`), a `table` of every
  judged sentence, and a `summary_table`. 56 papers came back `green`, 99
  `red`, 19 `na` (no p-value/CI sentence detected), and 46 `fail` (a SPIKE
  weekly token-budget 429 mid-run, not a real module error).
- **`claude_judgments.csv`** -- Claude's own independent judgment
  (`claude_misinterpreted`, `claude_category`, `claude_notes`) for the same
  435 sentences `build_stratified_435_labeled_xlsx.R` samples, read and
  judged directly rather than via a further scripted LLM call. **A second
  LLM's opinion, not ground truth.**
- **`build_stratified_435_labeled_xlsx.R`** -- the single script that
  reproduces everything: draws a stratified, seeded sample from the raw
  results (150 sentences reporting a significant p value, 150
  nonsignificant, and every CI-only sentence in the corpus -- 135, short of
  a 150 target since that's all the corpus had), retroactively fixes a real
  module bug (below), merges in Claude's judgment, and writes the labeled
  spreadsheet.
  ```
  Rscript build_stratified_435_labeled_xlsx.R
  ```
- **`p_ci_validation_stratified_435_labeled.xlsx`** -- the script's output.
  435 rows, each with the model's judgment (`model_misinterpreted`,
  `model_category`, `model_explanation`, `model_confidence`) alongside
  Claude's (`claude_misinterpreted`, `claude_category`,
  `claude_agrees_with_model`, `claude_notes`). Overall agreement: 384/392
  comparable rows (43 had no model judgment due to extraction failures) =
  98.0%; by stratum: sig 95.8%, nonsig 100%, ci_only 98.1%. Disagreements
  were mostly borderline calls on whether "did not differ significantly"
  crosses from plain reporting into an absence-of-effect claim (the
  `nonsig_sample`/`nonsig_population` categories), plus a few likely model
  false positives and occasional category mismatches.

## A module bug found and fixed here

The SPIKE-hosted model sometimes returned a `misinterpretation_type`
category alongside `misinterpreted == FALSE`, contradicting the module's
own schema description ("if misinterpreted is TRUE, else null").
`ellmer::type_enum()` has no way to enforce a cross-field constraint like
that -- the model can satisfy each field's own type individually while
still violating the relationship prose asked for between them. Found in 4
of 435 sampled rows. Fixed two ways:

1. **In the module itself** (`metacheck-new`'s
   `inst/modules/stat_p_ci_interpretation.R`): after the LLM call returns,
   `misinterpretation_type` is now forced to `NA` wherever `misinterpreted`
   is `FALSE` or `NA`, for both the structured and prompt-instructed
   fallback code paths.
2. **Retroactively in this repo's data**: `build_stratified_435_labeled_xlsx.R`
   nulls the same stray categories in `_p_ci_all_papers_spike_result.rds`
   (the raw corpus run predates the module fix), so the labeled spreadsheet
   reads as if the fix had always been in place.

## Known limitations

- SPIKE-1's weekly token budget is a hard cap; a full-corpus run (~1,900
  papers) will very likely need to span more than one week, resuming after
  each reset.
- Claude's judgment is a second-opinion cross-check, not a substitute for
  human-coded validation. No human-coded ground-truth labels exist yet for
  this module (unlike `stat_p_nonsig`, whose roxygen `<validation>` tag
  reports a real sensitivity/PPV figure against 194 hand-checked papers) --
  producing that is the next real step.
