WITH base AS (
  SELECT *
  FROM tmp_cohort_mv
),

-- Vasopressors (0–24h post MV start)
vaso_itemids AS (
  SELECT itemid
  FROM public.d_items
  WHERE linksto IN ('inputevents_mv','inputevents_cv')
    AND (
      lower(label) LIKE '%norepinephrine%' OR lower(label) LIKE '%levophed%'
      OR lower(label) LIKE '%epinephrine%' OR lower(label) LIKE '%adrenaline%'
      OR lower(label) LIKE '%vasopressin%'
      OR lower(label) LIKE '%phenylephrine%' OR lower(label) LIKE '%neosynephrine%'
      OR lower(label) LIKE '%dopamine%'
    )
),
vaso_mv AS (
  SELECT DISTINCT b.icustay_id, 1 AS vaso_24h
  FROM base b
  JOIN public.inputevents_mv ie ON ie.icustay_id = b.icustay_id
  JOIN vaso_itemids vi ON ie.itemid = vi.itemid
  WHERE b.mv_start IS NOT NULL
    AND ie.starttime >= b.mv_start
    AND ie.starttime <  b.mv_start + interval '24 hours'
    AND COALESCE(ie.rate, ie.amount, 0) > 0
),
vaso_cv AS (
  SELECT DISTINCT b.icustay_id, 1 AS vaso_24h
  FROM base b
  JOIN public.inputevents_cv ie ON ie.icustay_id = b.icustay_id
  JOIN vaso_itemids vi ON ie.itemid = vi.itemid
  WHERE b.mv_start IS NOT NULL
    AND ie.charttime >= b.mv_start
    AND ie.charttime <  b.mv_start + interval '24 hours'
    AND COALESCE(ie.rate, ie.amount, 0) > 0
),
vaso AS (
  SELECT icustay_id, 1 AS vaso_24h
  FROM (SELECT * FROM vaso_mv UNION SELECT * FROM vaso_cv) u
),

-- Vitals mapping
vital_map AS (
  SELECT
    itemid,
    CASE
      WHEN lower(label) LIKE '%heart rate%' THEN 'hr'
      WHEN lower(label) LIKE '%mean arterial pressure%' OR lower(label) LIKE '%mean bp%' OR lower(label) LIKE '%map%' THEN 'map'
      WHEN lower(label) LIKE '%temperature%' THEN 'temp'
      WHEN lower(label) LIKE '%o2 saturation%' OR lower(label) LIKE '%spo2%' OR lower(label) LIKE '%oxygen saturation%' THEN 'spo2'
      ELSE NULL
    END AS vital
  FROM public.d_items
  WHERE linksto = 'chartevents'
),

vitals_24h AS (
  SELECT
    b.icustay_id,
    AVG(ce.valuenum) FILTER (WHERE vm.vital='hr')   AS hr_mean_24h,
    MIN(ce.valuenum) FILTER (WHERE vm.vital='hr')   AS hr_min_24h,
    MAX(ce.valuenum) FILTER (WHERE vm.vital='hr')   AS hr_max_24h,

    AVG(ce.valuenum) FILTER (WHERE vm.vital='map')  AS map_mean_24h,
    MIN(ce.valuenum) FILTER (WHERE vm.vital='map')  AS map_min_24h,
    MAX(ce.valuenum) FILTER (WHERE vm.vital='map')  AS map_max_24h,

    AVG(ce.valuenum) FILTER (WHERE vm.vital='temp') AS temp_mean_24h,
    MIN(ce.valuenum) FILTER (WHERE vm.vital='temp') AS temp_min_24h,
    MAX(ce.valuenum) FILTER (WHERE vm.vital='temp') AS temp_max_24h,

    AVG(ce.valuenum) FILTER (WHERE vm.vital='spo2') AS spo2_mean_24h,
    MIN(ce.valuenum) FILTER (WHERE vm.vital='spo2') AS spo2_min_24h,
    MAX(ce.valuenum) FILTER (WHERE vm.vital='spo2') AS spo2_max_24h
  FROM base b
  JOIN public.chartevents ce ON ce.icustay_id = b.icustay_id
  JOIN vital_map vm ON ce.itemid = vm.itemid
  WHERE b.mv_start IS NOT NULL
    AND vm.vital IS NOT NULL
    AND ce.charttime >= b.mv_start
    AND ce.charttime <  b.mv_start + interval '24 hours'
    AND ce.valuenum IS NOT NULL
  GROUP BY b.icustay_id
),

-- Labs mapping
lab_map AS (
  SELECT
    itemid,
    CASE
      WHEN lower(label) = 'ph' THEN 'ph'
      WHEN lower(label) = 'po2' OR lower(label) LIKE '%po2%' THEN 'pao2'
      WHEN lower(label) = 'pco2' OR lower(label) LIKE '%pco2%' THEN 'paco2'
      WHEN lower(label) LIKE '%lactate%' THEN 'lactate'
      WHEN lower(label) LIKE '%sodium%' THEN 'sodium'
      WHEN lower(label) LIKE '%potassium%' THEN 'potassium'
      WHEN lower(label) LIKE '%hematocrit%' THEN 'hematocrit'
      WHEN lower(label) LIKE 'wbc%' OR lower(label) LIKE '%wbc%' THEN 'wbc'
      ELSE NULL
    END AS lab
  FROM public.d_labitems
),

labs_24h AS (
  SELECT
    b.icustay_id,
    AVG(le.valuenum) FILTER (WHERE lm.lab='ph')         AS ph_mean_24h,
    MIN(le.valuenum) FILTER (WHERE lm.lab='ph')         AS ph_min_24h,
    MAX(le.valuenum) FILTER (WHERE lm.lab='ph')         AS ph_max_24h,

    AVG(le.valuenum) FILTER (WHERE lm.lab='pao2')       AS pao2_mean_24h,
    MIN(le.valuenum) FILTER (WHERE lm.lab='pao2')       AS pao2_min_24h,
    MAX(le.valuenum) FILTER (WHERE lm.lab='pao2')       AS pao2_max_24h,

    AVG(le.valuenum) FILTER (WHERE lm.lab='paco2')      AS paco2_mean_24h,
    MIN(le.valuenum) FILTER (WHERE lm.lab='paco2')      AS paco2_min_24h,
    MAX(le.valuenum) FILTER (WHERE lm.lab='paco2')      AS paco2_max_24h,

    AVG(le.valuenum) FILTER (WHERE lm.lab='lactate')    AS lactate_mean_24h,
    MIN(le.valuenum) FILTER (WHERE lm.lab='lactate')    AS lactate_min_24h,
    MAX(le.valuenum) FILTER (WHERE lm.lab='lactate')    AS lactate_max_24h,

    AVG(le.valuenum) FILTER (WHERE lm.lab='sodium')     AS sodium_mean_24h,
    MIN(le.valuenum) FILTER (WHERE lm.lab='sodium')     AS sodium_min_24h,
    MAX(le.valuenum) FILTER (WHERE lm.lab='sodium')     AS sodium_max_24h,

    AVG(le.valuenum) FILTER (WHERE lm.lab='potassium')  AS potassium_mean_24h,
    MIN(le.valuenum) FILTER (WHERE lm.lab='potassium')  AS potassium_min_24h,
    MAX(le.valuenum) FILTER (WHERE lm.lab='potassium')  AS potassium_max_24h,

    AVG(le.valuenum) FILTER (WHERE lm.lab='hematocrit') AS hematocrit_mean_24h,
    MIN(le.valuenum) FILTER (WHERE lm.lab='hematocrit') AS hematocrit_min_24h,
    MAX(le.valuenum) FILTER (WHERE lm.lab='hematocrit') AS hematocrit_max_24h,

    AVG(le.valuenum) FILTER (WHERE lm.lab='wbc')        AS wbc_mean_24h,
    MIN(le.valuenum) FILTER (WHERE lm.lab='wbc')        AS wbc_min_24h,
    MAX(le.valuenum) FILTER (WHERE lm.lab='wbc')        AS wbc_max_24h
  FROM base b
  JOIN public.labevents le ON le.hadm_id = b.hadm_id
  JOIN lab_map lm ON le.itemid = lm.itemid
  WHERE b.mv_start IS NOT NULL
    AND lm.lab IS NOT NULL
    AND le.charttime >= b.mv_start
    AND le.charttime <  b.mv_start + interval '24 hours'
    AND le.valuenum IS NOT NULL
  GROUP BY b.icustay_id
)

SELECT
  b.icustay_id,
  COALESCE(v.vaso_24h,0) AS vaso_24h,
  vit.*,
  lab.*
FROM base b
LEFT JOIN vaso v ON b.icustay_id = v.icustay_id
LEFT JOIN vitals_24h vit ON b.icustay_id = vit.icustay_id
LEFT JOIN labs_24h lab ON b.icustay_id = lab.icustay_id;
