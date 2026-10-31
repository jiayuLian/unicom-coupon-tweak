// couponhook.m — TrollStore dylib
// 让中国联通 App 的「本机交费券」给他人号码交费:
//   1) hook 主进程 NSURLSession 原生请求, 改写 commonBean.phoneNo / cityCode / currentPhoneNumberAes
//   2) hook WKWebViewConfiguration.init, 给所有 WebView 注入 JS, 改写 H5 层 fetch/XHR 参数
// 全部走 objc runtime C API, 不依赖苹果 SDK; 符号由目标 App 运行时解析。
#import "config_gen.h"
#import "objc_runtime_min.h"
#import "rt_bridge.h"

// ---------- 配置 (来自 config_gen.h, 由 Makefile/CI 注入) ----------
static const char *g_target_phone = TARGET_PHONE_CSTR;
static const char *g_target_city  = TARGET_CITY_CSTR;
static const char *g_target_aes   = TARGET_PHONE_AES_CSTR;  // 可能为空字符串

// ---------- 注入到 WebView 的 JS ----------
// 改写页面里所有出去的请求的 phoneNo / cityCode / currentPhoneNumberAes 字段
static const char *INJECT_JS =
"(function(){"
"var TP='" TARGET_PHONE_CSTR "',TC='" TARGET_CITY_CSTR "',TA='" TARGET_PHONE_AES_CSTR "';"
"function rw(q){if(!q)return q;"
"q=q.replace(/(commonBean\\.phoneNo)=[^&]*/g,'$1='+TP);"
"q=q.replace(/(commonBean\\.cityCode)=[^&]*/g,'$1='+TC);"
"if(TA&&TA.length)q=q.replace(/(currentPhoneNumberAes)=[^&]*/g,'$1='+TA);"
"q=q.replace(/(phoneNo)=[^&]*/g,'$1='+TP);"
"q=q.replace(/\"commonBean\\.phoneNo\"\\s*:\\s*\"[^\"]*\"/g,'\"commonBean.phoneNo\":\"'+TP+'\"');"
"q=q.replace(/\"commonBean\\.cityCode\"\\s*:\\s*\"[^\"]*\"/g,'\"commonBean.cityCode\":\"'+TC+'\"');"
"return q;}"
"var O=XMLHttpRequest.prototype.open;"
"XMLHttpRequest.prototype.open=function(m,u){u=rw(u);return O.apply(this,arguments);};"
"var S=XMLHttpRequest.prototype.send;"
"XMLHttpRequest.prototype.send=function(d){if(typeof d==='string')d=rw(d);return S.apply(this,arguments);};"
"var F=window.fetch;"
"window.fetch=function(u,i){if(typeof u==='string')u=rw(u);if(i&&typeof i.body==='string')i=Object.assign({},i,{body:rw(i.body)});return F(u,i);};"
"})();";

// ---------- 工具 ----------
static int is_unicom_host(id req) {
    id url = rt_request_url(req);
    if (!url) return 0;
    const char *s = rt_cstr(objc_msgSend(url, sel_registerName("absoluteString")));
    if (!s) return 0;
    if (strstr(s, "unicom") || strstr(s, "10010") || strstr(s, "wo.com") ||
        strstr(s, "npfwap") || strstr(s, "chinaunicom")) return 1;
    return 0;
}

// form 字符串: 把 key=value 中的 value 替换为 val (匹配 &key= 或 行首key=)
static void form_replace_all(char *out, size_t outsz, const char *body, const char *key, const char *val) {
    if (!out || outsz == 0) return;
    out[0] = '\0';
    if (!body || !key || !val) return;
    size_t klen = strlen(key);
    size_t blen = strlen(body);
    const char *p = body;
    while (p < body + blen) {
        const char *found = strstr(p, key);
        if (!found) { strncat(out, p, outsz - strlen(out) - 1); break; }
        int ok_pre = (found == body) || (*(found - 1) == '&');
        int ok_suf = (found + klen < body + blen) && (*(found + klen) == '=');
        if (ok_pre && ok_suf) {
            size_t before = (size_t)(found - p);
            strncat(out, p, before);
            strncat(out, key, outsz - strlen(out) - 1);
            strncat(out, "=", outsz - strlen(out) - 1);
            strncat(out, val, outsz - strlen(out) - 1);
            const char *v = found + klen + 1;
            const char *amp = strchr(v, '&');
            p = amp ? amp : (body + blen);
        } else {
            char t[2] = {*p, 0};
            strncat(out, t, outsz - strlen(out) - 1);
            p++;
        }
    }
}

// JSON 字符串: 替换 "key" : "value" 中的 value
static void json_replace_key(char *out, size_t outsz, const char *body, const char *key, const char *val) {
    if (!out || outsz == 0) { return; }
    out[0] = '\0';
    if (!body || !key || !val) return;
    char pat[256];
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    size_t plen = strlen(pat);
    size_t blen = strlen(body);
    const char *p = body;
    while (p < body + blen) {
        const char *found = strstr(p, pat);
        if (!found) { strncat(out, p, outsz - strlen(out) - 1); break; }
        const char *colon = strchr(found + plen, ':');
        if (!colon) { strncat(out, p, 1); p++; continue; }
        const char *q = colon + 1;
        while (*q == ' ' || *q == '\t' || *q == '\n' || *q == '\r') q++;
        if (*q != '"') { strncat(out, p, 1); p++; continue; }
        const char *vstart = q + 1;
        const char *vend = strchr(vstart, '"');
        if (!vend) { strncat(out, p, 1); p++; continue; }
        size_t before = (size_t)(vstart - p);
        strncat(out, p, before);
        strncat(out, "\"", outsz - strlen(out) - 1);
        strncat(out, val, outsz - strlen(out) - 1);
        strncat(out, "\"", outsz - strlen(out) - 1);
        p = vend + 1;
    }
}

// 改写请求体 (form 或 JSON), 返回新 request (mutable). 非联通请求返回原 request.
static id rewrite_request(id request) {
    if (!is_unicom_host(request)) return request;
    id mreq = rt_request_mutable(request);
    if (!mreq) return request;
    id bodyStr = rt_request_httpbody_str(mreq);
    const char *body = rt_cstr(bodyStr);
    if (body && *body) {
        size_t cap = strlen(body) * 3 + 1024;
        char *b1 = (char *)malloc(cap);
        char *b2 = (char *)malloc(cap);
        if (b1 && b2) {
            char *cur = b1, *nxt = b2;
            strncpy(cur, body, cap - 1); cur[cap - 1] = '\0';
            if (body[0] == '{') {
                #define CHAIN_JSON(K,V) do { json_replace_key(nxt,cap,cur,K,V); char *_t=cur;cur=nxt;nxt=_t; } while(0)
                CHAIN_JSON("commonBean.phoneNo", g_target_phone);
                CHAIN_JSON("commonBean.cityCode", g_target_city);
                if (g_target_aes && g_target_aes[0]) CHAIN_JSON("currentPhoneNumberAes", g_target_aes);
                CHAIN_JSON("phoneNo", g_target_phone);
                #undef CHAIN_JSON
            } else {
                #define CHAIN_FORM(K,V) do { form_replace_all(nxt,cap,cur,K,V); char *_t=cur;cur=nxt;nxt=_t; } while(0)
                CHAIN_FORM("commonBean.phoneNo", g_target_phone);
                CHAIN_FORM("commonBean.cityCode", g_target_city);
                if (g_target_aes && g_target_aes[0]) CHAIN_FORM("currentPhoneNumberAes", g_target_aes);
                CHAIN_FORM("phoneNo", g_target_phone);
                #undef CHAIN_FORM
            }
            rt_request_set_httpbody_str(mreq, cur);
            free(b1); free(b2);
        }
    }
    rt_log("couponhook: request rewritten");
    return mreq;
}

// ---------- NSURLSession hook ----------
static IMP g_orig_dataTask_ch = NULL;
static IMP g_orig_dataTask = NULL;
static IMP g_orig_upload_ch = NULL;
static IMP g_orig_upload = NULL;
static IMP g_orig_upload_file_ch = NULL;

static id hook_dataTask_ch(id self, SEL _cmd, id request, id handler) {
    id nr = rewrite_request(request);
    return ((id(*)(id, SEL, id, id))g_orig_dataTask_ch)(self, _cmd, nr, handler);
}
static id hook_dataTask(id self, SEL _cmd, id request) {
    id nr = rewrite_request(request);
    return ((id(*)(id, SEL, id))g_orig_dataTask)(self, _cmd, nr);
}
static id hook_upload_ch(id self, SEL _cmd, id request, id body, id handler) {
    id nr = rewrite_request(request);
    return ((id(*)(id, SEL, id, id, id))g_orig_upload_ch)(self, _cmd, nr, body, handler);
}
static id hook_upload(id self, SEL _cmd, id request, id body) {
    id nr = rewrite_request(request);
    return ((id(*)(id, SEL, id, id))g_orig_upload)(self, _cmd, nr, body);
}
static id hook_upload_file_ch(id self, SEL _cmd, id request, id fileURL, id handler) {
    id nr = rewrite_request(request);
    return ((id(*)(id, SEL, id, id, id))g_orig_upload_file_ch)(self, _cmd, nr, fileURL, handler);
}

// ---------- WKWebViewConfiguration hook (注入 JS) ----------
static IMP g_orig_cfg_init = NULL;
static id my_cfg_init(id self, SEL _cmd) {
    id cfg = ((id(*)(id, SEL))g_orig_cfg_init)(self, _cmd);
    if (!cfg) return cfg;
    id ucc = objc_msgSend(cfg, sel_registerName("userContentController"));
    if (!ucc) return cfg;
    Class WKUserScript = (Class)objc_getClass("WKUserScript");
    if (!WKUserScript) return cfg;
    id script = objc_msgSend((id)WKUserScript, sel_registerName("alloc"));
    // initWithSource:injectionTime:forMainFrameOnly:  (0=AtDocumentStart, NO=all frames)
    script = objc_msgSend(script, sel_registerName("initWithSource:injectionTime:forMainFrameOnly:"),
                          rt_str(INJECT_JS), (int)0, (BOOL)0);
    objc_msgSend(ucc, sel_registerName("addUserScript:"), script);
    return cfg;
}

static void hook_instance(Class cls, const char *selname, IMP newimp, IMP *orig_slot) {
    if (!cls) return;
    SEL sel = sel_registerName(selname);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { rt_log("couponhook: method not found"); return; }
    *orig_slot = method_getImplementation(m);
    method_setImplementation(m, newimp);
}

__attribute__((constructor))
static void tweak_init(void) {
    rt_log("couponhook: loaded");
    Class NSURLSessionCls = (Class)objc_getClass("NSURLSession");
    if (NSURLSessionCls) {
        hook_instance(NSURLSessionCls, "dataTaskWithRequest:completionHandler:", (IMP)hook_dataTask_ch, &g_orig_dataTask_ch);
        hook_instance(NSURLSessionCls, "dataTaskWithRequest:", (IMP)hook_dataTask, &g_orig_dataTask);
        hook_instance(NSURLSessionCls, "uploadTaskWithRequest:fromData:completionHandler:", (IMP)hook_upload_ch, &g_orig_upload_ch);
        hook_instance(NSURLSessionCls, "uploadTaskWithRequest:fromData:", (IMP)hook_upload, &g_orig_upload);
        hook_instance(NSURLSessionCls, "uploadTaskWithRequest:fromFile:completionHandler:", (IMP)hook_upload_file_ch, &g_orig_upload_file_ch);
    }
    Class WKConfigCls = (Class)objc_getClass("WKWebViewConfiguration");
    if (WKConfigCls) {
        hook_instance(WKConfigCls, "init", (IMP)my_cfg_init, &g_orig_cfg_init);
    }
}
