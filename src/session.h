#include "md4c.h"

typedef struct MD4W_SESSION MD4W_SESSION;
MD4W_SESSION* md4w_open(void);
void md4w_close(MD4W_SESSION*);
int md4w_parse(const MD_CHAR*, MD_SIZE, const MD_PARSER*, void*, MD4W_SESSION*, MD_SIZE);
