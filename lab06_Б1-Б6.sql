-- Модуль 6. Лабораторная работа №6 «Объединение наборов: единые журналы и сравнение периодов»
-- Команда Б. Вариант 2 «Производство и закупки»

SET search_path TO pitanie, public;

-- ОБЩАЯ ЧАСТЬ

-- О1. Число ИНН в двух справочниках с UNION ALL.
SELECT COUNT(*) AS inn_count
FROM (
    SELECT c.inn FROM customers AS c
    UNION ALL
    SELECT s.inn FROM suppliers AS s) AS all_inn;

-- О2. Число различных ИНН с UNION.
SELECT COUNT(*) AS unique_inn_count
FROM (
    SELECT c.inn FROM customers AS c
    UNION
    SELECT s.inn FROM suppliers AS s) AS unique_inn;

-- О3. Какие ИНН повторяются и сколько раз?
SELECT x.inn, COUNT(*) AS records_count
FROM (
    SELECT c.inn FROM customers AS c
    UNION ALL
    SELECT s.inn FROM suppliers AS s) AS x
GROUP BY x.inn
HAVING COUNT(*) > 1
ORDER BY records_count DESC, x.inn;

-- О4. Общие ИНН клиентов и поставщиков (INTERSECT).
SELECT c.inn FROM customers AS c
INTERSECT
SELECT s.inn FROM suppliers AS s;

-- Б1. ЕДИНЫЙ ЖУРНАЛ ПОТЕРЬ ПРОИЗВОДСТВА
SELECT
    j.event_type,
    EXTRACT(YEAR FROM j.event_date)::int AS event_year,
    j.unit,
    COUNT(*) AS events_count,
    ROUND(SUM(j.qty), 2) AS total_qty,
    ROUND(SUM(j.amount_rub), 2) AS total_amount_rub
FROM (
    SELECT
        'Брак'::text AS event_type,
        b.production_date::date AS event_date,
        b.line_id,
        b.defect_qty::numeric AS qty,
        p.unit::text AS unit,
        (b.defect_qty * p.standard_cost)::numeric AS amount_rub
    FROM production_batches AS b
    JOIN products AS p ON p.product_id = b.product_id
    WHERE b.defect_qty > 0
    UNION ALL
    SELECT
        'Простой'::text,
        d.start_time::date,
        d.line_id,
        EXTRACT(EPOCH FROM (d.end_time - d.start_time)) / 3600,
        'ч'::text,
        NULL::numeric
    FROM equipment_downtime AS d
    WHERE d.end_time IS NOT NULL
    UNION ALL
    SELECT
        'Списание'::text,
        w.writeoff_date::date,
        NULL::int,
        w.quantity::numeric,
        rm.unit::text,
        w.amount::numeric
    FROM material_writeoffs AS w
    JOIN raw_materials AS rm ON rm.material_id = w.material_id
    WHERE w.quantity > 0) AS j
GROUP BY j.event_type, EXTRACT(YEAR FROM j.event_date), j.unit
ORDER BY j.event_type, event_year, j.unit;

-- Б2. ПРОСТОИ ПО ЛИНИЯМ В 2024 И 2025 ГОДАХ
SELECT
    l.line_id,
    l.line_name,
    ROUND(COALESCE(SUM(EXTRACT(EPOCH FROM (d.end_time - d.start_time)) / 3600)
        FILTER (WHERE d.start_time >= DATE '2024-01-01'
                  AND d.start_time < DATE '2025-01-01'), 0), 2) AS hours_2024,
    ROUND(COALESCE(SUM(EXTRACT(EPOCH FROM (d.end_time - d.start_time)) / 3600)
        FILTER (WHERE d.start_time >= DATE '2025-01-01'
                  AND d.start_time < DATE '2026-01-01'), 0), 2) AS hours_2025
FROM production_lines AS l
LEFT JOIN equipment_downtime AS d
    ON d.line_id = l.line_id AND d.end_time IS NOT NULL
GROUP BY l.line_id, l.line_name
ORDER BY l.line_id;

-- Б3. ЗАКУПАЕМ ТО, ЧТО НЕ ИСПОЛЬЗУЕМ? (EXCEPT)

-- Б3.1. Материалы из закупок, которых нет в рецептурах.
SELECT rm.material_id, rm.material_name
FROM purchase_order_items AS poi
JOIN raw_materials AS rm ON rm.material_id = poi.material_id
EXCEPT
SELECT rm.material_id, rm.material_name
FROM recipes AS r
JOIN raw_materials AS rm ON rm.material_id = r.material_id;

-- Б3.2. Материалы из рецептур, которые не закупались.
SELECT rm.material_id, rm.material_name
FROM recipes AS r
JOIN raw_materials AS rm ON rm.material_id = r.material_id
EXCEPT
SELECT rm.material_id, rm.material_name
FROM purchase_order_items AS poi
JOIN raw_materials AS rm ON rm.material_id = poi.material_id;

-- Б3.3. Новые пары «поставщик — материал» в 2025 г. по сравнению с 2024 г.
SELECT
    np.supplier_id,
    s.supplier_name,
    np.material_id,
    rm.material_name
FROM (
    SELECT po.supplier_id, poi.material_id
    FROM purchase_orders AS po
    JOIN purchase_order_items AS poi ON poi.po_id = po.po_id
    WHERE po.order_date >= DATE '2025-01-01'
      AND po.order_date < DATE '2026-01-01'
    EXCEPT
    SELECT po.supplier_id, poi.material_id
    FROM purchase_orders AS po
    JOIN purchase_order_items AS poi ON poi.po_id = po.po_id
    WHERE po.order_date >= DATE '2024-01-01'
      AND po.order_date < DATE '2025-01-01') AS np
JOIN suppliers AS s ON s.supplier_id = np.supplier_id
JOIN raw_materials AS rm ON rm.material_id = np.material_id
ORDER BY np.supplier_id, np.material_id;

-- Б3.4. Поставщики с заказами в 2025 г., которых не было в 2024 г.
SELECT s.supplier_id, s.supplier_name
FROM suppliers AS s
WHERE s.supplier_id IN (
    SELECT po.supplier_id
    FROM purchase_orders AS po
    WHERE po.order_date >= DATE '2025-01-01'
      AND po.order_date < DATE '2026-01-01'
    EXCEPT
    SELECT po.supplier_id
    FROM purchase_orders AS po
    WHERE po.order_date >= DATE '2024-01-01'
      AND po.order_date < DATE '2025-01-01');

-- Б4. ОБЩИЕ МАТЕРИАЛЫ ПОСТАВЩИКОВ (INTERSECT)
-- Б4.1. Материалы АгроСнаба (supplier_id = 3), которые есть у конкурентов.
SELECT rm.material_id, rm.material_name
FROM raw_materials AS rm
WHERE rm.material_id IN (
    SELECT poi.material_id
    FROM purchase_orders AS po
    JOIN purchase_order_items AS poi ON poi.po_id = po.po_id
    WHERE po.supplier_id = 3
    INTERSECT
    SELECT poi.material_id
    FROM purchase_orders AS po
    JOIN purchase_order_items AS poi ON poi.po_id = po.po_id
    WHERE po.supplier_id <> 3)
ORDER BY rm.material_id;


-- Б5. ПОСЛЕДНИЕ 3 ПОЗИЦИИ ЗАКУПОК И ЦЕНА КОНКУРЕНТА (LATERAL)
SELECT
    s.supplier_name,
    last3.po_number,
    last3.order_date,
    rm.material_name,
    last3.unit_price,
    competitor.min_price AS competitor_price,
    ROUND(100.0 * (last3.unit_price - competitor.min_price)
          / NULLIF(competitor.min_price, 0), 2) AS price_difference_pct
FROM suppliers AS s
CROSS JOIN LATERAL (
    SELECT
        po.po_number,
        po.order_date,
        poi.po_item_id,
        poi.material_id,
        poi.unit_price
    FROM purchase_orders AS po
    JOIN purchase_order_items AS poi ON poi.po_id = po.po_id
    WHERE po.supplier_id = s.supplier_id
    ORDER BY po.order_date DESC, poi.po_item_id DESC
    LIMIT 3) AS last3
JOIN raw_materials AS rm ON rm.material_id = last3.material_id
LEFT JOIN LATERAL (
    SELECT MIN(poi2.unit_price) AS min_price
    FROM purchase_orders AS po2
    JOIN purchase_order_items AS poi2 ON poi2.po_id = po2.po_id
    WHERE po2.supplier_id <> s.supplier_id
      AND poi2.material_id = last3.material_id
      AND po2.order_date BETWEEN last3.order_date - INTERVAL '90 days'
      AND last3.order_date) AS competitor ON TRUE
ORDER BY s.supplier_name, last3.order_date DESC, last3.po_item_id DESC;

-- Б6*. КАЛЕНДАРЬ ПРОСТОЕВ ЛИНИИ 2 (LATERAL)
SELECT
    m.month_start::date AS month_start,
    COALESCE(d.events_count, 0) AS events_count,
    ROUND(COALESCE(d.hours, 0), 2) AS downtime_hours
FROM generate_series(
    DATE '2024-01-01',
    DATE '2025-12-01',
    INTERVAL '1 month') AS m(month_start)
LEFT JOIN LATERAL (SELECT
        COUNT(*) AS events_count,
        SUM(EXTRACT(EPOCH FROM (e.end_time - e.start_time)) / 3600) AS hours
    FROM equipment_downtime AS e
    WHERE e.line_id = 2
      AND e.start_time >= m.month_start
      AND e.start_time < m.month_start + INTERVAL '1 month') AS d ON TRUE
ORDER BY m.month_start;
