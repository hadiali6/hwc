#ifndef UTIL_MACROS_H
#define UTIL_MACROS_H

#define MAX(A, B)               ((A) > (B) ? (A) : (B))

#define MIN(A, B)               ((A) < (B) ? (A) : (B))

#define ROUND(X)                ((int)((X < 0) ? (X - 0.5) : (X + 0.5)))

#define LENGTH(X)               (sizeof X / sizeof X[0])

#define END(A)                  ((A) + LENGTH(A))

#define TAGMASK                 ((1u << TAGCOUNT) - 1)

#define CLEANMASK(mask)         (mask & ~WLR_MODIFIER_CAPS)

#define LISTEN(E, L, H)         wl_signal_add((E), ((L)->notify = (H), (L)))

#define LISTEN_STATIC(E, H)                           \
do {                                                  \
    static struct wl_listener _l = { .notify = (H) }; \
    wl_signal_add((E), &_l);                          \
} while (0)

#endif
