#ifndef libsmc_h
#define libsmc_h


#include <stdint.h>


typedef int IOReturn;


#define kIOReturnSuccess 0


IOReturn smc_open(void);


IOReturn smc_write_safe(
    uint32_t key,
    void *bytes,
    uint32_t size
);


IOReturn smc_read_safe(
    uint32_t key,
    void *bytes,
    int32_t *size
);


IOReturn smc_read_n(
    uint32_t key,
    void *bytes,
    int32_t size
);


#endif
