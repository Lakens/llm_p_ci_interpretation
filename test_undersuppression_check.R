# ─────────────────────────────────────────────────────────────────────────────
# Check whether nonsig_sample/nonsig_population's new vocabulary list catches
# genuine misinterpretations phrased in ways the earlier (thinner) category
# text missed -- "equally X" phrasing, and a regression check against
# sentences that worked in earlier tests today.
#
# Calls .p_ci_llm_judge() directly (the module's OWN judging function) rather
# than reconstructing the prompt by hand, so this test always exercises
# exactly the live prompt -- no risk of the test's copy drifting from the
# module's, which is what caused an earlier false conclusion this session.
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript test_undersuppression_check.R
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
  id = 1:6,
  expect = c(
    "FLAG: 'equally beneficial' (the real case that started this investigation, p = .18)",
    "FLAG: 'equally X' variant #2",
    "FLAG: 'did not differ' variant",
    "FLAG: nonsig_population (worked in the very first test today)",
    "FLAG: nonsig_sample (worked in the very first test today)",
    "NO FLAG: plain significant result, no claim"
  ),
  expanded = c(
    "Participants judged the target to be significantly less moral when he volunteered at the homeless shelter (M = 4.75, SE = 0.28) than when he volunteered at the coffee shop (M = 5.62, SE = 0.26), t(100) = 2.27, p = .025. In addition, they rated the agent's actions as equally beneficial when he volunteered at the homeless shelter (M = 6.33, SE = 0.24) and when he volunteered at the coffee shop (M = 5.83, SE = 0.28), p = .18.",
    "Response times were equally fast across the two conditions (M = 512ms vs M = 528ms), t(60) = 1.10, p = .28.",
    "The two groups did not differ on the outcome measure, t(38) = 0.9, p = .37.",
    "Reaction times did not differ significantly between the two conditions, t(45) = 1.20, p = .24, demonstrating that font color has no effect on processing speed.",
    "This effect did not vary by participant's sex, \u03b2 = 0.025, p = .806, semipartial r = -.02.",
    "The correlation was significant, r(88) = .34, p = .001, 95% CI [0.15, 0.51]."
  ),
  stat_text = c("p = .025; p = .18", "p = .28", "p = .37", "p = .24", "p = .806", "p = .001"),
  paper_id = "test",
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(sentences))) {
  row <- sentences[i, ]
  message("\n[", i, "/6] expect: ", row$expect)
  message("  ", substr(row$expanded, 1, 120))

  one_row <- sentences[i, c("expanded", "stat_text", "paper_id")]
  t0 <- Sys.time()
  judged <- tryCatch(
    .p_ci_llm_judge(one_row, seed = 8675309 + i),
    error = function(e) { message("  ! ERROR: ", conditionMessage(e)); NULL }
  )
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (!is.null(judged)) {
    res <- judged$table
    message("  misinterpreted: ", res$misinterpreted,
           " | type: ", as.character(res$misinterpretation_type),
           " | confidence: ", res$confidence, " | ", round(elapsed, 1), "s")
    message("  quoted_claim: ", res$quoted_claim)
    message("  explanation: ", res$explanation)
  }
}
