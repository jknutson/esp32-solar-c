/*
SELECT SPLIT_PART(topic, '/', 2) as device, text as temperature FROM journal
WHERE RIGHT(topic, 11) = 'temperature' ORDER BY text DESC ;
*/

SELECT 
SPLIT_PART(topic, '/', 2) as device,
MIN(text::float) as min_temperature, 
MAX(text::float) as max_temperature,
AVG(text::float) as avg_temperature
FROM journal
WHERE RIGHT(topic, 11) = 'temperature'
AND text::float < 500 -- weed out outliers/erroneous readings
GROUP BY 1;


SELECT * FROM journal

SELECT current_date - INTEGER '1' AS yesterday_date;

SELECT (current_date - INTERVAL '1 day')::date AS yesterday_date;

SELECT (current_date - INTERVAL '1 month')::date AS month_ago_date;
