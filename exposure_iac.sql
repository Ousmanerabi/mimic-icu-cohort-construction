WITH base AS (
  SELECT *
  FROM tmp_cohort_mv
),
iac AS (
  SELECT
    b.icustay_id,
    MIN(pe.starttime) AS iac_time
  FROM base b
  JOIN public.procedureevents_mv pe
    ON pe.icustay_id = b.icustay_id
  WHERE pe.itemid = 225752
    AND pe.starttime IS NOT NULL
  GROUP BY b.icustay_id
)
SELECT
  b.icustay_id,
  i.iac_time,
  CASE
    WHEN b.mv_start IS NULL THEN 0
    WHEN i.iac_time IS NOT NULL
     AND i.iac_time >= b.mv_start
     AND i.iac_time <  b.mv_start + interval '24 hours'
    THEN 1 ELSE 0
  END AS iac_exposed
FROM base b
LEFT JOIN iac i
  ON b.icustay_id = i.icustay_id;
