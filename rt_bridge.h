#ifndef RT_BRIDGE_H
#define RT_BRIDGE_H
// Foundation 常用操作的 C 封装。全部走 objc_msgSend + sel_registerName + objc_getClass,
// 不依赖任何苹果 SDK 头文件, 由运行时目标 App 已加载的 Foundation / libobjc 提供符号。
#include "objc_runtime_min.h"

// ---- NSString ----
id   rt_str(const char *cstr);          // const char* -> NSString*
const char *rt_cstr(id nsstr);          // NSString* -> UTF8 C string (调用方立即使用, 不跨调用持有)

// ---- NSData ----
id   rt_data(const void *bytes, size_t len);
const void *rt_data_bytes(id data);
size_t rt_data_len(id data);

// ---- NSURL / NSURLRequest ----
id   rt_request_url(id req);            // -> NSURL* (原对象, 只读)
id   rt_request_mutable(id req);        // NSURLRequest -> NSMutableURLRequest (mutableCopy)
const char *rt_request_httpmethod(id req);
id   rt_request_httpbody_str(id req);   // HTTPBody -> NSString* (UTF8)
void rt_request_set_httpbody_str(id req, const char *body);

// ---- NSURL (构造) ----
id   rt_url(const char *str);

// ---- JSON ----
id   rt_json_serialize(id obj);         // id -> NSData*
id   rt_json_parse(id data);            // NSData* -> id

// ---- logging (NSLog) ----
void rt_log(const char *msg);

#endif
