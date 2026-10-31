#!/usr/bin/env python3
# frida_locate.py
# 在 iOS 真机定位联通 App 生 custom.currentPhoneNumberAes 所用的 AES 加密,
# 打印 key/iv/算法, 并演示用同样参数加密"目标号"得到 TARGET_AES 密文。
#
# 前置:
#   手机: TrollStore 装 Frida, 或 AltStore/sideload 的 Frida.app
#   Mac : pip install frida frida-tools pycryptodome
#   运行: python3 frida_locate.py
#
# 用法:
#   1) 跑脚本, 脚本会 spawn 联通 App 并 hook CCCrypt
#   2) 在 App 里走一次"本机交费到提交"流程 (触发加密本机号)
#   3) 终端会打印类似:
#        [CCCrypt] ENC alg=AES keyLen=16
#          key = 000102030405060708090a0b0c0d0e0f
#          iv  = 000102030405060708090a0b0c0d0e0f
#          in  = 15623251936
#   4) 把 key/iv 填到下方 AES_KEY / AES_IV, 把 TARGET_PHONE 改成目标号
#   5) 脚本末尾会直接算出 encrypt(目标号) 的 hex, 粘进 couponhook.m 的 kTargetPhoneAes
#
import frida
import sys

BUNDLE = "com.chinaunicom.mobilebusiness"
TARGET_PHONE = "15629799900"   # 想加密的目标号
# ↓↓↓ 从日志里拿到后填这里 ↓↓↓
AES_KEY = bytes.fromhex("000102030405060708090a0b0c0d0e0f")  # 占位, 替换为真实 key
AES_IV  = bytes.fromhex("000102030405060708090a0b0c0d0e0f")  # 占位, 替换为真实 iv (ECB 时忽略)
USE_CBC = True  # 若日志显示无 iv (iv=null) 则改成 False (ECB)

JS_HOOK = r"""
Interceptor.attach(Module.findExportByName(null, "CCCrypt"), {
  onEnter: function(args){
    var op = args[0].toInt32();      // 0 = encrypt
    var alg = args[1].toInt32();     // 0 = kCCAlgorithmAES
    if (alg !== 0) return;
    var keyLen = args[3].toInt32();
    var keyPtr = args[4];
    var ivPtr  = args[5];
    var inLen  = args[6].toInt32();
    var inPtr  = args[7];
    if (op !== 0) return;
    try {
      var key = keyPtr.readByteArray(keyLen);
      var iv  = ivPtr.isNull() ? null : ivPtr.readByteArray(16);
      var data = inPtr.readByteArray(Math.min(inLen, 64));
      console.log("[CCCrypt] ENC alg=AES keyLen=" + keyLen);
      console.log("  key = " + hexlify(key));
      console.log("  iv  = " + (iv ? hexlify(iv) : "null(ECB)"));
      console.log("  in  = " + bytesToStr(data));
    } catch(e) { console.log("err " + e); }
  }
});
function hexlify(a){
  var s=""; var b=new Uint8Array(a);
  for(var i=0;i<b.length;i++) s+=("0"+b[i].toString(16)).slice(-2);
  return s;
}
function bytesToStr(a){
  var s=""; var b=new Uint8Array(a);
  for(var i=0;i<b.length;i++) s+=String.fromCharCode(b[i]);
  return s;
}
console.log("[*] CCCrypt hooked, do a pay now...");
"""

def on_message(msg, data):
    if msg["type"] == "send":
        print(msg["payload"])
    elif msg["type"] == "error":
        print("FRIDA ERROR:", msg["description"])

def main():
    try:
        dev = frida.get_usb_device(timeout=10)
    except Exception as e:
        print("找不到 USB 设备:", e); sys.exit(1)
    pid = dev.spawn([BUNDLE])
    session = dev.attach(pid)
    script = session.create_script(JS_HOOK)
    script.on("message", on_message)
    script.load()
    dev.resume(pid)
    print("[*] App spawned, 在手机上走一次本机交费流程, 看上面的 key/iv ...")
    print("[*] Ctrl+C 退出")
    try:
        sys.stdin.read()
    except KeyboardInterrupt:
        pass

    # 拿到真实 key/iv 后, 本地复现加密目标号
    if AES_KEY != bytes.fromhex("000102030405060708090a0b0c0d0e0f"):
        from Crypto.Cipher import AES
        from Crypto.Util.Padding import pad
        raw = TARGET_PHONE.encode("utf-8")
        if USE_CBC:
            cip = AES.new(AES_KEY, AES.MODE_CBC, AES_IV)
        else:
            cip = AES.new(AES_KEY, AES.MODE_ECB)
        ct = cip.encrypt(pad(raw, 16))
        print("\n[+] encrypt(%s) = %s" % (TARGET_PHONE, ct.hex()))
        print("    把上面这串粘进 couponhook.m 的 kTargetPhoneAes\n")
    else:
        print("\n[!] 还没填真实 AES_KEY/AES_IV, 先按日志填好再跑一次本脚本拿目标号密文\n")

if __name__ == "__main__":
    main()
