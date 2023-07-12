/*
SELECT SPLIT_PART(topic, '/', 2) as device, text as temperature FROM journal
WHERE RIGHT(topic, 11) = 'temperature' ORDER BY text DESC ;
 */

-- daily temperature average
SELECT
SPLIT_PART(topic, '/', 2) as device,
MIN(text::float) as min_temperature,
MAX(text::float) as max_temperature,
AVG(text::float) as avg_temperature
FROM journal
WHERE RIGHT(topic, 11) = 'temperature'
AND text::float < 120 AND text::float > -120-- weed out outliers/erroneous readings
-- AND DATE(time::timestamp) = DATE(current_date) -- today
AND DATE(time::timestamp) = (current_date - INTERVAL '1 day')::date -- yesterday
GROUP BY 1;


SELECT * FROM journal LIMIT 1;

SELECT current_date - INTEGER '1' AS yesterday_date;

SELECT (current_date - INTERVAL '1 day')::date AS yesterday_date;

SELECT (current_date - INTERVAL '2 month')::date AS month_ago_date;

