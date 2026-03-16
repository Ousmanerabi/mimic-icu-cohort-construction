# =============================================================================
# Project  : Effect of Early IAC Placement on 28-Day Mortality
#            in Mechanically Ventilated ICU Patients (MIMIC-III)
# Script   : Analysis — Descriptive statistics, logistic regression,
#            propensity score matching, IPTW
# Requires : mimic_iac_cohort.R must be run first (produces final_cohort_v3)
# Author   : Ousmane Diallo, MPH-PhD
# =============================================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(gtsummary)
library(MatchIt)
library(WeightIt)
library(cobalt)
library(survey)
library(broom)

# =============================================================================
# SECTION 1: DESCRIPTIVE ANALYSIS — TABLE 1
# =============================================================================

# -----------------------------------------------------------------------------
# 1A. Baseline characteristics by IAC exposure (standard Table 1)
# -----------------------------------------------------------------------------
# Continuous variables: median (IQR)
# Categorical variables: n (%)
# Statistical tests added via add_p() — for descriptive purposes only;
# balance should be formally assessed via SMD (see Section 1B).

table1 <- tbl_summary(
  final_cohort_v3,
  include = c(age, gender, insurance_grp, icu_type,
              charlson_score, adm_type_grp, ethnicity_grp),
  by      = iac_exposed_re,
  missing = "no",
  label   = list(
    age           ~ "Age (years)",
    gender        ~ "Sex",
    charlson_score ~ "Charlson comorbidity index",
    icu_type      ~ "ICU type",
    ethnicity_grp ~ "Ethnic group",
    insurance_grp ~ "Insurance",
    adm_type_grp  ~ "Admission type"
  )
) |>
  add_n() |>                                  # total non-missing per variable
  add_p() |>                                  # p-value for group difference
  modify_header(label = "**Variable**") |>
  bold_labels()

table1

# -----------------------------------------------------------------------------
# 1B. Standardized Mean Differences (SMD) — covariate balance at baseline
# -----------------------------------------------------------------------------
# SMD is the preferred balance metric in propensity score analyses.
# Threshold: |SMD| < 0.10 indicates acceptable balance (Austin 2009).
# Reported alongside Table 1 as per protocol §7 (descriptive analysis).

table1_smd <- final_cohort_v3 |>
  dplyr::select(age, gender, charlson_score, icu_type,
                insurance_grp, adm_type_grp, ethnicity_grp,
                death_28d, iac_exposed_re) |>
  tbl_summary(
    by = iac_exposed_re,
    label = list(
      age           ~ "Age (years)",
      gender        ~ "Sex",
      charlson_score ~ "Charlson comorbidity index",
      icu_type      ~ "ICU type",
      insurance_grp ~ "Insurance",
      adm_type_grp  ~ "Admission type",
      ethnicity_grp ~ "Ethnic group",
      death_28d     ~ "28-day mortality"
    ),
    statistic = list(
      all_continuous()  ~ "{median} ({p25}, {p75})",
      all_categorical() ~ "{n} ({p}%)"
    ),
    missing = "no"
  ) |>
  add_difference(
    test = list(
      all_continuous()  ~ "smd",
      all_categorical() ~ "smd"
    )
  ) |>
  modify_header(estimate ~ "**SMD**") |>
  bold_labels()

table1_smd

# =============================================================================
# SECTION 2: PRIMARY ANALYSIS — MULTIVARIABLE LOGISTIC REGRESSION
# =============================================================================
# Outcome  : 28-day all-cause mortality (binary)
# Exposure : early IAC (No-IAC = reference)
# Covariates: age (per 10 years), sex, Charlson score, ICU type,
#             insurance, admission type, ethnicity
# Results reported as adjusted odds ratios (aOR) with 95% CI.

fit_logistic <- glm(
  death_28d ~ iac_exposed_re + age10 + gender + charlson_score +
    icu_type + insurance_grp + adm_type_grp + ethnicity_grp,
  family = binomial,
  data   = final_cohort_v3
)

summary(fit_logistic)

# Odds ratios with 95% CI and p-values
questionr::odds.ratio(fit_logistic)

# -----------------------------------------------------------------------------
# Forest plot — logistic regression coefficients
# -----------------------------------------------------------------------------

g_logistic <- ggstats::ggcoef_model(
  fit_logistic,
  exponentiate = TRUE,
  variable_labels = c(
    age10          = "Age (per 10 years)",
    iac_exposed_re = "Early IAC exposure",
    gender         = "Sex",
    charlson_score = "Charlson comorbidity index",
    icu_type       = "ICU type",
    insurance_grp  = "Insurance",
    adm_type_grp   = "Admission type",
    ethnicity_grp  = "Ethnic group"
  ),
  no_reference_row          = broom.helpers::all_categorical(),
  categorical_terms_pattern = "{level}/{reference_level}"
)

ggplot2::ggsave(
  filename = "coef_forest_logistic.png",
  plot     = g_logistic,
  device   = "png",
  width    = 10,
  height   = 7,
  dpi      = 300,
  bg       = "white"
)

# =============================================================================
# SECTION 3: PROPENSITY SCORE MATCHING (PSM)
# =============================================================================
# Method  : 1:1 nearest neighbor matching on logistic PS (distance = "glm")
# Caliper : 0.2 SD of the logit of the PS (standard recommendation)
# Replace : FALSE (matching without replacement)
# Covariates used to estimate PS: same as logistic regression model
# Reference: Stuart (2010), MatchIt documentation

# Ensure exposure is a factor with correct reference level
final_cohort_v3 <- final_cohort_v3 |>
  dplyr::mutate(
    iac_exposed_re = relevel(as.factor(iac_exposed_re), ref = "No-IAC")
  )

# -----------------------------------------------------------------------------
# 3A. Fit PS matching model
# -----------------------------------------------------------------------------

match_obj <- matchit(
  iac_exposed_re ~ age + gender + charlson_score + icu_type +
    insurance_grp + adm_type_grp + ethnicity_grp,
  data     = final_cohort_v3,
  method   = "nearest",
  distance = "glm",      # PS estimated via logistic regression
  ratio    = 1,          # 1:1 matching
  replace  = FALSE,      # without replacement
  caliper  = 0.2         # 0.2 SD of logit PS
)

# Matching summary: number matched, unmatched, balance
summary(match_obj)

# -----------------------------------------------------------------------------
# 3B. Extract matched dataset and run outcome model
# -----------------------------------------------------------------------------

matched_data <- match.data(match_obj) |>
  dplyr::mutate(age10 = age / 10)

# Logistic regression in matched sample (doubly robust: PS + covariate adjustment)
fit_psm <- glm(
  death_28d ~ iac_exposed_re + age10 + gender + charlson_score +
    icu_type + insurance_grp + adm_type_grp + ethnicity_grp,
  family = binomial,
  data   = matched_data
)

summary(fit_psm)

# Forest plot — PS-matched model
g_psm <- ggstats::ggcoef_model(
  fit_psm,
  exponentiate = TRUE,
  variable_labels = c(
    age10          = "Age (per 10 years)",
    iac_exposed_re = "Early IAC exposure",
    gender         = "Sex",
    charlson_score = "Charlson comorbidity index",
    icu_type       = "ICU type",
    insurance_grp  = "Insurance",
    adm_type_grp   = "Admission type",
    ethnicity_grp  = "Ethnic group"
  ),
  no_reference_row          = broom.helpers::all_categorical(),
  categorical_terms_pattern = "{level}/{reference_level}"
)

ggplot2::ggsave(
  filename = "coef_forest_psm.png",
  plot     = g_psm,
  device   = "png",
  width    = 10,
  height   = 7,
  dpi      = 300,
  bg       = "white"
)

# =============================================================================
# SECTION 4: INVERSE PROBABILITY OF TREATMENT WEIGHTING (IPTW)
# =============================================================================
# Estimand : Average Treatment Effect (ATE)
#            — generalizes to the full analytical population
# Method   : PS estimated via logistic regression (WeightIt, method = "ps")
# Weights  : stabilized ATE weights (WeightIt default)
# SE       : robust sandwich SE via survey::svyglm (quasibinomial family)
# Reference: Hernán & Robins (2020), WeightIt documentation

# -----------------------------------------------------------------------------
# 4A. Estimate IPTW weights
# -----------------------------------------------------------------------------

w_out <- weightit(
  iac_exposed_re ~ age + gender + charlson_score + icu_type +
    insurance_grp + adm_type_grp + ethnicity_grp,
  data     = final_cohort_v3,
  method   = "ps",    # propensity score via logistic regression
  estimand = "ATE"    # average treatment effect
)

summary(w_out)

# Attach weights to dataset
final_cohort_v3 <- final_cohort_v3 |>
  dplyr::mutate(w_iptw = w_out$weights)

# -----------------------------------------------------------------------------
# 4B. Weight diagnostics
# -----------------------------------------------------------------------------

summary(final_cohort_v3$w_iptw)
quantile(final_cohort_v3$w_iptw,
         probs = c(.01, .05, .10, .50, .90, .95, .99),
         na.rm = TRUE)

# Visual check: weight distribution should not have extreme outliers
hist(final_cohort_v3$w_iptw,
     breaks = 50,
     main   = "IPTW weight distribution (ATE)",
     xlab   = "Weight")

# Truncation at 1st–99th percentile to reduce influence of extreme weights
# NOTE: truncation introduces bias; use only if extreme weights are present
w_lo <- quantile(final_cohort_v3$w_iptw, 0.01, na.rm = TRUE)
w_hi <- quantile(final_cohort_v3$w_iptw, 0.99, na.rm = TRUE)

final_cohort_v3 <- final_cohort_v3 |>
  dplyr::mutate(
    w_iptw_trunc = pmin(pmax(w_iptw, w_lo), w_hi)
  )

# -----------------------------------------------------------------------------
# 4C. Balance diagnostics after weighting
# -----------------------------------------------------------------------------

bt_w <- bal.tab(w_out, un = TRUE, disp.v.ratio = FALSE, binary = "std")
bt_w

# Quick Love plot via cobalt (aggregated, 1 row per variable)
love.plot(
  w_out,
  stats        = "mean.diffs",
  abs          = TRUE,
  threshold    = 0.10,
  var.order    = "unadjusted",
  drop.distance = TRUE,
  sample.names = c("Before weighting", "After weighting"),
  aggregate    = "max"
)

# -----------------------------------------------------------------------------
# 4D. IPTW outcome model (robust SE via survey design)
# -----------------------------------------------------------------------------

des_iptw <- svydesign(
  ids     = ~1,
  weights = ~w_iptw,   # use w_iptw_trunc if truncation applied
  data    = final_cohort_v3
)

fit_iptw <- svyglm(
  death_28d ~ iac_exposed_re + age + gender + charlson_score +
    icu_type + insurance_grp + adm_type_grp + ethnicity_grp,
  design = des_iptw,
  family = quasibinomial()   # robust to weight-induced overdispersion
)

summary(fit_iptw)

# Odds ratios with 95% CI
or_iptw <- broom::tidy(fit_iptw, conf.int = TRUE, exponentiate = TRUE)
or_iptw

# Forest plot — IPTW model
g_iptw <- ggstats::ggcoef_model(
  fit_iptw,
  exponentiate = TRUE,
  variable_labels = c(
    age            = "Age (years)",
    iac_exposed_re = "Early IAC exposure",
    gender         = "Sex",
    charlson_score = "Charlson comorbidity index",
    icu_type       = "ICU type",
    insurance_grp  = "Insurance",
    adm_type_grp   = "Admission type",
    ethnicity_grp  = "Ethnic group"
  ),
  no_reference_row          = broom.helpers::all_categorical(),
  categorical_terms_pattern = "{level}/{reference_level}"
)

ggplot2::ggsave(
  filename = "coef_forest_iptw.png",
  plot     = g_iptw,
  device   = "png",
  width    = 10,
  height   = 7,
  dpi      = 300,
  bg       = "white"
)

# =============================================================================
# SECTION 5: COMBINED LOVE PLOT — Unadjusted vs PSM vs IPTW
# =============================================================================
# Displays covariate balance across all three analytical approaches in one plot.
# Each variable is represented by its maximum |SMD| across dummy indicators.
# Reference line at |SMD| = 0.10 (acceptable balance threshold).

# -----------------------------------------------------------------------------
# 5A. Extract balance tables
# -----------------------------------------------------------------------------

b_m <- bal.tab(match_obj, un = TRUE)   # PS matching balance
b_w <- bal.tab(w_out,     un = TRUE)   # IPTW balance

# -----------------------------------------------------------------------------
# 5B. Helper function: reshape balance table → long format (1 row per variable)
# -----------------------------------------------------------------------------
# For categorical variables with multiple dummies, takes the maximum |SMD|
# as the representative balance statistic for that variable.

balance_to_long <- function(bt, method_label) {
  bt$Balance |>
    tibble::rownames_to_column("term") |>
    # Supprimer les lignes parasites
    dplyr::filter(
      !is.na(term),
      term != "",
      term != "distance",
      term != "(Intercept)"
    ) |>
    dplyr::transmute(
      term,
      smd_un  = Diff.Un,
      smd_adj = Diff.Adj,
      base_var = dplyr::case_when(
        grepl("^icu_type",      term) ~ "ICU type",
        grepl("^insurance_grp", term) ~ "Insurance",
        grepl("^adm_type_grp",  term) ~ "Admission type",
        grepl("^ethnicity_grp", term) ~ "Ethnic group",
        grepl("^gender",        term) ~ "Sex",
        term == "age"                 ~ "Age (years)",
        term == "charlson_score"      ~ "Charlson score",
        TRUE                          ~ NA_character_   # ← exclure tout le reste
      )
    ) |>
    dplyr::filter(!is.na(base_var)) |>        # ← supprimer les non-mappés
    dplyr::group_by(base_var) |>
    dplyr::summarise(
      Unadjusted = max(abs(smd_un),  na.rm = TRUE),
      Adjusted   = max(abs(smd_adj), na.rm = TRUE),
      .groups    = "drop"
    ) |>
    tidyr::pivot_longer(
      cols      = c(Unadjusted, Adjusted),
      names_to  = "sample",
      values_to = "smd"
    ) |>
    dplyr::mutate(method = method_label)
}
# -----------------------------------------------------------------------------
# 5C. Build combined dataset (Unadjusted + PSM adjusted + IPTW adjusted)
# -----------------------------------------------------------------------------

bal_match <- balance_to_long(b_m, "PS matching")
bal_iptw  <- balance_to_long(b_w, "IPTW")

# Unadjusted is identical for both methods — keep one copy
bal_unadj <- bal_match |>
  dplyr::filter(sample == "Unadjusted") |>
  dplyr::mutate(method = "Unadjusted")

bal_plot <- dplyr::bind_rows(
  bal_unadj,
  bal_match |> dplyr::filter(sample == "Adjusted"),
  bal_iptw  |> dplyr::filter(sample == "Adjusted")
) |>
  dplyr::mutate(sample = method) |>
  dplyr::select(base_var, smd, sample)

# Order variables from worst to best balance (unadjusted)
var_order <- bal_unadj |>
  dplyr::arrange(smd) |>
  dplyr::pull(base_var)

bal_plot <- bal_plot |>
  dplyr::mutate(base_var = factor(base_var, levels = var_order))

# -----------------------------------------------------------------------------
# 5D. Combined Love plot
# -----------------------------------------------------------------------------

g_love <- ggplot2::ggplot(
  bal_plot,
  aes(x = smd, y = base_var, color = sample, shape = sample)
) +
  geom_point(size = 3) +
  geom_vline(xintercept = 0.1, linetype = "dashed", color = "grey40") +
  scale_x_continuous(
    limits = c(0, 0.40),
    breaks = c(0, 0.10, 0.20, 0.30, 0.40),
    labels = c("0", "0.10", "0.20", "0.30", "0.40")
  ) +
  scale_color_manual(values = c(
    "Unadjusted"  = "#E41A1C",
    "PS matching" = "#377EB8",
    "IPTW"        = "#4DAF4A"
  )) +
  scale_shape_manual(values = c(
    "Unadjusted"  = 15,   # carré
    "PS matching" = 17,   # triangle
    "IPTW"        = 16    # cercle
  )) +
  labs(
    x        = "Absolute Standardized Mean Difference (|SMD|)",
    y        = "",
    title    = "Covariate balance: Unadjusted vs PS matching vs IPTW",
    subtitle = "Acceptable balance threshold: |SMD| < 0.10",
    color    = "Method",
    shape    = "Method"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    panel.grid.minor = element_blank(),
    legend.position  = "right"
  )


ggplot2::ggsave(
  filename = "love_plot_combined.png",
  plot     = g_love,
  device   = "png",
  width    = 10,
  height   = 7,
  dpi      = 300,
  bg       = "white"
)
