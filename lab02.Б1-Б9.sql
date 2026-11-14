-- Модуль 2. Приводим данные в порядок и считаем точно

SET search_path TO pitanie, public;
SET lc_time = 'ru_RU.UTF-8';

-- О1. Названия и типы столбцов production_batches
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'pitanie'
  AND table_name = 'production_batches'
ORDER BY ordinal_position;

-- Только целочисленные столбцы
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'pitanie'
  AND table_name = 'production_batches'
  AND data_type IN ('smallint', 'integer', 'bigint')
ORDER BY ordinal_position;

-- О2. Календарь декабря 2025 года
SELECT d::date AS calendar_date,
       TO_CHAR(d, 'TMDay') AS day_of_week,
       CASE
           WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN 'выходной'
           ELSE 'рабочий'
       END AS day_type
FROM generate_series(DATE '2025-12-01',
                     DATE '2025-12-31',
                     INTERVAL '1 day') AS dates(d)
ORDER BY d;

-- Б1. Десять самых долгих закрытых простоев
SELECT d.downtime_id,
       l.line_name,
       d.start_time,
       d.end_time,
       (d.end_time - d.start_time)::text AS duration,
       ROUND(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600, 2)
           AS hours
FROM equipment_downtime AS d
JOIN production_lines AS l ON d.line_id = l.line_id
WHERE d.end_time IS NOT NULL
ORDER BY d.end_time - d.start_time DESC
LIMIT 10;

-- Б2. Незакрытые простои на 01.01.2026
SELECT d.downtime_id,
       d.line_id,
       d.start_time,
       DATE '2026-01-01' - d.start_time::date AS open_days,
       ROUND(EXTRACT(EPOCH FROM TIMESTAMP '2026-01-01 00:00' - d.start_time)
             / 3600, 2) AS possible_hours
FROM equipment_downtime AS d
WHERE d.end_time IS NULL
ORDER BY d.start_time;

-- Б3. Простои линии 2 по годам (готовый запрос из задания)
SELECT EXTRACT(YEAR FROM start_time) AS yr,
       COUNT(*) AS events,
       ROUND(SUM(EXTRACT(EPOCH FROM end_time - start_time)) / 3600, 1)
           AS hours
FROM equipment_downtime
WHERE line_id = 2
GROUP BY EXTRACT(YEAR FROM start_time)
ORDER BY yr;

-- Б4. Правильный расчет процента брака

AND poi.received_date::date - po.expected_date::date >= 4;

-- Б6.3. Какие поставщики допустили эти опоздания и какой у них рейтинг?
SELECT DISTINCT s.supplier_id, s.supplier_name, s.rating
FROM purchase_order_items AS poi
JOIN purchase_orders AS po ON poi.po_id = po.po_id
JOIN suppliers AS s ON po.supplier_id = s.supplier_id
WHERE poi.received_date IS NOT NULL
  AND poi.received_date::date - po.expected_date::date >= 4;


-- Б7. Возраст производственных линий на 31.12.2025
SELECT l.line_id,
       l.line_name,
       l.launch_year,
       2025 - l.launch_year AS age_years,
       AGE(DATE '2025-12-31', MAKE_DATE(l.launch_year, 1, 1)) AS exact_age,
       CASE
           WHEN 2025 - l.launch_year >= 15 THEN 'кандидат на модернизацию'
           WHEN 2025 - l.launch_year BETWEEN 8 AND 14 THEN 'плановый контроль'
           ELSE 'в норме'
       END AS line_status
FROM production_lines AS l
ORDER BY age_years DESC;

-- Б8. Стоимость списаний

-- Б8.1. Десять самых дорогих списаний с истекшим сроком годности
SELECT r.material_name,
       w.quantity,
       w.amount,
       ROUND(w.amount / w.quantity, 2) AS price_per_unit,
       ROUND(w.amount, -3) AS amount_thousands,
       TO_CHAR(w.amount, 'FM999G999G990D00') AS amount_formatted
FROM material_writeoffs AS w
JOIN raw_materials AS r ON w.material_id = r.material_id
WHERE w.reason = 'Истёк срок годности'
ORDER BY w.amount DESC
LIMIT 10;

-- Б8.2. На всех списаниях деление amount / quantity может вызвать ошибку,
SELECT w.writeoff_id,
       w.material_id,
       w.quantity,
       w.amount,
       ROUND(w.amount / NULLIF(w.quantity, 0), 2) AS price_per_unit
FROM material_writeoffs AS w;

-- Проверка: 7 списаний с нулевым количеством.
SELECT COUNT(*) AS zero_quantity_count
FROM material_writeoffs AS w
WHERE w.quantity = 0;

-- Б8.3. Общая сумма списаний материала из первой строки Б8.1
SELECT r.material_name,
       SUM(w.amount) AS total_amount,
       ROUND(SUM(w.amount), -3) AS amount_thousands,
       ROUND(SUM(w.amount) / 1000000.0, 2) AS amount_millions
FROM material_writeoffs AS w
JOIN raw_materials AS r ON w.material_id = r.material_id
WHERE w.reason = 'Истёк срок годности'
  AND w.material_id = (
      SELECT w2.material_id
      FROM material_writeoffs AS w2
      WHERE w2.reason = 'Истёк срок годности'
      ORDER BY w2.amount DESC
      LIMIT 1)
GROUP BY r.material_name;

-- Б9*. Когда ломается линия 2 в 2025 году
SELECT d.downtime_id,
       TO_CHAR(d.start_time, 'TMDy') AS weekday,
       EXTRACT(HOUR FROM d.start_time) AS start_hour,
       CASE
           WHEN EXTRACT(HOUR FROM d.start_time) BETWEEN 8 AND 19
               THEN 'день'
           ELSE 'ночь'
       END AS time_of_day,
       ROUND(EXTRACT(EPOCH FROM d.end_time - d.start_time) / 3600, 2)
           AS downtime_hours
FROM equipment_downtime AS d
WHERE d.line_id = 2
  AND d.downtime_category = 'Поломка оборудования'
  AND d.start_time >= TIMESTAMP '2025-01-01'
  AND d.start_time < TIMESTAMP '2026-01-01'
ORDER BY d.start_time;
