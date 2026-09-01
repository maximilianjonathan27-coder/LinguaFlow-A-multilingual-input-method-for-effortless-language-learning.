#include "../LinguaFlowInputMethod/Rime/LFRimeBridge.h"

#include <stdio.h>

int main(int argc, char **argv) {
    const char *input = argc > 1 ? argv[1] : "nihao";
    if (!LFRimeInitialize(
            ".build/DerivedData/Build/Products/Debug/LinguaFlow.app/Contents/Resources/Rime",
            ".build/RimeBridgeUser",
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
