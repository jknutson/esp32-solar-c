#
# This is a project Makefile. It is assumed the directory this Makefile resides in is a
# project subdirectory.
#

# PROJECT_NAME := esp32-solar-c

# include $(IDF_PATH)/make/project.mk
.PHONY: build

monitor:
	@idf.py monitor

build:
	@ninja -C build build.ninja
