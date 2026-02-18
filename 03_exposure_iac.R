# Exposure: arterial line placement within 0-24h of MV start
# Output: data.frame `cohort_iac` (cohort_mv + iac_time + iac_exposed)

sql_path <- "SQL/exposure_iac.sql"
stopifnot(file.exists(sql_path))
stopifnot(exists("cohort_mv"))

# Need mv_start & icustay_id in temp table for time-window logic
tmp <- cohort_mv[, c("subject_id","hadm_id","icustay_id","intime","outtime","mv_start")]
DBI::dbWriteTable(con, "tmp_cohort_mv", tmp, temporary = TRUE, overwrite = TRUE)

iac <- DBI::dbGetQuery(con, paste(readLines(sql_path), collapse = "\n"))

cohort_iac <- dplyr::left_join(cohort_mv, iac, by = "icustay_id")

req <- c("iac_time","iac_exposed")
miss <- setdiff(req, names(cohort_iac))
if (length(miss) > 0) stop("cohort_iac missing columns: ", paste(miss, collapse=", "))

message("03_exposure_iac: exposed=", sum(cohort_iac$iac_exposed %in% 1, na.rm = TRUE),
        " / total=", nrow(cohort_iac))
