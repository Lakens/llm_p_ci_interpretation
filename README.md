# llm_p_ci_interpretation

Validation work for `stat_p_ci_interpretation`, a Metacheck module (on the
`p-interpretation-check` branch of `metacheck-new`) that uses an LLM to judge
whether a sentence reporting a *p* value or confidence interval defines or
uses that statistic correctly, per 11 named misinterpretation categories
(e.g. `p_null_true`, `ci_prob_of_parameter`, `nonsig_sample`,
`nonsig_population`; see the module's own roxygen `@details` for the full
list and definitions).

## Models used

- **Groq (`groq/openai/gpt-oss-20b`)**: the model used for the original
  iterative prompt-development testing (the `test_*.R` and early `run_*.R`
  scripts) -- single sentences, ten hand-written sentences, 1-vs-2-example
  prompt comparisons, category disambiguation retests, and a determinism
  check. Billed per call.
- **TU/e SPIKE-1 gateway (`vllm/best-live`)**: TU/e's internal GPU cluster,
  reached through `https://spike-gateway-runai-aiteam.inference.spike.tue.nl/v1`,
  an OpenAI-compatible endpoint. `best-live` routes to whichever model the
  gateway currently has live (at the time of the corpus run, this was
  `deepseek-ai/DeepSeek-V4.1-Flash`). Used for the large-scale corpus run
  (`run_p_ci_all_papers_spike.R`) since it draws on an institutional token
  budget rather than per-call billing. Requires TU/e network access (VPN or
  eduroam) and a real `SPIKE_API_KEY` (subject to a **weekly token budget**;
  exceeding it returns HTTP 429 until the budget resets).
- **Claude (this conversation, `claude-sonnet-5`)**: independently read and
  judged a random 200-row sample as a second-opinion cross-check (see below).
  This is a second LLM's opinion, not ground truth.

Metacheck's `llm.R` routes both Groq and SPIKE calls through the same
`llm()`/`module_run()` machinery; SPIKE is reached via metacheck's existing
`vllm/<model>` provider path (`options(metacheck.llm.vllm.base_url = ...)`),
built for exactly this kind of custom OpenAI-compatible endpoint.

## Files

**Module test/development scripts** (run against Groq, on the psychsci
corpus or hand-written sentences):
- `run_p_ci.R`, `run_p_ci_one_paper.R`, `run_p_ci_all_papers.R` -- run the
  module on one or all papers.
- `test_p_ci_single_sentence.R`, `test_p_ci_ten_sentences.R`,
  `test_p_ci_1v2_examples.R`, `test_ci_disambiguation.R`,
  `test_p_null_true_retest.R`, `test_seed_determinism.R`,
  `test_undersuppression_check.R` -- adversarial/regression tests exercising
  specific categories, prompt variants, and determinism.

**SPIKE variants** (same module, routed through TU/e's SPIKE-1 gateway
instead of Groq):
- `run_p_ci_one_paper_spike.R` -- single-paper smoke test.
- `run_p_ci_all_papers_spike.R` -- resume-safe batch runner: saves results
  after every paper (not just at the end) to
  `_p_ci_all_papers_spike_result.rds`, so it can be interrupted and resumed;
  a paper whose stored result came back `traffic_light == "fail"` (an LLM
  call failure, e.g. a budget 429) is treated as **not done** and is
  retried on the next run, rather than being silently skipped forever.

**Result files** (`.rds`, from the scripts above):
- `_p_ci_single_sentence_result.rds`, `_p_ci_ten_sentences_result.rds`,
  `_p_ci_1v2_examples_result.rds`, `_p_ci_one_paper_result.rds` -- Groq test
  outputs.
- `_p_ci_one_paper_spike_result.rds` -- SPIKE single-paper output.
- `_p_ci_all_papers_spike_result.rds` -- SPIKE batch output. As of the last
  run: 220 papers processed (0 R-level errors), of which 56 came back
  `green`, 99 `red`, 19 `na` (no p-value/CI sentences detected), and 46
  `fail` (SPIKE weekly token budget exceeded mid-run; these are queued for
  retry once the budget resets, per the resume logic above).
- `_discussion_gap_exploration.rds` -- from earlier, related exploratory
  work; not produced by any script in this folder.

**Validation spreadsheets** (built from `_p_ci_all_papers_spike_result.rds`):
- `build_validation_xlsx.R` -> **`p_ci_validation.xlsx`**: one row per
  sentence that got a real judgment (from the 155 `green`/`red` papers only
  -- the 46 `fail` papers hold no genuine judgment and are excluded). 1,721
  rows. Columns: `paper_id`, `sentence`, `stat_text`, and the model's own
  `model_quoted_claim` / `model_misinterpreted` / `model_category` /
  `model_explanation` / `model_confidence`, plus three blank columns
  (`human_misinterpreted`, `human_category`, `human_notes`) left for a human
  coder to fill in, so sensitivity/PPV can eventually be computed against
  real labels (the same kind of statistic `stat_p_nonsig`'s roxygen
  `<validation>` tag reports for that module).
- `build_claude_evaluation_xlsx.R` -> **`p_ci_validation_claude_sample.xlsx`**:
  a random 200-row subset of the 1,721 (fixed seed `20260926`, reproducible),
  with three added columns from Claude's own independent reading of each
  sentence: `claude_misinterpreted`, `claude_category`, and
  `claude_agrees_with_model` (plus `claude_notes` explaining the call,
  especially on disagreements). **This is a second LLM's opinion, not
  ground truth** -- it does not by itself establish the module's real-world
  accuracy, which still needs human-coded labels (see `p_ci_validation.xlsx`
  above). Agreement on this sample: 182/189 comparable rows (11 rows had no
  model judgment to compare against) = 96.3%. Disagreements were mostly
  borderline calls on whether a nonsignificant-result sentence crossed from
  plain reporting into an absence-of-effect claim (the `nonsig_sample`/
  `nonsig_population` categories), plus one likely model false positive
  (row 39, an asterisk-significance legend flagged as `nonsig_population`
  with no actual claim in the text) and one category disagreement (row 64,
  `nonsig_sample` vs. `nonsig_population`).
- `build_stratified_435_xlsx.R` -> **`p_ci_validation_stratified_435.xlsx`**,
  labeled by `build_stratified_435_labeled_xlsx.R` into
  **`p_ci_validation_stratified_435_labeled.xlsx`**: a stratified sample --
  150 rows where the sentence reports a significant p value, 150 where it
  reports a nonsignificant p value, and every CI-only sentence in the corpus
  at the time (135 -- short of a 150 target, since the corpus only had 135
  total), 435 rows in total, each tagged with a `stratum` column
  (`sig`/`nonsig`/`ci_only`). Every row also has Claude's own independent
  judgment (`claude_misinterpreted`, `claude_category`,
  `claude_agrees_with_model`, `claude_notes`), read and judged directly in
  conversation rather than via a further scripted LLM call. **Still a second
  LLM's opinion, not ground truth.** Overall agreement: 382/391 comparable
  rows (97.7%); by stratum: sig 97.9%, nonsig 97.9%, ci_only 97.1%.
  Disagreements followed the same pattern as the 200-row sample above:
  mostly borderline calls on whether "did not differ significantly" crosses
  from plain reporting into an absence-of-effect claim, plus a few likely
  model false positives (e.g. a correctly-stated CI-excludes-zero heuristic
  mislabeled `nonsig_population` despite `misinterpreted == FALSE`) and
  occasional category mismatches (`nonsig_sample` vs. `nonsig_population`,
  or `p_other` where a `nonsig_*` label fit better).

## Known limitations

- SPIKE-1's weekly token budget is a hard cap; a full-corpus run (~1,900
  papers) will very likely need to span more than one week, resuming after
  each reset.
- The Claude-judged 200-row sample is a second-opinion cross-check, not a
  substitute for the human-coded validation `p_ci_validation.xlsx` still
  needs to produce a real sensitivity/PPV figure.
