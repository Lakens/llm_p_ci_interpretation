# ─────────────────────────────────────────────────────────────────────────────
# Directly test whether the SAME sentence with the SAME seed produces the
# SAME judgment twice in a row via Groq (gpt-oss-20b, temperature = 0).
# 2 calls total.
# ─────────────────────────────────────────────────────────────────────────────

metacheck_new_path <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/metacheck-new"
devtools::load_all(metacheck_new_path)
source(file.path(metacheck_new_path, "inst/modules/stat_p_ci_interpretation.R"))

llm_use(TRUE)
llm_cache(FALSE)
llm_max_calls(5)
metacheck::llm_model("groq/openai/gpt-oss-20b")

sentence <- "This effect did not vary by participant's sex, \u03b2 = 0.025, p = .806, semipartial r = -.02."
one_row <- data.frame(expanded = sentence, stat_text = "p = .806", stringsAsFactors = FALSE)

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
  "specific errors, or for drawing a broader conclusion not covered by the",
  "categories above (e.g. 'this shows a strong effect', a claim about",
  "effect SIZE/IMPORTANCE rather than about what the p value or CI means).",
  "Note that treating NONSIGNIFICANCE as evidence the effect is absent",
  "(nonsig_sample/nonsig_population) is IN SCOPE and must still be flagged",
  "-- it is a specific, named category above, not an out-of-scope",
  "'dichotomous thinking' concern to be waved off. If the sentence only",
  "reports the statistic without making a claim about its meaning, treat",
  "that as NOT misinterpreted. When genuinely",
  "uncertain whether the quoted claim fits a category's exact logical",
  "structure, prefer NOT misinterpreted over forcing a near-fit label, and",
  "give a lower confidence score."
)
structured_prompt <- paste0(
  "You will see a sentence from a scientific manuscript that reports a p value or a confidence interval (CI). Judge whether the sentence's own DEFINITION OR USE of what that p value or confidence interval MEANS is technically correct, per the specific misinterpretation categories below.\n\n",
  "Categories:\n", cat_list, "\n\n",
  anti_forcing
)

run_once <- function(n) {
  res <- llm(text = one_row, system_prompt = structured_prompt, type = .p_ci_type_spec(),
            text_col = "expanded", model = llm_model(), params = list(seed = 999))
  message("Call ", n, ": misinterpreted=", res$misinterpreted,
         " type=", as.character(res$misinterpretation_type),
         " confidence=", res$confidence)
  message("  explanation: ", res$explanation)
  res
}

r1 <- run_once(1)
r2 <- run_once(2)

message("\nIdentical results: ", identical(r1$misinterpreted, r2$misinterpreted) &&
       identical(as.character(r1$misinterpretation_type), as.character(r2$misinterpretation_type)))
