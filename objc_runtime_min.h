#ifndef OBJC_RUNTIME_MIN_H
#define OBJC_RUNTIME_MIN_H
// 最小 objc runtime 声明子集 + 用到的 libc 函数声明。
// 完全不依赖任何系统头文件 (交叉编译 apple target 时宿主 glibc 头会引发冲突),
// 所有符号由目标 App 进程里的 libobjc / libSystem 在加载时解析
// (dylib 以 -undefined dynamic_lookup 链接)。声明取自苹果 objc4 开源头。

typedef unsigned long size_t;
typedef _Bool BOOL;  // arm64 上 Obj-C BOOL 即 C99 bool

#ifndef NULL
#define NULL ((void *)0)
#endif

typedef struct objc_class *Class;
typedef struct objc_object *id;
typedef struct objc_selector *SEL;
typedef struct objc_method *Method;
typedef struct objc_ivar *Ivar;
typedef id (*IMP)(id, SEL, ...);
typedef void *objc_property_t;

// ---- objc runtime ----
id   objc_getClass(const char *name);
id   objc_getMetaClass(const char *name);
id   objc_lookUpClass(const char *name);
SEL  sel_registerName(const char *str);
SEL  sel_getUid(const char *str);
const char *sel_getName(SEL sel);
id   objc_msgSend(id self, SEL op, ...);
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

// ---- libc (运行时由 iOS libSystem 提供, 仅声明) ----
void *malloc(size_t);
void free(void *);
size_t strlen(const char *);
int strcmp(const char *, const char *);
char *strcpy(char *, const char *);
char *strncpy(char *, const char *, size_t);
char *strstr(const char *, const char *);
char *strchr(const char *, int);
char *strncat(char *, const char *, size_t);
int snprintf(char *, size_t, const char *, ...);

#endif
