# esp32-solar-c

[![license](https://img.shields.io/github/license/mashape/apistatus.svg)]()

## Introduction

This is largely based on an [example application](https://github.com/DavidAntliff/esp32-ds18b20-example) for the Maxim Integrated DS18B20 Programmable Resolution 1-Wire Digital Thermometer device, the ADC example code from the esp-idf repository on GitHub, and many Google searches. Some of the code I may have even written myself!

Ensure that submodules are cloned:

```
$ git clone --recursive https://github.com/jknutson/esp32-solar-c.git
```

Build the application with:

```
$ cd esp32-solar-c
$ idf.py menuconfig    # set your Wifi, MQTT, and 1-Wire GPIO configuration - see below
$ idf.py build
$ idf.py -p (PORT) flash monitor
```

The program does a number of things:
- detect your connected devices (DS18B20)
- periodically:
  - obtain readings from devices/inputs
  - perform any necessary calculations on readings
  - publish data to MQTT topic(s)
  - print data to console

## Dependencies

This application makes use of the following components (included as submodules):

 * components/[esp32-owb](https://github.com/DavidAntliff/esp32-owb)
 * components/[esp32-ds18b20](https://github.com/DavidAntliff/esp32-ds18b20)

## Hardware

### DS18B20 "OneWire" Temperature Sensor

To run this example, connect one or more DS18B20 devices to a single GPIO on the ESP32. Use the recommended pull-up 
resistor of 4.7 KOhms, connected to the 3.3V supply.

`idf.py menuconfig` can be used to set the 1-Wire GPIO.

If you have several devices and see occasional CRC errors, consider using a 2.2 kOhm pull-up resistor instead. Also 
consider adding decoupling capacitors between the sensor supply voltage and ground, as close to each sensor as possible.

If you wish to enable a second GPIO to control an external strong pull-up circuit for parasitic power mode, ensure 
`CONFIG_ENABLE_STRONG_PULLUP=y` and `CONFIG_STRONG_PULLUP_GPIO` is set appropriately.
 
See documentation for [esp32-ds18b20](https://www.github.com/DavidAntliff/esp32-ds18b20-example#parasitic-power-mode)
for further information about parasitic power mode, including strong pull-up configuration.

### ADC

2 ADC inputs are read from:
- GPIO34 (ADC1/CH6) - Current Sensor
- GPIO35 (ADC1/CH7) - Voltage Divider

ADC1 is used as ADC2 is shared with WiFi, which is used in this application.

### Monitoring

You can use the idf.py tool to interact with and monitor the device:

```
MQTT Published (polled temperature): yes
raw voltage:  142 mV
real voltage:  852 mV
topic:  esp32/esp32_58EA84/voltage
MQTT Published (polled voltage): yes
temperature (c): 23.875000
temperature (f): 74.975000
MQTT topic:  esp32/esp32_58EA84-28ffc69ca4160514/temperature
```


## License

The code in this project is licensed under the MIT license - see LICENSE for details.

## Links

 * [DS18B20 Datasheet](http://datasheets.maximintegrated.com/en/ds/DS18B20.pdf)
 * [Espressif IoT Development Framework for ESP32](https://github.com/espressif/esp-idf)
 * [mqtt-pg-logger](https://github.com/rosenloecher-it/mqtt-pg-logger)

## Acknowledgements

"1-Wire" is a registered trademark of Maxim Integrated.
