# Derive features in 0–24h post MV start:
# - vasopressors flag
# - vitals summaries
# - labs summaries
# Output: data.frame `cohort_feat`

sql_path <- "SQL/features_vitals_labs_vaso.sql"
stopifnot(file.exists(sql_path))
stopifnot(exists("cohort_iac"))

# temp table includes mv_start and IDs used for joins
tmp <- cohort_iac[, c("subject_id","hadm_id","icustay_id","intime","outtime","mv_start")]
DBI::dbWriteTable(con, "tmp_cohort_mv", tmp, temporary = TRUE, overwrite = TRUE)

feat <- DBI::dbGetQuery(con, paste(readLines(sql_path), collapse = "\n"))

cohort_feat <- dplyr::left_join(cohort_iac, feat, by = "icustay_id")

if (!"vaso_24h" %in% names(cohort_feat)) stop("vaso_24h not present after merge.")
message("04_features: vaso_24h=1 count=", sum(cohort_feat$vaso_24h %in% 1, na.rm = TRUE))
