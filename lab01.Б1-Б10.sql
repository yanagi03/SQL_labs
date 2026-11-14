--Подготовка
SET search_path TO pitanie, public;
SELECT COUNT(*) FROM orders;      -- 4458 — подключение работает

--Б1 Партии с высоким браком 
--Партии с процентом брака > 5 
SELECT batch_id, batch_number, line_id, shift, production_date, planned_qty, produced_qty, defect_qty,
    ROUND(100.0 * defect_qty / NULLIF(produced_qty, 0),2) AS defect_percent
FROM production_batches
WHERE defect_qty > 0.05 * produced_qty
ORDER BY defect_qty * 1.0 / NULLIF(produced_qty, 0) DESC;

--Определение проблемной линии и смены 
 SELECT line_id, shift,
    COUNT(*) AS defective_batches
FROM production_batches
WHERE defect_qty > 0.05 * produced_qty
GROUP BY line_id, shift
ORDER BY defective_batches DESC;

--Гипотеза: Повышенный уровень брака связан с определённой 
--комбинацией производственной линии и рабочей смены. Возможно, 
--причиной является особенность технологического процесса, 
--состояние оборудования или условия работы в конкретную смену

-- Проверка гипотезы
WITH problem_combo AS (
    SELECT line_id, shift
    FROM production_batches
    WHERE defect_qty > 0.05 * produced_qty
    GROUP BY line_id, shift
    ORDER BY COUNT(*) DESC
    LIMIT 1)
SELECT COUNT(*) AS exceptions_count
FROM production_batches pb
CROSS JOIN problem_combo pc
WHERE pb.defect_qty > 0.05 * pb.produced_qty
  AND NOT (pb.line_id = pc.line_id AND pb.shift = pc.shift);

--Сколько всего партий у этой линии в эту смену 
SELECT line_id, shift,
    COUNT(*) AS total_batches,
    COUNT(*) FILTER (
        WHERE defect_qty > 0.05 * produced_qty) AS high_defect_batches,
    ROUND(100.0 * COUNT(*) FILTER ( WHERE defect_qty > 0.05 * produced_qty) / COUNT(*),2) AS problem_share_percent
FROM production_batches
GROUP BY line_id, shift
HAVING COUNT(*) FILTER (
    WHERE defect_qty > 0.05 * produced_qty) > 0
ORDER BY high_defect_batches DESC;

--Б2 Кто работает в проблемной смене 
--Найти операторов 
WITH problem_combo AS (
    SELECT line_id, shift
    FROM production_batches
    WHERE defect_qty > 0.05 * produced_qty
    GROUP BY line_id, shift
    ORDER BY COUNT(*) DESC
    LIMIT 1)
SELECT DISTINCT pb.operator_id
FROM production_batches pb
JOIN problem_combo pc
    ON pb.line_id = pc.line_id
   AND pb.shift = pc.shift
ORDER BY pb.operator_id;

--ФИО операторов 
WITH problem_combo AS (
    SELECT line_id, shift
    FROM production_batches
    WHERE defect_qty > 0.05 * produced_qty
    GROUP BY line_id, shift
    ORDER BY COUNT(*) DESC
    LIMIT 1)
SELECT DISTINCT e.employee_id, e.full_name, e.position, e.department
FROM production_batches pb
JOIN problem_combo pc
    ON pb.line_id = pc.line_id
   AND pb.shift = pc.shift
JOIN employees e
    ON pb.operator_id = e.employee_id
ORDER BY e.full_name;

--Б3 Незакрытые простои
SELECT downtime_id, line_id, start_time, end_time, reason, downtime_category
FROM equipment_downtime
WHERE end_time IS NULL
ORDER BY start_time ASC;

--Б4 Простои линии 2
-- Простои за 2024 и 2025 годы
SELECT EXTRACT(YEAR FROM start_time)::INT AS year,
    COUNT(*) AS downtime_count
FROM equipment_downtime
WHERE line_id = 2
  AND start_time >= TIMESTAMP '2024-01-01'
  AND start_time < TIMESTAMP '2026-01-01'
GROUP BY EXTRACT(YEAR FROM start_time)
ORDER BY year;

--Поломки вызванные износом или отказом 
SELECT downtime_id, line_id, start_time, end_time, reason, downtime_category
FROM equipment_downtime
WHERE line_id = 2
  AND start_time >= TIMESTAMP '2025-01-01'
  AND start_time < TIMESTAMP '2026-01-01'
  AND (reason ILIKE '%износ%' OR reason ILIKE 'отказ%')
ORDER BY start_time;

--Б5 Поставки с отклонением качества
--Вывести позиции поставок с проблемной приемкой 
SELECT po_item_id, po_id, material_id, quantity, received_qty, received_date, quality_status, unit_price
FROM purchase_order_items
WHERE quality_status IN ('Принято частично','Отклонено')
ORDER BY received_date ASC NULLS LAST;

--Сравнить варианты проверки статуса 
SELECT COUNT(*) AS not_accepted_count
FROM purchase_order_items
WHERE quality_status <> 'Принято';

--Только молочное сырье 
SELECT po_item_id, po_id, material_id, received_date, received_qty, quality_status
FROM purchase_order_items
WHERE quality_status IN ('Принято частично','Отклонено')
AND material_id IN (1, 2)
ORDER BY received_date;

--Б6 Поставщики "на проверку"
SELECT supplier_id, supplier_name, rating, region_id, contract_date, payment_terms_days, phone
FROM suppliers
WHERE rating IS NULL
   OR rating < 4.0
ORDER BY rating ASC NULLS FIRST;

--Б7. Недовыпуск 
--Вывести топ-10 партий по недовыпуску
SELECT batch_id, batch_number,line_id, shift, production_date, planned_qty, produced_qty,planned_qty - produced_qty AS shortfall_qty,
ROUND(100.0 * produced_qty / NULLIF(planned_qty, 0),1) AS plan_completion_percent
FROM production_batches
ORDER BY shortfall_qty DESC
FETCH FIRST 10 ROWS WITH TIES;

--Партии с выполнением плана ниже 90%
SELECT COUNT(*) AS underperforming_batches
FROM production_batches
WHERE produced_qty < 0.9 * planned_qty;

--Распределение партий по годам 
SELECT line_id, EXTRACT(YEAR FROM production_date)::INT AS year, COUNT(*) AS batches_count
FROM production_batches
WHERE produced_qty < 0.9 * planned_qty
GROUP BY line_id, EXTRACT(YEAR FROM production_date)
ORDER BY batches_count DESC;

--Гипотеза об одной линии и одном годе 
WITH problem_group AS (
    SELECT line_id, EXTRACT(YEAR FROM production_date)::INT AS year
    FROM production_batches
    WHERE produced_qty < 0.9 * planned_qty
    GROUP BY line_id, EXTRACT(YEAR FROM production_date)
    ORDER BY COUNT(*) DESC
    LIMIT 1)
SELECT COUNT(*) AS exceptions_count
FROM production_batches pb
CROSS JOIN problem_group pg
WHERE pb.produced_qty < 0.9 * pb.planned_qty
  AND NOT (pb.line_id = pg.line_id AND EXTRACT(YEAR FROM pb.production_date)::INT = pg.year);


--Б8 Списания сырья 
-- 10 крупнейших списаний просроченной продукции 
SELECT writeoff_id, material_id, writeoff_date, quantity, reason, amount
FROM material_writeoffs
WHERE reason = 'Истёк срок годности'
ORDER BY amount DESC
LIMIT 10;

--Название сырья и срок годности 
SELECT mw.writeoff_id, mw.material_id, rm.material_name, rm.shelf_life_days, mw.writeoff_date, mw.quantity, mw.amount
FROM material_writeoffs mw
JOIN raw_materials rm
    ON mw.material_id = rm.material_id
WHERE mw.reason = 'Истёк срок годности'
ORDER BY mw.amount DESC
LIMIT 10;

--Наибольшая сумма списаний 
SELECT mw.material_id, rm.material_name, rm.shelf_life_days,
COUNT(*) AS writeoffs_count, SUM(mw.amount) AS total_writeoff_rub
FROM material_writeoffs mw
JOIN raw_materials rm
    ON mw.material_id = rm.material_id
WHERE mw.reason = 'Истёк срок годности'
GROUP BY
    mw.material_id,
    rm.material_name,
    rm.shelf_life_days
ORDER BY total_writeoff_rub DESC;

--Б9 Цифры для руководства
--Количество и сумма списаний материала 10 
SELECT COUNT(*) AS writeoffs, SUM(amount) AS writeoff_rub
FROM material_writeoffs
WHERE material_id = 10
  AND reason = 'Истёк срок годности';

--Недовыпуск линии 2 за 2025 год
SELECT SUM(planned_qty - produced_qty) AS line2_2025_shortfall_units
FROM production_batches
WHERE line_id = 2
  AND production_date >= DATE '2025-01-01';
