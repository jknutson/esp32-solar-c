#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "esp_wifi.h"
#include "esp_system.h"
#include "nvs_flash.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "protocol_examples_common.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/queue.h"

#include "lwip/sockets.h"
#include "lwip/dns.h"
#include "lwip/netdb.h"

#include "esp_system.h"
#include "esp_log.h"
#include "mqtt_client.h"
#include "driver/gpio.h"
#include "driver/adc.h"
#include "esp_adc_cal.h"

#include "owb.h"
#include "owb_rmt.h"
#include "ds18b20.h"

#define GPIO_DS18B20_0       (CONFIG_ONE_WIRE_GPIO)
#define MAX_DEVICES          (8)
#define DS18B20_RESOLUTION   (DS18B20_RESOLUTION_12_BIT)
#define NO_OF_SAMPLES        64        // Multisampling
#define SAMPLE_PERIOD        (30000)   // milliseconds
#define DEFAULT_VREF         3300      // should this be 1100? readings seemed low at that value

static esp_adc_cal_characteristics_t *adc_chars;
static const adc_channel_t current_channel = ADC_CHANNEL_6; // ADC1 CH6 == GPIO34
static const adc_channel_t voltage_channel = ADC_CHANNEL_7; // ADC1 CH7 == GPIO35
static const adc_bits_width_t width = ADC_WIDTH_BIT_12;
static const adc_atten_t atten = ADC_ATTEN_DB_0;
static const adc_unit_t unit = ADC_UNIT_1;

// TODO: OneWire & ADC Tags
static const char *TAG = "ESP-SOLAR";
char *MQ_TOPIC_BASE = "iot/esp32";

float acs712_voltage_to_current(uint32_t v) {
	const int acs712_offset_mv = 2500;  // 2.5V == 0A
	const int acs712_sens_mv_a = 100;   // 100mV/a
	// not going to bother with negative current for now
	if (v <= acs712_offset_mv) {
		return 0;
	}
	return ((int)v - 2500) / acs712_sens_mv_a;
}

void app_main() {
	// Application/System Setup
	ESP_ERROR_CHECK(nvs_flash_init());
	ESP_ERROR_CHECK(esp_netif_init());
	ESP_ERROR_CHECK(esp_event_loop_create_default());
	// this could be improved, see protocols/README.md in esp-idf/examples
	ESP_ERROR_CHECK(example_connect());
	// Override global log level
	esp_log_level_set("*", ESP_LOG_INFO);
	// To debug, use 'make menuconfig' to set default Log level to DEBUG, then uncomment:
	//esp_log_level_set("owb", ESP_LOG_DEBUG);
	//esp_log_level_set("ds18b20", ESP_LOG_DEBUG);
	// get MAC addr to use as "unique" identifier
	uint8_t mac_i[6] = {0};
	esp_read_mac(mac_i, ESP_MAC_WIFI_STA);
	ESP_LOGI(TAG, "MAC Address: %02X%02X%02X%02X%02X%02X", mac_i[0], mac_i[1], mac_i[2], mac_i[3], mac_i[4], mac_i[5]);
	char s_mac[13];  // 12 chars + 1 for nul
	sprintf(s_mac, "%02X%02X%02X%02X%02X%02X", mac_i[0], mac_i[1], mac_i[2], mac_i[3], mac_i[4], mac_i[5]);

	// ADC setup
	// Check if Two Point or Vref are burned into eFuse
	adc1_config_width(width);
	adc1_config_channel_atten(current_channel, atten);
	adc1_config_channel_atten(voltage_channel, atten);
	// Characterize ADC
	adc_chars = calloc(1, sizeof(esp_adc_cal_characteristics_t));
	esp_adc_cal_characterize(unit, atten, width, DEFAULT_VREF, adc_chars);

	// OneWire/DS18B20
	// Stable readings require a brief period before communication
	vTaskDelay(2000.0 / portTICK_PERIOD_MS);
	// Create a 1-Wire bus, using the RMT timeslot driver
	OneWireBus * owb;
	owb_rmt_driver_info rmt_driver_info;
	owb = owb_rmt_initialize(&rmt_driver_info, GPIO_DS18B20_0, RMT_CHANNEL_1, RMT_CHANNEL_0);
	owb_use_crc(owb, true);  // enable CRC check for ROM code
	// Find all connected devices
	ESP_LOGI(TAG, "Find OneWire devices");
	OneWireBus_ROMCode device_rom_codes[MAX_DEVICES] = {0};
	int num_devices = 0;
	OneWireBus_SearchState search_state = {0};
	bool found = false;
	owb_search_first(owb, &search_state, &found);

	// MQTT
	esp_mqtt_client_config_t mqtt_cfg = {
		.uri = CONFIG_BROKER_URL,
	};
	esp_mqtt_client_handle_t client = esp_mqtt_client_init(&mqtt_cfg);
	esp_mqtt_client_start(client);
	while (found)
	{
		char rom_code_s[17];
		owb_string_from_rom_code(search_state.rom_code, rom_code_s, sizeof(rom_code_s));
		ESP_LOGI(TAG, "OneWire Device Found -  id:%d, rom_code:%s", num_devices, rom_code_s);
		device_rom_codes[num_devices] = search_state.rom_code;
		++num_devices;
		owb_search_next(owb, &search_state, &found);
	}

	// In this example, if a single device is present, then the ROM code is probably
	// not very interesting, so just print it out. If there are multiple devices,
	// then it may be useful to check that a specific device is present.

	if (num_devices == 1)
	{
		// For a single device only:
		OneWireBus_ROMCode rom_code;
		owb_status status = owb_read_rom(owb, &rom_code);
		if (status == OWB_STATUS_OK)
		{
			char rom_code_s[OWB_ROM_CODE_STRING_LENGTH];
			owb_string_from_rom_code(rom_code, rom_code_s, sizeof(rom_code_s));
			ESP_LOGI(TAG, "Single device %s present", rom_code_s);
		}
		else
		{
			ESP_LOGI(TAG, "An error occurred reading ROM code: %d", status);
		}
	}
	else
	{
		// Search for a known ROM code (LSB first):
		// For example: 0x1502162ca5b2ee28
		OneWireBus_ROMCode known_device = {
			.fields.family = { 0x28 },
			.fields.serial_number = { 0xee, 0xb2, 0xa5, 0x2c, 0x16, 0x02 },
			.fields.crc = { 0x15 },
		};
		char rom_code_s[OWB_ROM_CODE_STRING_LENGTH];
		owb_string_from_rom_code(known_device, rom_code_s, sizeof(rom_code_s));
		bool is_present = false;

		owb_status search_status = owb_verify_rom(owb, known_device, &is_present);
		if (search_status == OWB_STATUS_OK)
		{
			ESP_LOGI(TAG, "Device %s is %s", rom_code_s, is_present ? "present" : "not present");
		}
		else
		{
			ESP_LOGI(TAG, "An error occurred searching for known device: %d", search_status);
		}
	}

	// Create DS18B20 devices on the 1-Wire bus
	DS18B20_Info * devices[MAX_DEVICES] = {0};
	for (int i = 0; i < num_devices; ++i)
	{
		DS18B20_Info * ds18b20_info = ds18b20_malloc();  // heap allocation
		devices[i] = ds18b20_info;

		if (num_devices == 1)
		{
			ESP_LOGI(TAG, "Single device optimisations enabled");
			ds18b20_init_solo(ds18b20_info, owb);          // only one device on bus
		}
		else
		{
			ds18b20_init(ds18b20_info, owb, device_rom_codes[i]); // associate with bus and device
		}
		ds18b20_use_crc(ds18b20_info, true);           // enable CRC check on all reads
		ds18b20_set_resolution(ds18b20_info, DS18B20_RESOLUTION);
	}

	// Check for parasitic-powered devices
	bool parasitic_power = false;
	ds18b20_check_for_parasite_power(owb, &parasitic_power);
	if (parasitic_power) {
		ESP_LOGI(TAG, "Parasitic-powered devices detected");
	}

	// In parasitic-power mode, devices cannot indicate when conversions are complete,
	// so waiting for a temperature conversion must be done by waiting a prescribed duration
	owb_use_parasitic_power(owb, parasitic_power);

#ifdef CONFIG_ENABLE_STRONG_PULLUP_GPIO
	// An external pull-up circuit is used to supply extra current to OneWireBus devices
	// during temperature conversions.
	owb_use_strong_pullup_gpio(owb, CONFIG_STRONG_PULLUP_GPIO);
#endif

	// Read temperatures more efficiently by starting conversions on all devices at the same time
	int errors_count[MAX_DEVICES] = {0};
	// TODO: allow this to work without temp sensor
	if (num_devices > 0) {
		TickType_t last_wake_time = xTaskGetTickCount();

		// main loop
		for (;;) {
			ds18b20_convert_all(owb);

			// In this application all devices use the same resolution,
			// so use the first device to determine the delay
			ds18b20_wait_for_conversion(devices[0]);

			// Read the results immediately after conversion otherwise it may fail
			// (using printf before reading may take too long)
			float readings[MAX_DEVICES] = { 0 };
			DS18B20_ERROR errors[MAX_DEVICES] = { 0 };

			for (int i = 0; i < num_devices; ++i) {
				errors[i] = ds18b20_read_temp(devices[i], &readings[i]);
			}

			// Print results in a separate loop, after all have been read
			for (int i = 0; i < num_devices; ++i) {
				if (errors[i] != DS18B20_OK) {
					++errors_count[i];
				}

				// ESP_LOGI(TAG, "  %d: %.1f    %d errors", i, readings[i], errors_count[i]);
				float temp_f = (readings[i] * 9 / 5) + 32;
				char s_temp_f[8];  // TODO: figure out what size this should be
				char mq_topic_temp_f[128]; // TODO: figure out size of this char array
				sprintf(s_temp_f, "%.2f", temp_f);
				sprintf(mq_topic_temp_f, "%s-%s-%i/temperature_f", MQ_TOPIC_BASE, s_mac, i);
				// publish MQTT message(s)
				int temp_f_msg_id = esp_mqtt_client_publish(client, mq_topic_temp_f, s_temp_f, 0, 0, 0);
				ESP_LOGI(TAG, "MQTT published - topic:%s, payload:%s, id:%i", mq_topic_temp_f, s_temp_f, temp_f_msg_id);
			}

			// ADC Readings
			uint32_t adc_current_reading = 0;
			uint32_t adc_voltage_reading = 0;
			//Multisampling
			for (int i = 0; i < NO_OF_SAMPLES; i++) {
				if (unit == ADC_UNIT_1) {
					adc_current_reading += adc1_get_raw((adc1_channel_t)current_channel);
					adc_voltage_reading += adc1_get_raw((adc1_channel_t)voltage_channel);
				} else {
					int current_raw;
					int voltage_raw;
					adc2_get_raw((adc2_channel_t)current_channel, width, &current_raw);
					adc2_get_raw((adc2_channel_t)voltage_channel, width, &voltage_raw);
					adc_current_reading += current_raw;
					adc_voltage_reading += voltage_raw;
				}
			}
			adc_current_reading /= NO_OF_SAMPLES;
			adc_voltage_reading /= NO_OF_SAMPLES;
			uint32_t adc_current_v = esp_adc_cal_raw_to_voltage(adc_current_reading, adc_chars);
			uint32_t adc_voltage_v = esp_adc_cal_raw_to_voltage(adc_voltage_reading, adc_chars);
			char s_current[8];  // TODO: figure out what size this should be
			char s_voltage[8];  // TODO: figure out what size this should be
			char mq_current_topic[128]; // TODO: figure out size of this char array
			char mq_voltage_topic[128]; // TODO: figure out size of this char array
			float current = acs712_voltage_to_current(adc_current_v);
			sprintf(s_current, "%.2f", current);
			sprintf(s_voltage, "%d", adc_voltage_v);
			sprintf(mq_current_topic, "%s-%s/current_a", MQ_TOPIC_BASE, s_mac);
			sprintf(mq_voltage_topic, "%s-%s/voltage_mv", MQ_TOPIC_BASE, s_mac);
			// TODO: it seems that either these pins are tied together on my board, or there is a bug reporting the same reading for both
			esp_mqtt_client_publish(client, mq_current_topic, s_current, 0, 0, 0);
			esp_mqtt_client_publish(client, mq_voltage_topic, s_voltage, 0, 0, 0);
			ESP_LOGI(TAG, "MQTT published - topic:%s, payload:%s", mq_current_topic, s_current);
			ESP_LOGI(TAG, "MQTT published - topic:%s, payload:%s", mq_voltage_topic, s_voltage);

			vTaskDelayUntil(&last_wake_time, SAMPLE_PERIOD / portTICK_PERIOD_MS);
		}
	}
	else
	{
		ESP_LOGI(TAG, "No DS18B20 devices detected!");
	}

	// clean up dynamically allocated data
	for (int i = 0; i < num_devices; ++i)
	{
		ds18b20_free(&devices[i]);
	}
	owb_uninitialize(owb);

	ESP_LOGI(TAG, "Restarting now.");
	fflush(stdout);
	vTaskDelay(1000 / portTICK_PERIOD_MS);
	esp_restart();
}
