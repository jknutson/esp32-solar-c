SELECT
	SPLIT_PART(topic, '/', 2)||'_'||to_char(date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt'), 'YYYYMMDDHH24') as id,
	date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') as hour,
	avg(text::float) AS avg_temperature
	-- ,SPLIT_PART(topic, '/', 2) as station
FROM journal
WHERE RIGHT(topic, 11) = 'temperature'
	AND text::float < 118 AND text::float > -118 -- weed out outliers/erroneous readings
	-- AND DATE(time::timestamp) = DATE(current_date) -- today
	-- AND DATE(time::timestamptz AT TIME ZONE 'cdt') = DATE(current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 day') -- yesterday
	AND date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') = date_trunc('hour', current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 hour')-- previous hour
GROUP BY 1,2
ORDER BY 1,2

CREATE TABLE wm_hourly_readings (
id varchar(100) unique primary key not null,
hour timestamp,
avg_temperature float,
avg_humidity float,
wind_speed_gust_mph float,
wind_speed_avg_mph float,
wind_speed_direction varchar(3),
rainfall_hour float,
rainfall_day float
);
create unique index idx_wm_hourly_readings_id_hour on wm_hourly_readings (id, hour);

-- TEMPERATURE
INSERT INTO wm_hourly_readings (id, hour, avg_temperature)
SELECT
	SPLIT_PART(topic, '/', 2)||'_'||to_char(date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt'), 'YYYYMMDDHH24') as id,
	date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') as hour,
	avg(text::float) AS avg_temperature
	-- ,SPLIT_PART(topic, '/', 2) as station
FROM journal
WHERE 
    -- RIGHT(topic, 11) = 'temperature'
	topic = 'iot/pico/temperature_avg'
	AND text::float < 118 AND text::float > -118 -- weed out outliers/erroneous readings
	-- AND DATE(time::timestamp) = DATE(current_date) -- today
	-- AND DATE(time::timestamptz AT TIME ZONE 'cdt') = DATE(current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 day') -- yesterday
	-- AND date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') = date_trunc('hour', current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 hour')-- previous hour
GROUP BY 1,2
ORDER BY 1,2
ON CONFLICT(id, hour)
DO UPDATE
SET avg_temperature = EXCLUDED.avg_temperature;

-- HUMIDITY
INSERT INTO wm_hourly_readings (id, hour, avg_humidity)
SELECT
	SPLIT_PART(topic, '/', 2)||'_'||to_char(date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt'), 'YYYYMMDDHH24') as id,
	date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') as hour,
	avg(text::float) AS avg_humidity
FROM journal
WHERE 
	topic = 'iot/pico/humidity_avg'
	AND text::float < 118 AND text::float > -118 -- weed out outliers/erroneous readings
	AND date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') = date_trunc('hour', current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 hour')-- previous hour
GROUP BY 1,2 ORDER BY 1,2
ON CONFLICT(id, hour) DO UPDATE SET avg_humidity = EXCLUDED.avg_humidity;

-- WIND SPEED GUST (MAX)
INSERT INTO wm_hourly_readings (id, hour, wind_speed_gust_mph)
SELECT
	SPLIT_PART(topic, '/', 2)||'_'||to_char(date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt'), 'YYYYMMDDHH24') as id,
	date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') as hour,
	max(text::float) AS wind_speed_gust_mph
FROM journal
WHERE 
	topic = 'iot/pico/wind_speed_gust_mph'
	AND text::float < 118 AND text::float > -118 -- weed out outliers/erroneous readings
	-- AND date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') = date_trunc('hour', current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 hour')-- previous hour
GROUP BY 1,2 ORDER BY 1,2
ON CONFLICT(id, hour) DO UPDATE SET wind_speed_gust_mph = EXCLUDED.wind_speed_gust_mph;

-- WIND SPEED AVG (MAX/HOUR)
INSERT INTO wm_hourly_readings (id, hour, wind_speed_avg_mph)
SELECT
	SPLIT_PART(topic, '/', 2)||'_'||to_char(date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt'), 'YYYYMMDDHH24') as id,
	date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') as hour,
	max(text::float) AS wind_speed_avg_mph
FROM journal
WHERE 
	topic = 'iot/pico/wind_speed_avg_mph'
	AND text::float < 118 AND text::float > -118 -- weed out outliers/erroneous readings
	-- AND date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') = date_trunc('hour', current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 hour')-- previous hour
GROUP BY 1,2 ORDER BY 1,2
ON CONFLICT(id, hour) DO UPDATE SET wind_speed_avg_mph = EXCLUDED.wind_speed_avg_mph;

-- RAINFALL (HOUR) (MAX)
-- TODO: we are doing hourly aggregation in python also, let's see if doing max() makes sense here
INSERT INTO wm_hourly_readings (id, hour, rainfall_hour)
SELECT
	SPLIT_PART(topic, '/', 2)||'_'||to_char(date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt'), 'YYYYMMDDHH24') as id,
	date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') as hour,
	max(text::float) AS rainfall_hour
FROM journal
WHERE 
	topic = 'iot/pico/rain_in_hr'
	AND text::float < 118 AND text::float > -118 -- weed out outliers/erroneous readings
	-- AND date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') = date_trunc('hour', current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 hour')-- previous hour
GROUP BY 1,2 ORDER BY 1,2
ON CONFLICT(id, hour) DO UPDATE SET rainfall_hour = EXCLUDED.rainfall_hour;



select * from journal where left(topic,3)='iot' order by journal_id desc limit 15;
SELECT * FROM wm_hourly_readings order by hour desc limit 2;
