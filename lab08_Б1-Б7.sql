-- МОДУЛЬ 8. Динамика, рейтинги и ABC-анализ
-- Команда Б. Вариант 2: Производство и закупки
SET search_path TO pitanie, public;

-- ОБЩАЯ ЧАСТЬ 
-- О1. Выручка строки. Отменённые заказы не учитываются.
SELECT
    oi.order_item_id,
    ROUND(oi.quantity * oi.unit_price *
          (1 - oi.discount_pct / 100.0), 2) AS revenue_rub
FROM order_items AS oi
JOIN orders AS o ON o.order_id = oi.order_id
WHERE o.status <> 'Отменён'
LIMIT 10;

-- О2. Процент брака отдельной партии.
SELECT
    b.batch_number,
    ROUND(100.0 * b.defect_qty /
          NULLIF(b.produced_qty, 0), 2) AS defect_percent
FROM production_batches AS b
LIMIT 10;

-- О3. Продолжительность закрытого простоя в часах.
SELECT
    d.downtime_id,
    ROUND(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600, 2)
        AS downtime_hours
FROM equipment_downtime AS d
WHERE d.end_time IS NOT NULL
LIMIT 10;


-- Б1. РЕЙТИНГ ПОСТАВЩИКОВ ПО ЦЕНЕ ВНУТРИ МАТЕРИАЛА
-- Б1.1. Средневзвешенная цена и объём по материалу и поставщику в 2025 г.
SELECT
    poi.material_id,
    rm.material_name,
    s.supplier_name,
    SUM(poi.quantity) AS purchased_qty,
    ROUND(SUM(poi.quantity * poi.unit_price) /
          NULLIF(SUM(poi.quantity), 0), 2) AS avg_price
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
JOIN raw_materials AS rm ON rm.material_id = poi.material_id
WHERE po.order_date >= DATE '2025-01-01'
  AND po.order_date < DATE '2026-01-01'
GROUP BY poi.material_id, rm.material_name, s.supplier_id, s.supplier_name
ORDER BY poi.material_id, avg_price;

-- Б1.2–Б1.3. Место по цене, лучшая цена, переплата и топ-10.
WITH prices AS (
    SELECT
        poi.material_id,
        po.supplier_id,
        SUM(poi.quantity) AS qty,
        SUM(poi.quantity * poi.unit_price) /
            NULLIF(SUM(poi.quantity), 0) AS avg_price
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po ON po.po_id = poi.po_id
    WHERE po.order_date >= DATE '2025-01-01'
      AND po.order_date < DATE '2026-01-01'
    GROUP BY poi.material_id, po.supplier_id
),
rating AS (
    SELECT
        p.*,
        DENSE_RANK() OVER (
            PARTITION BY p.material_id ORDER BY p.avg_price
        ) AS price_rank,
        MIN(p.avg_price) OVER (
            PARTITION BY p.material_id
        ) AS best_price,
        COUNT(*) OVER (
            PARTITION BY p.material_id
        ) AS supplier_count
    FROM prices AS p
)
SELECT
    rm.material_name,
    s.supplier_name,
    r.qty,
    ROUND(r.avg_price, 2) AS avg_price,
    r.price_rank,
    ROUND(r.best_price, 2) AS best_price,
    ROUND(100.0 * (r.avg_price - r.best_price) /
          NULLIF(r.best_price, 0), 1) AS overpay_percent,
    ROUND(r.qty * (r.avg_price - r.best_price), 2) AS overpay_rub
FROM rating AS r
JOIN raw_materials AS rm ON rm.material_id = r.material_id
JOIN suppliers AS s ON s.supplier_id = r.supplier_id
WHERE r.supplier_count > 1
  AND r.price_rank > 1
ORDER BY overpay_rub DESC
LIMIT 10;

-- Б1.4. Общая переплата по поставщикам в 2025 г.
WITH prices AS (
    SELECT
        poi.material_id,
        po.supplier_id,
        SUM(poi.quantity) AS qty,
        SUM(poi.quantity * poi.unit_price) /
            NULLIF(SUM(poi.quantity), 0) AS avg_price
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po ON po.po_id = poi.po_id
    WHERE po.order_date >= DATE '2025-01-01'
      AND po.order_date < DATE '2026-01-01'
    GROUP BY poi.material_id, po.supplier_id
),
rating AS (
    SELECT
        p.*,
        MIN(p.avg_price) OVER (PARTITION BY p.material_id) AS best_price
    FROM prices AS p
)
SELECT
    s.supplier_name,
    ROUND(SUM(r.qty * (r.avg_price - r.best_price)), 2) AS total_overpay_rub
FROM rating AS r
JOIN suppliers AS s ON s.supplier_id = r.supplier_id
GROUP BY s.supplier_id, s.supplier_name
ORDER BY total_overpay_rub DESC;


-- Б2. СКОЛЬЗЯЩЕЕ СРЕДНЕЕ БРАКА ЗА 7 СМЕН
-- Б2.1. Процент брака партии и средняя за последние 7 строк линии.
SELECT
    b.batch_id,
    b.batch_number,
    b.line_id,
    b.production_date,
    b.shift,
    ROUND(100.0 * b.defect_qty /
          NULLIF(b.produced_qty, 0), 2) AS defect_percent,
    ROUND(AVG(100.0 * b.defect_qty /
              NULLIF(b.produced_qty, 0)) OVER (
        PARTITION BY b.line_id
        ORDER BY b.production_date, b.shift, b.batch_id
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS ma7
FROM production_batches AS b
WHERE b.production_date >= DATE '2025-01-01'
  AND b.production_date < DATE '2026-01-01'
ORDER BY b.line_id, b.production_date, b.shift, b.batch_id;

-- Б2.2. Средняя MA7, максимальная MA7 и число строк с MA7 > 3%.
SELECT
    x.line_id,
    ROUND(AVG(x.ma7), 2) AS average_ma7,
    ROUND(MAX(x.ma7), 2) AS maximum_ma7,
    COUNT(*) FILTER (WHERE x.ma7 > 3) AS shifts_over_3
FROM (
    SELECT
        b.line_id,
        AVG(100.0 * b.defect_qty / NULLIF(b.produced_qty, 0)) OVER (
            PARTITION BY b.line_id
            ORDER BY b.production_date, b.shift, b.batch_id
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS ma7
    FROM production_batches AS b
    WHERE b.production_date >= DATE '2025-01-01'
      AND b.production_date < DATE '2026-01-01'
) AS x
GROUP BY x.line_id
ORDER BY x.line_id;

-- Б3. ИЗМЕНЕНИЕ ЗАКУПОЧНЫХ ЦЕН (LAG)
-- Б3.1. Молочный жир (material_id = 14): скачки более 10%.
WITH purchases AS (
    SELECT
        po.order_date,
        s.supplier_name,
        poi.po_item_id,
        poi.unit_price,
        LAG(poi.unit_price) OVER (
            ORDER BY po.order_date, po.po_id, poi.po_item_id
        ) AS previous_price
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po ON po.po_id = poi.po_id
    JOIN suppliers AS s ON s.supplier_id = po.supplier_id
    WHERE poi.material_id = 14
)
SELECT
    p.order_date,
    p.supplier_name,
    p.previous_price,
    p.unit_price,
    ROUND(100.0 * (p.unit_price - p.previous_price) /
          NULLIF(p.previous_price, 0), 1) AS price_growth_percent
FROM purchases AS p
WHERE p.unit_price > 1.10 * p.previous_price
ORDER BY p.order_date, p.po_item_id;

-- Б3.2. Средняя цена по материалу и месяцу: рост более 15%.
WITH monthly AS (
    SELECT
        poi.material_id,
        DATE_TRUNC('month', po.order_date)::date AS month_start,
        AVG(poi.unit_price) AS avg_price
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po ON po.po_id = poi.po_id
    GROUP BY poi.material_id, DATE_TRUNC('month', po.order_date)
),
changes AS (
    SELECT
        m.*,
        LAG(m.avg_price) OVER (
            PARTITION BY m.material_id ORDER BY m.month_start
        ) AS previous_avg_price
    FROM monthly AS m
)
SELECT
    rm.material_name,
    c.month_start,
    ROUND(c.previous_avg_price, 2) AS previous_avg_price,
    ROUND(c.avg_price, 2) AS avg_price,
    ROUND(100.0 * (c.avg_price - c.previous_avg_price) /
          NULLIF(c.previous_avg_price, 0), 1) AS growth_percent
FROM changes AS c
JOIN raw_materials AS rm ON rm.material_id = c.material_id
WHERE c.avg_price > 1.15 * c.previous_avg_price
ORDER BY c.month_start, rm.material_name;

-- Б3 (дополнительно по вопросу): какие продукты используют молочный жир.
SELECT
    p.product_name,
    r.qty_per_unit
FROM recipes AS r
JOIN products AS p ON p.product_id = r.product_id
WHERE r.material_id = 14
ORDER BY r.qty_per_unit DESC;

-- Б4. ЧАСЫ ПРОСТОЯ ЛИНИИ 2 ПО МЕСЯЦАМ: НАРАСТАЮЩИЙ ИТОГ
SELECT
    m.month_number,
    ROUND(m.hours_2024, 1) AS hours_2024,
    ROUND(m.hours_2025, 1) AS hours_2025,
    ROUND(SUM(m.hours_2024) OVER (
        ORDER BY m.month_number
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 1) AS cumulative_2024,
    ROUND(SUM(m.hours_2025) OVER (
        ORDER BY m.month_number
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 1) AS cumulative_2025
FROM (
    SELECT
        EXTRACT(MONTH FROM d.start_time)::int AS month_number,
        COALESCE(SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600)
            FILTER (WHERE EXTRACT(YEAR FROM d.start_time) = 2024), 0)
            AS hours_2024,
        COALESCE(SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600)
            FILTER (WHERE EXTRACT(YEAR FROM d.start_time) = 2025), 0)
            AS hours_2025
    FROM equipment_downtime AS d
    WHERE d.line_id = 2
      AND d.end_time IS NOT NULL
      AND d.start_time >= TIMESTAMP '2024-01-01'
      AND d.start_time < TIMESTAMP '2026-01-01'
    GROUP BY EXTRACT(MONTH FROM d.start_time)
) AS m
ORDER BY m.month_number;

-- Б5. ИНТЕРВАЛЫ МЕЖДУ ПОЛОМКАМИ
SELECT
    d.line_id,
    EXTRACT(YEAR FROM d.start_time)::int AS production_year,
    COUNT(*) AS breakdown_count,
    ROUND(AVG(d.days_between), 1) AS avg_days_between
FROM (
    SELECT
        e.line_id,
        e.start_time,
        EXTRACT(EPOCH FROM (
            e.start_time - LAG(e.end_time) OVER (
                PARTITION BY e.line_id
                ORDER BY e.start_time, e.downtime_id
            )
        )) / 86400 AS days_between
    FROM equipment_downtime AS e
    WHERE e.downtime_category = 'Поломка оборудования'
) AS d
GROUP BY d.line_id, EXTRACT(YEAR FROM d.start_time)
ORDER BY d.line_id, production_year;

-- Б6. ABC-АНАЛИЗ ЗАКУПОК МАТЕРИАЛОВ ЗА 2025 ГОД
WITH costs AS (
    SELECT
        poi.material_id,
        SUM(poi.quantity * poi.unit_price) AS spend_rub
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po ON po.po_id = poi.po_id
    WHERE po.order_date >= DATE '2025-01-01'
      AND po.order_date < DATE '2026-01-01'
    GROUP BY poi.material_id
),
running AS (
    SELECT
        c.*,
        SUM(c.spend_rub) OVER () AS all_spend_rub,
        SUM(c.spend_rub) OVER (
            ORDER BY c.spend_rub DESC, c.material_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_rub
    FROM costs AS c
)
SELECT
    rm.material_name,
    ROUND(r.spend_rub, 2) AS spend_rub,
    ROUND(100.0 * r.spend_rub / NULLIF(r.all_spend_rub, 0), 1)
        AS share_percent,
    ROUND(100.0 * r.cumulative_rub / NULLIF(r.all_spend_rub, 0), 1)
        AS cumulative_percent,
    CASE
        WHEN 100.0 * r.cumulative_rub / NULLIF(r.all_spend_rub, 0) <= 80
            THEN 'A'
        WHEN 100.0 * r.cumulative_rub / NULLIF(r.all_spend_rub, 0) <= 95
            THEN 'B'
        ELSE 'C'
    END AS abc_class
FROM running AS r
JOIN raw_materials AS rm ON rm.material_id = r.material_id
ORDER BY r.spend_rub DESC, r.material_id;

-- Б7*. ТОП-3 ПАРТИИ ПО ПЕРЕРАСХОДУ КАКАО-ПОРОШКА В КАЖДОМ МЕСЯЦЕ
WITH cocoa AS (
    SELECT
        b.batch_id,
        b.batch_number,
        b.line_id,
        DATE_TRUNC('month', b.production_date)::date AS month_start,
        100.0 * (mc.quantity - r.qty_per_unit * b.produced_qty) /
            NULLIF(r.qty_per_unit * b.produced_qty, 0) AS excess_percent
    FROM production_batches AS b
    JOIN recipes AS r
        ON r.product_id = b.product_id AND r.material_id = 8
    JOIN material_consumption AS mc
        ON mc.batch_id = b.batch_id AND mc.material_id = r.material_id
    WHERE b.production_date >= DATE '2025-01-01'
      AND b.production_date < DATE '2026-01-01'
      AND mc.quantity > r.qty_per_unit * b.produced_qty
),
rated AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.month_start
            ORDER BY c.excess_percent DESC, c.batch_id
        ) AS row_number
    FROM cocoa AS c
)
SELECT
    r.month_start,
    r.row_number,
    r.batch_number,
    r.line_id,
    ROUND(r.excess_percent, 2) AS excess_percent
FROM rated AS r
WHERE r.row_number <= 3
ORDER BY r.month_start, r.row_number;

