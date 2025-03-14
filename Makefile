BUILD_DIR := build
SOURCE_DIR := src
INCLUDE_DIR := include
MODULES_DIR := modules
SCRIPTS_DIR := scripts
TARGETS_DIR := targets
MAPS_DIR := maps


ifneq ($(MAKECMDGOALS),generate_target)
ifneq ($(MAKECMDGOALS),clean)

# Checks the existence of the provided target
SUPPORTED_TARGETS := $(shell ls $(TARGETS_DIR))

# Check if the target needs attach operation before use
SERIAL_TARGETS := $(shell ls $(TARGETS_DIR)/*/actions/attach | awk -F "/" '{print $2}')

# if no target is provided, use the first one as default
ifeq ($(TARGET),)
  TARGET := $(shell echo $(SUPPORTED_TARGETS) | awk '{print $$1}')
  $(warning No target specified, using $(TARGET) as default target.)
endif

ifeq ($(MAKECMDGOALS),attach)
ifeq ($(filter $(TARGET), $(SERIAL_TARGETS)),)
  SERIAL_PORT := $(shell python3 $(SCRIPTS_DIR)/detect_serial.py $(TARGET))
else
  $(error "Attach is only necessary for targets $(SERIAL_TARGETS).")
endif
endif

ifeq ($(filter $(TARGET), $(SUPPORTED_TARGETS)),)
  $(error "Provided target ($(TARGET)) not in $(SUPPORTED_TARGETS).")
endif

# Get target informations
TARGET_DIR := $(TARGETS_DIR)/$(TARGET)

CODE_START := $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) code_start)
CODE_SIZE := $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) code_size)

DATA_START := $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) data_start)
DATA_SIZE := $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) data_size)

HEAP_SIZE := $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) heap_size)

# Get target architecture and compilation flags
ARCH := $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) architecture)

CFLAGS += -nostdlib
CFLAGS += -nostartfiles
CFLAGS += $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) architecture_specific_gcc_flags)
CFLAGS += $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) debug_gcc_flags)
CFLAGS += -march=$(ARCH)
CFLAGS += -ffreestanding
CFLAGS += -ffunction-sections
CFLAGS += -fdata-sections
CFLAGS += -O0
CFLAGS += $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) gcc_flags)

# Get tools compatible with the target
CC := $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) compiler)
NM := $(shell python3 $(SCRIPTS_DIR)/extract_target_info.py $(TARGET) nm)

MODULES_SRC = $(foreach module,$(MODULES), $(MODULES_DIR)/$(module)/module.c)
MODULES_OBJ = $(foreach module,$(MODULES), $(BUILD_DIR)/$(MODULES_DIR)/$(module)/module.o)
MODULES_BUILD = $(foreach module,$(MODULES), $(BUILD_DIR)/$(MODULES_DIR)/$(module))

DEPENDENCIES = $(shell python3 $(SCRIPTS_DIR)/extract_dependencies.py $(MODULES))
DEPENDENCIES_GCC_FLAGS = $(foreach dependency,$(DEPENDENCIES), -D$(dependency)_ENABLED)
endif
endif

all: build
default: build

clean_internalblue_logs:
	rm -rf internalblue*
	rm -rf btsnoop.log

$(MODULES_BUILD):
	mkdir -p $(MODULES_BUILD)

create_build_directory: $(MODULES_BUILD)
	mkdir -p $(BUILD_DIR)
	mkdir -p $(MAPS_DIR)

$(BUILD_DIR)/$(MODULES_DIR)/%/module.o: $(MODULES_DIR)/%/module.c
	$(CC) $< $(CFLAGS) $(DEPENDENCIES_GCC_FLAGS) -c -o $@ -I $(INCLUDE_DIR)

$(BUILD_DIR)/callbacks.c: $(MODULES_OBJ)
	python3 $(SCRIPTS_DIR)/generate_callbacks.py $(ARCH) $(MODULES)

$(BUILD_DIR)/trampolines.c: $(TARGET_DIR)/patch.conf
	python3 $(SCRIPTS_DIR)/generate_trampolines.py $(TARGET) $(DEPENDENCIES)

$(BUILD_DIR)/out.elf: $(BUILD_DIR)/callbacks.c $(MODULES_OBJ) $(SOURCE_DIR)/*.c $(SOURCE_DIR)/**/*.c $(BUILD_DIR)/trampolines.c $(TARGET_DIR)/wrapper.c
	$(CC) $(DEPENDENCIES_GCC_FLAGS) -DHEAP_SIZE=$(HEAP_SIZE) $(BUILD_DIR)/callbacks.c $(MODULES_OBJ) $(SOURCE_DIR)/*.c $(SOURCE_DIR)/**/*.c $(BUILD_DIR)/trampolines.c $(CFLAGS) $(TARGET_DIR)/wrapper.c -T $(TARGET_DIR)/linker.ld $(TARGET_DIR)/functions.ld -o $(BUILD_DIR)/out.elf -I $(INCLUDE_DIR) -Wl,"--defsym=CODE_START=$(CODE_START)" -Wl,"--defsym=CODE_SIZE=$(CODE_SIZE)" -Wl,"--defsym=DATA_START=$(DATA_START)"  -Wl,"--defsym=DATA_SIZE=$(DATA_SIZE)"

$(BUILD_DIR)/symbols.sym: $(BUILD_DIR)/out.elf
	$(NM) -S -a $(BUILD_DIR)/out.elf | sort > $(BUILD_DIR)/symbols.sym

$(BUILD_DIR)/patches.csv: $(BUILD_DIR)/symbols.sym
	python3 $(SCRIPTS_DIR)/generate_patches.py $(TARGET) $(DEPENDENCIES)
	cp $(BUILD_DIR)/patches.csv $(MAPS_DIR)/$(TARGET).csv

build: clean create_build_directory $(BUILD_DIR)/patches.csv

attach:
	$(TARGET_DIR)/actions/attach $(SERIAL_PORT)

patch:
	python3 $(SCRIPTS_DIR)/patch_target.py $(TARGET)

clean: clean_internalblue_logs
	rm -rf build

log:
	python3 $(SCRIPTS_DIR)/interact.py $(TARGET) log
