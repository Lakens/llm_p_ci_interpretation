# ─────────────────────────────────────────────────────────────────────────────
# Run stat_p_ci_interpretation (branch p-interpretation-check of metacheck-new)
# on papers in the psychsci corpus, one at a time, via TU/e's SPIKE-1 gateway
# instead of Groq (no per-call billing against a credit budget).
#
# Resume-safe: results are saved incrementally (after every paper, not just at
# the end), and a re-run skips any paper already present in the saved results
# file, so this can be stopped (Ctrl+C) any time without losing completed
# work, and picked back up later by just running it again. Set FORCE_ALL to
# TRUE to ignore this and reprocess every paper regardless (e.g. after a
# module code change).
#
# Set PAPER_LIMIT to cap how many NEW papers this run processes -- start
# small (e.g. 5 or 20) to see results and timing before doing more.
#
# Requires TU/e network access (VPN or eduroam) -- SPIKE-1 is internal and
# will 404 from outside it.
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript run_p_ci_all_papers_spike.R
# Progress and any errors print to the console as it runs; safe to Ctrl+C and
# resume later by running it again.
# ─────────────────────────────────────────────────────────────────────────────

FORCE_ALL   <- FALSE
PAPER_LIMIT <- 200L   # start small; set higher (or NULL for all remaining) once
                      # you've seen this batch's results and timing

# ── Which SPIKE-1 model to use ────────────────────────────────────────────
# Per C:/Users/dlakens/.continue/config.yaml: a single gateway, real API key
# (SPIKE_API_KEY), and "best-live" routes to whichever model the gateway
# currently has live.
SPIKE_MODEL <- "best-live"
spike_url   <- "https://spike-gateway-runai-aiteam.inference.spike.tue.nl/v1"

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

# ── LLM setup (SPIKE-1, via metacheck's vllm/ provider path) ──────────────
spike_key <- Sys.getenv("SPIKE_API_KEY")
if (!nzchar(spike_key)) stop("SPIKE_API_KEY is not set in the environment.", call. = FALSE)

options(metacheck.llm.vllm.base_url = spike_url)
Sys.setenv(VLLM_API_KEY = spike_key)

llm_use(TRUE)
llm_cache(TRUE)
llm_max_calls(100000)
metacheck::llm_model(paste0("vllm/", SPIKE_MODEL))

# ── Load the corpus ────────────────────────────────────────────────────────
papers <- readRDS("C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/papers_private/psychsci.rds")
message("Loaded ", length(papers), " papers from the psychsci corpus.")
all_ids <- names(papers) %||% vapply(papers, paper_id, character(1))

# ── Resume state ────────────────────────────────────────────────────────────
# A paper counts as "done" only if it completed with a real traffic light --
# "fail" means the LLM calls themselves errored out (e.g. SPIKE's weekly
# token budget returning HTTP 429) and must be retried, not skipped, even
# though module_run() itself returned normally (status == "ok" at the R
# level) and the paper is therefore already a key in `results`.
results_path <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/llm_p_ci_interpretation/_p_ci_all_papers_spike_result.rds"
results <- if (!isTRUE(FORCE_ALL) && file.exists(results_path)) readRDS(results_path) else list()

failed_tl_ids <- names(results)[vapply(results, function(r)
  identical(r$status, "ok") && identical(r$traffic_light, "fail"), logical(1))]
if (length(failed_tl_ids) > 0) {
  message(length(failed_tl_ids), " paper(s) previously came back traffic_light ",
         "'fail' (LLM call failure, e.g. a budget 429) -- will retry them.")
  results[failed_tl_ids] <- NULL
}

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

  # Save after EVERY paper, not just at the end, so stopping this run (Ctrl+C
  # or otherwise) never loses completed work.
  saveRDS(results, results_path)
}

status <- vapply(results, `[[`, character(1), "status")
message("\nDone: ", sum(status == "ok"), " ok, ", sum(status == "error"),
       " failed (", length(results), " of ", length(all_ids), " total papers).")

tl_v <- vapply(results, function(r) if (identical(r$status, "ok"))
  (r$traffic_light %||% NA_character_) else NA_character_, character(1))
message("Traffic lights: ", paste(sprintf("%s=%d", names(table(tl_v)), table(tl_v)), collapse = ", "))
message("Saved results to: ", results_path)
