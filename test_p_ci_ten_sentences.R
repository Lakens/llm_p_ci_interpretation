# ─────────────────────────────────────────────────────────────────────────────
# Ten hand-written sentences to stress-test stat_p_ci_interpretation's LLM
# judgment after the quoted_claim / anti-forcing / confidence fixes.
#
# Mix of:
#   - 6 genuine misinterpretations, one per targeted category (should flag)
#   - 4 sentences that should NOT flag: plain correct reporting, the CI-overlap
#     heuristic (again, differently phrased, to check the earlier fix
#     generalises), Murphy et al.'s own "No Misinterpretation" case (reports
#     nonsignificance without claiming absence), and an out-of-scope
#     overclaiming case (significance-as-importance -- not this module's job,
#     should not flag even though it IS a real misinterpretation of a
#     different kind)
#
# Ten separate llm() calls (not one batched call) so each sentence's result is
# clearly attributable, default reasoning effort (no llm_reasoning() change),
# capture_reasoning = TRUE for inspection. Same directly-called-llm() pattern
# as test_p_ci_single_sentence.R, for the same reason (the module itself does
# not yet pass capture_reasoning through).
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript test_p_ci_ten_sentences.R
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
llm_cache(FALSE)   # fresh calls -- avoid any stale cache entry with no .reasoning
llm_max_calls(20)
metacheck::llm_model("groq/openai/gpt-oss-20b")

sentences <- data.frame(
  id = 1:10,
  expect = c(
    "FLAG: ci_prob_of_parameter",
    "FLAG: ci_representativeness",
    "FLAG: p_null_true",
    "FLAG: p_due_to_chance",
    "FLAG: nonsig_population",
    "FLAG: p_alpha_error_of_result",
    "NO FLAG: plain correct reporting",
    "NO FLAG: CI-overlap heuristic (rephrased)",
    "NO FLAG: Murphy et al. 'No Misinterpretation' case",
    "NO FLAG: out-of-scope overclaiming (significance != importance)"
  ),
  expanded = c(
    "The 95% CI = [0.12, 0.45] means there is a 95% probability that the true effect size falls within this range.",
    "With a 95% confidence level, we can be confident our sample is representative of the broader population.",
    "The p-value of .03 indicates a 97% probability that the alternative hypothesis is correct.",
    "Given the extremely low p-value (p < .001), it is highly unlikely that this result occurred merely by chance.",
    "Reaction times did not differ significantly between the two conditions, t(45) = 1.20, p = .24, demonstrating that font color has no effect on processing speed.",
    "Because p < .05, there is less than a 5% chance that this particular finding is a false positive.",
    "The correlation was significant, r(88) = .34, p = .001, 95% CI [0.15, 0.51].",
    "Because the confidence intervals for the two groups did not overlap, we concluded the difference was statistically significant.",
    "The interaction effect was not significant, F(1, 60) = 0.89, p = .35, and no significant effect was found in this analysis.",
    "The effect was highly significant (p < .001), demonstrating a substantial and meaningful impact on employee wellbeing."
  ),
  stat_text = c("95% CI", "95% confidence level", "p = .03", "p < .001",
               "p = .24", "p < .05", "p = .001", "CI overlap", "p = .35", "p < .001"),
  paper_id = "test",
  stringsAsFactors = FALSE
)

# Same prompt the module's .p_ci_llm_judge() builds (structured_prompt), built
# here once since llm() is called directly per row for capture_reasoning.
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

results <- list()
for (i in seq_len(nrow(sentences))) {
  row <- sentences[i, ]
  message("\n[", i, "/10] expect: ", row$expect)
  message("  ", substr(row$expanded, 1, 100))

  one_row <- data.frame(expanded = row$expanded, stat_text = row$stat_text,
                        paper_id = "test", stringsAsFactors = FALSE)

  t0 <- Sys.time()
  res <- tryCatch(
    llm(
      text = one_row,
      system_prompt = structured_prompt,
      type = .p_ci_type_spec(),
      text_col = "expanded",
      model = llm_model(),
      params = list(seed = 8675309 + i),
      capture_reasoning = TRUE
    ),
    error = function(e) { message("  ! ERROR: ", conditionMessage(e)); NULL }
  )
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (!is.null(res)) {
    message("  misinterpreted: ", res$misinterpreted,
           " | type: ", as.character(res$misinterpretation_type),
           " | confidence: ", res$confidence,
           " | elapsed: ", round(elapsed, 1), "s")
    message("  quoted_claim: ", res$quoted_claim)
    message("  explanation: ", res$explanation)
  }

  results[[i]] <- list(id = row$id, expect = row$expect, sentence = row$expanded,
                       result = res, elapsed = elapsed)
}

saveRDS(results, "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/metacheck-testing/_p_ci_ten_sentences_result.rds")
message("\nSaved to: _p_ci_ten_sentences_result.rds")
