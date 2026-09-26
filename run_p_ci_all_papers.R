# ─────────────────────────────────────────────────────────────────────────────
# Run stat_p_ci_interpretation (branch p-interpretation-check of metacheck-new)
# on EVERY paper in the psychsci corpus (~1900+ papers). This is a real, large,
# BILLED run against Groq -- do not launch without deciding to spend that, and
# consider running a smaller PAPER_LIMIT first.
#
# Resume-safe: results are saved incrementally (after every paper, not just at
# the end), and a re-run skips any paper already present in the saved results
# file, so an interrupted run just needs re-running rather than starting over.
# Set FORCE_ALL <- TRUE to ignore this and reprocess every paper regardless
# (e.g. after a module code change).
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript run_p_ci_all_papers.R
# Progress and any errors print to the console as it runs; safe to Ctrl+C and
# resume later.
# ─────────────────────────────────────────────────────────────────────────────

FORCE_ALL   <- FALSE
PAPER_LIMIT <- NULL   # set to an integer (e.g. 50) to cap how many papers this
                      # run processes, for a smaller/cheaper trial before the
                      # full corpus; NULL processes every remaining paper

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

# ── LLM setup (Groq; GROQ_API_KEY already set in this session's environment) ─
llm_use(TRUE)
llm_cache(TRUE)
llm_max_calls(100000)
metacheck::llm_model("groq/openai/gpt-oss-20b")

# ── Load the corpus ────────────────────────────────────────────────────────
papers <- readRDS("C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/papers_private/psychsci.rds")
message("Loaded ", length(papers), " papers from the psychsci corpus.")
all_ids <- names(papers) %||% vapply(papers, paper_id, character(1))

# ── Resume state ────────────────────────────────────────────────────────────
results_path <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/metacheck-testing/_p_ci_all_papers_result.rds"
results <- if (!isTRUE(FORCE_ALL) && file.exists(results_path)) readRDS(results_path) else list()

todo_ids <- setdiff(all_ids, names(results))
if (!is.null(PAPER_LIMIT)) todo_ids <- utils::head(todo_ids, PAPER_LIMIT)
message(length(names(results)), " paper(s) already done (from a previous run), ",
       length(todo_ids), " to process this run.")

# ── Process each paper, saving incrementally ──────────────────────────────
for (i in seq_along(todo_ids)) {
  pid   <- todo_ids[[i]]
  paper <- papers[[pid]]

  message("\n[", i, "/", length(todo_ids), "] ", pid)

  t0 <- Sys.time()
  res <- tryCatch({
    out <- module_run(paper, "stat_p_ci_interpretation")
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

    n_flagged <- if (!is.null(out$table$misinterpreted))
      sum(out$table$misinterpreted, na.rm = TRUE) else NA_integer_
    message("  traffic_light: ", out$traffic_light,
           " | rows: ", nrow(out$table), " | flagged: ", n_flagged,
           " | ", round(elapsed, 1), "s")

    list(paper_id = pid, status = "ok", traffic_light = out$traffic_light,
        summary_text = out$summary_text, table = out$table,
        summary_table = out$summary_table, elapsed = elapsed)
  }, error = function(e) {
    message("  ! failed: ", conditionMessage(e))
    list(paper_id = pid, status = "error", message = conditionMessage(e),
        elapsed = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  })

  results[[pid]] <- res

  # Save after EVERY paper, not just at the end, so an interrupted run (or one
  # stopped deliberately) never loses completed work.
  saveRDS(results, results_path)
}

status <- vapply(results, `[[`, character(1), "status")
message("\nDone: ", sum(status == "ok"), " ok, ", sum(status == "error"),
       " failed (", length(results), " of ", length(all_ids), " total papers).")

tl_v <- vapply(results, function(r) if (identical(r$status, "ok"))
  (r$traffic_light %||% NA_character_) else NA_character_, character(1))
message("Traffic lights: ", paste(sprintf("%s=%d", names(table(tl_v)), table(tl_v)), collapse = ", "))
message("Saved results to: ", results_path)
