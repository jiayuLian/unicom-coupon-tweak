ARCH    = arm64
SDK     = $(shell xcrun --sdk iphoneos --show-sdk-path)
CC      = clang

# 可通过环境变量覆盖 (本地 make TARGET_PHONE=xxx 或 CI workflow_dispatch 注入)
TARGET_PHONE     ?= 15629799900
TARGET_CITY      ?= 724
TARGET_PHONE_AES ?=

CFLAGS  = -dynamiclib -arch $(ARCH) \
          -framework Foundation -framework WebKit -framework UIKit \
          -isysroot $(SDK) -mios-version-min=15.0 -fobjc-arc -O2

TARGET  = couponhook.dylib
CONFIG_H = config_gen.h

# 生成配置头: 让 CI 通过环境变量注入目标号/城市码/AES密文, 避免改源码
$(CONFIG_H):
	@printf '#define TARGET_PHONE @"%s"\n' '$(TARGET_PHONE)' > $(CONFIG_H)
	@printf '#define TARGET_CITY @"%s"\n' '$(TARGET_CITY)' >> $(CONFIG_H)
	@if [ -n "$(TARGET_PHONE_AES)" ]; then \
		printf '#define TARGET_PHONE_AES @"%s"\n' '$(TARGET_PHONE_AES)' >> $(CONFIG_H); \
	else \
		printf '#define TARGET_PHONE_AES @"__FILL_FROM_FRIDA__"\n' >> $(CONFIG_H); \
	fi
	@echo "[*] generated $(CONFIG_H): phone=$(TARGET_PHONE) city=$(TARGET_CITY) aes=$(TARGET_PHONE_AES)"

$(TARGET): $(CONFIG_H) couponhook.m
	$(CC) $(CFLAGS) -o $@ couponhook.m

sign: $(TARGET)
	ldid -S entitlements.plist $(TARGET)

clean:
	rm -f $(TARGET) $(CONFIG_H)

.PHONY: clean sign
