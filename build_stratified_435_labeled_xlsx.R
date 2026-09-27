# ─────────────────────────────────────────────────────────────────────────────
# Merge Claude's independent judgments (three CSVs, one per stratum, written
# directly from reading each sentence in conversation) onto the stratified
# 435-row spreadsheet built by build_stratified_435_xlsx.R, producing the
# final labeled workbook.
#
# claude_* columns are a second LLM's opinion, not ground truth -- see
# README.md.
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript build_stratified_435_labeled_xlsx.R
# ─────────────────────────────────────────────────────────────────────────────

scratch <- "C:/Users/dlakens/AppData/Local/Temp/claude/c--Users-dlakens-OneDrive---TU-Eindhoven-git-repos-metacheck-new/dbcdeb41-cd1b-4d63-9506-a36ec63bc6c2/scratchpad"
working_path <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/llm_p_ci_interpretation/_stratified_435_working.rds"
out_path     <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/llm_p_ci_interpretation/p_ci_validation_stratified_435_labeled.xlsx"

sub <- readRDS(working_path)

judg_ci      <- read.csv(file.path(scratch, "claude_judgments_ci.csv"),      stringsAsFactors = FALSE)
judg_sig     <- read.csv(file.path(scratch, "claude_judgments_sig.csv"),     stringsAsFactors = FALSE)
judg_nonsig  <- read.csv(file.path(scratch, "claude_judgments_nonsig.csv"), stringsAsFactors = FALSE)

judg <- rbind(judg_ci, judg_sig, judg_nonsig)
stopifnot(nrow(judg) == nrow(sub))
stopifnot(all(sort(judg$rowid) == sort(sub$rowid)))

judg <- judg[match(sub$rowid, judg$rowid), ]
stopifnot(all(judg$rowid == sub$rowid))

sub$claude_misinterpreted <- as.logical(judg$claude_misinterpreted)
sub$claude_category       <- ifelse(judg$claude_category == "NA", NA_character_, judg$claude_category)
sub$claude_agrees_with_model <- judg$claude_agrees_with_model
sub$claude_notes          <- judg$claude_notes

sub$claude_agrees_with_model[is.na(sub$model_misinterpreted)] <- NA
sub$rowid <- NULL

n_comparable <- sum(!is.na(sub$claude_agrees_with_model))
n_agree      <- sum(sub$claude_agrees_with_model, na.rm = TRUE)
message("Total rows: ", nrow(sub))
message("Comparable rows (model gave a non-NA judgment): ", n_comparable)
message("Overall agreement: ", n_agree, "/", n_comparable, " = ",
       round(100 * n_agree / n_comparable, 1), "%")

message("\nBy stratum:")
for (s in unique(sub$stratum)) {
  rows <- sub$stratum == s
  n_c <- sum(!is.na(sub$claude_agrees_with_model[rows]))
  n_a <- sum(sub$claude_agrees_with_model[rows], na.rm = TRUE)
  message("  ", s, ": ", n_a, "/", n_c, " = ",
         if (n_c > 0) paste0(round(100 * n_a / n_c, 1), "%") else "NA")
}

library(openxlsx)
wb <- createWorkbook()
addWorksheet(wb, "validation")
writeData(wb, "validation", sub)
freezePane(wb, "validation", firstRow = TRUE)
setColWidths(wb, "validation", cols = seq_len(ncol(sub)),
            widths = c(10, 16, 60, 14, 40, 12, 26, 50, 10, 12, 20, 30, 12, 20, 16, 40))
saveWorkbook(wb, out_path, overwrite = TRUE)

message("\nSaved: ", out_path)
