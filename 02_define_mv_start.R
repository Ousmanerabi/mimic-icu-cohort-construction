# Define MV start time for each icustay in base cohort
# Output: data.frame `cohort_mv` (base + mv_start)

sql_path <- "SQL/mv_start.sql"
stopifnot(file.exists(sql_path))
stopifnot(exists("base_cohort"))

# Write base cohort ids to a temp table (session-scoped)
DBI::dbWriteTable(con, "tmp_base_cohort",
                  base_cohort[, c("subject_id","hadm_id","icustay_id","intime","outtime")],
                  temporary = TRUE, overwrite = TRUE)

mv_start <- DBI::dbGetQuery(con, paste(readLines(sql_path), collapse = "\n"))

# Merge back
cohort_mv <- dplyr::left_join(base_cohort, mv_start, by = "icustay_id")

if (!"mv_start" %in% names(cohort_mv)) stop("mv_start not created/merged.")
message("02_define_mv_start: mv_start non-missing=", sum(!is.na(cohort_mv$mv_start)),
        "/", nrow(cohort_mv))
