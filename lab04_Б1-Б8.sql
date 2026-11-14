-- Модуль 4. Лабораторная работа «Группирование и агрегирование данных»
-- Команда Б. Вариант 2 «Производство и закупки»

SET search_path TO pitanie, public;


-- ОБЩАЯ ЧАСТЬ

-- Общая проверка 1. Выручка и скидки по неотменённым заказам.
SELECT
    ROUND(SUM(oi.quantity * oi.unit_price *
          (1 - oi.discount_pct / 100.0)), 2) AS revenue_rub,
    ROUND(SUM(oi.quantity * oi.unit_price *
          oi.discount_pct / 100.0), 2) AS discount_rub
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.order_id
WHERE o.status <> 'Отменён';

-- Общая проверка 2. Взвешенный процент брака по всем партиям.
SELECT
    ROUND(100.0 * SUM(b.defect_qty) /
          NULLIF(SUM(b.produced_qty), 0), 2) AS defect_percent
FROM production_batches AS b;

-- Общая проверка 3. Фактический расход относительно нормы.
-- Соединяем расход по партии И материалу.
SELECT
    ROUND(SUM(mc.quantity) /
          NULLIF(SUM(r.qty_per_unit * b.produced_qty), 0), 4)
        AS actual_to_norm_ratio
FROM production_batches AS b
JOIN recipes AS r ON r.product_id = b.product_id
JOIN material_consumption AS mc
    ON mc.batch_id = b.batch_id AND mc.material_id = r.material_id;


-- Б1. БРАК ПО ЛИНИЯМ И СМЕНАМ (CUBE)
-- Б1.1. Одна строка = линия + смена; линия; смена; общий итог.
SELECT
    CASE WHEN GROUPING(b.line_id) = 1 THEN 'Все линии'
         ELSE 'Линия ' || b.line_id::text END AS line_name,
    CASE WHEN GROUPING(b.shift) = 1 THEN 'Все смены'
         ELSE b.shift END AS shift,
    COUNT(*) AS batches_count,
    SUM(b.produced_qty) AS produced_qty,
    SUM(b.defect_qty) AS defect_qty,
    ROUND(100.0 * SUM(b.defect_qty) /
          NULLIF(SUM(b.produced_qty), 0), 2) AS defect_percent
FROM production_batches AS b
GROUP BY CUBE (b.line_id, b.shift)
ORDER BY GROUPING(b.line_id, b.shift), b.line_id, b.shift;

-- Б1.2. Операторы в худшей ячейке «линия + смена».
SELECT
    b.line_id,
    b.shift,
    e.full_name AS operator_name,
    COUNT(*) AS batches_count,
    ROUND(100.0 * SUM(b.defect_qty) /
          NULLIF(SUM(b.produced_qty), 0), 2) AS defect_percent
FROM production_batches AS b
JOIN employees AS e ON e.employee_id = b.operator_id
JOIN (
    SELECT line_id, shift
    FROM production_batches
    GROUP BY line_id, shift
    ORDER BY 100.0 * SUM(defect_qty) /NULLIF(SUM(produced_qty), 0) 
    DESC LIMIT 1) AS worst ON worst.line_id = b.line_id AND worst.shift = b.shift
GROUP BY b.line_id, b.shift, e.employee_id, e.full_name
ORDER BY defect_percent DESC;


-- Б2. ЦЕНЫ МАТЕРИАЛОВ И ПЕРЕПЛАТА
-- Б2.1. Сахар, сироп, какао-порошок: по поставщику и материалу.
SELECT
    s.supplier_name,
    rm.material_name,
    COUNT(*) AS deliveries_count,
    SUM(poi.quantity) AS purchased_qty,
    ROUND(SUM(poi.quantity * poi.unit_price) /
          NULLIF(SUM(poi.quantity), 0), 2) AS weighted_price,
    ROUND(AVG(poi.unit_price), 2) AS simple_avg_price
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
JOIN raw_materials AS rm ON rm.material_id = poi.material_id
WHERE poi.material_id IN (4, 5, 8)
GROUP BY s.supplier_id, s.supplier_name, rm.material_id, rm.material_name
ORDER BY rm.material_name, weighted_price DESC;

-- Б2.2. Поставщик № 3: средние цены, доля объёма и переплата.
SELECT
    rm.material_name,
    ROUND(AVG(poi.unit_price) FILTER (WHERE po.supplier_id = 3), 2)
        AS agro_price,
    ROUND(AVG(poi.unit_price) FILTER (WHERE po.supplier_id <> 3), 2)
        AS other_price,
    ROUND(100.0 * SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3) /
          NULLIF(SUM(poi.quantity), 0), 2) AS agro_share_percent,
    ROUND(
        (SUM(poi.quantity) FILTER (WHERE po.supplier_id = 3)) *
        ((AVG(poi.unit_price) FILTER (WHERE po.supplier_id = 3)) -
         (AVG(poi.unit_price) FILTER (WHERE po.supplier_id <> 3))),2) AS overpayment_rub
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN raw_materials AS rm ON rm.material_id = poi.material_id
GROUP BY rm.material_id, rm.material_name
HAVING COUNT(*) FILTER (WHERE po.supplier_id = 3) > 0
ORDER BY overpayment_rub DESC NULLS LAST;

-- Б2.3. Какую долю позиций каждый закупщик размещает у поставщика № 3?
SELECT
    e.full_name AS buyer,
    COUNT(*) AS all_items,
    COUNT(*) FILTER (WHERE po.supplier_id = 3) AS agro_items,
    ROUND(100.0 * COUNT(*) FILTER (WHERE po.supplier_id = 3) /
          NULLIF(COUNT(*), 0), 2) AS agro_percent
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN employees AS e ON e.employee_id = po.employee_id
GROUP BY e.employee_id, e.full_name
ORDER BY agro_percent DESC;

-- Б3. ОПОЗДАНИЯ И КАЧЕСТВО ПОСТАВОК
SELECT
    s.supplier_name,
    COUNT(*) AS items_count,
    ROUND(AVG(poi.received_date::date - po.expected_date::date), 2)
        AS avg_delay_days,
    MAX(poi.received_date::date - po.expected_date::date)
        AS max_delay_days,
    COUNT(*) FILTER (WHERE poi.received_date::date > po.expected_date::date)
        AS late_items,
    COUNT(*) FILTER (WHERE poi.quality_status IN ('Принято частично', 'Отклонено'))
        AS quality_problems,
    ROUND(100.0 * SUM(poi.received_qty) /
          NULLIF(SUM(poi.quantity), 0), 2) AS accepted_percent
FROM suppliers AS s
JOIN purchase_orders AS po ON po.supplier_id = s.supplier_id
JOIN purchase_order_items AS poi ON poi.po_id = po.po_id
GROUP BY s.supplier_id, s.supplier_name
HAVING AVG(poi.received_date::date - po.expected_date::date) > 1
ORDER BY avg_delay_days DESC;

-- Б4. ЧАСЫ ПРОСТОЯ ПО ЛИНИЯМ И ГОДАМ
-- Б4.1. ROLLUP: линия + год; линия за все годы; общий итог.
SELECT
    CASE WHEN GROUPING(d.line_id) = 1 THEN 'Все линии'
         ELSE 'Линия ' || d.line_id::text END AS line_name,
    CASE WHEN GROUPING(EXTRACT(YEAR FROM d.start_time)) = 1
         THEN 'Все годы'
         ELSE EXTRACT(YEAR FROM d.start_time)::int::text END AS year,
    COUNT(*) AS downtime_count,
    COUNT(*) - COUNT(d.end_time) AS open_downtime_count,
    ROUND(SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time)) / 3600, 1)
        AS downtime_hours
FROM equipment_downtime AS d
GROUP BY ROLLUP (d.line_id, EXTRACT(YEAR FROM d.start_time))
ORDER BY GROUPING(d.line_id, EXTRACT(YEAR FROM d.start_time)),
         d.line_id, EXTRACT(YEAR FROM d.start_time);

-- Б4.2. Сводная таблица: одна строка = линия.
SELECT
    l.line_name,
    ROUND(SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time))
          FILTER (WHERE EXTRACT(YEAR FROM d.start_time) = 2024) / 3600, 1)
        AS hours_2024,
    ROUND(SUM(EXTRACT(EPOCH FROM d.end_time - d.start_time))
          FILTER (WHERE EXTRACT(YEAR FROM d.start_time) = 2025) / 3600, 1)
        AS hours_2025,
    COUNT(*) FILTER (WHERE d.downtime_category = 'Поломка оборудования')
        AS breakdown_count
FROM production_lines AS l
LEFT JOIN equipment_downtime AS d ON d.line_id = l.line_id
GROUP BY l.line_id, l.line_name
ORDER BY l.line_id;

-- Б4.3. Расходы на ремонт по годам.
SELECT
    EXTRACT(YEAR FROM e.expense_date)::int AS year,
    ROUND(SUM(e.amount) / 1000000.0, 2) AS repairs_million_rub
FROM expenses AS e
WHERE e.expense_category ILIKE '%ремонт%'
GROUP BY EXTRACT(YEAR FROM e.expense_date)
ORDER BY year;

-- Б5. СПИСАНИЯ СЫРЬЯ
-- Б5.1. Одна строка = материал; доля от ОБЩЕЙ суммы всех списаний.
SELECT
    rm.material_name,
    COUNT(*) AS writeoffs_count,
    SUM(w.quantity) AS written_off_qty,
    ROUND(SUM(w.amount), 2) AS writeoff_rub,
    ROUND(100.0 * SUM(w.amount) /
          NULLIF((SELECT SUM(w2.amount) FROM material_writeoffs AS w2), 0), 1)
        AS share_percent,
    STRING_AGG(DISTINCT w.reason, ', ') AS reasons
FROM material_writeoffs AS w
JOIN raw_materials AS rm ON rm.material_id = w.material_id
GROUP BY rm.material_id, rm.material_name
HAVING SUM(w.amount) > 50000
ORDER BY writeoff_rub DESC;

-- Б5.2. Для лидера: сколько ПОЛУЧЕНО и ИЗРАСХОДОВАНО по годам.
SELECT
    COALESCE(p.material_id, c.material_id) AS material_id,
    COALESCE(p.year, c.year) AS year,
    COALESCE(p.received_qty, 0) AS received_qty,
    COALESCE(c.consumed_qty, 0) AS consumed_qty
FROM (
    SELECT
        poi.material_id,
        EXTRACT(YEAR FROM poi.received_date)::int AS year,
        SUM(poi.received_qty) AS received_qty
    FROM purchase_order_items AS poi
    WHERE poi.received_date IS NOT NULL
    GROUP BY poi.material_id, EXTRACT(YEAR FROM poi.received_date)) AS p
FULL JOIN (
    SELECT
        mc.material_id,
        EXTRACT(YEAR FROM b.production_date)::int AS year,
        SUM(mc.quantity) AS consumed_qty
    FROM material_consumption AS mc
    JOIN production_batches AS b ON b.batch_id = mc.batch_id
    GROUP BY mc.material_id, EXTRACT(YEAR FROM b.production_date)) AS c 
    ON c.material_id = p.material_id AND c.year = p.year
WHERE COALESCE(p.material_id, c.material_id) = (
    SELECT w.material_id
    FROM material_writeoffs AS w
    GROUP BY w.material_id
    ORDER BY SUM(w.amount) DESC
    LIMIT 1)
ORDER BY year;

-- Б6. ПЕРЕРАСХОД СЫРЬЯ: ФАКТ / НОРМА
-- Б6.1. Одна строка = линия + материал.
SELECT
    b.line_id,
    rm.material_name,
    ROUND(SUM(r.qty_per_unit * b.produced_qty), 2) AS norm_qty,
    ROUND(SUM(mc.quantity), 2) AS actual_qty,
    ROUND(SUM(mc.quantity) /
          NULLIF(SUM(r.qty_per_unit * b.produced_qty), 0), 4) AS ratio
FROM production_batches AS b
JOIN recipes AS r ON r.product_id = b.product_id
JOIN material_consumption AS mc
    ON mc.batch_id = b.batch_id AND mc.material_id = r.material_id
JOIN raw_materials AS rm ON rm.material_id = r.material_id
GROUP BY b.line_id, r.material_id, rm.material_name
HAVING SUM(mc.quantity) > 1.03 * SUM(r.qty_per_unit * b.produced_qty)
ORDER BY ratio DESC;

-- Б6.2. Найденное молочное сырьё по сменам.
SELECT
    b.line_id,
    b.shift,
    rm.material_name,
    ROUND(SUM(r.qty_per_unit * b.produced_qty), 2) AS norm_qty,
    ROUND(SUM(mc.quantity), 2) AS actual_qty,
    ROUND(SUM(mc.quantity) /
          NULLIF(SUM(r.qty_per_unit * b.produced_qty), 0), 4) AS ratio
FROM production_batches AS b
JOIN recipes AS r ON r.product_id = b.product_id
JOIN material_consumption AS mc
    ON mc.batch_id = b.batch_id AND mc.material_id = r.material_id
JOIN raw_materials AS rm ON rm.material_id = r.material_id
WHERE (rm.material_name ILIKE '%молок%'
       OR rm.material_name ILIKE '%молоч%'
       OR rm.material_name ILIKE '%слив%')
  AND (b.line_id, r.material_id) IN (
      SELECT b2.line_id, r2.material_id
      FROM production_batches AS b2
      JOIN recipes AS r2 ON r2.product_id = b2.product_id
      JOIN material_consumption AS mc2
          ON mc2.batch_id = b2.batch_id AND mc2.material_id = r2.material_id
      GROUP BY b2.line_id, r2.material_id
      HAVING SUM(mc2.quantity) >
             1.03 * SUM(r2.qty_per_unit * b2.produced_qty))
GROUP BY b.line_id, b.shift, r.material_id, rm.material_name
ORDER BY b.line_id, rm.material_name, b.shift;

-- Б7. ВЫПОЛНЕНИЕ ПЛАНА С GROUPING SETS
SELECT
    CASE WHEN GROUPING(b.line_id) = 1 THEN 'Все линии'
         ELSE 'Линия ' || b.line_id::text END AS line_name,
    CASE WHEN GROUPING(EXTRACT(YEAR FROM b.production_date)) = 1
         THEN 'Все годы'
         ELSE EXTRACT(YEAR FROM b.production_date)::int::text END AS year,
    SUM(b.planned_qty) AS planned_qty,
    SUM(b.produced_qty) AS produced_qty,
    SUM(b.planned_qty) - SUM(b.produced_qty) AS shortfall_qty,
    ROUND(100.0 * SUM(b.produced_qty) /
          NULLIF(SUM(b.planned_qty), 0), 1) AS fulfillment_percent
FROM production_batches AS b
GROUP BY GROUPING SETS (
    (b.line_id, EXTRACT(YEAR FROM b.production_date)),
    (b.line_id),
    (EXTRACT(YEAR FROM b.production_date)),())
ORDER BY GROUPING(b.line_id, EXTRACT(YEAR FROM b.production_date)),b.line_id, 
EXTRACT(YEAR FROM b.production_date);

-- Б8*. ЦЕНА МОЛОЧНОГО ЖИРА ПО КВАРТАЛАМ
SELECT
    DATE_TRUNC('quarter', po.order_date)::date AS quarter_start,
    ROUND(SUM(poi.quantity * poi.unit_price) /
          NULLIF(SUM(poi.quantity), 0), 2) AS weighted_avg_price,
    MIN(poi.unit_price) AS min_price,
    MAX(poi.unit_price) AS max_price
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
WHERE poi.material_id = 14
GROUP BY DATE_TRUNC('quarter', po.order_date)
ORDER BY quarter_start;
