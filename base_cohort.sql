WITH co AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.icustay_id,
    icu.intime,
    icu.outtime,
    EXTRACT(EPOCH FROM (icu.outtime - icu.intime))/60.0/60.0/24.0 AS icu_length_of_stay,
    EXTRACT(EPOCH FROM (icu.intime - pat.dob))/60.0/60.0/24.0/365.242 AS age,
    RANK() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS icustay_id_order
  FROM public.icustays icu
  JOIN public.patients pat
    ON icu.subject_id = pat.subject_id
),
serv AS (
  SELECT
    icu.hadm_id,
    icu.icustay_id,
    se.curr_service,
    CASE
      WHEN se.curr_service LIKE '%SURG' THEN 1
      WHEN se.curr_service = 'ORTHO' THEN 1
      ELSE 0
    END AS surgical,
    RANK() OVER (PARTITION BY icu.hadm_id ORDER BY se.transfertime DESC) AS rnk
  FROM public.icustays icu
  LEFT JOIN public.services se
    ON icu.hadm_id = se.hadm_id
   AND se.transfertime < icu.intime + interval '12 hour'
)
SELECT
  co.*,
  CASE WHEN co.icu_length_of_stay < 2 THEN 1 ELSE 0 END AS exclusion_los,
  CASE WHEN co.age < 16 THEN 1 ELSE 0 END AS exclusion_age,
  CASE WHEN co.icustay_id_order <> 1 THEN 1 ELSE 0 END AS exclusion_first_stay,
  CASE WHEN COALESCE(s.surgical,0) = 1 THEN 1 ELSE 0 END AS exclusion_surgical
FROM co
LEFT JOIN serv s
  ON co.icustay_id = s.icustay_id
 AND s.rnk = 1;
