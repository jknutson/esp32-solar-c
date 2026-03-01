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
AND text::float < 115 AND text::float > -115-- weed out outliers/erroneous readings
-- AND DATE(time::timestamp) = DATE(current_date) -- today
AND DATE(time::timestamp AT TIME ZONE 'cdt') = DATE(current_timestamp - INTERVAL '1 day') -- yesterday
GROUP BY 1;


CREATE UNIQUE INDEX idx_summaries_time_station on wm_daily_summaries ("date", station);

CREATE OR REPLACE FUNCTION wm_update_yesterday_summaries()
       RETURNS VOID AS 
       $$
      INSERT INTO wm_daily_summaries
      SELECT
      DATE(time::timestamptz AT TIME ZONE 'cdt') as "date",
      MIN(text::float) as min_temperature,
      MAX(text::float) as max_temperature,
      AVG(text::float) as avg_temperature,
      SPLIT_PART(topic, '/', 2) as station
      FROM journal
      WHERE RIGHT(topic, 11) = 'temperature'
      AND text::float < 115 AND text::float > -115-- weed out outliers/erroneous readings
      -- AND DATE(time::timestamp) = DATE(current_date) -- today
      AND DATE(time::timestamptz AT TIME ZONE 'cdt') = DATE(current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 day') -- yesterday
      GROUP BY 1,5
      ON CONFLICT("date", station) -- TODO: ensure this will work when we have multiple stations
      DO UPDATE
        SET min_temperature = EXCLUDED.min_temperature, max_temperature = EXCLUDED.max_temperature, avg_temperature = EXCLUDED.avg_temperature;
      $$
      LANGUAGE sql STRICT;



-- select time,time::timestamp,time::timestamptz at time zone 'cst' from journal order by 1 desc limit 5;

SELECT * FROM journal LIMIT 1;

SELECT current_date - INTEGER '1' AS yesterday_date;

SELECT (current_date - INTERVAL '1 day')::date AS yesterday_date;

SELECT (current_date - INTERVAL '2 month')::date AS month_ago_date;

/* view for past 24 hours worth of hourly summaries */
CREATE OR REPLACE VIEW public.wm_readings_24_hours AS
SELECT id, hour, avg_temperature, avg_humidity, wind_speed_gust_mph, wind_speed_avg_mph, replace(wind_speed_direction, '"', '') as wind_speed_direction, rainfall_hour, rainfall_day
	FROM public.wm_hourly_readings order by hour desc limit 24;
