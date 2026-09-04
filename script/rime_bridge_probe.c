#include "../LinguaFlowInputMethod/Rime/LFRimeBridge.h"

#include <stdio.h>

static int verify_incremental_input(const char *input) {
    LFRimeCandidateItem *items = NULL;
    int count = LFRimeGetCandidates(input, 5, &items);
    LFRimeFreeCandidates(items, count);
    return count > 0;
}

int main(int argc, char **argv) {
    const char *shared_data_dir = argc > 1 ? argv[1] : ".build/RimeShared";
    const char *user_data_dir = argc > 2 ? argv[2] : ".build/RimeBridgeUser";
    const char *input = argc > 3 ? argv[3] : "nihao";
    if (!LFRimeInitialize(
            shared_data_dir,
            user_data_dir,
            "linguaflow_pinyin")) {
        fprintf(stderr, "Rime initialization failed: %s\n", LFRimeLastError());
        return 1;
    }

    // Exercise append, trailing deletion, and a later full replacement. This
    // catches persistent-session drift before the input method is installed.
    const char *incremental_inputs[] = {"n", "ni", "nihao", "niha", NULL};
    for (int index = 0; incremental_inputs[index] != NULL; ++index) {
        if (!verify_incremental_input(incremental_inputs[index])) {
            fprintf(
                stderr,
                "Incremental Rime query failed for %s: %s\n",
                incremental_inputs[index],
                LFRimeLastError());
            return 2;
        }
    }

    LFRimeCandidateItem *items = NULL;
    int count = LFRimeGetCandidates(input, 20, &items);
    printf("input=%s candidates=%d\n", input, count);
    for (int index = 0; index < count; ++index) {
        printf("%d\t%s\t%s\n", index + 1, items[index].text, items[index].comment);
    }
    LFRimeFreeCandidates(items, count);
    return count > 0 ? 0 : 3;
}
