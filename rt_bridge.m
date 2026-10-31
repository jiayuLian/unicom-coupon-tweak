#import "rt_bridge.h"
#import "objc_runtime_min.h"
// 不引入 <string.h>: 交叉编译 apple target 时它会拉入宿主 glibc 头链 (bits/libc-header-start.h) 导致 fatal;
// 本文件只用 objc_runtime_min.h 提供的 size_t, 不调用任何 libc 字符串函数。

// NSString 编码常量: NSUTF8StringEncoding = 4
#define RT_NSUTF8 4

static SEL s(const char *name) { return sel_registerName(name); }
static Class C(const char *name) { return (Class)objc_getClass(name); }

id rt_str(const char *cstr) {
    Class NSStringCls = C("NSString");
    if (!NSStringCls) return NULL;
    id obj = objc_msgSend((id)NSStringCls, s("alloc"));
    return objc_msgSend(obj, s("initWithUTF8String:"), cstr ? cstr : "");
}

const char *rt_cstr(id nsstr) {
    if (!nsstr) return NULL;
    return (const char *)objc_msgSend(nsstr, s("UTF8String"));
}

id rt_data(const void *bytes, size_t len) {
    Class NSDataCls = C("NSData");
    if (!NSDataCls) return NULL;
    return objc_msgSend((id)NSDataCls, s("dataWithBytes:length:"), bytes, (unsigned long)len);
}

const void *rt_data_bytes(id data) {
    if (!data) return NULL;
    return (const void *)objc_msgSend(data, s("bytes"));
}
size_t rt_data_len(id data) {
    if (!data) return 0;
    return (size_t)objc_msgSend(data, s("length"));
}

id rt_request_url(id req) {
    if (!req) return NULL;
    return objc_msgSend(req, s("URL"));
}

id rt_request_mutable(id req) {
    if (!req) return NULL;
    // NSURLRequest 遵循 NSMutableCopying, mutableCopy 返回 NSMutableURLRequest
    return objc_msgSend(req, s("mutableCopy"));
}

const char *rt_request_httpmethod(id req) {
    if (!req) return NULL;
    return rt_cstr(objc_msgSend(req, s("HTTPMethod")));
}

id rt_request_httpbody_str(id req) {
    if (!req) return NULL;
    id body = objc_msgSend(req, s("HTTPBody"));   // NSData*
    if (!body) return NULL;
    Class NSStringCls = C("NSString");
    id obj = objc_msgSend((id)NSStringCls, s("alloc"));
    return objc_msgSend(obj, s("initWithData:encoding:"), body, (unsigned long)RT_NSUTF8);
}

void rt_request_set_httpbody_str(id req, const char *body) {
    if (!req) return;
    id bodyStr = rt_str(body);
    if (!bodyStr) return;
    id data = objc_msgSend(bodyStr, s("dataUsingEncoding:"), (unsigned long)RT_NSUTF8);
    objc_msgSend(req, s("setHTTPBody:"), data);
}

id rt_url(const char *str) {
    Class NSURLCls = C("NSURL");
    if (!NSURLCls) return NULL;
    id obj = objc_msgSend((id)NSURLCls, s("alloc"));
    return objc_msgSend(obj, s("initWithString:"), rt_str(str));
}

id rt_json_serialize(id obj) {
    Class CLS = C("NSJSONSerialization");
    if (!CLS) return NULL;
    return objc_msgSend((id)CLS, s("dataWithJSONObject:options:error:"), obj, 0, NULL);
}

id rt_json_parse(id data) {
    Class CLS = C("NSJSONSerialization");
    if (!CLS) return NULL;
    return objc_msgSend((id)CLS, s("JSONObjectWithData:options:error:"), data, 0, NULL);
}

void rt_log(const char *msg) {
    extern void NSLog(id format, ...);
    if (!msg) return;
    NSLog(rt_str(msg));
}
