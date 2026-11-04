#include <stdint.h>
typedef struct { uint64_t total, available, compressed, swap; int pressure, memoryOK, processesOK, agents, unreadable; uint64_t resident; } HRReading;
HRReading hr_read(void);
int hr_agent(const char *name);
