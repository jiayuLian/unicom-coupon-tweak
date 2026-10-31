#ifndef OBJC_RUNTIME_MIN_H
#define OBJC_RUNTIME_MIN_H
// 最小 objc runtime 声明子集。这些符号由目标 App 进程里的 libobjc 在加载时解析
// (dylib 以 -undefined dynamic_lookup 链接, 不链接任何系统库)。声明取自苹果 objc4 开源头。
#include <stddef.h>
#include <stdbool.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct objc_class *Class;
typedef struct objc_object *id;
typedef struct objc_selector *SEL;
typedef struct objc_method *Method;
typedef struct objc_ivar *Ivar;
typedef struct objc_protocol *Protocol;
typedef id (*IMP)(id, SEL, ...);
typedef void *objc_property_t;

id   objc_getClass(const char *name);
id   objc_getMetaClass(const char *name);
id   objc_lookUpClass(const char *name);
SEL  sel_registerName(const char *str);
SEL  sel_getUid(const char *str);
const char *sel_getName(SEL sel);
id   objc_msgSend(id self, SEL op, ...);
id   objc_msgSendSuper(void *super_info, SEL op, ...);
Class object_getClass(id obj);
const char *object_getClassName(id obj);
const char *class_getName(Class cls);
Class class_getSuperclass(Class cls);

Method class_getInstanceMethod(Class cls, SEL name);
Method class_getClassMethod(Class cls, SEL name);
IMP    method_getImplementation(Method m);
IMP    method_setImplementation(Method m, IMP imp);
void   method_exchangeImplementations(Method m1, Method m2);
const char *method_getTypeEncoding(Method m);
BOOL   class_addMethod(Class cls, SEL name, IMP imp, const char *types);

Class  objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes);
void   objc_registerClassPair(Class cls);

id   objc_getAssociatedObject(id obj, void *key);
void objc_setAssociatedObject(id obj, void *key, id value, int policy);
void objc_removeAssociatedObjects(id obj);

#if defined(__cplusplus)
}
#endif
#endif
