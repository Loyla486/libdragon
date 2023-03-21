BUILD_DIR ?= .
SOURCE_DIR ?= .
USO_ELF_BASE_DIR ?= .
USO_BASE_DIR ?= .
N64_DFS_OFFSET ?= 1M # Override this to offset where the DFS file will be located inside the ROM

N64_ROM_TITLE = "Made with libdragon" # Override this with the name of your game or project
N64_ROM_SAVETYPE = # Supported savetypes: none eeprom4k eeprom16 sram256k sram768k sram1m flashram
N64_ROM_RTC = # Set to true to enable the Joybus Real-Time Clock
N64_ROM_REGIONFREE = # Set to true to allow booting on any console region

# Override this to use a toolchain installed separately from libdragon
N64_GCCPREFIX ?= $(N64_INST)
N64_ROOTDIR = $(N64_INST)
N64_BINDIR = $(N64_ROOTDIR)/bin
N64_INCLUDEDIR = $(N64_ROOTDIR)/mips64-elf/include
N64_LIBDIR = $(N64_ROOTDIR)/mips64-elf/lib
N64_HEADERPATH = $(N64_LIBDIR)/header
N64_GCCPREFIX_TRIPLET = $(N64_GCCPREFIX)/bin/mips64-elf-

COMMA:=,

N64_CC = $(N64_GCCPREFIX_TRIPLET)gcc
N64_CXX = $(N64_GCCPREFIX_TRIPLET)g++
N64_AS = $(N64_GCCPREFIX_TRIPLET)as
N64_AR = $(N64_GCCPREFIX_TRIPLET)ar
N64_LD = $(N64_GCCPREFIX_TRIPLET)ld
N64_OBJCOPY = $(N64_GCCPREFIX_TRIPLET)objcopy
N64_OBJDUMP = $(N64_GCCPREFIX_TRIPLET)objdump
N64_SIZE = $(N64_GCCPREFIX_TRIPLET)size
N64_NM = $(N64_GCCPREFIX_TRIPLET)nm

N64_CHKSUM = $(N64_BINDIR)/chksum64
N64_ED64ROMCONFIG = $(N64_BINDIR)/ed64romconfig
N64_MKDFS = $(N64_BINDIR)/mkdfs
N64_TOOL = $(N64_BINDIR)/n64tool
N64_SYM = $(N64_BINDIR)/n64sym
N64_AUDIOCONV = $(N64_BINDIR)/audioconv64
N64_MKSPRITE = $(N64_BINDIR)/mksprite
N64_MKFONT = $(N64_BINDIR)/mkfont
N64_MKUSO = $(N64_BINDIR)/mkuso
N64_MKEXTERN = $(N64_BINDIR)/mkextern
N64_MKMSYM = $(N64_BINDIR)/mkmsym

N64_CFLAGS =  -march=vr4300 -mtune=vr4300 -I$(N64_INCLUDEDIR)
N64_CFLAGS += -falign-functions=32   # NOTE: if you change this, also change backtrace() in backtrace.c
N64_CFLAGS += -ffunction-sections -fdata-sections -g -ffile-prefix-map=$(CURDIR)=
N64_CFLAGS += -ffast-math -ftrapping-math -fno-associative-math
N64_CFLAGS += -DN64 -O2 -Wall -Werror -Wno-error=deprecated-declarations -fdiagnostics-color=always
N64_ASFLAGS = -mtune=vr4300 -march=vr4300 -Wa,--fatal-warnings  -I$(N64_INCLUDEDIR)
N64_RSPASFLAGS = -march=mips1 -mabi=32 -Wa,--fatal-warnings  -I$(N64_INCLUDEDIR)
N64_LDFLAGS = -g -L$(N64_LIBDIR) -ldragon -lm -ldragonsys -Tn64.ld -T$(USO_EXTERNS_LIST) --gc-sections --wrap __do_global_ctors
N64_USOLDFLAGS = -Ur -Tuso.ld

# Enable exporting all global symbols from main exe
ifeq ($(MSYM_EXPORT_ALL),1)
N64_MKMSYMFLAGS = -a
else
N64_MKMSYMFLAGS = -i $(USO_EXTERNS_LIST)
endif

N64_TOOLFLAGS = --header $(N64_HEADERPATH) --title $(N64_ROM_TITLE)
N64_ED64ROMCONFIGFLAGS =  $(if $(N64_ROM_SAVETYPE),--savetype $(N64_ROM_SAVETYPE))
N64_ED64ROMCONFIGFLAGS += $(if $(N64_ROM_RTC),--rtc) 
N64_ED64ROMCONFIGFLAGS += $(if $(N64_ROM_REGIONFREE),--regionfree)

ifeq ($(D),1)
CFLAGS+=-g3
CXXFLAGS+=-g3
ASFLAGS+=-g
RSPASFLAGS+=-g
LDFLAGS+=-g
endif

# automatic .d dependency generation
CFLAGS+=-MMD     
CXXFLAGS+=-MMD
ASFLAGS+=-MMD
RSPASFLAGS+=-MMD

N64_CXXFLAGS := $(N64_CFLAGS)
N64_CFLAGS += -std=gnu99

USO_EXTERNS_LIST := $(BUILD_DIR)/uso_externs.lst

# Change all the dependency chain of z64 ROMs to use the N64 toolchain.
%.z64: CC=$(N64_CC)
%.z64: CXX=$(N64_CXX)
%.z64: AS=$(N64_AS)
%.z64: LD=$(N64_LD)
%.z64: CFLAGS+=$(N64_CFLAGS)
%.z64: CXXFLAGS+=$(N64_CXXFLAGS)
%.z64: ASFLAGS+=$(N64_ASFLAGS)
%.z64: RSPASFLAGS+=$(N64_RSPASFLAGS)
%.z64: LDFLAGS+=$(N64_LDFLAGS)
%.z64: $(BUILD_DIR)/%.elf
	@echo "    [Z64] $@"
	$(N64_SYM) $< $<.sym
	$(N64_MKMSYM) $(N64_MKMSYMFLAGS) $< $<.msym
	$(N64_OBJCOPY) -O binary $< $<.bin
	@rm -f $@
	DFS_FILE="$(filter %.dfs, $^)"; \
	if [ -z "$$DFS_FILE" ]; then \
		$(N64_TOOL) $(N64_TOOLFLAGS) --toc --output $@ $<.bin --align 8 $<.sym --align 8 $<.msym; \
	else \
		$(N64_TOOL) $(N64_TOOLFLAGS) --toc --output $@ $<.bin --align 8 $<.sym --align 8 $<.msym --align 16 "$$DFS_FILE"; \
	fi
	if [ ! -z "$(strip $(N64_ED64ROMCONFIGFLAGS))" ]; then \
		$(N64_ED64ROMCONFIG) $(N64_ED64ROMCONFIGFLAGS) $@; \
	fi
	$(N64_CHKSUM) $@ >/dev/null

%.v64: %.z64
	@echo "    [V64] $@"
	$(N64_OBJCOPY) -I binary -O binary --reverse-bytes=2 $< $@

%.dfs:
	@mkdir -p $(dir $@)
	@echo "    [DFS] $@"
	$(N64_MKDFS) $@ $(<D) >/dev/null

# Assembly rule. We use .S for both RSP and MIPS assembly code, and we differentiate
# using the prefix of the filename: if it starts with "rsp", it is RSP ucode, otherwise
# it's a standard MIPS assembly file.
$(BUILD_DIR)/%.o: $(SOURCE_DIR)/%.S
	@mkdir -p $(dir $@)
	set -e; \
	FILENAME="$(notdir $(basename $@))"; \
	if case "$$FILENAME" in "rsp"*) true;; *) false;; esac; then \
		SYMPREFIX="$(subst .,_,$(subst /,_,$(basename $@)))"; \
		TEXTSECTION="$(basename $@).text"; \
		DATASECTION="$(basename $@).data"; \
		BINARY="$(basename $@).elf"; \
		echo "    [RSP] $<"; \
		$(N64_CC) $(RSPASFLAGS) -L$(N64_LIBDIR) -nostartfiles -Wl,-Trsp.ld -Wl,--gc-sections -o $@ $<; \
		mv "$@" $$BINARY; \
		$(N64_OBJCOPY) -O binary -j .text $$BINARY $$TEXTSECTION.bin; \
		$(N64_OBJCOPY) -O binary -j .data $$BINARY $$DATASECTION.bin; \
		$(N64_OBJCOPY) -I binary -O elf32-bigmips -B mips4300 \
				--redefine-sym _binary_$${SYMPREFIX}_text_bin_start=$${FILENAME}_text_start \
				--redefine-sym _binary_$${SYMPREFIX}_text_bin_end=$${FILENAME}_text_end \
				--redefine-sym _binary_$${SYMPREFIX}_text_bin_size=$${FILENAME}_text_size \
				--set-section-alignment .data=8 \
				--rename-section .text=.data $$TEXTSECTION.bin $$TEXTSECTION.o; \
		$(N64_OBJCOPY) -I binary -O elf32-bigmips -B mips4300 \
				--redefine-sym _binary_$${SYMPREFIX}_data_bin_start=$${FILENAME}_data_start \
				--redefine-sym _binary_$${SYMPREFIX}_data_bin_end=$${FILENAME}_data_end \
				--redefine-sym _binary_$${SYMPREFIX}_data_bin_size=$${FILENAME}_data_size \
				--set-section-alignment .data=8 \
				--rename-section .text=.data $$DATASECTION.bin $$DATASECTION.o; \
		$(N64_SIZE) -G $$BINARY; \
		$(N64_LD) -relocatable $$TEXTSECTION.o $$DATASECTION.o -o $@; \
		rm $$TEXTSECTION.bin $$DATASECTION.bin $$TEXTSECTION.o $$DATASECTION.o; \
	else \
		echo "    [AS] $<"; \
		$(CC) -c $(ASFLAGS) -o $@ $<; \
	fi

$(BUILD_DIR)/%.o: $(SOURCE_DIR)/%.c 
	@mkdir -p $(dir $@)
	@echo "    [CC] $<"
	$(CC) -c $(CFLAGS) -o $@ $<

$(BUILD_DIR)/%.o: $(SOURCE_DIR)/%.cpp
	@mkdir -p $(dir $@)
	@echo "    [CXX] $<"
	$(CXX) -c $(CXXFLAGS) -o $@ $<

%.elf: $(N64_LIBDIR)/libdragon.a $(N64_LIBDIR)/libdragonsys.a $(N64_LIBDIR)/n64.ld uso.ld
	@mkdir -p $(dir $@)
	@echo "    [LD] $@"
# We always use g++ to link except for ucode and USO files (detected with -mno-gpopt in CFLAGS) because of the inconsistencies
# between ld when it comes to global ctors dtors. Also see __do_global_ctors
	if [ -z "$(filter -mno-gpopt, $(CFLAGS))" ]; then \
		touch $(USO_EXTERNS_LIST); \
		$(CXX) -o $@ $(filter %.o, $^) -lc $(patsubst %,-Wl$(COMMA)%,$(LDFLAGS)) -Wl,-Map=$(BUILD_DIR)/$(notdir $(basename $@)).map; \
	else \
		$(N64_LD) $(N64_USOLDFLAGS) -Map=$(basename $@).map -o $@ $(filter %.o, $^); \
	fi
	$(N64_SIZE) -G $@

# Change all the dependency chain of USO files to use the N64 toolchain.
%.uso: CC=$(N64_CC)
%.uso: CXX=$(N64_CXX)
%.uso: AS=$(N64_AS)
%.uso: LD=$(N64_LD)
%.uso: CFLAGS+=$(N64_CFLAGS) -mno-gpopt
%.uso: CXXFLAGS+=$(N64_CXXFLAGS) -mno-gpopt
%.uso: ASFLAGS+=$(N64_ASFLAGS)
%.uso: RSPASFLAGS+=$(N64_RSPASFLAGS)
%.uso: LDFLAGS+=$(N64_LDFLAGS)

$(USO_BASE_DIR)/%.uso: $(USO_ELF_BASE_DIR)/%.elf
	@mkdir -p $(dir $@)
	@echo "    [MKUSO] $@"
	$(N64_MKUSO) -o $(dir $@) $<
	$(N64_SYM) $< $@.sym
	$(N64_MKEXTERN) -o $(USO_EXTERNS_LIST) $<
	
ifneq ($(V),1)
.SILENT:
endif
