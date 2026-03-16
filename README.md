# Early Arterial Catheter Use and 28-Day Mortality in Mechanically Ventilated ICU Patients

**Retrospective cohort study using MIMIC-III EHR data**  
Ousmane Diallo, MPH-PhD · Protocol v2.0 · December 2025

---

## Research Question

Among mechanically ventilated adult ICU patients **not receiving vasopressors** in the first 24 hours after MV initiation, is **early IAC placement (within 0–24h of MV start)** associated with 28-day all-cause mortality?

---

## Study Design

- **Design**: Retrospective observational cohort, target-trial inspired
- **Data source**: MIMIC-III (Beth Israel Deaconess Medical Center, PhysioNet)
- **Time zero**: MV initiation (earliest documented ventilation event)
- **Exposure window**: 0–24h after MV start
- **Outcome**: 28-day all-cause mortality
- **Confounding strategy**: Multivariable logistic regression + propensity score matching + IPTW (ATE)

---

## Cohort

| Step | N |
|------|---|
| MIMIC-III icustays (all) | ~61,000 |
| After primary exclusions | 2,387 |
| **Final analytical cohort** | **1,106** |
| — Early IAC exposed | 470 (42.5%) |
| — No early IAC | 636 (57.5%) |

**Exclusion criteria (sequential):**
1. ICU LOS < 2 days
2. Age < 16 years
3. Not first ICU stay
4. Surgical service admission
5. MV start > 24h after ICU admission
6. No MV event recorded
7. CSRU admission (systematic pre-ICU arterial line placement)
8. Vasopressor use in first 24h after MV start

---

## Key Results

| Model | OR | 95% CI | p-value |
|-------|----|--------|---------|
| Multivariable logistic regression | 1.37 | 0.99 – 1.89 | 0.056 |
| IPTW (ATE) | 1.36 | 0.98 – 1.88 | 0.064 |
| PS Matching (1:1 nearest neighbor) | pending | — | — |

**Early IAC placement was not significantly associated with lower 28-day mortality** after adjustment. Results are consistent across analytical approaches, supporting the null hypothesis specified in Protocol v2.0.

Crude mortality: 16.4% (No-IAC) vs 19.6% (IAC) — higher in IAC group, consistent with **confounding by indication**.

---

## Repository Structure

```
iac-mv-study/
├── mimic_iac_cohort.R       # SQL + R cohort construction pipeline
├── mimic_iac_analysis.R     # Descriptive analysis, logistic regression, PSM, IPTW
└── README.md
```

---

## Requirements

```r
# R packages
library(dplyr)
library(tidyr)
library(ggplot2)
library(gtsummary)
library(MatchIt)
library(WeightIt)
library(cobalt)
library(survey)
library(broom)
library(questionr)
library(ggstats)

# Database
# PostgreSQL (MIMIC-III) via DBI + RPostgres
```

---

## Reproducibility Notes

- Cohort is extracted via SQL; all derivations are explicitly documented in `mimic_iac_cohort.R`
- A temporary PostgreSQL table (`tmp_cohort_mv`) is created at runtime — must be rebuilt if session is restarted:
```r
DBI::dbWriteTable(con, "tmp_cohort_mv", analytic, temporary = TRUE, overwrite = TRUE)
```
- Analysis script (`mimic_iac_analysis.R`) requires `final_cohort_v3` produced by the cohort script

---

## Limitations

- **Residual confounding**: severity-of-illness scores (SOFA, APACHE) and high-resolution vitals/labs unavailable due to storage constraints
- **Exposure misclassification**: IAC documentation may be incomplete or recorded after actual placement
- **Single-center**: BIDMC only — generalizability may be limited
- **Complete separation**: admission type (elective, n=30, 0 deaths) — coefficient not interpretable; primary exposure estimate unaffected

---

## Data Access

MIMIC-III is freely available via [PhysioNet](https://physionet.org/content/mimiciii/) after credentialing and data use agreement. No data is included in this repository.

---

## Protocol

Full protocol (v2.0): [ousmanediallo.com/projects/iac-mv-study/protocol_v2](https://ousmanediallo.com/projects/iac-mv-study/protocol_v2)

---

## License

Code: MIT  
Data: PhysioNet Data Use Agreement (not included in this repository)
