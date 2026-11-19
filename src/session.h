#include "md4c.h"

typedef struct MD4W_SESSION MD4W_SESSION;
MD4W_SESSION* md4w_open(void);
void md4w_close(MD4W_SESSION*);
int md4w_parse(const MD_CHAR*, MD_SIZE, const MD_PARSER*, void*, MD4W_SESSION*, MD_SIZE);

void md4w_rule_chars(void*, char*);
int md4w_match(void*, int kind, const char*, MD_SIZE, MD_SIZE*);
void md4w_tag(void*, int rule, MD_SIZE start, MD_SIZE end, int closing);
int md4w_inner(void*, int rule, const char*, MD_SIZE, MD_SIZE*, MD_SIZE*);
