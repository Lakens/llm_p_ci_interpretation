# ─────────────────────────────────────────────────────────────────────────────
# Re-test sentence #3 from test_p_ci_ten_sentences.R after adding a second
# example to p_null_true's category description (the "probability the
# alternative is correct" framing). Previously mislabeled p_other; checking
# whether it now correctly returns p_null_true.
#
#   "The p-value of .03 indicates a 97% probability that the alternative
#   hypothesis is correct."
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript test_p_null_true_retest.R
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
llm_max_calls(5)
metacheck::llm_model("groq/openai/gpt-oss-20b")

sentence <- "The p-value of .03 indicates a 97% probability that the alternative hypothesis is correct."

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

one_row <- data.frame(expanded = sentence, stat_text = "p = .03",
                      paper_id = "test", stringsAsFactors = FALSE)

cat("Sentence:\n", sentence, "\n\n")
cat("Sending ONE call to Groq (gpt-oss-20b, default reasoning effort) ...\n")

t0 <- Sys.time()
res <- llm(
  text = one_row,
  system_prompt = structured_prompt,
  type = .p_ci_type_spec(),
  text_col = "expanded",
  model = llm_model(),
  params = list(seed = 8675309 + 3),
  capture_reasoning = TRUE
)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

cat("\nDone in", round(elapsed, 1), "s\n\n")
cat("misinterpreted:", res$misinterpreted, "\n")
cat("misinterpretation_type:", as.character(res$misinterpretation_type),
   "  [expected: p_null_true]\n")
cat("confidence:", res$confidence, "\n")
cat("quoted_claim:", res$quoted_claim, "\n")
cat("explanation:", res$explanation, "\n\n")
cat("reasoning trace:\n")
cat(if (".reasoning" %in% names(res) && !is.na(res$.reasoning)) res$.reasoning else "(none captured)", "\n")
