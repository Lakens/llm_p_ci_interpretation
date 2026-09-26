devtools::load_all("C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/metacheck-new")
llm_use(TRUE)
llm_model("groq/openai/gpt-oss-20b")
llm_max_calls(200)   # default is 30; some papers have more p-value/CI sentences than that

papers <- readRDS("C:/Users/dlakens/OneDrive - TU Eindhoven/git_repos/papers_private/psychsci.rds")

# one paper
out <- module_run(papers[[1]], "stat_p_ci_interpretation")

# all papers
# out <- module_run(papers, "stat_p_ci_interpretation")

report(papers[[1806]], "stat_p_ci_interpretation")   # generate a report instead of just the module output
