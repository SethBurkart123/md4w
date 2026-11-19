#define MD4W_STREAMING 0x10000000u

static int
md4w_at_tail(MD_CTX* ctx, OFF end)
{
    if(!(ctx->parser.flags & MD4W_STREAMING)) return FALSE;
    while(end < ctx->size && ISBLANK(end)) end++;
    return end == ctx->size;
}

static void
md4w_repair_marks(MD_CTX* ctx, OFF end)
{
    int i;
    for(i = 0; i < ctx->n_marks - 1; i++) {
        MD_MARK* m = &ctx->marks[i];
        if(m->flags & MD_MARK_RESOLVED) {
            if((m->flags & MD_MARK_OPENER) && m->next > i)
                i = m->next;
            continue;
        }
        if(m->ch == 'D') continue;
        if(m->ch == '[' || m->ch == '!') {
            m->ch = 'H';
            m->flags = MD_MARK_RESOLVED;
        } else if(m->ch == ']' && (m->end == end || CH(m->end) == '(')) {
            m->ch = 'H';
            m->end = end;
            m->flags = MD_MARK_RESOLVED;
        } else if(m->ch == '|' || (m->end == end && ISANYOF_(m->ch, "*_~`$"))) {
            m->ch = 'H';
            m->flags = MD_MARK_RESOLVED;
        } else if((m->flags & MD_MARK_POTENTIAL_OPENER) && ISANYOF_(m->ch, "*_~`$")) {
            m->ch = (m->ch == '`' || m->ch == '$') ? 'R' : 'E';
            m->flags = MD_MARK_RESOLVED;
        }
    }
}
