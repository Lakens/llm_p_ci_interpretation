# ─────────────────────────────────────────────────────────────────────────────
# Single-sentence smoke test of stat_p_ci_interpretation's .p_ci_llm_judge()
# after the quoted_claim / anti-forcing / confidence fixes, using the EXACT
# sentence that produced a false positive in the first full-corpus test run:
#
#   "Using these aIATs as a baseline, results still showed that suppressing
#   memories led to significantly reduced D scores (the nonoverlapping 95%
#   CIs indicate significant differences)present experiment: M = 0.13, 95%
#   CI = [-0.03, 0.29]; Hu et al. (2012, N = 64): M = 0.49, 95% CI = [0.40,
#   0.58]; Agosta and Sartori (2013; N = 412): M = 0.58, 95% CI = [0.41,
#   0.73]."
#
# Previously flagged ci_confidence_in_realized_interval -- a false positive,
# since "nonoverlapping CIs indicate a significant difference" is a
# directionally CORRECT informal heuristic, not a misinterpretation. The goal
# here is just to see whether the fixed prompt/schema gets this one sentence
# right, with the actual reasoning trace captured for inspection.
#
# ONE LLM call, default reasoning effort (no llm_reasoning() override),
# capture_reasoning = TRUE. A background wall-clock cap is enforced from
# the calling side (see the accompanying PowerShell invocation) rather than
# relying on any timeout inside llm() itself, since none exists yet on the
# Groq path.
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript test_p_ci_single_sentence.R
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
llm_cache(FALSE)   # force a fresh call -- this exact sentence's cache key
                   # (if any) predates capture_reasoning and would return a
                   # cached df with no .reasoning column otherwise
llm_max_calls(5)
metacheck::llm_model("groq/openai/gpt-oss-20b")

sentence <- "Using these aIATs as a baseline, results still showed that suppressing memories led to significantly reduced D scores (the nonoverlapping 95% CIs indicate significant differences)present experiment: M = 0.13, 95% CI = [-0.03, 0.29]; Hu et al. (2012, N = 64): M = 0.49, 95% CI = [0.40, 0.58]; Agosta and Sartori (2013; N = 412): M = 0.58, 95% CI = [0.41, 0.73]."

stats_found <- data.frame(
  expanded  = sentence,
  stat_text = "95% CI",
  paper_id  = "test",
  stringsAsFactors = FALSE
)

cat("Sentence:\n", sentence, "\n\n")
cat("Sending ONE call to Groq (gpt-oss-20b, default reasoning effort) ...\n")

# .p_ci_llm_judge() itself does not (yet) pass capture_reasoning through to
# llm() -- that is a separate module-design decision (always capturing it
# has cache/output-shape implications for every caller, not just this
# diagnostic), so this test calls llm() directly with the SAME prompt/type
# the module's own structured_prompt/.p_ci_type_spec() build, just adding
# capture_reasoning = TRUE, rather than editing the module for a one-off check.
structured_prompt <- {
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
  paste0(
    "You will see a sentence from a scientific manuscript that reports a p value or a confidence interval (CI). Judge whether the sentence's own DEFINITION OR USE of what that p value or confidence interval MEANS is technically correct, per the specific misinterpretation categories below (from Bergwerff, Corten, & van Batenburg-Eddes's compendium of real misinterpretations found in technical guidance documents, grounded in Morey et al. 2016's correct definition of a confidence interval).\n\n",
    "Categories:\n", cat_list, "\n\n",
    anti_forcing
  )
}

t0 <- Sys.time()
judged <- llm(
  text = stats_found,
  system_prompt = structured_prompt,
  type = .p_ci_type_spec(),
  text_col = "expanded",
  model = llm_model(),
  params = list(seed = 8675309),
  capture_reasoning = TRUE
)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

cat("\nDone in", round(elapsed, 1), "s\n\n")
cat("misinterpreted:", judged$misinterpreted, "\n")
cat("misinterpretation_type:", as.character(judged$misinterpretation_type), "\n")
cat("confidence:", judged$confidence, "\n")
cat("quoted_claim:", judged$quoted_claim, "\n")
cat("explanation:", judged$explanation, "\n\n")
cat("reasoning trace:\n")
cat(if (".reasoning" %in% names(judged) && !is.na(judged$.reasoning)) judged$.reasoning else "(none captured)", "\n")

saveRDS(judged, "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/metacheck-testing/_p_ci_single_sentence_result.rds")
cat("\nSaved to: _p_ci_single_sentence_result.rds\n")
