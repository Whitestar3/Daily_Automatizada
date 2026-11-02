-- Nodo n8n: BBDD_CALIDAD

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
SLA_D AS (
  SELECT
    DATE_TRUNC(DATE(START_DATE), WEEK(SUNDAY))            AS semana_inicio,
    SUM(NUMERATOR)                                        AS SLA_NUMERATOR,
    SUM(DENOMINATOR)                                      AS SLA_DENOMINATOR,
    SAFE_DIVIDE(SUM(NUMERATOR), SUM(DENOMINATOR))         AS SLA_PCT
  FROM `your-project.source.INBOUND_SLA`
  WHERE WAREHOUSE_ID = 'CD-01'
    AND DATE(START_DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND DATE(START_DATE) < CURRENT_DATE()
  GROUP BY 1
),
REA_D AS (
  SELECT
    DATE_TRUNC(DATE(R.FECHA_REAPERTURA), WEEK(SUNDAY))    AS semana_inicio,
    SUM(IF(R.ESTADO_EXC = 'FUERA DE 48h', 1, 0))         AS REAPERTURAS_FUERA_SLA,
    MAX(I.INB)                                            AS INB_TOTALES,
    SAFE_DIVIDE(
      SUM(IF(R.ESTADO_EXC = 'FUERA DE 48h', 1, 0)),
      MAX(I.INB)
    )                                                     AS PCT_REAPERTURAS
  FROM `your-project.cx.REOPENINGS` R
  LEFT JOIN (
    SELECT
      DATE_TRUNC(DATE(INB_RECEIVED_DATETIME), WEEK(SUNDAY)) AS semana_inicio,
      COUNT(DISTINCT INBOUND_ID)                            AS INB
    FROM `your-project.cx.INBOUND_CONTACTS_AGG`
    WHERE WAREHOUSE = 'CD-01'
      AND DATE(INB_RECEIVED_DATETIME) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    GROUP BY 1
  ) I ON I.semana_inicio = DATE_TRUNC(DATE(R.FECHA_REAPERTURA), WEEK(SUNDAY))
  WHERE R.WAREHOUSE = 'CD-01'
    AND DATE(R.FECHA_REAPERTURA) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND DATE(R.FECHA_REAPERTURA) < CURRENT_DATE()
    AND R.ESTADO_EXC = 'FUERA DE 48h'
  GROUP BY 1
),
DPMO_CRUCE_D AS (
  SELECT
    DATE_TRUNC(DATE(d.DATE_FINISH), WEEK(SUNDAY))         AS semana_inicio,
    ROUND(SAFE_DIVIDE(COUNT(1), MAX(p.INBOUND_SKU)) * 1000000, 0) AS DPMO_CRUCE
  FROM `your-project.cx.SKU_CLAIMS` d
  LEFT JOIN (
    SELECT
      DATE_TRUNC(DATE(MIN_ARRIVAL_DATETIME_TZ), WEEK(SUNDAY)) AS semana_inicio,
      COUNT(INBOUND_SKU)                                    AS INBOUND_SKU
    FROM `your-project.cx.SKU_PROCESSED`
    WHERE WAREHOUSE = 'CD-01'
    GROUP BY 1
  ) p ON DATE_TRUNC(DATE(d.DATE_FINISH), WEEK(SUNDAY)) = p.semana_inicio
  WHERE d.WAREHOUSE = 'CD-01'
    AND d.CULPABILIDADE = 'ERROR OPERATIVO'
    AND d.CDU_GROUP IN ('CRUCE SKU','CRUCE IS')
    AND DATE(d.DATE_FINISH) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND DATE(d.DATE_FINISH) < CURRENT_DATE()
  GROUP BY 1
),
DPMO_FALT_D AS (
  SELECT
    DATE_TRUNC(DATE(d.DATE_FINISH), WEEK(SUNDAY))         AS semana_inicio,
    ROUND(SAFE_DIVIDE(
      COUNT(IF(d.REASON NOT IN ('SIN REAPERTURA','SIN REAPERTURA - FPP'), d.SKU, NULL)),
      MAX(p.INBOUND_SKU)
    ) * 1000000, 0)                                       AS DPMO_FALTANTE
  FROM `your-project.cx.SKU_CLAIMS` d
  LEFT JOIN (
    SELECT
      DATE_TRUNC(DATE(MIN_ARRIVAL_DATETIME_TZ), WEEK(SUNDAY)) AS semana_inicio,
      COUNT(INBOUND_SKU)                                    AS INBOUND_SKU
    FROM `your-project.cx.SKU_PROCESSED`
    WHERE WAREHOUSE = 'CD-01'
    GROUP BY 1
  ) p ON DATE_TRUNC(DATE(d.DATE_FINISH), WEEK(SUNDAY)) = p.semana_inicio
  WHERE d.WAREHOUSE = 'CD-01'
    AND d.CULPABILIDADE = 'ERROR OPERATIVO'
    AND d.CDU_GROUP = 'FALTANTES'
    AND DATE(d.DATE_FINISH) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND DATE(d.DATE_FINISH) < CURRENT_DATE()
  GROUP BY 1
),
CR_D AS (
  SELECT
    DATE_TRUNC(DATE(DATA_ACONTECIMENTO), WEEK(SUNDAY))    AS semana_inicio,
    SUM(CX_CASE_ID)                                       AS SUM_CX_CASE_ID,
    SUM(ENVIOS)                                           AS SUM_ENVIOS,
    SAFE_DIVIDE(SUM(CX_CASE_ID), SUM(ENVIOS))             AS CONTACT_RATE
  FROM `your-project.cx.CONTACT_RATE`
  WHERE WAREHOUSE = 'CD-01'
    AND DATE(DATA_ACONTECIMENTO) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND DATE(DATA_ACONTECIMENTO) < CURRENT_DATE()
  GROUP BY 1
),
TEO_D AS (
  SELECT
    DATE_TRUNC(DATE, WEEK(SUNDAY))                        AS semana_inicio,
    SAFE_DIVIDE(
      SUM(IF(PROCESS = 'inbound audit', UNITS_TEO_INB, 0)),
      SUM(UNITS_GNP)
    )                                                     AS TEO_INBOUND_AUDIT
  FROM `your-project.source.TEO_SUMMARY`
  WHERE WAREHOUSE_ID = 'CD-01'
    AND SITE_ID = 'MLC'
    AND DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND DATE < CURRENT_DATE()
  GROUP BY 1
),
AUD_D AS (
  SELECT
    DATE_TRUNC(DATE(A.FBM_CREATED_DATE), WEEK(SUNDAY))   AS semana_inicio,
    SUM(A.ERROR_UNITS)                                    AS ERROR_UNITS,
    MAX(P.Unid)                                           AS UNID,
    ROUND(
      SAFE_DIVIDE(SUM(A.ERROR_UNITS), MAX(P.Unid)) * 1000000, 0
    )                                                     AS INBOUND_AUDIT
  FROM `your-project.source.INBOUND_AUDIT` A
  LEFT JOIN (
    SELECT
      DATE_TRUNC(DATE(START_DATE), WEEK(SUNDAY))          AS semana_inicio,
      SUM(UNITS)                                          AS Unid
    FROM `your-project.source.EMPLOYEE_ATTRIBUTES`
    WHERE LOGISTIC_CENTER_ID = 'CD-01'
      AND PROCESS    = 'inbound'
      AND SUBPROCESS = 'putaway'
      AND START_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    GROUP BY 1
  ) P ON P.semana_inicio = DATE_TRUNC(DATE(A.FBM_CREATED_DATE), WEEK(SUNDAY))
  WHERE A.WAREHOUSE_ID = 'CD-01'
    AND DATE(A.FBM_CREATED_DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND DATE(A.FBM_CREATED_DATE) < CURRENT_DATE()
  GROUP BY 1
)
SELECT
  S.semana_fiscal,
  SLA_D.SLA_PCT,
  SLA_D.SLA_NUMERATOR,
  SLA_D.SLA_DENOMINATOR,
  REA_D.REAPERTURAS_FUERA_SLA,
  REA_D.INB_TOTALES,
  REA_D.PCT_REAPERTURAS,
  DPMO_CRUCE_D.DPMO_CRUCE,
  DPMO_FALT_D.DPMO_FALTANTE,
  CR_D.CONTACT_RATE,
  CR_D.SUM_CX_CASE_ID,
  CR_D.SUM_ENVIOS,
  TEO_D.TEO_INBOUND_AUDIT,
  AUD_D.INBOUND_AUDIT
FROM SEMANA S
LEFT JOIN SLA_D        ON SLA_D.semana_inicio        = S.semana_inicio
LEFT JOIN REA_D        ON REA_D.semana_inicio        = S.semana_inicio
LEFT JOIN DPMO_CRUCE_D ON DPMO_CRUCE_D.semana_inicio = S.semana_inicio
LEFT JOIN DPMO_FALT_D  ON DPMO_FALT_D.semana_inicio  = S.semana_inicio
LEFT JOIN CR_D         ON CR_D.semana_inicio         = S.semana_inicio
LEFT JOIN TEO_D        ON TEO_D.semana_inicio        = S.semana_inicio
LEFT JOIN AUD_D        ON AUD_D.semana_inicio        = S.semana_inicio
ORDER BY S.semana_fiscal DESC
