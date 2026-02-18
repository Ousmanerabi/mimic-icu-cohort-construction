# Build base ICU cohort + exclusion flags
# Output: data.frame `base_cohort`

sql_path <- "SQL/base_cohort.sql"
stopifnot(file.exists(sql_path))

base_cohort <- DBI::dbGetQuery(con, paste(readLines(sql_path), collapse = "\n"))

# Minimal sanity checks
required_cols <- c("subject_id","hadm_id","icustay_id","intime","outtime",
                   "icu_length_of_stay","age","icustay_id_order",
                   "exclusion_los","exclusion_age","exclusion_first_stay","exclusion_surgical")
missing <- setdiff(required_cols, names(base_cohort))
if (length(missing) > 0) stop("base_cohort missing columns: ", paste(missing, collapse=", "))

message("01_build_base_cohort: rows=", nrow(base_cohort),
        " unique icustay_id=", dplyr::n_distinct(base_cohort$icustay_id))
