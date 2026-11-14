-- Модуль 5. Лабораторная работа «Вложенные запросы: ищем потери»

SET search_path TO pitanie, public;

-- Общая 1. Продукты дороже средней базовой цены.
SELECT p.product_id, p.product_name, p.base_price
FROM products AS p
WHERE p.base_price > (
    SELECT AVG(p2.base_price)
    FROM products AS p2
)
ORDER BY p.base_price DESC;

-- Общая 2. Клиенты без заказов: NOT IN.
SELECT c.customer_id, c.customer_name
FROM customers AS c
WHERE c.customer_id NOT IN (
    SELECT o.customer_id
    FROM orders AS o
);

-- Общая 3. Те же клиенты без заказов: NOT EXISTS.
SELECT c.customer_id, c.customer_name
FROM customers AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM orders AS o
    WHERE o.customer_id = c.customer_id
);


-- Задание Б-1.1. Цена позиции выше средней цены того же материала.
SELECT COUNT(*) AS expensive_items
FROM purchase_order_items AS poi
WHERE poi.unit_price > (
    SELECT AVG(p2.unit_price)
    FROM purchase_order_items AS p2
    WHERE p2.material_id = poi.material_id
);

-- Задание Б-1.2. Цена более чем на 10 % выше средней
SELECT
    po.supplier_id,
    (SELECT s.supplier_name
     FROM suppliers AS s
     WHERE s.supplier_id = po.supplier_id) AS supplier_name,
    poi.material_id,
    (SELECT rm.material_name
     FROM raw_materials AS rm
     WHERE rm.material_id = poi.material_id) AS material_name,
    COUNT(*) AS expensive_items
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
WHERE poi.unit_price > 1.10 * (
    SELECT AVG(p2.unit_price)
    FROM purchase_order_items AS p2
    JOIN purchase_orders AS po2 ON po2.po_id = p2.po_id
    WHERE p2.material_id = poi.material_id
      AND DATE_TRUNC('quarter', po2.order_date) =
          DATE_TRUNC('quarter', po.order_date)
)
GROUP BY po.supplier_id, poi.material_id
ORDER BY expensive_items DESC, po.supplier_id;

-- Задание Б-2.1. Для каждого материала выбираем минимальную
SELECT
    t.supplier_id,
    s.supplier_name,
    ROUND(SUM(t.quantity * (t.unit_price - t.best_price)), 2)
        AS overpayment_rub
FROM (
    SELECT
        po.supplier_id,
        poi.material_id,
        poi.quantity,
        poi.unit_price,
        (SELECT MIN(a.avg_price)
         FROM (
             SELECT p2.material_id,
                    po2.supplier_id,
                    AVG(p2.unit_price) AS avg_price
             FROM purchase_order_items AS p2
             JOIN purchase_orders AS po2 ON po2.po_id = p2.po_id
             GROUP BY p2.material_id, po2.supplier_id
         ) AS a
         WHERE a.material_id = poi.material_id) AS best_price
    FROM purchase_order_items AS poi
    JOIN purchase_orders AS po ON po.po_id = poi.po_id
) AS t
JOIN suppliers AS s ON s.supplier_id = t.supplier_id
GROUP BY t.supplier_id, s.supplier_name
ORDER BY overpayment_rub DESC;

-- Задание Б-2.2. Какие закупщики оформляли заказы поставщикам.
SELECT
    s.supplier_name,
    e.full_name AS buyer_name,
    COUNT(*) AS orders_count
FROM purchase_orders AS po
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
LEFT JOIN employees AS e ON e.employee_id = po.employee_id
GROUP BY s.supplier_id, s.supplier_name, e.employee_id, e.full_name
ORDER BY s.supplier_name, orders_count DESC;


-- Задание Б-3.1. У поставщика не было статуса «Отклонено».
SELECT s.supplier_id, s.supplier_name
FROM suppliers AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM purchase_orders AS po
    JOIN purchase_order_items AS poi ON poi.po_id = po.po_id
    WHERE po.supplier_id = s.supplier_id
      AND poi.quality_status = 'Отклонено'
)
ORDER BY s.supplier_id;

-- Задание Б-3.2. Не было ни «Отклонено», ни «Принято частично».
SELECT s.supplier_id, s.supplier_name
FROM suppliers AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM purchase_orders AS po
    JOIN purchase_order_items AS poi ON poi.po_id = po.po_id
    WHERE po.supplier_id = s.supplier_id
      AND poi.quality_status IN ('Отклонено', 'Принято частично')
)
ORDER BY s.supplier_id;

-- Задание Б-3.3. Сравнение закупочных цен сахара-песка (id = 4).
SELECT
    s.supplier_id,
    s.supplier_name,
    ROUND(AVG(poi.unit_price), 2) AS avg_sugar_price,
    MIN(poi.unit_price) AS min_price,
    MAX(poi.unit_price) AS max_price
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
WHERE poi.material_id = 4
GROUP BY s.supplier_id, s.supplier_name
ORDER BY avg_sugar_price;

-- Задание Б-4.1. Партии с браком выше взвешенного
SELECT
    b.line_id,
    b.shift,
    COUNT(*) AS batches_count,
    ROUND(100.0 * SUM(b.defect_qty) /
          NULLIF(SUM(b.produced_qty), 0), 2) AS defect_percent
FROM production_batches AS b
WHERE 100.0 * b.defect_qty / NULLIF(b.produced_qty, 0) > (
    SELECT 100.0 * SUM(b2.defect_qty) / NULLIF(SUM(b2.produced_qty), 0)
    FROM production_batches AS b2
    WHERE b2.line_id = b.line_id
)
GROUP BY b.line_id, b.shift
ORDER BY b.line_id, b.shift;

-- Задание Б-4.2. Порог в 2 раза выше среднего брака линии.
SELECT
    b.line_id,
    b.shift,
    b.operator_id,
    (SELECT e.full_name
     FROM employees AS e
     WHERE e.employee_id = b.operator_id) AS operator_name,
    COUNT(*) AS batches_count
FROM production_batches AS b
WHERE 100.0 * b.defect_qty / NULLIF(b.produced_qty, 0) > 2 * (
    SELECT 100.0 * SUM(b2.defect_qty) / NULLIF(SUM(b2.produced_qty), 0)
    FROM production_batches AS b2
    WHERE b2.line_id = b.line_id
)
GROUP BY b.line_id, b.shift, b.operator_id
ORDER BY batches_count DESC;

-- Задание Б-4.3. Стоимость всего брака по линиям и сменам.
SELECT
    b.line_id,
    b.shift,
    SUM(b.defect_qty) AS defect_units,
    ROUND(SUM(b.defect_qty * p.standard_cost), 2) AS defect_cost_rub
FROM production_batches AS b
JOIN products AS p ON p.product_id = b.product_id
GROUP BY b.line_id, b.shift
ORDER BY defect_cost_rub DESC;


-- Задание Б-5. Используем EXISTS + EXISTS.
SELECT
    t.material_name,
    t.shelf_life_days,
    t.received_qty,
    t.writeoff_qty,
    t.writeoff_amount,
    ROUND(100.0 * t.writeoff_qty / NULLIF(t.received_qty, 0), 2)
        AS writeoff_percent
FROM (
    SELECT
        rm.material_id,
        rm.material_name,
        rm.shelf_life_days,
        (SELECT SUM(poi.received_qty)
         FROM purchase_order_items AS poi
         WHERE poi.material_id = rm.material_id) AS received_qty,
        (SELECT SUM(w.quantity)
         FROM material_writeoffs AS w
         WHERE w.material_id = rm.material_id
           AND w.quantity > 0) AS writeoff_qty,
        (SELECT SUM(w.amount)
         FROM material_writeoffs AS w
         WHERE w.material_id = rm.material_id
           AND w.quantity > 0) AS writeoff_amount
    FROM raw_materials AS rm
    WHERE EXISTS (
        SELECT 1
        FROM purchase_order_items AS poi
        WHERE poi.material_id = rm.material_id
    )
      AND EXISTS (
        SELECT 1
        FROM material_writeoffs AS w
        WHERE w.material_id = rm.material_id
          AND w.quantity > 0
    )
) AS t
ORDER BY t.writeoff_amount DESC;


-- Задание Б-6. Производная таблица по линии и материалу +
SELECT
    x.line_id,
    rm.material_name,
    ROUND(x.norm_qty, 2) AS norm_qty,
    ROUND(x.actual_qty, 2) AS actual_qty,
    ROUND(x.actual_qty - x.norm_qty, 2) AS excess_qty,
    ROUND((SELECT AVG(poi.unit_price)
           FROM purchase_order_items AS poi
           WHERE poi.material_id = x.material_id), 2) AS avg_price,
    ROUND((x.actual_qty - x.norm_qty) *
          (SELECT AVG(poi.unit_price)
           FROM purchase_order_items AS poi
           WHERE poi.material_id = x.material_id), 2) AS excess_cost_rub
FROM (
    SELECT
        b.line_id,
        r.material_id,
        SUM(mc.quantity) AS actual_qty,
        SUM(r.qty_per_unit * b.produced_qty) AS norm_qty
    FROM production_batches AS b
    JOIN recipes AS r ON r.product_id = b.product_id
    JOIN material_consumption AS mc
        ON mc.batch_id = b.batch_id
       AND mc.material_id = r.material_id
    GROUP BY b.line_id, r.material_id
) AS x
JOIN raw_materials AS rm ON rm.material_id = x.material_id
WHERE x.actual_qty > 1.03 * x.norm_qty
ORDER BY excess_cost_rub DESC;

-- Задание Б-7.1. Ошибка: в рейтингах московских поставщиков есть NULL.
SELECT s.supplier_id, s.supplier_name, s.rating
FROM suppliers AS s
WHERE s.rating > ALL (
    SELECT s2.rating
    FROM suppliers AS s2
    WHERE s2.region_id = 1
);

-- Задание Б-7.2. Правильно: убираем NULL из подзапроса.
SELECT s.supplier_id, s.supplier_name, s.rating
FROM suppliers AS s
WHERE s.rating > ALL (
    SELECT s2.rating
    FROM suppliers AS s2
    WHERE s2.region_id = 1
      AND s2.rating IS NOT NULL
)
ORDER BY s.rating DESC;

-- ДОПОЛНИТЕЛЬНОЕ ЗАДАНИЕ 1.
SELECT
    rm.material_name,
    poi.received_date,
    po.po_number,
    s.supplier_name
FROM raw_materials AS rm
JOIN purchase_order_items AS poi ON poi.material_id = rm.material_id
JOIN purchase_orders AS po ON po.po_id = poi.po_id
JOIN suppliers AS s ON s.supplier_id = po.supplier_id
WHERE rm.material_group = 'Сахар и сиропы'
  AND poi.received_date IS NOT NULL
  AND poi.received_date = (
      SELECT MAX(p2.received_date)
      FROM purchase_order_items AS p2
      WHERE p2.material_id = rm.material_id
  )
ORDER BY rm.material_name, s.supplier_name;

-- ДОПОЛНИТЕЛЬНОЕ ЗАДАНИЕ 2.

SELECT
    b.line_id,
    b.shift,
    COUNT(*) AS batches_count,
    ROUND(100.0 * SUM(b.defect_qty) /
          NULLIF(SUM(b.produced_qty), 0), 2) AS defect_percent
FROM production_batches AS b
JOIN (
    SELECT
        b2.line_id,
        100.0 * SUM(b2.defect_qty) /
        NULLIF(SUM(b2.produced_qty), 0) AS avg_defect_percent
    FROM production_batches AS b2
    GROUP BY b2.line_id
) AS a ON a.line_id = b.line_id
WHERE 100.0 * b.defect_qty / NULLIF(b.produced_qty, 0) > a.avg_defect_percent
GROUP BY b.line_id, b.shift
ORDER BY b.line_id, b.shift;

-- СРАВНЕНИЕ ПЛАНОВ: выполните EXPLAIN для двух вариантов.
EXPLAIN
SELECT b.line_id, b.shift, COUNT(*) AS batches_count
FROM production_batches AS b
WHERE 100.0 * b.defect_qty / NULLIF(b.produced_qty, 0) > (
    SELECT 100.0 * SUM(b2.defect_qty) / NULLIF(SUM(b2.produced_qty), 0)
    FROM production_batches AS b2
    WHERE b2.line_id = b.line_id
)
GROUP BY b.line_id, b.shift;

-- Вариант с рассчитанным один раз средним по каждой линии.
EXPLAIN
SELECT b.line_id, b.shift, COUNT(*) AS batches_count
FROM production_batches AS b
JOIN (
    SELECT b2.line_id,
           100.0 * SUM(b2.defect_qty) /
           NULLIF(SUM(b2.produced_qty), 0) AS avg_defect_percent
    FROM production_batches AS b2
    GROUP BY b2.line_id
) AS a ON a.line_id = b.line_id
WHERE 100.0 * b.defect_qty / NULLIF(b.produced_qty, 0) > a.avg_defect_percent
GROUP BY b.line_id, b.shift;
