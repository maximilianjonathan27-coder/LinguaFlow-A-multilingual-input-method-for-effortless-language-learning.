#ifndef LF_RIME_BRIDGE_H
#define LF_RIME_BRIDGE_H

#include <stdbool.h>

typedef struct {
    char *text;
    char *comment;
} LFRimeCandidateItem;

bool LFRimeInitialize(
    const char *shared_data_dir,
    const char *user_data_dir,
    const char *schema_id
);

int LFRimeGetCandidates(
    const char *input,
    int limit,
    LFRimeCandidateItem **items
);

void LFRimeFreeCandidates(LFRimeCandidateItem *items, int count);
const char *LFRimeLastError(void);

#endif
