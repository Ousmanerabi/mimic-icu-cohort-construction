# =============================================================================
# Project  : Effect of Early Intra-Arterial Catheter (IAC) Placement on
#            28-Day Mortality in Mechanically Ventilated ICU Patients
# Data     : MIMIC-III (Medical Information Mart for Intensive Care)
# Database : PostgreSQL via AWS RDS
# Author   : Ousman
# =============================================================================
#
# Research Question:
#   Does early IAC placement (within 24h of mechanical ventilation initiation)
#   reduce 28-day mortality among non-surgical, adult ICU patients?
#
# Analytical approach:
#   1. Cohort construction with explicit exclusion criteria
#   2. Exposure: IAC within 24h of MV start (binary)
#   3. Outcome : 28-day all-cause mortality (binary)
#   4. Confounding control: logistic regression, PS matching, IPTW
#
# Exclusion criteria (applied sequentially):
#   - ICU length of stay < 2 days
#   - Age < 16 years (pediatric patients)
#   - Not the patient's first ICU stay
#   - Surgical service (any *SURG or ORTHO)
#   - Cardiac Surgery Recovery Unit (CSRU)
#   - Vasopressor use within 24h of MV start (high severity confounder)
#   - No mechanical ventilation event recorded
# =============================================================================

library(DBI)
library(RPostgres)
library(dplyr)

# -----------------------------------------------------------------------------
# 0. DATABASE CONNECTION
# -----------------------------------------------------------------------------

# Connect to MIMIC-III PostgreSQL instance on AWS RDS
# NOTE: In production, store credentials in environment variables (.Renviron)
con <- dbConnect(
  RPostgres::Postgres(),
  host     = "mimiciii-rds.czmoceumuq7i.us-east-2.rds.amazonaws.com",
  port     = 5432,
  user     = "postgres",
  password = Sys.getenv("MIMIC_PASSWORD"),  # store in .Renviron
  dbname   = "mimiciii"
)

# -----------------------------------------------------------------------------
# STEP 1: BASE COHORT WITH EXCLUSION FLAGS
# -----------------------------------------------------------------------------
# Build the initial cohort from icustays + patients.
# Compute age, ICU length of stay, ICU stay order per patient,
# and surgical service flag within 12h of ICU admission.
# All exclusion criteria are flagged (1 = exclude) but not yet applied.

cohort_base <- DBI::dbGetQuery(con,
                               "WITH co AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.icustay_id,
      icu.intime,
      icu.outtime,
      -- ICU length of stay in days
      EXTRACT(EPOCH FROM outtime - intime) / 3600.0 / 24.0 AS icu_los_days,
      -- Age at ICU admission (years)
      EXTRACT(EPOCH FROM icu.intime - pat.dob) / 3600.0 / 24.0 / 365.242 AS age,
      -- Rank ICU stays per patient by admission time (1 = first stay)
      RANK() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS icustay_id_order
    FROM icustays icu
    JOIN patients pat ON icu.subject_id = pat.subject_id
  ),

  serv AS (
    SELECT
      icu.icustay_id,
      -- Flag any surgical or orthopedic service
      CASE
        WHEN curr_service LIKE '%SURG' THEN 1
        WHEN curr_service = 'ORTHO'   THEN 1
        ELSE 0
      END AS surgical,
      -- Most recent service transfer before ICU admission (within 12h window)
      RANK() OVER (PARTITION BY icu.hadm_id ORDER BY se.transfertime DESC) AS rank
    FROM icustays icu
    LEFT JOIN services se
      ON icu.hadm_id = se.hadm_id
      AND se.transfertime < icu.intime + interval '12' hour
  )

  SELECT
    co.*,
    icu.first_careunit,
    -- Exclusion flags (1 = patient should be excluded)
    CASE WHEN co.icu_los_days     <  2 THEN 1 ELSE 0 END AS exclusion_los,
    CASE WHEN co.age              < 16 THEN 1 ELSE 0 END AS exclusion_age,
    CASE WHEN co.icustay_id_order != 1 THEN 1 ELSE 0 END AS exclusion_first_stay,
    CASE WHEN serv.surgical        = 1 THEN 1 ELSE 0 END AS exclusion_surgical
  FROM co
  LEFT JOIN icustays icu ON co.icustay_id  = icu.icustay_id
  LEFT JOIN serv         ON co.icustay_id  = serv.icustay_id
                        AND serv.rank = 1"
)

# Sanity check: count patients per exclusion flag combination
cohort_base |>
  dplyr::count(exclusion_los, exclusion_age,
               exclusion_first_stay, exclusion_surgical)

# -----------------------------------------------------------------------------
# STEP 2: MECHANICAL VENTILATION START TIME (mv_start)
# -----------------------------------------------------------------------------
# Identify the earliest MV initiation time per ICU stay.
# Two sources are combined to maximize capture:
#   - procedureevents_mv : itemids 224385 (intubation), 225792 (invasive MV)
#   - chartevents        : itemids 226260, 223849, 720 (MV mode chart entries)
# COALESCE prioritizes procedureevents over chartevents.

mv_tbl <- DBI::dbGetQuery(con,
                          "WITH co_ids AS (
    SELECT icustay_id, intime, outtime
    FROM icustays
  ),

  -- Source 1: MV start from procedure events
  mv_proc AS (
    SELECT p.icustay_id, MIN(p.starttime) AS mv_start_proc
    FROM procedureevents_mv p
    JOIN co_ids c ON c.icustay_id = p.icustay_id
    WHERE p.itemid IN (224385, 225792)   -- intubation / invasive ventilation
      AND p.starttime BETWEEN c.intime AND c.outtime
    GROUP BY p.icustay_id
  ),

  -- Source 2: MV start from chart events (fallback)
  mv_chart AS (
    SELECT ce.icustay_id, MIN(ce.charttime) AS mv_start_chart
    FROM chartevents ce
    JOIN co_ids c ON c.icustay_id = ce.icustay_id
    WHERE ce.itemid IN (226260, 223849, 720)   -- ventilator mode entries
      AND ce.charttime BETWEEN c.intime AND c.outtime
      AND ce.value IS NOT NULL
    GROUP BY ce.icustay_id
  )

  SELECT
    c.icustay_id,
    -- Use procedure event if available, fall back to chart event
    COALESCE(mv_proc.mv_start_proc, mv_chart.mv_start_chart) AS mv_start
  FROM co_ids c
  LEFT JOIN mv_proc  ON c.icustay_id = mv_proc.icustay_id
  LEFT JOIN mv_chart ON c.icustay_id = mv_chart.icustay_id"
)

# -----------------------------------------------------------------------------
# STEP 3: APPLY EXCLUSIONS → ANALYTICAL COHORT
# -----------------------------------------------------------------------------
# Join MV data to base cohort and apply all exclusion criteria.
# Patients without a recorded MV event are also excluded (not ventilated).
#
# Protocol §7 criterion: MV start must occur within 24h of ICU admission.
# This ensures time zero is aligned with the early ICU period and reduces
# the risk of including patients ventilated late in their stay (different
# clinical trajectory from patients ventilated on admission).

analytic <- cohort_base |>
  dplyr::left_join(mv_tbl, by = "icustay_id") |>
  dplyr::filter(
    exclusion_los          == 0,   # ICU LOS >= 2 days
    exclusion_age          == 0,   # Age >= 16 years
    exclusion_first_stay   == 0,   # First ICU stay only
    exclusion_surgical     == 0,   # Non-surgical service
    !is.na(mv_start),              # Must have a MV event
    # MV start within 24h of ICU admission (protocol §7)
    as.numeric(difftime(mv_start, intime, units = "hours")) <= 24
  )

cat("Analytical cohort (pre-secondary exclusions):", nrow(analytic), "patients\n")

# -----------------------------------------------------------------------------
# STEP 4: PUSH COHORT TO POSTGRESQL (temporary table)
# -----------------------------------------------------------------------------
# Required for subsequent SQL CTEs that join against the cohort.
# Temporary tables are session-scoped and dropped on disconnect.

DBI::dbWriteTable(con, "tmp_cohort_mv", analytic,
                  temporary = TRUE, overwrite = TRUE)

DBI::dbGetQuery(con, "SELECT COUNT(*) FROM tmp_cohort_mv;")

# -----------------------------------------------------------------------------
# STEP 5: EXPOSURE — IAC PLACEMENT (iac_exposed)
# -----------------------------------------------------------------------------
# Identify earliest IAC placement per ICU stay (itemid 225752 = Arterial Line).
# Exposure is defined as IAC placed within 24h of MV initiation.

analytic_iac <- DBI::dbGetQuery(con,
                                "WITH iac AS (
    SELECT
      c.icustay_id,
      MIN(pe.starttime) AS iac_time   -- earliest arterial line placement
    FROM tmp_cohort_mv c
    JOIN procedureevents_mv pe ON pe.icustay_id = c.icustay_id
    WHERE pe.itemid = 225752           -- Arterial Line (MetaVision)
      AND pe.starttime IS NOT NULL
    GROUP BY c.icustay_id
  )

  SELECT
    c.*,
    iac.iac_time,
    -- Binary exposure: IAC placed within 24h of MV start
    CASE
      WHEN iac.iac_time IS NOT NULL
       AND iac.iac_time >= c.mv_start
       AND iac.iac_time <  c.mv_start + interval '24 hours'
      THEN 1 ELSE 0
    END AS iac_exposed
  FROM tmp_cohort_mv c
  LEFT JOIN iac ON c.icustay_id = iac.icustay_id"
)

cat("Cohort with IAC exposure:", nrow(analytic_iac), "patients\n")

# -----------------------------------------------------------------------------
# STEP 6: OUTCOME — 28-DAY ALL-CAUSE MORTALITY (death_28d)
# -----------------------------------------------------------------------------
# Death is captured from two sources (COALESCE):
#   - admissions.deathtime : in-hospital death time
#   - patients.dod         : date of death (out-of-hospital or discharge)
# A patient is classified as dead (1) if death occurred within 28 days
# of MV initiation. Patients with no death record are classified as alive (0).
# Patients without an MV start remain NULL.

death_28d_tbl <- DBI::dbGetQuery(con,
                                 "SELECT
     b.icustay_id,
     CASE
       WHEN b.mv_start IS NULL
         THEN NULL    -- no MV event; should not occur after Step 3 filter
       WHEN COALESCE(a.deathtime, p.dod) IS NULL
         THEN 0       -- no death recorded → alive at 28 days
       WHEN COALESCE(a.deathtime, p.dod) <= b.mv_start + interval '28 days'
         THEN 1       -- death within 28 days of MV start
       ELSE 0         -- death after 28-day window → censored as alive
     END AS death_28d
   FROM tmp_cohort_mv b
   LEFT JOIN admissions a ON b.hadm_id    = a.hadm_id
   LEFT JOIN patients   p ON b.subject_id = p.subject_id"
)

# Sanity check: distribution of outcome
death_28d_tbl |> dplyr::count(death_28d)

# -----------------------------------------------------------------------------
# STEP 7: COVARIATES — VASOPRESSORS + DEMOGRAPHICS + COMORBIDITIES
# -----------------------------------------------------------------------------
# Collected within 24h of MV start:
#   - vaso_24h     : vasopressor use (binary) — used as secondary exclusion
#                    (vasopressor patients represent extreme severity confounding)
#   - ethnicity    : from admissions table
#   - admission_type, insurance: from admissions table
#   - gender       : from patients table
#   - charlson_score: Charlson Comorbidity Index (ICD-9 based, simplified proxy)
#     Weights: MI=1, CHF=1, COPD=1, DM=1, DM+complications=2,
#              renal=2, liver=2, cancer=2, HIV/AIDS=6

covariates <- DBI::dbGetQuery(con,
                              "-- Vasopressor item IDs (MetaVision + CareVue)
  WITH vaso_itemids AS (
    SELECT itemid
    FROM d_items
    WHERE linksto IN ('inputevents_mv', 'inputevents_cv')
      AND (
        lower(label) LIKE '%norepinephrine%'
        OR lower(label) LIKE '%levophed%'
        OR lower(label) LIKE '%epinephrine%'
        OR lower(label) LIKE '%vasopressin%'
        OR lower(label) LIKE '%phenylephrine%'
        OR lower(label) LIKE '%dopamine%'
      )
  ),

  -- Vasopressor use: MetaVision (rate/amount-based)
  vaso_mv AS (
    SELECT DISTINCT ie.icustay_id, 1 AS vaso_24h
    FROM inputevents_mv ie
    JOIN tmp_cohort_mv b  ON b.icustay_id = ie.icustay_id
    JOIN vaso_itemids  vi ON ie.itemid     = vi.itemid
    WHERE ie.starttime >= b.mv_start
      AND ie.starttime <  b.mv_start + interval '24 hours'
      AND COALESCE(ie.rate, ie.amount, 0) > 0
  ),

  -- Vasopressor use: CareVue (charttime-based)
  vaso_cv AS (
    SELECT DISTINCT ie.icustay_id, 1 AS vaso_24h
    FROM inputevents_cv ie
    JOIN tmp_cohort_mv b  ON b.icustay_id = ie.icustay_id
    JOIN vaso_itemids  vi ON ie.itemid     = vi.itemid
    WHERE ie.charttime >= b.mv_start
      AND ie.charttime <  b.mv_start + interval '24 hours'
      AND COALESCE(ie.rate, ie.amount, 0) > 0
  ),

  -- Combine both vasopressor sources
  vaso AS (
    SELECT icustay_id, 1 AS vaso_24h
    FROM (SELECT * FROM vaso_mv UNION SELECT * FROM vaso_cv) u
  ),

  -- ICD-9 diagnosis codes for Charlson scoring
  dx AS (
    SELECT hadm_id, icd9_code FROM diagnoses_icd
  ),

  -- Charlson comorbidity flags (binary per condition)
  charlson_flags AS (
    SELECT
      b.hadm_id,
      MAX(CASE WHEN icd9_code ~ '^(410|412)'                        THEN 1 ELSE 0 END) AS mi,
      MAX(CASE WHEN icd9_code ~ '^(428)'                            THEN 1 ELSE 0 END) AS chf,
      MAX(CASE WHEN icd9_code ~ '^(490|491|492|493|494|495|496)'    THEN 1 ELSE 0 END) AS copd,
      MAX(CASE WHEN icd9_code ~ '^(250[0-3])'                       THEN 1 ELSE 0 END) AS dm,
      MAX(CASE WHEN icd9_code ~ '^(250[4-9])'                       THEN 1 ELSE 0 END) AS dm_comp,
      MAX(CASE WHEN icd9_code ~ '^(585)'                            THEN 1 ELSE 0 END) AS renal,
      MAX(CASE WHEN icd9_code ~ '^(571|572)'                        THEN 1 ELSE 0 END) AS liver,
      MAX(CASE WHEN icd9_code ~ '^(14[0-9]|1[5-9][0-9]|[2-9][0-9]{2})' THEN 1 ELSE 0 END) AS cancer,
      MAX(CASE WHEN icd9_code ~ '^(042|043|044)'                    THEN 1 ELSE 0 END) AS hiv
    FROM tmp_cohort_mv b
    LEFT JOIN dx ON dx.hadm_id = b.hadm_id
    GROUP BY b.hadm_id
  ),

  -- Weighted Charlson score
  charlson AS (
    SELECT
      hadm_id,
      (1*mi + 1*chf + 1*copd + 1*dm + 2*dm_comp +
       2*renal + 2*liver + 2*cancer + 6*hiv) AS charlson_score
    FROM charlson_flags
  )

  SELECT
    b.icustay_id,
    COALESCE(v.vaso_24h, 0) AS vaso_24h,   -- 0 if no vasopressor
    a.ethnicity,
    a.admission_type,
    a.insurance,
    p.gender,
    c.charlson_score
  FROM tmp_cohort_mv b
  LEFT JOIN vaso       v ON b.icustay_id = v.icustay_id
  LEFT JOIN admissions a ON b.hadm_id    = a.hadm_id
  LEFT JOIN patients   p ON b.subject_id = p.subject_id
  LEFT JOIN charlson   c ON b.hadm_id    = c.hadm_id"
)

cat("Covariates table:", nrow(covariates), "rows\n")

# -----------------------------------------------------------------------------
# STEP 8: ASSEMBLE FINAL COHORT
# -----------------------------------------------------------------------------
# Join exposure, outcome, and covariates into a single analytic dataset.

final_cohort <- analytic_iac |>
  dplyr::left_join(death_28d_tbl, by = "icustay_id")

cat("final_cohort:", nrow(final_cohort),
    "| death_28d NA:", sum(is.na(final_cohort$death_28d)), "\n")

# Distribution check: exposure × outcome
final_cohort |>
  dplyr::count(iac_exposed, death_28d) |>
  dplyr::mutate(pct = round(n / sum(n) * 100, 1))

# -----------------------------------------------------------------------------
# STEP 9: RECODE VARIABLES (final_cohort_v2)
# -----------------------------------------------------------------------------
# Join covariates and create grouped categorical variables for analysis.
# Groupings follow standard epidemiological conventions:
#   - ethnicity_grp : ASIAN / BLACK / WHITE / OTHER
#   - insurance_grp : Public / Private / Uninsured
#   - adm_type_grp  : ELECTIVE / NON ELECTIVE / OTHER
#   - icu_type      : MICU / SURGICAL / CARDIAC / OTHER
#   - iac_exposed_re: "No-IAC" / "IAC" (character, releveled later)

final_cohort_v2 <- final_cohort |>
  dplyr::left_join(covariates, by = "icustay_id") |>
  dplyr::mutate(
    
    ethnicity_grp = dplyr::case_when(
      ethnicity == "ASIAN"                               ~ "ASIAN",
      ethnicity %in% c("BLACK","BLACK/AFRICAN AMERICAN") ~ "BLACK",
      ethnicity == "WHITE"                               ~ "WHITE",
      TRUE                                               ~ "OTHER"
    ),
    
    insurance_grp = dplyr::case_when(
      insurance %in% c("Government","Medicaid","Medicare") ~ "Public",
      insurance == "Self Pay"                              ~ "Uninsured",
      TRUE                                                 ~ "Private"
    ),
    
    adm_type_grp = dplyr::case_when(
      admission_type == "ELECTIVE"                    ~ "ELECTIVE",
      admission_type %in% c("URGENT","EMERGENCY")     ~ "NON ELECTIVE",
      TRUE                                            ~ "OTHER"
    ),
    
    icu_type = dplyr::case_when(
      first_careunit == "MICU"              ~ "MICU",
      first_careunit %in% c("SICU","TSICU") ~ "SURGICAL",
      first_careunit == "CCU"               ~ "CARDIAC",
      TRUE                                  ~ "OTHER"
    ),
    
    # Flag patients admitted to Cardiac Surgery Recovery Unit (excluded later)
    first_careunit_exclu = dplyr::if_else(first_careunit == "CSRU", 1L, 0L),
    
    # Readable exposure label
    iac_exposed_re = dplyr::if_else(iac_exposed == 0, "No-IAC", "IAC")
  )

cat("final_cohort_v2:", nrow(final_cohort_v2), "rows\n")

# -----------------------------------------------------------------------------
# STEP 10: APPLY SECONDARY EXCLUSIONS → ANALYTICAL COHORT (final_cohort_v3)
# -----------------------------------------------------------------------------
# Exclude:
#   - CSRU patients (cardiac surgery — different clinical pathway)
#   - Patients with vasopressor use within 24h of MV start
#     (extreme severity confounding not adequately captured by other covariates)
# Select analysis variables and cast to appropriate types.
# Reference levels for factors: No-IAC for exposure, WHITE for ethnicity.

final_cohort_v3 <- final_cohort_v2 |>
  dplyr::filter(
    first_careunit_exclu == 0,   # exclude CSRU
    vaso_24h             == 0    # exclude vasopressor use in first 24h
  ) |>
  dplyr::select(
    subject_id, hadm_id, icustay_id,
    intime, outtime,
    age, mv_start,
    death_28d, iac_exposed, iac_exposed_re,
    vaso_24h, gender,
    insurance_grp, icu_type,
    charlson_score, adm_type_grp, ethnicity_grp
  ) |>
  dplyr::mutate(
    age10 = age / 10,   # age scaled per 10 years for OR interpretation
    dplyr::across(
      c(death_28d, iac_exposed_re, vaso_24h, gender,
        insurance_grp, icu_type, adm_type_grp, ethnicity_grp),
      as.factor
    ),
    iac_exposed_re = relevel(iac_exposed_re, ref = "No-IAC"),
    ethnicity_grp  = relevel(ethnicity_grp,  ref = "WHITE")
  )

# Final cohort summary
cat("final_cohort_v3:", nrow(final_cohort_v3), "patients\n")
final_cohort_v3 |> dplyr::count(iac_exposed_re, death_28d)

# -----------------------------------------------------------------------------
# QUALITY CONTROL CHECKS (protocol §7)
# -----------------------------------------------------------------------------

# 1. No duplicate ICU stays — each row must be a unique icustay_id
stopifnot(
  "Duplicate icustay_id detected in final_cohort_v3" =
    !any(duplicated(final_cohort_v3$icustay_id))
)

# 2. MV start within ICU stay bounds (intime <= mv_start <= outtime)
mv_bounds_check <- final_cohort_v3 |>
  dplyr::filter(mv_start < intime | mv_start > outtime)

if (nrow(mv_bounds_check) > 0) {
  warning(nrow(mv_bounds_check),
          " patients have mv_start outside ICU stay bounds — review timestamps")
} else {
  message("OK: all mv_start timestamps are within ICU stay bounds")
}

# 3. No missing values on key analysis variables
key_vars <- c("death_28d", "iac_exposed_re", "age", "gender",
              "charlson_score", "icu_type", "insurance_grp",
              "adm_type_grp", "ethnicity_grp")

na_check <- final_cohort_v3 |>
  dplyr::summarise(dplyr::across(dplyr::all_of(key_vars),
                                 ~ sum(is.na(.x)))) |>
  tidyr::pivot_longer(dplyr::everything(),
                      names_to  = "variable",
                      values_to = "n_missing") |>
  dplyr::filter(n_missing > 0)

if (nrow(na_check) > 0) {
  warning("Missing values detected in key variables:")
  print(na_check)
} else {
  message("OK: no missing values in key analysis variables")
}