-- Nodo n8n: BBDD_AT

WITH SEMANA AS (
  SELECT
    DATE_TRUNC(d, WEEK(SUNDAY))                                             AS semana_inicio,
    DATE_ADD(DATE_TRUNC(d, WEEK(SUNDAY)), INTERVAL 6 DAY)                  AS semana_fin,
    CONCAT('W', LPAD(CAST(DATE_DIFF(DATE_TRUNC(d, WEEK(SUNDAY)),
      DATE '2025-12-28', WEEK) + 1 AS STRING), 2, '0'),
      '-', CAST(EXTRACT(YEAR FROM d) AS STRING))                           AS semana_fiscal
  FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY), WEEK(SUNDAY)),
    DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)),
    INTERVAL 1 WEEK
  )) AS d
)
SELECT
  S.semana_fiscal,
  DATE(A.START_DATE)                                                        AS FECHA,
  SUM(CASE
    WHEN A.HIRING_DATE = false
    AND A.ROL IN ('rep','team_lead')
    AND A.AT_NET IS NOT NULL
    THEN A.NET_WORK_DURATION ELSE 0
  END)                                                                      AS AT_NUMERADOR,
  SUM(CASE
    WHEN A.HIRING_DATE = false
    AND A.ROL IN ('rep','team_lead')
    AND A.AT_NET IS NOT NULL
    THEN A.TARGET_DURATION ELSE 0
  END)                                                                      AS AT_DENOMINADOR,
  SAFE_DIVIDE(
    SUM(CASE
      WHEN A.HIRING_DATE = false
      AND A.ROL IN ('rep','team_lead')
      AND A.AT_NET IS NOT NULL
      THEN A.NET_WORK_DURATION ELSE 0
    END),
    SUM(CASE
      WHEN A.HIRING_DATE = false
      AND A.ROL IN ('rep','team_lead')
      AND A.AT_NET IS NOT NULL
      THEN A.TARGET_DURATION ELSE 0
    END)
  )                                                                         AS AT_PCT
FROM `your-project.source.AVAILABLE_TIME` A
JOIN SEMANA S
  ON DATE(A.START_DATE) BETWEEN S.semana_inicio AND S.semana_fin
WHERE A.LOGISTIC_CENTER_ID = 'CD-01'
  AND A.AREA               = 'inbound_fbm'
  AND DATE(A.START_DATE)   >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
  AND DATE(A.START_DATE)   < CURRENT_DATE()
GROUP BY ALL
ORDER BY FECHA DESC
