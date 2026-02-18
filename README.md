# MIMIC-III ICU Cohort Construction (R + SQL)

This repository demonstrates an end-to-end **real-world EMR cohort construction workflow** using the public **MIMIC-III** ICU database (PostgreSQL) and reproducible R pipelines.

## Objective
Build an **adult, non-surgical, first ICU stay** cohort and derive:
- Mechanical ventilation start time (MV)
- Exposure: arterial line placement within **0–24h post MV**
- Covariates: vasopressors (0–24h), vitals and labs (0–24h), demographics, and Charlson comorbidity score
- Outcome-ready variables (e.g., 28-day mortality logic can be added on top of MV start)

## Data Source
MIMIC-III (PostgreSQL). No patient-level data are included in this repo.

## Cohort Definition
**Inclusion**
- ICU stays with available `intime/outtime`
- First ICU stay per subject

**Exclusion flags**
- ICU LOS < 2 days
- Age < 16
- Not first ICU stay
- Surgical service (SURG/ORTHO)

## Key Derivations
### MV start
MV start derived from:
- Procedure events (intubation / invasive ventilation)
- Chart events (ventilator mode / mechanically ventilated signals)
Using the earliest available timestamp within ICU stay.

### Exposure: arterial line (IAC)
IAC exposure = 1 if arterial line placement occurs in `[MV start, MV start + 24h)`.

### Covariates (0–24h post MV)
- Vasopressors: norepinephrine, epinephrine, vasopressin, phenylephrine, dopamine
- Vitals summary: HR, MAP, Temp, SpO2 (mean/min/max)
- Labs summary: pH, PaO2, PaCO2, lactate, sodium, potassium, hematocrit, WBC (mean/min/max)
- Charlson comorbidity score (ICD9-based pragmatic proxy)

## How to Run
1) Create a `.env` file locally (never commit it):
```bash
cp .env.example .env
