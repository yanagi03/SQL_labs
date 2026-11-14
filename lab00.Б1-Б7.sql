SET search_path TO pitanie, public;

--Какие таблицы есть в базе 
SELECT c.relname              AS table_name,
       obj_description(c.oid) AS description
FROM   pg_class     AS c
JOIN   pg_namespace AS n ON n.oid = c.relnamespace
WHERE  n.nspname = 'pitanie'
  AND  c.relkind = 'r'
ORDER  BY c.relname;

--Как устроена одна таблица 
SELECT column_name, data_type, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'pitanie'
  AND  table_name   = 'orders'
ORDER  BY ordinal_position;

--Связи между таблицами
SELECT conrelid::regclass         AS child_table,
       confrelid::regclass        AS parent_table,
       pg_get_constraintdef(oid)  AS definition
FROM   pg_constraint
WHERE  contype = 'f'
  AND  connamespace = 'pitanie'::regnamespace
ORDER  BY 1, 2;

--Кто работает в компании
SELECT e.department,
       e.full_name,
       e.position,
       m.full_name AS manager_name
FROM   employees      AS e
LEFT   JOIN employees AS m ON m.employee_id = e.manager_id
ORDER  BY e.department, e.position;

--Вариант Б 
--Б.1. Поставщики и сырьё
SELECT * FROM suppliers ORDER BY supplier_id;
SELECT * FROM raw_materials ORDER BY material_group, material_name;

--Б.2. Проследите одну закупку
--Шаг 1. Заказ поставщику
SELECT po.*, s.supplier_name, e.full_name AS buyer
FROM   purchase_orders AS po
JOIN   suppliers       AS s ON s.supplier_id = po.supplier_id
JOIN   employees       AS e ON e.employee_id = po.employee_id
WHERE  po.po_number = 'ЗП-2024-00081';

--Шаг 2. Что заказали и что приняли
SELECT m.material_name, m.unit, poi.quantity, poi.unit_price,
       poi.received_qty, poi.received_date, poi.quality_status
FROM   purchase_order_items AS poi
JOIN   raw_materials        AS m ON m.material_id = poi.material_id
WHERE  poi.po_id = 81;

--Б.3. Производственные линии
SELECT l.*, e.full_name AS responsible
FROM   production_lines AS l
JOIN   employees        AS e ON e.employee_id = l.responsible_id
ORDER  BY l.line_id;

--Б.4. Проследите одну производственную партию
--Шаг 1. Партия
SELECT b.*, p.product_name, e.full_name AS operator
FROM   production_batches AS b
JOIN   products           AS p ON p.product_id  = b.product_id
JOIN   employees          AS e ON e.employee_id = b.operator_id
WHERE  b.batch_number = 'П250312-3Н';

--Шаг 2.Рецептура продукта (норма на 1 шт.)
SELECT m.material_name, m.unit, r.qty_per_unit
FROM   recipes       AS r
JOIN   raw_materials AS m ON m.material_id = r.material_id
WHERE  r.product_id = 7;

--Шаг 3. Расход сырья: факт и норма
SELECT m.material_name,
       mc.quantity                               AS fact_qty,
       ROUND(r.qty_per_unit * b.produced_qty, 3) AS norm_qty
FROM   material_consumption AS mc
JOIN   production_batches   AS b ON b.batch_id = mc.batch_id
JOIN   raw_materials        AS m ON m.material_id = mc.material_id
JOIN   recipes              AS r ON r.product_id = b.product_id
                                AND r.material_id = mc.material_id
WHERE  b.batch_number = 'П250312-3Н';

--Б.5. События-потери: простои и списания
SELECT * FROM equipment_downtime ORDER BY start_time LIMIT 10;
SELECT * FROM material_writeoffs ORDER BY writeoff_date LIMIT 10;

--Б.6. Бизнес-правила
SELECT quality_status, COUNT(*) AS items_cnt
FROM   purchase_order_items
GROUP  BY quality_status
ORDER  BY items_cnt DESC;
