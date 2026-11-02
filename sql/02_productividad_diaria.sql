-- Nodo n8n: BBDD_PRODUCTIVIDAD_DIARIO

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
  DATE(L.START_DATE)                                                       AS FECHA,

  -- INP = unidades putaway / NET_HH TOTAL del area inbound
  SAFE_DIVIDE(
    SUM(IF(L.PROCESS = 'putaway', L.UNITS, 0)),
    SUM(L.TIEMPO_SISTEMICO + L.TIEMPO_NO_SISTEMICO + L.TND + L.EXTENDED_IDLE_TIME)
  )                                                                         AS INP,

  -- Unidades CH + DCI
  SUM(IF(L.PROCESS IN ('checkin','direct_checkin'), L.UNITS, 0))           AS UNID_CH_DCI,

  -- Unidades Putaway
  SUM(IF(L.PROCESS = 'putaway', L.UNITS, 0))                               AS UNID_PUTAWAY,

  -- Neta Receiving
  SAFE_DIVIDE(
    SUM(IF(L.PROCESS = 'receiving', L.UNITS, 0)),
    SUM(IF(L.PROCESS = 'receiving',
      L.TIEMPO_SISTEMICO + L.TIEMPO_NO_SISTEMICO + L.TND + L.EXTENDED_IDLE_TIME, 0))
  )                                                                         AS NETA_RECEIVING,

  -- Neta Checkin
  SAFE_DIVIDE(
    SUM(IF(L.PROCESS = 'checkin', L.UNITS, 0)),
    SUM(IF(L.PROCESS = 'checkin',
      L.TIEMPO_SISTEMICO + L.TIEMPO_NO_SISTEMICO + L.TND + L.EXTENDED_IDLE_TIME, 0))
  )                                                                         AS NETA_CHECKIN,

  -- Neta DCI
  SAFE_DIVIDE(
    SUM(IF(L.PROCESS = 'direct_checkin', L.UNITS, 0)),
    SUM(IF(L.PROCESS = 'direct_checkin',
      L.TIEMPO_SISTEMICO + L.TIEMPO_NO_SISTEMICO + L.TND + L.EXTENDED_IDLE_TIME, 0))
  )                                                                         AS NETA_DCI,

  -- Neta Putaway
  SAFE_DIVIDE(
    SUM(IF(L.PROCESS = 'putaway', L.UNITS, 0)),
    SUM(IF(L.PROCESS = 'putaway',
      L.TIEMPO_SISTEMICO + L.TIEMPO_NO_SISTEMICO + L.TND + L.EXTENDED_IDLE_TIME, 0))
  )                                                                         AS NETA_PUTAWAY,

  -- TPH CH + DCI
  SAFE_DIVIDE(
    SUM(IF(L.PROCESS IN ('checkin','direct_checkin'), L.UNITS, 0)),
    SUM(IF(L.PROCESS IN ('checkin','direct_checkin'),
      L.TIEMPO_SISTEMICO + L.TIEMPO_NO_SISTEMICO + L.TND + L.EXTENDED_IDLE_TIME, 0))
  )                                                                         AS TPH_CH_DCI,

  -- TPH Putaway
  SAFE_DIVIDE(
    SUM(IF(L.PROCESS = 'putaway', L.UNITS, 0)),
    SUM(IF(L.PROCESS = 'putaway',
      L.TIEMPO_SISTEMICO + L.TIEMPO_NO_SISTEMICO + L.TND + L.EXTENDED_IDLE_TIME, 0))
  )                                                                         AS TPH_PUTAWAY,

  -- Share DCI
  SAFE_DIVIDE(
    SUM(IF(L.PROCESS = 'direct_checkin', L.UNITS, 0)),
    SUM(IF(L.PROCESS IN ('checkin','direct_checkin'), L.UNITS, 0))
  ) * 100                                                                   AS SHARE_DCI,

  -- Targets
  MAX(IF(L.PROCESS = 'putaway',        L.TARGET_AREA_PNET,                NULL)) AS TARGET_INP,
  MAX(IF(L.PROCESS = 'receiving',      L.TARGET_PROCESS_NET_PRODUCTIVITY,  NULL)) AS TARGET_NETA_RECEIVING,
  MAX(IF(L.PROCESS = 'checkin',        L.TARGET_PROCESS_NET_PRODUCTIVITY,  NULL)) AS TARGET_NETA_CHECKIN,
  MAX(IF(L.PROCESS = 'direct_checkin', L.TARGET_PROCESS_NET_PRODUCTIVITY,  NULL)) AS TARGET_NETA_DCI,
  MAX(IF(L.PROCESS = 'putaway',        L.TARGET_PROCESS_NET_PRODUCTIVITY,  NULL)) AS TARGET_NETA_PUTAWAY

FROM `your-project.source.OPERATOR_PRODUCTIVITY` L
JOIN SEMANA S
  ON DATE(L.START_DATE) BETWEEN S.semana_inicio AND S.semana_fin
WHERE L.LOGISTIC_CENTER_ID = 'CD-01'
  AND L.AREA = 'inbound'
  AND DATE(L.START_DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
  AND DATE(L.START_DATE) < CURRENT_DATE()
GROUP BY S.semana_fiscal, FECHA
ORDER BY FECHA DESC
