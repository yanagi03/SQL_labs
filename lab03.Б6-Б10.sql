-- Модуль 3. Команда Б. Задания Б6–Б10

SET search_path TO pitanie, public;

-- Б6. Опоздания и качество поставок

-- Б6.1. Поставки с опозданием более трёх дней
SELECT s.supplier_name, r.material_name, po.expected_date,poi.received_date,
    poi.received_date::date - po.expected_date::date AS delay_days,poi.quality_status
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON poi.po_id = po.po_id
JOIN suppliers AS s
    ON po.supplier_id = s.supplier_id
JOIN raw_materials AS r
    ON poi.material_id = r.material_id
WHERE poi.received_date::date >
      po.expected_date::date + 3
ORDER BY delay_days DESC;


-- Б6.2. Позиции с качеством, отличным от «Принято»
SELECT poi.po_item_id, s.supplier_name, r.material_name, poi.quality_status
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON poi.po_id = po.po_id
JOIN suppliers AS s
    ON po.supplier_id = s.supplier_id
JOIN raw_materials AS r
    ON poi.material_id = r.material_id
WHERE poi.quality_status <> 'Принято';

-- Б6.3. Неполученные позиции
SELECT poi.po_item_id, po.po_number, s.supplier_name, r.material_name, po.expected_date
FROM purchase_order_items AS poi
JOIN purchase_orders AS po
    ON poi.po_id = po.po_id
JOIN suppliers AS s
    ON po.supplier_id = s.supplier_id
JOIN raw_materials AS r
    ON poi.material_id = r.material_id
WHERE poi.received_date IS NULL;

-- Б7. Простои с линией и ответственным

-- Б7.1. Все простои
SELECT d.downtime_id, l.line_name, e.full_name AS responsible,
    d.start_time, d.end_time,
    ROUND(
        EXTRACT(EPOCH FROM
            d.end_time - d.start_time) / 3600, 2) AS downtime_hours,
    d.downtime_category,d.reason
FROM equipment_downtime AS d
JOIN production_lines AS l
    ON d.line_id = l.line_id
LEFT JOIN employees AS e
    ON l.responsible_id = e.employee_id
ORDER BY d.start_time;

-- Б7.2. Незакрытые простои
SELECT d.downtime_id, l.line_name, e.full_name AS responsible, d.start_time,
    COALESCE(
        d.end_time::text,
        'НЕ ЗАКРЫТ') AS end_time_status
FROM equipment_downtime AS d
JOIN production_lines AS l
    ON d.line_id = l.line_id
LEFT JOIN employees AS e
    ON l.responsible_id = e.employee_id
WHERE d.end_time IS NULL;

-- Б7.3. Число поломок линии 2 по годам
SELECT
    EXTRACT(YEAR FROM start_time) AS year,
    COUNT(*) AS breakdown_count
FROM equipment_downtime
WHERE line_id = 2
  AND downtime_category = 'Поломка оборудования'
GROUP BY EXTRACT(YEAR FROM start_time)
ORDER BY year;

-- Б8. Норма и фактический расход сырья
SELECT b.batch_number, p.product_name, rm.material_name,
    ROUND(
        r.qty_per_unit * b.produced_qty, 2) AS norm_qty,
    mc.quantity AS actual_qty,
    ROUND(100.0 * (mc.quantity -r.qty_per_unit * b.produced_qty) / NULLIF(r.qty_per_unit * b.produced_qty, 0), 2) AS excess_percent
FROM production_batches AS b
JOIN products AS p
    ON b.product_id = p.product_id
JOIN recipes AS r
    ON b.product_id = r.product_id
JOIN raw_materials AS rm
    ON r.material_id = rm.material_id
JOIN material_consumption AS mc
    ON mc.batch_id = b.batch_id
   AND mc.material_id = r.material_id
WHERE b.line_id = 5
  AND b.production_date >= DATE '2025-01-01'
  AND b.production_date < DATE '2026-01-01'
  AND mc.quantity >
      r.qty_per_unit * b.produced_qty * 1.10
ORDER BY b.batch_number;

-- Б9*. Списания и материалы без списаний

-- Б9.1. Списания клубничного наполнителя
SELECT r.material_name, r.shelf_life_days, w.quantity, w.amount, w.reason
FROM material_writeoffs AS w
JOIN raw_materials AS r
    ON w.material_id = r.material_id
WHERE w.material_id = 10
ORDER BY w.writeoff_date;

-- Б9.2. Материалы, которые ни разу не списывались
SELECT r.material_id, r.material_name
FROM raw_materials AS r
LEFT JOIN material_writeoffs AS w
    ON r.material_id = w.material_id
WHERE w.writeoff_id IS NULL;

-- Б10*. Пропущенные смены
SELECT l.line_name, shifts.shift_name,
    COUNT(*) AS missing_shifts
FROM generate_series(
    DATE '2025-01-01',
    DATE '2025-12-31',
    INTERVAL '1 day') AS days(day_date)
CROSS JOIN production_lines AS l
CROSS JOIN (
    VALUES('Д', 'дневная'),('Н', 'ночная')) AS shifts(shift_code, shift_name)
LEFT JOIN production_batches AS b
    ON b.production_date = days.day_date::date
   AND b.line_id = l.line_id
   AND UPPER(LEFT(b.shift, 1)) = shifts.shift_code
WHERE b.batch_id IS NULL
GROUP BY l.line_id, l.line_name, shifts.shift_name
ORDER BY l.line_id, shifts.shift_name;
