#include <stdio.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "driver/adc.h"
#include "esp_adc_cal.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "mqtt_client.h"
#include "protocol_examples_common.h"

#include "owb.h"
#include "owb_rmt.h"
#include "ds18b20.h"

#define GPIO_DS18B20_0       (CONFIG_ONE_WIRE_GPIO)
#define MAX_DEVICES          (8)
#define DS18B20_RESOLUTION   (DS18B20_RESOLUTION_12_BIT)

#define DEFAULT_VREF    3300        // Use adc2_vref_to_gpio() to obtain a better estimate
#define NO_OF_SAMPLES   64          // Multisampling
#define SAMPLE_RATE     5000        // Milliseconds

static esp_adc_cal_characteristics_t *adc_chars;
static const adc_channel_t channel = ADC_CHANNEL_6;     //GPIO34 if ADC1, GPIO14 if ADC2
static const adc_bits_width_t width = ADC_WIDTH_BIT_12;
static const adc_atten_t atten = ADC_ATTEN_DB_0;
static const adc_unit_t unit = ADC_UNIT_1;

static const char *TAG = "ESP-SOLAR";
static const char *MQ_TOPIC_BASE = "iot/esp32";

float acs712_voltage_to_current(uint32_t v) {
  const int acs712_offset_mv = 2500;  // 2.5V == 0A
  const int acs712_sens_mv_a = 100;   // 100mV/a
  // not going to bother with negative current for now
  if (v <= acs712_offset_mv) {
    return 0;
  }
  return ((int)v - 2500) / acs712_sens_mv_a;
}

void app_main(void)
{
    // make some some important stuff is setup
    ESP_ERROR_CHECK(nvs_flash_init());
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    // this could be improved, see protocols/README.md in esp-idf/examples
    // ESP_ERROR_CHECK(example_connect());
    // Override global log level
    esp_log_level_set("*", ESP_LOG_INFO);
    // get MAC addr to use as "unique" identifier
    uint8_t mac_i[6] = {0};
    esp_read_mac(mac_i, ESP_MAC_WIFI_STA);
    char s_mac[13];  // 12 chars + 1 for nul
    sprintf(s_mac, "%02X%02X%02X%02X%02X%02X", mac_i[0], mac_i[1], mac_i[2], mac_i[3], mac_i[4], mac_i[5]);
    ESP_LOGI(TAG, "MAC Address: %s (WIFI_STA)", s_mac);


    // ADC setup
    // Check if Two Point or Vref are burned into eFuse
    adc1_config_width(width);
    adc1_config_channel_atten(channel, atten);
    // Characterize ADC
    adc_chars = calloc(1, sizeof(esp_adc_cal_characteristics_t));

    // main loop
    for (;;) {
        uint32_t adc_reading = 0;
        //Multisampling
        for (int i = 0; i < NO_OF_SAMPLES; i++) {
            if (unit == ADC_UNIT_1) {
                adc_reading += adc1_get_raw((adc1_channel_t)channel);
            } else {
                int raw;
                adc2_get_raw((adc2_channel_t)channel, width, &raw);
                adc_reading += raw;
            }
        }
        adc_reading /= NO_OF_SAMPLES;
        uint32_t voltage = esp_adc_cal_raw_to_voltage(adc_reading, adc_chars);
        float current = acs712_voltage_to_current(voltage);
        printf("readings: %dmV, %fA\n", voltage, current);

        vTaskDelay(pdMS_TO_TICKS(SAMPLE_RATE));
    }
}
