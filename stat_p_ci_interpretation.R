#' P-Value and Confidence Interval Interpretation Check
#'
#' @description
#' Uses a large language model (LLM) to check whether sentences that interpret a reported *p* value or confidence interval define or use that statistic correctly. Covers two distinct kinds of misinterpretation: (1) specific, well-documented technical errors in what a *p* value or confidence interval means.
#'
#' @details
#' The module first uses [extract_p_values()] and a confidence-interval pattern to find every sentence that reports a *p* value or a confidence interval, then expands each match to its full sentence. When `llm_use()` is enabled, each sentence is sent to an LLM in a single call, which judges whether the sentence's own claim about what that *p* value or confidence interval means (or implies about the effect's existence, for a nonsignificant result) is technically correct, and if not, classifies it into one of the categories below.
#'
#' - **ci_prob_of_parameter**: treating the confidence level as the probability that the true (fixed) population parameter lies within the interval.
#' - **ci_confidence_in_realized_interval**: treating the confidence level as applying to this one already-computed interval, rather than to the procedure that generated it.
#' - **ci_property_of_sample**: treating the confidence interval as describing a property of the sample itself (e.g. its variability), rather than an estimate of a population parameter.
#' - **ci_vague**: describing a confidence interval in a way that is vague or incomplete rather than technically wrong (e.g. omitting the "repeated sampling" procedure the confidence level actually refers to).
#' - **p_null_true**: treating the *p* value as the probability that the null hypothesis is true (including the complementary phrasing "1 - p is the probability the alternative hypothesis is correct", the same claim from the other side).
#' - **p_due_to_chance**: treating the *p* value as the probability that the observed result occurred "by chance" or is a "coincidence".
#' - **p_data_given_null_incomplete**: defining the *p* value as the probability of the observed data given the null hypothesis, omitting that it is the probability of the observed data *or more extreme* data.
#' - **p_alpha_error_of_result**: treating alpha (or the *p* value) as the probability that this specific significant finding is itself wrong or a false positive, rather than the long-run Type I error rate of the testing procedure.
#' - **nonsig_sample**: treating a nonsignificant *p* value as showing the effect is absent, phrased about the sample tested (e.g. past-tense "the groups did not differ").
#' - **nonsig_population**: treating a nonsignificant *p* value as showing the effect is absent, phrased about (or generalised to) the population (e.g. present-tense "men and women do not differ").
#' - **p_other**: another incorrect definition or use of the *p* value not covered above.
#'
#' This module does not evaluate whether the underlying statistical test itself was appropriate, whether a reported number is correct, or whether a SIGNIFICANT result's importance/effect size is overclaimed — only whether the sentence's own definition or use of what the *p* value or confidence interval means is technically correct, including whether nonsignificance is incorrectly read as proof of no effect.
#'
#' Without an LLM (`llm_use(FALSE)`), the module only lists the sentences that contain a *p* value or confidence interval, without judging their interpretation, since there is no reliable regex-only way to detect a misinterpretation.
#'
#' If you want to help improve the module, reach out to the Metacheck development team.
#'
#' @keywords results
#'
#' @author Daniel Lakens (\email{D.Lakens@tue.nl})
#'
#' @references
#' Morey, R. D., Hoekstra, R., Rouder, J. N., Lee, M. D., & Wagenmakers, E.-J. (2016). The fallacy of placing confidence in confidence intervals. Psychonomic Bulletin & Review, 23(1), 103–123. https://doi.org/10.3758/s13423-015-0947-8
#'
#' Murphy, S. L., Merz, R., Reimann, L.-E., & Fernández, A. (2025). Nonsignificance misinterpreted as an effect's absence in psychology: Prevalence and temporal analyses. Royal Society Open Science, 12(3), 242167. https://doi.org/10.1098/rsos.242167
#'
#' Greenland, S., Senn, S. J., Rothman, K. J., Carlin, J. B., Poole, C., Goodman, S. N., & Altman, D. G. (2016). Statistical tests, P values, confidence intervals, and power: A guide to misinterpretations. European Journal of Epidemiology, 31(4), 337–350. https://doi.org/10.1007/s10654-016-0149-3
#'
#' @import dplyr
#'
#' @param paper a paper object or paperlist object
#' @param seed a seed for the LLM
#'
#' @returns a list
stat_p_ci_interpretation <- function(paper, seed = 8675309) {
  # find p-value and CI sentences ----
  p <- extract_p_values(paper)
  p$stat_type <- "p_value"
  p$stat_text <- p$text

  ci_pattern <- paste0(
    "\\b\\d{1,3}\\s*%\\s*(CI|confidence interval)", # "95% CI" / "95% confidence interval"
    "|CI\\s*(_?\\d{1,3})?\\s*[:=]?\\s*\\[\\s*-?\\d", # "CI = [...]" / "CI_95 [..."
    "|\\[\\s*-?\\d+\\.?\\d*\\s*,\\s*-?\\d+\\.?\\d*\\s*\\]" # a bracketed interval "[0.12, 0.98]"
  )
  ci <- text_search(paper, ci_pattern, return = "match", perl = TRUE)
  ci$stat_type <- "confidence_interval"
  ci$stat_text <- ci$text

  # Combine on shared columns only (extract_p_values() adds p_comp/p_value
  # that a CI match never has, and vice versa is not applicable here since CI
  # matches carry no extra columns) -- dplyr::bind_rows() fills the p-only
  # columns with NA for CI rows automatically.
  stats_found <- dplyr::bind_rows(p, ci)

  # Expand each match to its sentence PLUS the one immediately following it.
  # The interpretation of a statistic is very often not in the same sentence
  # that reports it at all -- "t(45) = 1.2, p = .24. This suggests the
  # intervention has no measurable impact." -- so a plus = 0 (same-sentence-
  # only) window misses the actual interpretive claim entirely; plus = 1
  # catches the common "statistic sentence, then interpretive sentence right
  # after" pattern without pulling in a whole paragraph's unrelated content.
  stats_found <- expand_text(stats_found, paper, expand_to = c("sentence"), plus = 1)

  # A single ORIGINAL sentence reporting several statistics (common: "t(28) =
  # 2.40, p = .02, 95% CI [0.10, 0.90]") produces one row per match here, all
  # sharing the same text_id (the match's own un-expanded sentence position) --
  # grouping on text_id, not on `expanded`, is required now that the window
  # extends past the matched sentence: two DIFFERENT original sentences can
  # otherwise land on overlapping/adjacent expanded windows and would be
  # wrongly merged by grouping on `expanded` text alone. Every matched
  # statistic in the group is combined into ONE stat_text (so the report shows
  # everything the judgment actually covers, not just the first match), and
  # the group is judged/reported once via its (first, arbitrary but
  # consistent) row's `expanded` window.
  stats_found <- stats_found |>
    dplyr::mutate(
      stat_text = paste(unique(stat_text), collapse = "; "),
      .by = dplyr::any_of(c("paper_id", "section_id", "paragraph_id", "text_id"))
    )
  stats_found <- stats_found[!duplicated(stats_found[c("paper_id", "section_id",
                                                        "paragraph_id", "text_id")]), ,
                            drop = FALSE]

  llm_failed <- FALSE
  # Upfront check against the CURRENT llm_max_calls() cap: one distinct
  # sentence needs one LLM call (llm() calls once per unique `expanded`
  # value, and stats_found is already deduplicated to one row per matched
  # sentence -- see the grouping above), so nrow(stats_found) is the exact
  # call count this run needs, never an underestimate. A statistics-heavy
  # paper can easily need more than the package default of 30 -- surface a
  # clear, specific message (with the exact command to raise it) here,
  # before llm()'s own generic error aborts the module run without any
  # paper-specific context (which module, which paper, how many sentences).
  n_needed <- nrow(stats_found)
  n_cap <- llm_max_calls()
  if (n_needed > n_cap && llm_use()) {
    stop(sprintf(
      paste0("stat_p_ci_interpretation needs %d LLM call%s for this paper's ",
             "%d p-value/CI sentence%s, but llm_max_calls() is set to %d. ",
             "Run llm_max_calls(%d) (or higher) before this module to allow it."),
      n_needed, plural(n_needed), n_needed, plural(n_needed), n_cap, n_needed
    ), call. = FALSE)
  }

  if (nrow(stats_found) > 0 && llm_use()) {
    ## LLM interpretation check ----
    judged <- .p_ci_llm_judge(stats_found, seed)
    llm_model_used <- judged$model
    table <- judged$table
    llm_failed <- isTRUE(judged$failed)

    report_text <- sprintf(
      "We used the LLM model '%s' to check whether %d sentence%s interpreting a reported *p* value or confidence interval did so correctly.",
      llm_model_used, nrow(stats_found), plural(nrow(stats_found))
    )
    if (!judged$structured) {
      report_text <- c(report_text,
        "(The provider does not support structured outputs for this schema; used prompt-based extraction instead.)")
    }
  } else if (nrow(stats_found) > 0) {
    ## no LLM: list only ----
    table <- stats_found
    table$misinterpreted <- NA
    table$misinterpretation_type <- NA_character_
    table$explanation <- NA_character_
    report_text <- "You chose to not use an LLM to assess whether these interpretations are correct, so please check each sentence below manually."
  } else {
    table <- stats_found
    table$misinterpreted <- logical(0)
    table$misinterpretation_type <- character(0)
    table$explanation <- character(0)
  }

  # guidance ----
  greenland2016 <- bibentry(
    bibtype = "Article",
    title = "Statistical tests, P values, confidence intervals, and power: A guide to misinterpretations",
    author = c(
      person("Sander", "Greenland"),
      person("Stephen J.", "Senn"),
      person("Kenneth J.", "Rothman"),
      person("John B.", "Carlin"),
      person("Charles", "Poole"),
      person("Steven N.", "Goodman"),
      person("Douglas G.", "Altman")
    ),
    journal = "European Journal of Epidemiology",
    year = 2016,
    volume = 31,
    number = 4,
    pages = "337--350",
    doi = "10.1007/s10654-016-0149-3"
  )

  morey2016 <- bibentry(
    bibtype = "Article",
    title = "The fallacy of placing confidence in confidence intervals",
    author = c(
      person("Richard D.", "Morey"),
      person("Rink", "Hoekstra"),
      person("Jeffrey N.", "Rouder"),
      person("Michael D.", "Lee"),
      person("Eric-Jan", "Wagenmakers")
    ),
    journal = "Psychonomic Bulletin & Review",
    year = 2016,
    volume = 23,
    number = 1,
    pages = "103--123",
    doi = "10.3758/s13423-015-0947-8"
  )

  murphy2025 <- bibentry(
    bibtype = "Article",
    title = "Nonsignificance misinterpreted as an effect's absence in psychology: Prevalence and temporal analyses",
    author = c(
      person("Stephen L.", "Murphy"),
      person("Raphael", "Merz"),
      person("Linda-Elisabeth", "Reimann"),
      person("Aurelio", "Fernández")
    ),
    journal = "Royal Society Open Science",
    year = 2025,
    volume = 12,
    number = 3,
    pages = "242167",
    doi = "10.1098/rsos.242167"
  )

  guidance <- c(
    "For a comprehensive guide to common misinterpretations of p values, confidence intervals, and statistical power, see:",
    format_ref(greenland2016),
    "For the only fully correct definition of a confidence interval, and why the common alternatives above are incorrect, see:",
    format_ref(morey2016),
    "For evidence that 76-85% of psychology articles that discuss a nonsignificant finding misinterpret it as showing the effect is absent, see:",
    format_ref(murphy2025)
  )

  # summary_table ----
  # `misinterpreted` is NA (not FALSE) whenever no LLM judgment was made (no
  # LLM used, or this row's own extraction failed) -- na.rm = TRUE counts only
  # a CONFIRMED misinterpretation, never an unchecked row.
  summary_table <- dplyr::summarise(table,
    n_p_ci_statements = dplyr::n(),
    n_misinterpreted = sum(misinterpreted, na.rm = TRUE),
    .by = paper_id
  )

  # traffic_light ----
  if (nrow(stats_found) == 0) {
    tl <- "na"
  } else if (!llm_use()) {
    tl <- "yellow" # listed but not checked -- always needs a manual look
  } else if (llm_failed) {
    tl <- "fail"
  } else if (sum(table$misinterpreted, na.rm = TRUE) > 0) {
    tl <- "red"
  } else {
    tl <- "green"
  }

  # summary_text and report ----
  if (nrow(stats_found) == 0) {
    summary_text <- "No sentences interpreting a *p* value or confidence interval were detected."
    report <- summary_text
  } else if (tl == "fail") {
    summary_text <- "The LLM check for p-value/CI interpretation failed to run; no results could be extracted. This is not the same as finding no misinterpretations -- please check manually or re-run the check."
    report <- c(summary_text, collapse_section(guidance))
  } else {
    n_mis <- sum(table$misinterpreted, na.rm = TRUE)
    summary_text <- if (!llm_use()) {
      sprintf(
        "We found %d sentence%s interpreting a *p* value or confidence interval; interpretation was not checked (no LLM used).",
        nrow(stats_found), plural(nrow(stats_found))
      )
    } else if (n_mis == 0) {
      sprintf(
        "We found %d sentence%s interpreting a *p* value or confidence interval, and none appeared to be misinterpreted.",
        nrow(stats_found), plural(nrow(stats_found))
      )
    } else {
      sprintf(
        "We found %d sentence%s interpreting a *p* value or confidence interval, of which %d may be misinterpreted.",
        nrow(stats_found), plural(nrow(stats_found)), n_mis
      )
    }

    # Every judged sentence carries an explanation, not just the flagged ones
    # (see .p_ci_llm_judge()'s type spec) -- a correctly-worded sentence's own
    # "why this is fine" is exactly what lets a reader verify the green
    # traffic light rather than take it on faith, so show every judged row
    # here, not only the misinterpreted ones. Flagged rows are still sorted
    # first (then by confidence within each group) so the reader sees the
    # important cases before the routine ones.
    show_table <- table
    if (!is.null(show_table$misinterpreted)) {
      mis_rank <- ifelse(is.na(show_table$misinterpreted), 0, show_table$misinterpreted)
      conf_rank <- if ("confidence" %in% names(show_table)) show_table$confidence else rep(0, nrow(show_table))
      conf_rank[is.na(conf_rank)] <- 0
      show_table <- show_table[order(-mis_rank, -conf_rank), , drop = FALSE]
    }

    # confidence is used above to RANK rows, but is intentionally not shown in
    # the report table -- kept internal (still present in the returned
    # `table` object for anyone inspecting the module's raw output directly).
    show_cols <- intersect(c("stat_text", "expanded", "misinterpreted",
                             "misinterpretation_type", "explanation"),
                           names(show_table))
    show_report_table <- show_table[, show_cols, drop = FALSE]
    if ("misinterpreted" %in% show_cols) {
      # Colour the TRUE/FALSE value itself so it reads at a glance -- red for
      # a flagged misinterpretation, green for a sentence judged correct.
      # Matches ref_accuracy.R's own red (#c00) convention elsewhere in this
      # package; escape = FALSE is scroll_table()'s own default, which is
      # what lets this raw HTML render instead of showing as literal text.
      mis <- show_report_table$misinterpreted
      show_report_table$misinterpreted <- dplyr::case_when(
        is.na(mis) ~ NA_character_,
        mis ~ "<span style=\"color:#c00\">misinterpreted</span>",
        TRUE ~ "<span style=\"color:#080\">correctly interpreted</span>"
      )
    }
    colnames(show_report_table) <- c("Statistic", "Sentence", "Misinterpreted", "Type",
                                     "Explanation")[seq_along(show_cols)]

    report <- c(
      report_text,
      if (nrow(show_report_table) > 0)
        scroll_table(show_report_table, colwidths = c(.1, .45, .15, .1, .2), maxrows = 10),
      collapse_section(guidance)
    )
  }

  # return a list ----
  list(
    table = table,
    summary_table = summary_table,
    na_replace = c(n_p_ci_statements = 0, n_misinterpreted = 0),
    traffic_light = tl,
    summary_text = summary_text,
    report = report
  )
}

# LLM interpretation judgment ----

.p_ci_categories <- function() {
  c(
    ci_prob_of_parameter = "Treats the confidence level as the probability that the TRUE (fixed) population parameter lies within the realised interval, stated as a DEFINITIONAL claim about what the CI itself MEANS -- signalled by phrasing like 'X% CI MEANS there is an X% chance...' or 'X% CI, i.e. an X% chance...', where the claim explains/defines the interval rather than reasoning onward FROM it. E.g. 'the 95% CI = [0.12, 0.45] MEANS there is a 95% probability that the true effect size falls within this range' (still this category even though it names the interval's own bounds -- 'CI MEANS...' is definitional phrasing, not an inference drawn from a separately-stated result). WRONG because a frequentist confidence interval cannot assign a probability to a fixed parameter -- only to the PROCEDURE across repeated sampling. Compare ci_confidence_in_realized_interval, the same underlying error but signalled by INFERENTIAL phrasing ('therefore'/'so'/'thus') drawing a conclusion from an already-stated result, not a 'CI means...' definition.",
    ci_confidence_in_realized_interval = "Treats the confidence level as attaching to THIS ONE already-computed interval specifically, stated as an INFERENCE drawn FROM an already-reported result rather than as a definition of what a CI means -- signalled by phrasing like '...[result stated]; THEREFORE/SO/THUS there is an X% chance/we can be X% confident...' (e.g. 'we can be 95% confident that this interval contains the true value'; or 'the 95% CI was [1.2, 3.8]; THERE IS THEREFORE a 95% chance the true mean lies between 1.2 and 3.8'). WRONG because the confidence level describes the long-run behaviour of the procedure across repeated samples, not a probability statement about any single realised interval. DISAMBIGUATION from ci_prob_of_parameter (the two are the SAME underlying error; the wording pattern -- NOT whether numeric bounds are present, both categories often include them -- decides which applies): 'CI MEANS X% chance...' (definitional) -> ci_prob_of_parameter; '[a result]; THEREFORE/SO X% chance/confident...' (inferential, drawing a conclusion from a separately-reported finding) -> ci_confidence_in_realized_interval; if genuinely indistinguishable, default to ci_prob_of_parameter as the more general category. NOT a misinterpretation, by contrast: a sentence that only reports the interval itself with no probability/confidence claim about it at all (e.g. 'the 95% CI was [1.2, 3.8]' alone, or '... M = 0.49, 95% CI [0.40, 0.58]' as part of listing results) -- reporting the numbers is not interpreting them.",
    ci_representativeness = "Treats the confidence level as measuring how REPRESENTATIVE the sample is of the population (e.g. 'a 95% confidence level means there is a 95% chance the sample is representative'). WRONG because the confidence level says nothing about sample representativeness.",
    ci_property_of_sample = "Treats the confidence interval as describing a property of the SAMPLE itself (e.g. its variability), rather than an inference about the population parameter -- e.g. 'the narrow 95% CI shows the sample had low variability'.",
    ci_vague = "Defines or describes the confidence interval in a way that is vague or incomplete -- it does not clearly state that the confidence level refers to the REPEATED-SAMPLING PROCEDURE that generated the interval, for all possible values of the parameter -- e.g. 'a confidence interval gives a plausible range for the parameter' (never mentions the repeated-sampling procedure at all).",
    p_null_true = "Treats the p value as the probability that the NULL HYPOTHESIS ITSELF is true (e.g. 'p = .03 means there is only a 3% chance the null hypothesis is correct'). The SAME error is also phrased the other way round, as a probability that the ALTERNATIVE hypothesis is correct instead (e.g. 'a p-value of .03 indicates a 97% probability that the alternative hypothesis is correct') -- both are p_null_true, since '(100 - p*100)% chance the alternative is right' and 'p*100% chance the null is right' assert the identical (wrong) claim from opposite sides of the same complementary probability.",
    p_due_to_chance = "Treats the p value as the probability that the observed result occurred BY CHANCE or is a mere coincidence (e.g. 'such a small p-value strongly suggests the observed correlation is not a coincidence'). WRONG because the p value already CONDITIONS ON the null hypothesis being true; it cannot separately quantify the probability that chance alone produced the result.",
    p_data_given_null_incomplete = "Defines the p value as simply the probability of the observed data given the null hypothesis, OMITTING that it is the probability of the observed data OR MORE EXTREME data. This drops the 'or more extreme' component that makes the definition technically complete.",
    p_alpha_error_of_result = "Treats alpha (or the p value) as the probability that THIS SPECIFIC significant finding is itself wrong/a false positive (e.g. 'p < .05 means there is less than a 5% chance this result is a false positive', or 'we can be 95% confident this specific effect is real'). WRONG because alpha is the long-run Type I error RATE of the testing PROCEDURE under the null hypothesis, not a probability that any one particular already-obtained result is incorrect -- the same procedure-vs-single-instance confusion as ci_confidence_in_realized_interval, applied to significance rather than a confidence interval.",
    nonsig_sample = "The underlying claim (see nonsig_population for the full logical-error statement, phrasing list, and in/out-of-scope boundary -- identical here except for WHO the claim is about): the SAME error, but phrased about the SAMPLE tested rather than generalised to the population -- typically past-tense language ('the groups did not differ', 'conditions A and B were indifferent') or a claim only coherent about the specific sample on hand, not a general/theoretical claim.",
    nonsig_population = paste0(
      "Treats a NONSIGNIFICANT p value (p > alpha, e.g. p > .05) as showing the true effect is EXACTLY ZERO or that two conditions/groups are IDENTICAL -- i.e. treats 'failed to reject the null' as equivalent to 'the null is true'. WRONG because nonsignificance only means the observed data are not surprising under the null hypothesis; the true effect is very rarely exactly zero, and a larger sample or more sensitive design could well have found a significant effect of the same, real, non-zero size. A study that is simply underpowered to detect a real small effect will produce a nonsignificant result even though the effect exists.\n\n",
      "This is a WELL-DOCUMENTED, HIGH-PREVALENCE error: Murphy, Merz, Reimann, & Fernandez (2025, Royal Society Open Science) found 76-85% of psychology articles that discuss a nonsignificant finding commit it. Their coding scheme is the basis for the phrasing list below -- flag a sentence using ANY of these patterns to describe a NONSIGNIFICANT result (not an exhaustive list; treat close paraphrases of the same idea the same way):\n",
      "  - explicit 'no effect' / zero-difference language: 'no effect', 'no difference', 'no relationship', 'not related to', 'not associated with', 'had no impact on', 'the same', 'identical', 'indifferent'\n",
      "  - SOFT/minimal-effect language used to convey the same absence-of-effect conclusion (these count too -- do not require blunt 'no effect' wording): 'similar', 'equally X' (e.g. 'equally fast', 'equally beneficial', 'equally moral'), 'essentially the same', 'comparable', 'did not vary by', 'did not differ (by/across/between)', 'indistinguishable'\n",
      "  - negated relationship-claim verbs: 'did not predict', 'did not relate to', 'was not associated with', 'was unrelated to' -- these claim the absence of a relationship, not merely that it could not be detected\n\n",
      "NOT this category (per the SAME source's own coding distinction -- do not flag these): a sentence that says the effect 'could not be found', 'was not detected', 'was not revealed', or explicitly acknowledges the effect might exist but be too small/underpowered to detect ('this nonsignificant finding could reflect a power or measurement sensitivity issue') -- 'find'/'detect'/'reveal' language correctly conveys an inability to find the effect, not a claim that it is absent, and is NOT a misinterpretation. Likewise, simply reporting 'nonsignificant'/'not significant'/'p > .05' with no further claim is not a misinterpretation -- only flag when the sentence goes on to assert absence/equality using language from the list above.\n\n",
      "This category is about the SAMPLE tested specifically (see nonsig_sample) or the whole POPULATION/a general, present-tense, theoretical claim (this category, nonsig_population) -- typically signalled by present-tense phrasing ('men and women do not differ in self-control', 'the intervention has no effect on wellbeing') or language clearly intended to generalise beyond the tested sample. Population-level claims are the more consequential version of this error, since they overgeneralise beyond what the study can support."
    ),
    p_other = "Any other incorrect definition or use of the p value not covered by the categories above (e.g. defining it as the probability of incorrectly rejecting the null hypothesis)."
  )
}

# ellmer type spec for structured judgment of whether a sentence correctly
# defines/uses the p-value/CI it reports. Built by hand rather than from a
# shipped JSON schema, following power.R's own precedent (a null-inclusive
# enum for an optional type_enum() field -- see power.R's own long comment on
# why: some providers' structured-output validators reject a field typed to
# allow null while its enum does not itself list null).
.p_ci_type_spec <- function() {
  cats <- .p_ci_categories()
  cat_desc <- paste(sprintf("'%s': %s", names(cats), cats), collapse = " ")

  ellmer::type_object(
    quoted_claim = ellmer::type_string(
      "The exact substring of the sentence that makes a claim about what the p value or confidence interval MEANS (not just reports its value). Empty string if the sentence makes no such claim at all -- in that case misinterpreted must be FALSE."
    ),
    misinterpreted = ellmer::type_boolean(
      "TRUE only if quoted_claim's specific wording matches the LOGICAL STRUCTURE of one of the misinterpretation categories below -- not merely its topic or vocabulary. A sentence that uses CI/p-value words (e.g. 'confidence interval', 'significant') without making the WRONG logical claim those categories describe is NOT a misinterpretation, even if a category sounds topically related. When genuinely uncertain whether quoted_claim fits a category's exact logical structure, prefer FALSE over forcing a near-fit label. FALSE if the sentence's claim about what the statistic means is technically correct, or if the sentence does not actually define/interpret the statistic at all (e.g. it only reports the number with no claim about what it means)."
    ),
    misinterpretation_type = ellmer::type_enum(
      c(names(cats), NA),
      description = paste("The specific kind of misinterpretation, if misinterpreted is TRUE, else null. Must be justified by quoted_claim's own logical structure, not by topical/vocabulary overlap with the category's wording.", cat_desc),
      required = FALSE
    ),
    explanation = ellmer::type_string(
      "A one-sentence explanation of why quoted_claim specifically (not the category's own definition text) is or is not technically correct."
    ),
    confidence = ellmer::type_number(
      "Your confidence that misinterpreted and misinterpretation_type are correct, from 0 (a guess) to 1 (certain). Reserve values above 0.8 for cases where quoted_claim unambiguously matches the category's logical structure; use a lower value for a borderline or debatable call."
    )
  )
}

# Judge each sentence's p/CI interpretation via LLM, preferring
# provider-enforced structured output with automatic fallback to
# prompt-instructed + json_expand() when a provider rejects structured output
# outright (see power.R's own .power_llm_extract() for the same pattern this
# mirrors, including why: issue #323).
.p_ci_llm_judge <- function(stats_found, seed) {
  cats <- .p_ci_categories()
  cat_list <- paste(sprintf("- %s: %s", names(cats), cats), collapse = "\n")

  # Shared "quote first, then classify" discipline: a category's own wording
  # (e.g. "confidence interval", "significant") sharing VOCABULARY with a
  # sentence is not evidence the sentence makes that category's specific
  # WRONG LOGICAL CLAIM -- confirmed as a real failure mode against actual
  # corpus output, where "nonoverlapping 95% CIs indicate significant
  # differences" (a claim that is directionally CORRECT, not a
  # misinterpretation at all) was still classified
  # ci_confidence_in_realized_interval purely because both mention "95% CI",
  # with an explanation that paraphrased the CATEGORY'S definition text
  # rather than analysing the sentence. Requiring the exact claim to be
  # quoted BEFORE classifying forces the category choice to be justified by
  # what the sentence actually says, not by which category's description
  # happens to share the most keywords with it.
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
    "give a lower confidence score.\n\n",
    "The sentence may report MULTIPLE separate statistics/tests (e.g. several",
    "p values and/or confidence intervals for different comparisons in the",
    "same sentence). Judge them TOGETHER as one sentence-level call: set",
    "misinterpreted to TRUE if AT LEAST ONE of the statistics in the sentence",
    "is misinterpreted, even if the others are reported correctly. Set",
    "quoted_claim to the specific wrong claim (from whichever statistic is",
    "misinterpreted), and name in explanation WHICH statistic/comparison the",
    "problem belongs to if more than one is present, so a reader can tell",
    "which part of the sentence the flag refers to."
  )

  structured_prompt <- paste0(
    "You will see a sentence from a scientific manuscript that reports a p value or a confidence interval (CI). Judge whether the sentence's own DEFINITION OR USE of what that p value or confidence interval MEANS is technically correct, per the specific misinterpretation categories below.\n\n",
    "Categories:\n", cat_list, "\n\n",
    anti_forcing
  )

  structured_result <- tryCatch(
    llm(
      text = stats_found,
      system_prompt = structured_prompt,
      type = .p_ci_type_spec(),
      text_col = "expanded",
      model = llm_model(),
      params = list(seed = seed)
    ),
    error = function(e) NULL
  )

  all_failed <- is.null(structured_result) ||
    (".error" %in% names(structured_result) &&
       all(vapply(structured_result$.error, isTRUE, logical(1))))

  if (!all_failed) {
    # llm()'s own return value is already `stats_found` left-joined with the
    # extracted columns (keyed on the `expanded` text, which is unique per row
    # here since stats_found was deduplicated on `expanded` before this call)
    # -- no separate bind needed, or wanted: stats_found's columns are already
    # present in structured_result exactly once.
    table <- structured_result
    table$misinterpretation_type <- as.character(table$misinterpretation_type)
    # The schema only asks the model, in prose, to return NA/null for
    # misinterpretation_type when misinterpreted is FALSE (ellmer::type_enum()
    # has no way to enforce a cross-field constraint like that) -- the model
    # is free to satisfy each field's own type individually while still
    # returning a category alongside a FALSE flag, which happens in practice
    # (confirmed against real corpus output). Enforced here rather than left
    # to the model, since only the module can guarantee it.
    table$misinterpretation_type[is.na(table$misinterpreted) |
                                    !table$misinterpreted] <- NA_character_
    # A row whose structured extraction itself errored (llm()'s own per-row
    # .error/.error_msg -- not every row, see all_failed above) leaves
    # misinterpreted/type/explanation NA, same as a row the model judged
    # non-misinterpreted-but-uncertain; the raw error text is dropped here
    # since a caller has no use for it once the row is folded into `table`.
    table$.error <- NULL
    table$.error_msg <- NULL

    return(list(
      table = table,
      model = attr(structured_result, "llm")$model,
      structured = TRUE,
      failed = FALSE
    ))
  }

  ## fallback: prompt-instructed JSON + json_expand ----
  preface <- paste0(
    "You will see a sentence from a scientific manuscript that reports a p value or confidence interval. Judge whether the sentence's own DEFINITION OR USE of what that statistic MEANS is technically correct, per the specific misinterpretation categories below.\n\n",
    "Categories:\n", cat_list, "\n\n",
    anti_forcing, "\n\n",
    "Return a JSON object with keys \"quoted_claim\" (the exact substring making the claim, or \"\" if none), \"misinterpreted\" (true/false), \"misinterpretation_type\" (one of ",
    paste(sprintf('"%s"', names(cats)), collapse = ", "),
    ", or null if not misinterpreted), \"explanation\" (a one-sentence explanation referring to quoted_claim specifically), and \"confidence\" (a number from 0 to 1, reserving values above 0.8 for an unambiguous match), bracketed by ```json and ```."
  )

  llm_results <- llm(
    text = stats_found,
    system_prompt = preface,
    text_col = "expanded",
    model = llm_model(),
    params = list(seed = seed)
  )

  table <- llm_results |> json_expand()

  row_failed <- if ("error" %in% names(table)) !is.na(table$error) else FALSE
  if (!"misinterpreted" %in% names(table)) {
    table$misinterpreted <- NA
    table$misinterpretation_type <- NA_character_
    table$explanation <- NA_character_
  } else if ("misinterpretation_type" %in% names(table)) {
    # Same cross-field inconsistency the structured path guards against
    # above -- the fallback's own prompt only asks for null in prose too
    # (line ~484's "or null if not misinterpreted"), so it is just as
    # unenforced against a model that ignores it.
    table$misinterpretation_type[is.na(table$misinterpreted) |
                                    !table$misinterpreted] <- NA_character_
  }

  list(
    table = table,
    model = attr(llm_results, "llm")$model,
    structured = FALSE,
    failed = nrow(stats_found) > 0 && all(row_failed)
  )
}
