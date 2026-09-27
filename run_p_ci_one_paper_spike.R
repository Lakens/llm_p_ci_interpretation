# ─────────────────────────────────────────────────────────────────────────────
# Run stat_p_ci_interpretation (branch p-interpretation-check of metacheck-new)
# on ONE paper from the psychsci corpus, using TU/e's SPIKE-1 vllm endpoints
# instead of Groq. Prints the traffic light, summary, and every flagged
# sentence with its category, confidence, and explanation.
#
# Requires TU/e network access (VPN or eduroam) -- SPIKE-1 is internal and
# will 404 from outside it.
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
# Set PAPER_ID below to a specific paper id (e.g. "0956797618796478"), or
# leave it NULL and set PAPER_INDEX to run the paper at that position in the
# corpus instead. Set SPIKE_MODEL to pick which SPIKE-1 model to use.
#   Rscript run_p_ci_one_paper_spike.R
# ─────────────────────────────────────────────────────────────────────────────

# ── Which paper to run ────────────────────────────────────────────────────
PAPER_ID    <- NULL   # e.g. "0956797618796478" -- takes priority if set
PAPER_INDEX <- 1L      # used only when PAPER_ID is NULL

# ── Which SPIKE-1 model to use ────────────────────────────────────────────
# Per C:/Users/dlakens/.continue/config.yaml, SPIKE is reached through a single
# gateway (not the per-model URLs in manuscript_processor.py), with a real API
# key (SPIKE_API_KEY) rather than a dummy bearer token, and "best-live" as the
# model name routes to whichever model the gateway currently has live.
SPIKE_MODEL <- "best-live"

spike_models <- list(
  "best-live" = list(
    url = "https://spike-gateway-runai-aiteam.inference.spike.tue.nl/v1",
    model_id = "best-live"
  )
)

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
# Uses the real SPIKE_API_KEY (already set in this session's environment),
# not a dummy token -- the gateway rejects requests without one.
model_cfg <- spike_models[[SPIKE_MODEL]]
if (is.null(model_cfg)) stop("Unknown SPIKE_MODEL '", SPIKE_MODEL, "'", call. = FALSE)

spike_key <- Sys.getenv("SPIKE_API_KEY")
if (!nzchar(spike_key)) stop("SPIKE_API_KEY is not set in the environment.", call. = FALSE)

options(metacheck.llm.vllm.base_url = model_cfg$url)
Sys.setenv(VLLM_API_KEY = spike_key)

llm_use(TRUE)
llm_cache(TRUE)
llm_max_calls(1000)
metacheck::llm_model(paste0("vllm/", model_cfg$model_id))

# ── Load the corpus and pick the paper ────────────────────────────────────
papers <- readRDS("C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/papers_private/psychsci.rds")
message("Loaded ", length(papers), " papers from the psychsci corpus.")

all_ids <- names(papers) %||% vapply(papers, paper_id, character(1))

pid <- if (!is.null(PAPER_ID)) {
  if (!PAPER_ID %in% all_ids)
    stop("PAPER_ID '", PAPER_ID, "' not found in the corpus.", call. = FALSE)
  PAPER_ID
} else {
  if (PAPER_INDEX < 1 || PAPER_INDEX > length(all_ids))
    stop("PAPER_INDEX ", PAPER_INDEX, " is out of range (corpus has ",
        length(all_ids), " papers).", call. = FALSE)
  all_ids[[PAPER_INDEX]]
}
paper <- papers[[pid]]
message("Running on paper: ", pid, " with model: vllm/", model_cfg$model_id)

# ── Run the module ─────────────────────────────────────────────────────────
t0 <- Sys.time()
out <- module_run(paper, "stat_p_ci_interpretation")
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

message("\ntraffic_light: ", out$traffic_light)
message("summary_text: ", out$summary_text)
n_flagged <- if (!is.null(out$table$misinterpreted))
  sum(out$table$misinterpreted, na.rm = TRUE) else NA_integer_
message("rows found: ", nrow(out$table), " | flagged misinterpreted: ", n_flagged,
       " | elapsed: ", round(elapsed, 1), "s")

if (!is.null(out$table) && nrow(out$table) > 0 && "misinterpreted" %in% names(out$table)) {
  flagged <- out$table[!is.na(out$table$misinterpreted) & out$table$misinterpreted, , drop = FALSE]
  if (nrow(flagged) > 0) {
    message("\nFlagged sentences:")
    for (r in seq_len(nrow(flagged))) {
      message("  - [", flagged$misinterpretation_type[r], "] (confidence: ",
              flagged$confidence[r], ")")
      message("    ", flagged$expanded[r])
      message("    why: ", flagged$explanation[r])
    }
  } else {
    message("\nNo misinterpretations flagged.")
  }
}

out_path <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/llm_p_ci_interpretation/_p_ci_one_paper_spike_result.rds"
saveRDS(list(paper_id = pid, model = SPIKE_MODEL, out = out, elapsed = elapsed), out_path)
message("\nSaved to: ", out_path)
