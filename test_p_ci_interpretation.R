# ─────────────────────────────────────────────────────────────────────────────
# Try out the new stat_p_ci_interpretation module (branch p-interpretation-check
# of metacheck-new) against a handful of real Psych Science corpus papers.
#
# This is a quick look, not a build: it does NOT write manifests, does NOT
# touch _tables/, and does NOT persist anything run_psych_science.R or
# test_reproducibility_psych_science.R rely on. It just loads the package from
# source, picks a random sample of papers from the corpus, runs the module
# (with the LLM turned ON -- the whole point of this module is the LLM
# judgment step, so llm_use(FALSE) would only exercise the list-only
# fallback), and prints each paper's traffic light / summary / flagged rows so
# the module's behaviour can be eyeballed against real text.
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript test_p_ci_interpretation.R
# Re-running draws a NEW random sample each time (see SEED below to fix it).
# ─────────────────────────────────────────────────────────────────────────────

metacheck_new_path <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/metacheck-new"

current_branch <- system2("git", c("-C", shQuote(metacheck_new_path),
                                   "branch", "--show-current"),
                          stdout = TRUE)
if (!identical(current_branch, "p-interpretation-check")) {
  stop("metacheck-new is on branch '", current_branch, "', not ",
       "'p-interpretation-check' (stat_p_ci_interpretation only exists ",
       "there). Check out that branch first:\n",
       "  git -C \"", metacheck_new_path, "\" checkout p-interpretation-check",
       call. = FALSE)
}

devtools::load_all(metacheck_new_path)

# ── LLM setup ──────────────────────────────────────────────────────────────
# Groq (GROQ_API_KEY already set in this session's environment), matching the
# provider run_psych_science.R names in its own commented-out model options.
# Caching is on so a re-run over the same papers does not re-bill identical
# (temperature-0) calls.
llm_use(TRUE)
llm_cache(TRUE)
llm_max_calls(1000)
metacheck::llm_model("groq/openai/gpt-oss-20b")

# ── Load the corpus and draw a random sample ──────────────────────────────
papers <- readRDS("C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/papers_private/psychsci.rds")
message("Loaded ", length(papers), " papers from the psychsci corpus.")

all_ids <- names(papers) %||% vapply(papers, paper_id, character(1))

N_PAPERS <- 10
SEED <- NULL   # set to an integer to reproduce the same sample across runs
if (!is.null(SEED)) set.seed(SEED)
sel_ids <- sample(all_ids, min(N_PAPERS, length(all_ids)))
message("Randomly selected ", length(sel_ids), " paper(s): ",
        paste(sel_ids, collapse = ", "))

# ── Run the module on each selected paper ─────────────────────────────────
results <- list()
for (i in seq_along(sel_ids)) {
  pid   <- sel_ids[[i]]
  paper <- papers[[pid]]

  message("\n[", i, "/", length(sel_ids), "] ", pid)

  t0 <- Sys.time()
  res <- tryCatch({
    out <- module_run(paper, "stat_p_ci_interpretation")
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

    message("  traffic_light: ", out$traffic_light)
    message("  summary_text: ", out$summary_text)
    n_flagged <- if (!is.null(out$table$misinterpreted))
      sum(out$table$misinterpreted, na.rm = TRUE) else NA_integer_
    message("  rows found: ", nrow(out$table), " | flagged misinterpreted: ", n_flagged,
            " | elapsed: ", round(elapsed, 1), "s")

    if (!is.null(out$table) && nrow(out$table) > 0 &&
        "misinterpreted" %in% names(out$table)) {
      flagged <- out$table[!is.na(out$table$misinterpreted) & out$table$misinterpreted, , drop = FALSE]
      if (nrow(flagged) > 0) {
        for (r in seq_len(nrow(flagged))) {
          message("    - [", flagged$misinterpretation_type[r], "] ",
                  substr(flagged$expanded[r], 1, 150))
          message("      why: ", flagged$explanation[r])
        }
      }
    }

    list(paper_id = pid, status = "ok", traffic_light = out$traffic_light,
        summary_text = out$summary_text, table = out$table,
        summary_table = out$summary_table, elapsed = elapsed)
  }, error = function(e) {
    message("  ! failed: ", conditionMessage(e))
    list(paper_id = pid, status = "error", message = conditionMessage(e),
        elapsed = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  })

  results[[pid]] <- res
}

# ── Summary across the sample ─────────────────────────────────────────────
status <- vapply(results, `[[`, character(1), "status")
message("\nDone: ", sum(status == "ok"), " ok, ", sum(status == "error"),
       " failed (", length(results), " total).")

tl_v <- vapply(results, function(r) if (identical(r$status, "ok"))
  (r$traffic_light %||% NA_character_) else NA_character_, character(1))
message("Traffic lights: ", paste(sprintf("%s=%d", names(table(tl_v)), table(tl_v)), collapse = ", "))

out_path <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/metacheck-testing/_p_ci_interpretation_test_results.rds"
saveRDS(results, out_path)
message("Saved results to: ", out_path)
