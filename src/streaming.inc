#define MD4W_STREAMING 0x10000000u

static int
md4w_at_tail(MD_CTX* ctx, OFF end)
{
    if(!(ctx->parser.flags & MD4W_STREAMING)) return FALSE;
    while(end < ctx->size && ISBLANK(end)) end++;
    return end == ctx->size;
}

static int
md4w_literal_after(MD_CTX* ctx, OFF close, OFF end)
{
    return close < end && !ISANYOF2(close, '(', '[');
}

/* Hides mark i through the end, with the blanks before it, as the paragraph's trailing blanks would be. */
static void
md4w_hide_tail(MD_CTX* ctx, int i, OFF end)
{
    MD_MARK* m = &ctx->marks[i];
    OFF floor = i > 0 ? ctx->marks[i-1].end : 0;
    while(m->beg > floor && ISBLANK(m->beg-1)) m->beg--;
    m->ch = 'H';
    m->end = end;
    m->flags = MD_MARK_RESOLVED;
}

/* The closer of a half link leaves the link. Its label keeps unclosed delimiters as text, as it will once finished. */
static CHAR
md4w_close_label(MD_CTX* ctx, int closer)
{
    int opener = ctx->marks[closer].prev, j;
    if(opener < 0 || ctx->marks[opener].ch != 'A') return 'H';
    for(j = opener+1; j < closer; j++) {
        if(ISANYOF2_(ctx->marks[j].ch, 'E', 'R')) {
            ctx->marks[j].ch = CH(ctx->marks[j].beg);
            ctx->marks[j].flags = 0;
        }
    }
    return 'a';
}

static void
md4w_repair_marks(MD_CTX* ctx, OFF end)
{
    int i;
    OFF last_close = 0;
    for(i = 0; i < ctx->n_marks - 1; i++)
        if(ctx->marks[i].ch == ']') last_close = ctx->marks[i].beg;
    for(i = 0; i < ctx->n_marks - 1; i++) {
        MD_MARK* m = &ctx->marks[i];
        if(m->flags & MD_MARK_RESOLVED) {
            if((m->flags & MD_MARK_OPENER) && m->next > i)
                i = m->next;
            continue;
        }
        if(m->ch == 'D') continue;
        if(m->ch == '[' || m->ch == '!') {
            /* Brackets closed and followed by plain text are already literal text. */
            if(m->next >= 0 ? md4w_literal_after(ctx, ctx->marks[m->next].end, end) : m->beg < last_close)
                continue;
            /* A half link is drawn as a link without a destination; a half image is hidden. */
            if(m->ch == '!') {
                md4w_hide_tail(ctx, i, end);
            } else {
                m->ch = 'A';
                m->flags = MD_MARK_RESOLVED;
            }
        } else if(m->ch == ']' && m->end < end && CH(m->end) == '[' && m->prev >= 0) {
            OFF close = m->end + 1;
            while(close < end && CH(close) != ']') {
                if(CH(close) == '\\' && close+1 < end) close++;
                close++;
            }
            m->end = close < end ? close+1 : end;
            m->ch = md4w_close_label(ctx, i);
            m->flags = MD_MARK_RESOLVED;
        } else if(m->ch == ']' && (m->end == end || CH(m->end) == '(')) {
            m->ch = md4w_close_label(ctx, i);
            m->end = end;
            m->flags = MD_MARK_RESOLVED;
        } else if(m->end == end && ISANYOF_(m->ch, "*_~`$")) {
            md4w_hide_tail(ctx, i, end);
        } else if((m->flags & MD_MARK_POTENTIAL_OPENER) && ISANYOF_(m->ch, "*_~`$")) {
            m->ch = (m->ch == '`' || m->ch == '$') ? 'R' : 'E';
            m->flags = MD_MARK_RESOLVED;
        }
    }
}
