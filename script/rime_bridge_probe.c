#include "../LinguaFlowInputMethod/Rime/LFRimeBridge.h"

#include <stdio.h>

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

    LFRimeCandidateItem *items = NULL;
    int count = LFRimeGetCandidates(input, 20, &items);
    printf("input=%s candidates=%d\n", input, count);
    for (int index = 0; index < count; ++index) {
        printf("%d\t%s\t%s\n", index + 1, items[index].text, items[index].comment);
    }
    LFRimeFreeCandidates(items, count);
    return count > 0 ? 0 : 2;
}
