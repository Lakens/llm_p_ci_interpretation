# ─────────────────────────────────────────────────────────────────────────────
# Build a stratified validation spreadsheet: 150 significant-p, 150
# nonsignificant-p, and every available CI-only sentence (135 -- the corpus's
# entire CI-only pool at the time of this run, short of the 150 target) from
# the SPIKE batch results (_p_ci_all_papers_spike_result.rds). 435 rows total.
#
# "Significant": p_value <= .05 with p_comp in ("<","="). "Nonsignificant":
# a p_value was extracted but does not meet that condition. "CI-only": no
# p_value was extracted at all (the row's stat_text is a CI, not a p-value).
#
# Reuses the existing random subset's seed and logic style
# (build_validation_xlsx.R, build_claude_evaluation_xlsx.R) for consistency.
# Every row gets a "stratum" label (sig / nonsig / ci_only) column.
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript build_stratified_435_xlsx.R
# ─────────────────────────────────────────────────────────────────────────────

results_path <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/llm_p_ci_interpretation/_p_ci_all_papers_spike_result.rds"
out_path     <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/llm_p_ci_interpretation/p_ci_validation_stratified_435.xlsx"

set.seed(20260926)

results <- readRDS(results_path)
ok <- Filter(function(x) identical(x$status, "ok") &&
                          x$traffic_light %in% c("green", "red"), results)
message(length(ok), " of ", length(results), " paper(s) had a real judgment (green/red).")

tables <- lapply(ok, function(x) x$table)
combined <- do.call(rbind, tables)
row.names(combined) <- NULL
message("Total sentence-rows available: ", nrow(combined))

is_sig <- !is.na(combined$p_value) & combined$p_value <= 0.05 &
         !is.na(combined$p_comp) & combined$p_comp %in% c("<", "=")
is_nonsig <- !is.na(combined$p_value) & !is_sig
is_ci_only <- is.na(combined$p_value)

stopifnot(sum(is_sig) + sum(is_nonsig) + sum(is_ci_only) == nrow(combined))

message("Pool sizes -- sig: ", sum(is_sig), " | nonsig: ", sum(is_nonsig),
       " | ci_only: ", sum(is_ci_only))

N_SIG    <- 150
N_NONSIG <- 150
N_CI     <- min(150, sum(is_ci_only))   # take every available CI-only row if fewer than 150

sig_idx    <- sample(which(is_sig), N_SIG)
nonsig_idx <- sample(which(is_nonsig), N_NONSIG)
ci_idx     <- which(is_ci_only)   # use ALL of them, no further sampling needed since N_CI == pool size
if (length(ci_idx) > N_CI) ci_idx <- sample(ci_idx, N_CI)

if (length(ci_idx) < 150) {
  message("NOTE: only ", length(ci_idx), " CI-only sentences exist in the corpus so far ",
         "(short of the 150 target) -- using all of them. Total will be ",
         N_SIG + N_NONSIG + length(ci_idx), " rows, not 450.")
}

sub <- rbind(
  cbind(combined[sig_idx, ],    stratum = "sig"),
  cbind(combined[nonsig_idx, ], stratum = "nonsig"),
  cbind(combined[ci_idx, ],     stratum = "ci_only")
)
row.names(sub) <- NULL

cols <- c("stratum", "paper_id", "expanded", "stat_text", "quoted_claim",
         "misinterpreted", "misinterpretation_type", "explanation", "confidence")
sub <- sub[, cols]
colnames(sub) <- c("stratum", "paper_id", "sentence", "stat_text", "model_quoted_claim",
                   "model_misinterpreted", "model_category", "model_explanation",
                   "model_confidence")

sub$human_misinterpreted <- NA
sub$human_category <- NA_character_
sub$human_notes <- NA_character_

message("\nFinal row count: ", nrow(sub))
message("By stratum: "); print(table(sub$stratum))

library(openxlsx)
wb <- createWorkbook()
addWorksheet(wb, "validation")
writeData(wb, "validation", sub)
freezePane(wb, "validation", firstRow = TRUE)
setColWidths(wb, "validation", cols = seq_len(ncol(sub)),
            widths = c(10, 16, 60, 14, 40, 12, 26, 50, 10, 12, 20, 30))
saveWorkbook(wb, out_path, overwrite = TRUE)

message("\nSaved: ", out_path)
