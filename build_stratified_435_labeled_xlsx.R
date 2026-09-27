# ─────────────────────────────────────────────────────────────────────────────
# Build the stratified, Claude-labeled validation spreadsheet, self-contained
# and reproducible from this repo's own committed files:
#
#   _p_ci_all_papers_spike_result.rds  (the SPIKE corpus run's raw output)
#   claude_judgments.csv               (Claude's independent per-sentence
#     judgment for every row, keyed by rowid to the sample this script draws)
#
# Produces: p_ci_validation_stratified_435_labeled.xlsx
#
# Steps:
#   1. Pull every sentence-row that got a real judgment (green/red papers
#      only -- "fail" papers hold no genuine judgment, from a SPIKE weekly
#      token-budget 429; see README.md).
#   2. Split into three strata: sig (p <= .05, reported as < or =), nonsig
#      (a p value was extracted but isn't sig), and ci_only (no p value
#      extracted -- a CI-only sentence).
#   3. Draw the SAME 435-row sample the original judgments were made against
#      (fixed seed, so this is reproducible): 150 sig, 150 nonsig, and every
#      available ci_only row (135 at the time this was built -- short of a
#      150 target, since the corpus only had 135 total).
#   4. Fix a real module bug retroactively: earlier runs of
#      stat_p_ci_interpretation() sometimes returned a misinterpretation_type
#      category alongside misinterpreted == FALSE, contradicting the
#      module's own schema description ("if misinterpreted is TRUE, else
#      null") -- ellmer::type_enum() has no way to enforce that cross-field
#      constraint. This is now fixed in the module itself (see
#      metacheck-new's inst/modules/stat_p_ci_interpretation.R), but this
#      script also nulls any stray category in the raw corpus data so the
#      sheet reads as if the fix had always been in place.
#   5. Merge in Claude's independent judgment for each row (from the three
#      CSVs) and compute agreement MECHANICALLY (claude_misinterpreted ==
#      model_misinterpreted) -- never scored by hand, to avoid conflating
#      agreement on the misinterpreted flag with disagreement over a
#      category label (a mistake made and corrected earlier in this
#      project's history).
#
# claude_* columns are a second LLM's independent opinion, not ground truth
# -- see README.md.
#
# ── HOW TO USE ───────────────────────────────────────────────────────────────
#   Rscript build_stratified_435_labeled_xlsx.R
# ─────────────────────────────────────────────────────────────────────────────

results_path <- "_p_ci_all_papers_spike_result.rds"
out_path     <- "p_ci_validation_stratified_435_labeled.xlsx"

set.seed(20260926)

# ── 1-3: rebuild the same stratified sample ───────────────────────────────
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

N_SIG <- 150; N_NONSIG <- 150
N_CI <- min(150, sum(is_ci_only))

sig_idx    <- sample(which(is_sig), N_SIG)
nonsig_idx <- sample(which(is_nonsig), N_NONSIG)
ci_idx     <- which(is_ci_only)
if (length(ci_idx) > N_CI) ci_idx <- sample(ci_idx, N_CI)

sub <- rbind(
  cbind(combined[sig_idx, ],    stratum = "sig"),
  cbind(combined[nonsig_idx, ], stratum = "nonsig"),
  cbind(combined[ci_idx, ],     stratum = "ci_only")
)
row.names(sub) <- NULL
sub$rowid <- seq_len(nrow(sub))

cols <- c("rowid", "stratum", "paper_id", "expanded", "stat_text", "quoted_claim",
         "misinterpreted", "misinterpretation_type", "explanation", "confidence")
sub <- sub[, cols]
colnames(sub) <- c("rowid", "stratum", "paper_id", "sentence", "stat_text",
                   "model_quoted_claim", "model_misinterpreted", "model_category",
                   "model_explanation", "model_confidence")

# ── 4: retroactively fix the FALSE+category module bug ────────────────────
stray <- !is.na(sub$model_category) &
        (is.na(sub$model_misinterpreted) | !sub$model_misinterpreted)
message("Stray categories on FALSE/NA rows found and nulled: ", sum(stray))
sub$model_category[stray] <- NA_character_

# ── 5: merge in Claude's independent judgment ──────────────────────────────
judg <- read.csv("claude_judgments.csv", stringsAsFactors = FALSE)
judg <- judg[match(sub$rowid, judg$rowid), ]
stopifnot(all(judg$rowid == sub$rowid))

sub$claude_misinterpreted    <- as.logical(judg$claude_misinterpreted)
sub$claude_category          <- ifelse(judg$claude_category == "NA", NA_character_, judg$claude_category)
sub$claude_notes             <- judg$claude_notes
sub$claude_agrees_with_model <- sub$claude_misinterpreted == sub$model_misinterpreted
sub$rowid <- NULL

n_comparable <- sum(!is.na(sub$claude_agrees_with_model))
n_agree      <- sum(sub$claude_agrees_with_model, na.rm = TRUE)
message("\nFinal row count: ", nrow(sub))
message("By stratum: "); print(table(sub$stratum))
message("Comparable rows (model gave a non-NA judgment): ", n_comparable)
message("Overall agreement: ", n_agree, "/", n_comparable, " = ",
       round(100 * n_agree / n_comparable, 1), "%")

# ── write the workbook ─────────────────────────────────────────────────────
library(openxlsx)
wb <- createWorkbook()
addWorksheet(wb, "validation")
writeData(wb, "validation", sub)
freezePane(wb, "validation", firstRow = TRUE)
width_map <- c(
  stratum = 12, paper_id = 16, sentence = 60, stat_text = 14,
  model_quoted_claim = 40, model_misinterpreted = 12, model_category = 26,
  model_explanation = 50, model_confidence = 10, claude_misinterpreted = 12,
  claude_category = 20, claude_notes = 40, claude_agrees_with_model = 16
)
setColWidths(wb, "validation", cols = seq_len(ncol(sub)),
            widths = width_map[names(sub)])
saveWorkbook(wb, out_path, overwrite = TRUE)

message("\nSaved: ", out_path)
