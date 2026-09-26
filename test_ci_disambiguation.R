# ─────────────────────────────────────────────────────────────────────────────
# Targeted retest of ci_prob_of_parameter vs ci_confidence_in_realized_interval
# after adding positive/negative examples and a disambiguation rule.
#
# 4 sentences:
#   1. The original still-failing case (expected ci_confidence_in_realized_
#      interval, was mislabeled ci_prob_of_parameter in both prior tests)
#   2. A clean ci_prob_of_parameter case (must still work -- checking the
#      disambiguation rule didn't break the OTHER category)
#   3. A negative example: plain CI reporting with no claim at all (must NOT
#      flag -- this is literally the negative example just added to the prompt)
#   4. A negative example variant: CI reported inline as part of a results
#      list (must NOT flag either)
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript test_ci_disambiguation.R
# ─────────────────────────────────────────────────────────────────────────────

metacheck_new_path <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/metacheck-new"

current_branch <- system2("git", c("-C", shQuote(metacheck_new_path),
                                   "branch", "--show-current"),
                          stdout = TRUE)
if (!identical(current_branch, "p-interpretation-check")) {
  stop("metacheck-new is on branch '", current_branch, "', not ",
       "'p-interpretation-check'. Check out that branch first.", call. = FALSE)
}

devtools::load_all(metacheck_new_path)
source(file.path(metacheck_new_path, "inst/modules/stat_p_ci_interpretation.R"))

llm_use(TRUE)
llm_cache(FALSE)
llm_max_calls(10)
metacheck::llm_model("groq/openai/gpt-oss-20b")

sentences <- data.frame(
  id = 1:4,
  expect = c(
    "FLAG: ci_confidence_in_realized_interval (previously failed twice)",
    "FLAG: ci_prob_of_parameter (sanity check -- must still work)",
    "NO FLAG: plain CI reporting alone (negative example)",
    "NO FLAG: CI reported inline in a results list (negative example variant)"
  ),
  expanded = c(
    "There is a 95% chance the true mean difference is between 1.2 and 3.8.",
    "The 95% CI = [0.12, 0.45] means there is a 95% probability that the true effect size falls within this range.",
    "The 95% CI was [1.2, 3.8].",
    "Reaction times improved significantly, M = 0.49, 95% CI [0.40, 0.58], p = .002."
  ),
  stat_text = c("95% chance", "95% CI", "95% CI", "95% CI"),
  stringsAsFactors = FALSE
)

cats <- .p_ci_categories()
cat_list <- paste(sprintf("- %s: %s", names(cats), cats), collapse = "\n")
anti_forcing <- paste(
  "Only flag a sentence as misinterpreted if it makes an actual claim about",
  "what the p value or confidence interval MEANS, and that claim's LOGICAL",
  "STRUCTURE -- not just its vocabulary -- matches one of the categories",
  "above. Quote the exact claim first (quoted_claim), then check whether",
  "THAT SPECIFIC WORDING commits the error the category describes. A",
  "sentence using CI/p-value terminology without making the category's",
  "specific wrong claim is NOT a misinterpretation, even if a category",
  "sounds topically related -- e.g. 'nonoverlapping confidence intervals",
  "indicate a significant difference' is a directionally CORRECT informal",
  "heuristic, not a misinterpretation, even though it mentions confidence",
  "intervals. Do NOT flag a sentence merely for reporting the number, for",
  "using loose/informal language that does not amount to one of these",
  "specific errors, for drawing a broader conclusion (e.g. 'this shows a",
  "strong effect'), or for a different kind of statistical concern (e.g.",
  "dichotomous significance language) -- those are out of scope for this",
  "check. If the sentence only reports the statistic without making a claim",
  "about its meaning, treat that as NOT misinterpreted. When genuinely",
  "uncertain whether the quoted claim fits a category's exact logical",
  "structure, prefer NOT misinterpreted over forcing a near-fit label, and",
  "give a lower confidence score."
)
structured_prompt <- paste0(
  "You will see a sentence from a scientific manuscript that reports a p value or a confidence interval (CI). Judge whether the sentence's own DEFINITION OR USE of what that p value or confidence interval MEANS is technically correct, per the specific misinterpretation categories below (from Bergwerff, Corten, & van Batenburg-Eddes's compendium of real misinterpretations found in technical guidance documents, grounded in Morey et al. 2016's correct definition of a confidence interval).\n\n",
  "Categories:\n", cat_list, "\n\n",
  anti_forcing
)

for (i in seq_len(nrow(sentences))) {
  row <- sentences[i, ]
  message("\n[", i, "/4] expect: ", row$expect)
  message("  ", row$expanded)

  one_row <- data.frame(expanded = row$expanded, stat_text = row$stat_text,
                        stringsAsFactors = FALSE)
  t0 <- Sys.time()
  res <- tryCatch(
    llm(text = one_row, system_prompt = structured_prompt, type = .p_ci_type_spec(),
        text_col = "expanded", model = llm_model(), params = list(seed = 8675309 + i)),
    error = function(e) { message("  ! ERROR: ", conditionMessage(e)); NULL }
  )
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (!is.null(res)) {
    message("  misinterpreted: ", res$misinterpreted,
           " | type: ", as.character(res$misinterpretation_type),
           " | confidence: ", res$confidence, " | ", round(elapsed, 1), "s")
    message("  quoted_claim: ", res$quoted_claim)
    message("  explanation: ", res$explanation)
  }
}
