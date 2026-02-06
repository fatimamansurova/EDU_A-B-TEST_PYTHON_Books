-- ==============================================================================
-- АНАЛИТИЧЕСКИЕ SQL‑ЗАПРОСЫ ДЛЯ ПРОЕКТА BOOKMATE
-- Автор: Мансурова Фатима
-- Дата: 2025-11-30
-- СУБД: PostgreSQL
-- ==============================================================================

/*
-------------------------------------------------------------------------------
1. РАСЧЁТ MAU АВТОРОВ (ТОП‑3 В НОЯБРЕ 2024)
Цель: выявить топ‑3 авторов по количеству активных пользователей (MAU) в ноябре 2024 г.
-------------------------------------------------------------------------------
*/
WITH november_data AS (
    SELECT
        a.puid,
        c.main_author_id,
        au.main_author_name
    FROM
        bookmate.audition a
    JOIN
        bookmate.content c ON a.main_content_id = c.main_content_id
    LEFT JOIN
        bookmate.author au ON c.main_author_id = au.main_author_id
    WHERE
        a.msk_business_dt_str BETWEEN '2024-11-01' AND '2024-11-30'
        AND a.usage_platform_ru IS NOT NULL  -- Можно оставить для фильтрации, при необходимости
)
SELECT
    main_author_name,
    COUNT(DISTINCT puid) AS mau
FROM
    november_data
GROUP BY
    main_author_name
ORDER BY
    mau DESC
LIMIT 3;


/*
-------------------------------------------------------------------------------
2. РАСЧЁТ MAU ПРОИЗВЕДЕНИЙ (ТОП‑3 В НОЯБРЕ 2024)
Цель: найти топ‑3 произведения по MAU, включая их жанры и авторов.
-------------------------------------------------------------------------------
*/

 -- Шаг 1: фильтруем только нужные сессии за ноябрь
WITH november_sessions AS (
    SELECT
        a.puid,
        a.main_content_id,
        a.usage_platform_ru
    FROM
        bookmate.audition a
    WHERE
        a.msk_business_dt_str BETWEEN '2024-11-01' AND '2024-11-30'
)
-- Шаг 2: присоединяем контент и выбираем нужные поля
, content_info AS (
    SELECT
        c.main_content_id,
        c.main_content_name,
        c.published_topic_title_list,
        c.main_author_id
    FROM
        bookmate.content c
    WHERE
        c.main_content_id IN (SELECT main_content_id FROM november_sessions)
)
-- Шаг 3: присоединяем авторов
, authors AS (
    SELECT
        a.main_author_id,
        a.main_author_name
    FROM
        bookmate.author a
)
-- Финальный подсчёт
SELECT
    ci.main_content_name,
    ci.published_topic_title_list,
    au.main_author_name,
    COUNT(DISTINCT ns.puid) AS mau
FROM
    november_sessions ns
JOIN
    content_info ci ON ns.main_content_id = ci.main_content_id
LEFT JOIN
    authors au ON ci.main_author_id = au.main_author_id
GROUP BY
    ci.main_content_name,
    ci.published_topic_title_list,
    au.main_author_name
ORDER BY
    mau DESC
LIMIT 3;


/*
-------------------------------------------------------------------------------
3. РАСЧЁТ RETENTION RATE (ЕЖЕДНЕВНЫЙ)
Цель: рассчитать ежедневный коэффициент удержания пользователей с 2 декабря 2024 г.
-------------------------------------------------------------------------------
*/




WITH active_users AS (
    SELECT DISTINCT puid
    FROM bookmate.audition
    WHERE msk_business_dt_str = '2024-12-02'
),

user_activities AS (
    SELECT
        puid,
        CAST(msk_business_dt_str AS DATE) AS event_date
    FROM bookmate.audition
),

user_days AS (
    SELECT
        ua.puid,
        ua.event_date,
        MIN(CAST('2024-12-02' AS DATE)) OVER (PARTITION BY ua.puid) AS install_date,
        (ua.event_date - MIN(CAST('2024-12-02' AS DATE)) OVER (PARTITION BY ua.puid)) AS day_since_install
    FROM user_activities ua
    WHERE ua.puid IN (SELECT puid FROM active_users)
),

retention AS (
    SELECT
        day_since_install,
        COUNT(DISTINCT puid) AS retained_users
    FROM user_days
    GROUP BY day_since_install
),

total_users AS (
    SELECT COUNT(DISTINCT puid) AS total_count
    FROM active_users
)

SELECT 
    rd.day_since_install,
    COALESCE(rd.retained_users, 0) AS retained_users,
    ROUND(COALESCE(rd.retained_users::DECIMAL / tu.total_count, 0), 2) AS retention_rate
FROM (
    SELECT 
        d.day_since_install,
        r.retained_users
    FROM generate_series(0, (SELECT MAX(day_since_install) FROM user_days)) AS d(day_since_install)
    LEFT JOIN retention r ON d.day_since_install = r.day_since_install
) rd
CROSS JOIN total_users tu
ORDER BY rd.day_since_install;


/*
-------------------------------------------------------------------------------
4. РАСЧЁТ LTV ПО ГОРОДАМ (МОСКВА И САНКТ‑ПЕТЕРБУРГ)
Цель: сравнить средний Lifetime Value (LTV) пользователей в Москве и СПб.
-------------------------------------------------------------------------------
*/

WITH active_users AS (
    SELECT DISTINCT
        puid,
        usage_geo_id_name AS city
    FROM
        bookmate.audition
    JOIN
        bookmate.geo ON bookmate.audition.usage_geo_id = bookmate.geo.usage_geo_id
),
revenue_per_city AS (
    SELECT
        city,
        COUNT(*) AS total_active_users,
        COUNT(*) * 399 AS total_revenue
    FROM
        active_users
    GROUP BY
        city
)
SELECT
    city,
    total_active_users AS total_users,
    ROUND(
        CASE WHEN total_active_users > 0 THEN total_revenue::numeric / total_active_users ELSE 0 END,
        2
    ) AS ltv
FROM
    revenue_per_city
WHERE
    city IN ('Москва', 'Санкт-Петербург')
ORDER BY
    total_users DESC;


/*
-------------------------------------------------------------------------------
5. РАСЧЁТ СРЕДНЕЙ ВЫРУЧКИ НА ПРОСЛУШАННЫЙ ЧАС (АНАЛОГ СРЕДНЕГО ЧЕКА)
Цель: рассчитать выручку на час прослушивания вместе с MAU и общим временем.
Период: сентябрь–ноябрь 2024 г.
-------------------------------------------------------------------------------
*/

SELECT
    DATE_TRUNC('month', msk_business_dt_str::date)::date AS month,
    COUNT(DISTINCT puid) AS mau,
    ROUND(SUM(hours)::numeric, 2) AS hours,
    ROUND((COUNT(DISTINCT puid) * 399)::numeric / NULLIF(SUM(hours), 0), 2) AS avg_hour_rev
FROM bookmate.audition
WHERE msk_business_dt_str::date >= '2024-09-01'
  AND msk_business_dt_str::date <  '2024-12-01'
GROUP BY 1
ORDER BY month;


