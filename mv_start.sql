WITH co AS (
  SELECT icustay_id, intime, outtime
  FROM tmp_base_cohort
),
mv_proc AS (
  SELECT
    p.icustay_id,
    MIN(p.starttime) AS mv_start_proc
  FROM public.procedureevents_mv p
  JOIN co ON co.icustay_id = p.icustay_id
  WHERE p.itemid IN (224385, 225792)
    AND p.starttime BETWEEN co.intime AND co.outtime
  GROUP BY p.icustay_id
),
mv_chart AS (
  SELECT
    ce.icustay_id,
    MIN(ce.charttime) AS mv_start_chart
  FROM public.chartevents ce
  JOIN co ON co.icustay_id = ce.icustay_id
  WHERE ce.itemid IN (226260, 223849, 720)
    AND ce.charttime BETWEEN co.intime AND co.outtime
    AND ce.value IS NOT NULL
  GROUP BY ce.icustay_id
)
SELECT
  co.icustay_id,
  COALESCE(mv_proc.mv_start_proc, mv_chart.mv_start_chart) AS mv_start
FROM co
LEFT JOIN mv_proc  ON co.icustay_id = mv_proc.icustay_id
LEFT JOIN mv_chart ON co.icustay_id = mv_chart.icustay_id;
