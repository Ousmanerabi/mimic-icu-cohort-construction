# Charlson comorbidity score (pragmatic ICD9 proxy)
# Output: data.frame `final_cohort`

sql_path <- "SQL/charlson.sql"
stopifnot(file.exists(sql_path))
stopifnot(exists("cohort_feat"))

# Use hadm_id list for comorbidity extraction
tmp <- cohort_feat[, c("subject_id","hadm_id","icustay_id")]
DBI::dbWriteTable(con, "tmp_hadm", tmp, temporary = TRUE, overwrite = TRUE)

cci <- DBI::dbGetQuery(con, paste(readLines(sql_path), collapse = "\n"))

final_cohort <- dplyr::left_join(cohort_feat, cci, by = "hadm_id")

if (!"charlson_score" %in% names(final_cohort)) stop("charlson_score not present after merge.")
message("05_charlson_index: charlson_score non-missing=",
        sum(!is.na(final_cohort$charlson_score)), "/", nrow(final_cohort))
