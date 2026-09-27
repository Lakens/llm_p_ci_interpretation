# ─────────────────────────────────────────────────────────────────────────────
# Build a human-codeable validation spreadsheet from the SPIKE batch results
# (_p_ci_all_papers_spike_result.rds): one row per sentence the module judged,
# with the model's own judgment alongside blank columns for a human coder to
# fill in, so sensitivity/PPV can be computed against real labels later (the
# same kind of validation stat_p_nonsig's roxygen <validation> tag reports).
#
# Only papers that got a REAL judgment (traffic_light green or red) are
# included -- "fail" papers (SPIKE weekly budget 429s) have no actual model
# judgment, just NA/error rows, and are excluded rather than coded as if they
# were real data.
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript build_validation_xlsx.R
# ─────────────────────────────────────────────────────────────────────────────

results_path   <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/llm_p_ci_interpretation/_p_ci_all_papers_spike_result.rds"
out_path       <- "C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/llm_p_ci_interpretation/p_ci_validation.xlsx"

results <- readRDS(results_path)

ok <- Filter(function(x) identical(x$status, "ok") &&
                          x$traffic_light %in% c("green", "red"), results)
message(length(ok), " of ", length(results), " paper(s) had a real judgment ",
       "(green/red); the rest (fail/na/error) are excluded.")

tables <- lapply(ok, function(x) x$table)
combined <- do.call(rbind, tables)
row.names(combined) <- NULL

cols <- c("paper_id", "expanded", "stat_text", "quoted_claim",
         "misinterpreted", "misinterpretation_type", "explanation", "confidence")
combined <- combined[, cols]
colnames(combined) <- c("paper_id", "sentence", "stat_text", "model_quoted_claim",
                        "model_misinterpreted", "model_category", "model_explanation",
                        "model_confidence")

# blank columns for a human coder to fill in
combined$human_misinterpreted <- NA
combined$human_category <- NA_character_
combined$human_notes <- NA_character_

message("Total rows: ", nrow(combined))

library(openxlsx)
wb <- createWorkbook()
addWorksheet(wb, "validation")
writeData(wb, "validation", combined)
freezePane(wb, "validation", firstRow = TRUE)
setColWidths(wb, "validation", cols = seq_len(ncol(combined)),
            widths = c(16, 60, 14, 40, 12, 26, 50, 10, 12, 20, 30))
saveWorkbook(wb, out_path, overwrite = TRUE)

message("Saved: ", out_path)
message("Rows: ", nrow(combined), " | Columns: ", ncol(combined))
