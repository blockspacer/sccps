SCREEPS_PATH=.
include make/globals.mk
.SECONDEXPANSION:
include make/patterns.mk

# Screeps C++ sources and object files
SRCS := cpu.cc creep.cc game.cc handle.cc flag.cc memory.cc module.cc path-finder.cc position.cc resource.cc room.cc structure.cc terrain.cc visual.cc
SRCS := $(addprefix src/,$(SRCS))
OBJS := $(addprefix $(BUILD_PATH)/,$(patsubst %.cc,%.o,$(SRCS)))
BC_OBJS := $(addprefix $(BUILD_PATH)/,$(patsubst %.cc,%.bc,$(SRCS)))

# Compilation options
CXXFLAGS += -Iinclude

# asmjs main module used for loading dynamic libraries
MAIN2_EMFLAGS := -s DEFAULT_LIBRARY_FUNCS_TO_INCLUDE=$$($(TO_JSON) < emscripten_symbols) \
	-s EXPORTED_FUNCTIONS=$$((cat dylib-symbols; egrep '[CD]1' dylib-symbols | perl -pe 's/([CD])1/$$1\x32/'; sed 's/^/_/' emscripten_symbols) | $(TO_JSON)) \
	-s EXTRA_EXPORTED_RUNTIME_METHODS="['loadDynamicLibrary']"
$(BUILD_PATH)/asmjs.js: $(BC_OBJS) dylib-symbols | nothing
	$(EMCXX) -o $@ $(BC_OBJS) $(EMFLAGS) $(MAIN_EMFLAGS) $(ASMJS_EMFLAGS) $(MAIN2_EMFLAGS)

# llvm bytecode targets
$(BUILD_PATH)/emasm-bc-files.txt: $(BC_OBJS) | nothing
	echo $^ > $@

# module
GYP_PATH := $(BUILD_PATH)/gyp
$(GYP_PATH)/binding.gyp: binding.gyp.template $(MAKEFILE_DEPS) | $$(@D)/.
	sed -e 's/SOURCES/'$$(echo marker.cc $(addprefix ../../../,$(SRCS)) | $(TO_JSON) | sed 's/\//\\\//g')'/' binding.gyp.template > $@
$(GYP_PATH)/marker.cc: $(BUILD_PATH)/module.a
	touch $@
$(GYP_PATH)/build/config.gypi: $(GYP_PATH)/binding.gyp
	cd $(GYP_PATH); node-gyp configure --debug
$(GYP_PATH)/build/Debug/module.node: $(GYP_PATH)/build/config.gypi $(GYP_PATH)/marker.cc nothing
	cd $(GYP_PATH); node-gyp build -v

# native archive
$(BUILD_PATH)/screeps.a: $(OBJS) | nothing
	$(AR) rcs $@ $^

# Linter. nb: we can't lint emasm sources because of EMASM macros
.PHONY: tidy
tidy:
	git ls-files '*.h' | xargs -J% -n1 ./tmp-hpp.sh $(CLANG_TIDY) % -header-filter='.*' -quiet -warnings-as-errors='*'
	git ls-files '*.cc' | grep -v emasm | xargs -n1 $(CLANG_TIDY) -quiet -warnings-as-errors='*'

# Cleanups. Exported symbols for dynamic library main are left alone by default because they only
# affect debug builds and keeping them around makes incremental builds more robust to changes
.PHONY: clean very-clean
clean:
	$(RM) -rf build
very-clean: clean
	$(RM) -rf $(DYLIB_LINKER_SYMBOLS) $(DYLIB_LINKER_SYMBOLS).marker
