# Makefile — 交叉编译 iOS arm64 dylib (Linux / GitHub Actions ubuntu-latest)
# 依赖: clang + lld (apt install clang lld)
# 配置通过环境变量注入, 不修改源码:
#   make TARGET_PHONE=15629799900 TARGET_CITY=724 TARGET_PHONE_AES=

# 交叉编译必须用 clang (cc/gcc 不认 -target aarch64-apple-ios); 用 := 强制覆盖 runner 的 CC=cc 环境变量
CC := clang
TARGET_PHONE      ?= 15629799900
TARGET_CITY       ?= 724
TARGET_PHONE_AES  ?=
MIN_IOS           ?= 14.0

# 关键: -nostdlib 去掉 clang 默认塞的 -lSystem; -undefined dynamic_lookup 让所有符号运行时解析
CFLAGS = -target aarch64-apple-ios -miphoneos-version-min=$(MIN_IOS) \
         -fuse-ld=lld -dynamiclib -nostdlib -undefined dynamic_lookup \
         -ObjC -O2 -fvisibility=hidden -fobjc-runtime=ios -I.

SRC = couponhook.m rt_bridge.m
OUT = couponhook.dylib

.PHONY: all sign clean

all: $(OUT)

config_gen.h:
	@printf '/* auto-generated, do not edit */\n' > config_gen.h
	@printf '#ifndef CONFIG_GEN_H\n' >> config_gen.h
	@printf '#define TARGET_PHONE_CSTR "%s"\n' "$(TARGET_PHONE)" >> config_gen.h
	@printf '#define TARGET_CITY_CSTR "%s"\n' "$(TARGET_CITY)" >> config_gen.h
	@printf '#define TARGET_PHONE_AES_CSTR "%s"\n' "$(TARGET_PHONE_AES)" >> config_gen.h
	@printf '#endif\n' >> config_gen.h

$(OUT): $(SRC) config_gen.h objc_runtime_min.h rt_bridge.h
	clang $(CFLAGS) -o $(OUT) $(SRC)

sign: $(OUT)
	python3 ldid_python.py $(OUT)

clean:
	rm -f $(OUT) config_gen.h
