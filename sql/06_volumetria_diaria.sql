-- Nodo n8n: BBDD_VOLUMETRIA_DIARIO

WITH
SEMANA AS (
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
),
SKU AS (
  SELECT
    INVENTORY_ID,
    CASE WHEN FLAG_TOTABLE = TRUE THEN 'TOTEABLE' ELSE 'NO TOTEABLE' END   AS FLAG_TOTEABLE,
    COALESCE(
      ITE_VOLUMEN,
      CASE
        WHEN ITE_HEIGHT > 0 AND ITE_LENGTH > 0 AND ITE_WIDTH > 0
        THEN ITE_HEIGHT * ITE_LENGTH * ITE_WIDTH / 1000.0
        ELSE NULL
      END
    )                                                                       AS V_LITROS
  FROM `your-project.source.SKU_DETAILS`
  WHERE LOGISTIC_CENTER_ID = 'CD-01'
    AND SIT_SITE_ID        = 'MLC'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY INVENTORY_ID
    ORDER BY (ITE_VOLUMEN IS NOT NULL) DESC, (ITE_HEIGHT IS NOT NULL) DESC
  ) = 1
),
OPS AS (
  SELECT DISTINCT
    CAST(OPERATOR_ID AS STRING)  AS OPERATOR_ID,
    DATE(START_DATE)             AS FECHA,
    PROCESS                      AS PROCESO
  FROM `your-project.source.OPERATOR_PRODUCTIVITY`
  WHERE AREA               = 'inbound'
    AND PROCESS            IN ('checkin','direct_checkin')
    AND LOGISTIC_CENTER_ID = 'CD-01'
    AND DATE(START_DATE)   >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND DATE(START_DATE)   < CURRENT_DATE()
),
VOL_CHK AS (
  SELECT
    'checkin'                                                               AS PROCESO,
    DATE(`your-project.udf.FN_TIMEZONE`('MLC', m.AUD_INS_DTTM)) AS FECHA,
    ROUND(SUM(m.FBM_QUANTITY * s.V_LITROS), 1)                             AS VOL_L_TOTAL,
    ROUND(SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'TOTEABLE',
      m.FBM_QUANTITY * s.V_LITROS, NULL)), 1)                              AS VOL_L_TOTEABLE,
    ROUND(SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'NO TOTEABLE',
      m.FBM_QUANTITY * s.V_LITROS, NULL)), 1)                              AS VOL_L_NO_TOTEABLE,
    SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'TOTEABLE',
      m.FBM_QUANTITY, 0))                                                  AS UDS_TOTEABLE,
    SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'NO TOTEABLE',
      m.FBM_QUANTITY, 0))                                                  AS UDS_NO_TOTEABLE,
    SUM(m.FBM_QUANTITY)                                                    AS UDS_TOTALES
  FROM `your-project.source.STOCK_MOVEMENTS` m
  INNER JOIN OPS ops
    ON  ops.OPERATOR_ID = CAST(m.FBM_USER_ID AS STRING)
    AND ops.FECHA = DATE(`your-project.udf.FN_TIMEZONE`('MLC', m.AUD_INS_DTTM))
    AND ops.PROCESO = 'checkin'
  LEFT JOIN SKU s ON s.INVENTORY_ID = m.INVENTORY_ID
  WHERE m.WAREHOUSE_ID       = 'CD-01'
    AND m.FBM_REASON_PROCESS = 'inbound'
    AND m.ADDRESS_FROM       IS NULL
    AND m.ADDRESS_TO         LIKE 'MU-%'
    AND m.AUD_INS_DTTM >= DATETIME(TIMESTAMP(DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY), 'America/Santiago'))
    AND m.AUD_INS_DTTM <  DATETIME(TIMESTAMP(CURRENT_DATE(), 'America/Santiago'))
  GROUP BY FECHA
),
VOL_DCI AS (
  SELECT
    'direct_checkin'                                                        AS PROCESO,
    DATE(`your-project.udf.FN_TIMEZONE`('MLC', m.AUD_INS_DTTM)) AS FECHA,
    ROUND(SUM(m.FBM_QUANTITY * s.V_LITROS), 1)                             AS VOL_L_TOTAL,
    ROUND(SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'TOTEABLE',
      m.FBM_QUANTITY * s.V_LITROS, NULL)), 1)                              AS VOL_L_TOTEABLE,
    ROUND(SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'NO TOTEABLE',
      m.FBM_QUANTITY * s.V_LITROS, NULL)), 1)                              AS VOL_L_NO_TOTEABLE,
    SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'TOTEABLE',
      m.FBM_QUANTITY, 0))                                                  AS UDS_TOTEABLE,
    SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'NO TOTEABLE',
      m.FBM_QUANTITY, 0))                                                  AS UDS_NO_TOTEABLE,
    SUM(m.FBM_QUANTITY)                                                    AS UDS_TOTALES
  FROM `your-project.source.STOCK_MOVEMENTS` m
  INNER JOIN OPS ops
    ON  ops.OPERATOR_ID = CAST(m.FBM_USER_ID AS STRING)
    AND ops.FECHA = DATE(`your-project.udf.FN_TIMEZONE`('MLC', m.AUD_INS_DTTM))
    AND ops.PROCESO = 'direct_checkin'
  LEFT JOIN SKU s ON s.INVENTORY_ID = m.INVENTORY_ID
  WHERE m.WAREHOUSE_ID       = 'CD-01'
    AND m.FBM_REASON_PROCESS = 'inbound'
    AND m.ADDRESS_FROM       IS NULL
    AND m.ADDRESS_TO         LIKE 'MU-%'
    AND m.AUD_INS_DTTM >= DATETIME(TIMESTAMP(DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY), 'America/Santiago'))
    AND m.AUD_INS_DTTM <  DATETIME(TIMESTAMP(CURRENT_DATE(), 'America/Santiago'))
  GROUP BY FECHA
),
VOL_PA AS (
  SELECT
    'putaway'                                                               AS PROCESO,
    DATE(m.FBM_CREATED_DATE)                                               AS FECHA,
    ROUND(SUM(m.FBM_QUANTITY * s.V_LITROS), 1)                             AS VOL_L_TOTAL,
    ROUND(SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'TOTEABLE',
      m.FBM_QUANTITY * s.V_LITROS, NULL)), 1)                              AS VOL_L_TOTEABLE,
    ROUND(SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'NO TOTEABLE',
      m.FBM_QUANTITY * s.V_LITROS, NULL)), 1)                              AS VOL_L_NO_TOTEABLE,
    SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'TOTEABLE',
      m.FBM_QUANTITY, 0))                                                  AS UDS_TOTEABLE,
    SUM(IF(IFNULL(s.FLAG_TOTEABLE,'NO TOTEABLE') = 'NO TOTEABLE',
      m.FBM_QUANTITY, 0))                                                  AS UDS_NO_TOTEABLE,
    SUM(m.FBM_QUANTITY)                                                    AS UDS_TOTALES
  FROM `your-project.source.STOCK_MOVEMENTS` m
  LEFT JOIN SKU s ON s.INVENTORY_ID = m.INVENTORY_ID
  WHERE m.WAREHOUSE_ID       = 'CD-01'
    AND m.FBM_REASON_PROCESS = 'put_away'
    AND DATE(m.FBM_CREATED_DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND DATE(m.FBM_CREATED_DATE) <  CURRENT_DATE()
    AND m.FBM_QUANTITY > 0
  GROUP BY FECHA
),
VOL_ALL AS (
  SELECT * FROM VOL_CHK
  UNION ALL
  SELECT * FROM VOL_DCI
  UNION ALL
  SELECT * FROM VOL_PA
)
SELECT
  S.semana_fiscal,
  V.FECHA,
  V.PROCESO,
  V.UDS_TOTALES,
  V.UDS_TOTEABLE,
  V.UDS_NO_TOTEABLE,
  V.VOL_L_TOTAL,
  V.VOL_L_TOTEABLE,
  V.VOL_L_NO_TOTEABLE,
  ROUND(SAFE_DIVIDE(V.UDS_TOTEABLE, V.UDS_TOTALES) * 100, 1)              AS PCT_TOTEABLE,
  ROUND(SAFE_DIVIDE(V.VOL_L_TOTAL, V.UDS_TOTALES), 3)                     AS VOL_POND_TOTAL
FROM VOL_ALL V
JOIN SEMANA S
  ON V.FECHA BETWEEN S.semana_inicio AND S.semana_fin
ORDER BY V.FECHA DESC, V.PROCESO
