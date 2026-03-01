/*
CREATE TABLE wm_hourly_readings (
id varchar(100) unique primary key not null,
hour timestamp,
avg_temperature float,
avg_humidity float,
wind_speed_gust_mph float,
wind_speed_avg_mph float,
wind_speed_direction varchar(5),
rainfall_hour float,
rainfall_day float
);

create unique index idx_wm_hourly_readings_id on wm_hourly_readings (id);
create unique index idx_wm_hourly_readings_id_hour on wm_hourly_readings (id, hour);
*/

/*
They can be run at any time (and any number of times), but they will
give the most complete and accurate results when run after the top of the hour,
looking back on hours with readings that are "complete".

You can adjust or remove the `AND date_trunc` part of the WHERE clause to adjust how far back the query will go

You could e.g. use cron to run hourly at ten minutes after:

```
# m h  dom mon dow   command
10 * * * * echo "select wm_update_hourly_summaries();" | psql -h localhost -U username -d database
```

A `~/.pgpass` file can be used to store the password for psql
*/

CREATE OR REPLACE FUNCTION public.wm_update_hourly_summaries(
	)
    RETURNS void
    LANGUAGE 'sql'
    COST 100
    VOLATILE STRICT PARALLEL UNSAFE
AS $BODY$

-- TEMPERATURE
INSERT INTO wm_hourly_readings (id, hour, avg_temperature)
SELECT
	SPLIT_PART(topic, '/', 2)||'_'||to_char(date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt'), 'YYYYMMDDHH24') as id,
	date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') as hour,
	avg(text::float) AS avg_temperature
FROM journal
WHERE 
	topic = 'iot/pico/temperature_avg'
	AND text::float < 118 AND text::float > -118 -- weed out outliers/erroneous readings
	AND date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') = date_trunc('hour', current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 hour')-- previous hour
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

-- WIND AND RAIN
INSERT INTO wm_hourly_readings (id, hour, rainfall_hour, rain_day, wind_speed_avg_mph, wind_speed_gust_mph, wind_speed_direction)
SELECT
	SPLIT_PART(topic, '/', 2)||'_'||to_char(date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt'), 'YYYYMMDDHH24') as id,
	date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') as hour,
	max((data->'rain_hr'->'measurement')::float) AS rainfall_hour,
	max((data->'rain_day'->'measurement')::float) AS rainfall_day,
	max((data->'wind'->'speed_mph')::float) AS wind_speed_avg_mph,
	max((data->'wind'->'gust_mph')::float) AS wind_speed_gust_mph,
	mode() WITHIN GROUP (ORDER BY data->'wind'->'direction') AS wind_speed_direction
FROM journal
WHERE
	topic = 'iot/pico/readings_json'
	--AND data->'wind' IS NOT null
	AND date_trunc('hour', time::timestamptz AT TIME ZONE 'cdt') = date_trunc('hour', current_timestamp AT TIME ZONE 'cdt' - INTERVAL '1 hour')-- previous hour
GROUP BY 1,2 ORDER BY 1,2
ON CONFLICT(id, hour) DO UPDATE SET
  rainfall_hour = EXCLUDED.rainfall_hour,
  rainfall_day = EXCLUDED.rainfall_day,
  wind_speed_avg_mph = EXCLUDED.wind_speed_avg_mph,
  wind_speed_gust_mph = EXCLUDED.wind_speed_gust_mph,
  wind_speed_direction = EXCLUDED.wind_speed_direction;

$BODY$;

/*
select wm_update_hourly_summaries();
select mode() WITHIN GROUP (ORDER BY data->'wind'->'direction') AS wind_speed_direction from journal;
select * from journal where left(topic,3)='iot' order by journal_id desc limit 15;
select data->'wind'->'direction' from journal where left(topic,3)='iot'  and data->'wind' is not null order by journal_id desc limit 15;
SELECT * FROM wm_hourly_readings order by hour desc limit 2;
*/
