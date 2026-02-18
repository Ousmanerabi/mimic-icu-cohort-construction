# MIMIC-IV ICU Cohort Construction (R + SQL)

End-to-end example of **real-world cohort construction** using **R + PostgreSQL SQL** on MIMIC-style ICU data.
Focus: **exclusion criteria**, **time-aligned exposure definition**, and **feature engineering** in a reproducible pipeline.

## What this repo demonstrates
- Cohort building from ICU stays with explicit **exclusion flags**
- Defining **mechanical ventilation start** (procedure + chart events)
- Exposure: **arterial line placement within 0–24h of MV start**
- 0–24h feature engineering: **vasopressors, vitals, labs**
- **Charlson comorbidity score** (pragmatic ICD9 proxy)
- Clear separation of concerns: `/R` orchestrates, `/SQL` contains queries

## Repo structure
- `R/01_build_base_cohort.R` – base cohort + exclusions  
- `R/02_define_mv_start.R` – MV start definition  
- `R/03_exposure_iac.R` – IAC exposure (0–24h)  
- `R/04_features_vitals_labs_vaso.R` – day-1 features  
- `R/05_charlson_index.R` – Charlson score  
- `R/99_run_all.R` – runs the full pipeline and saves outputs  
- `SQL/*.sql` – all SQL queries

## How to Run
1) Create a `.env` file locally:
```bash
cp .env.example .env
```

2) Edit .env with your database credentials.
3) Run
```R
source("R/99_run_all.R")
```
