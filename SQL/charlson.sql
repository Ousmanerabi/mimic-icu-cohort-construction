WITH hadm AS (
  SELECT DISTINCT hadm_id
  FROM tmp_hadm
),
dx AS (
  SELECT d.hadm_id, d.icd9_code
  FROM public.diagnoses_icd d
  JOIN hadm h ON h.hadm_id = d.hadm_id
),
flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN icd9_code ~ '^(410|412)' THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN icd9_code ~ '^(428)' THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN icd9_code ~ '^(490|491|492|493|494|495|496)' THEN 1 ELSE 0 END) AS copd,
    MAX(CASE WHEN icd9_code ~ '^(250[0-3])' THEN 1 ELSE 0 END) AS dm,
    MAX(CASE WHEN icd9_code ~ '^(250[4-9])' THEN 1 ELSE 0 END) AS dm_comp,
    MAX(CASE WHEN icd9_code ~ '^(585)' THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN icd9_code ~ '^(571|572)' THEN 1 ELSE 0 END) AS liver,
    MAX(CASE WHEN icd9_code ~ '^(140|141|142|143|144|145|146|147|148|149|150|151|152|153|154|155|156|157|158|159|160|161|162|163|164|165|166|167|168|169|170|171|172|174|175|176|177|178|179|180|181|182|183|184|185|186|187|188|189|190|191|192|193|194|195|196|197|198|199)' THEN 1 ELSE 0 END) AS cancer,
    MAX(CASE WHEN icd9_code ~ '^(042|043|044)' THEN 1 ELSE 0 END) AS hiv
  FROM dx
  GROUP BY hadm_id
)
SELECT
  hadm_id,
  ( 1*COALESCE(mi,0)
  + 1*COALESCE(chf,0)
  + 1*COALESCE(copd,0)
  + 1*COALESCE(dm,0)
  + 2*COALESCE(dm_comp,0)
  + 2*COALESCE(renal,0)
  + 2*COALESCE(liver,0)
  + 2*COALESCE(cancer,0)
  + 6*COALESCE(hiv,0)
  ) AS charlson_score
FROM flags;
