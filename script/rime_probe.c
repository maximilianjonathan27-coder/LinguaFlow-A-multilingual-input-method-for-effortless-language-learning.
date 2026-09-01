#include <rime_api.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *input = argc > 1 ? argv[1] : "nihao";
    RimeApi *api = rime_get_api();
    if (!api) {
        fprintf(stderr, "Unable to load the Rime API.\n");
        return 1;
    }

    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = ".build/RimeShared";
    traits.user_data_dir = ".build/RimeUser";
    traits.prebuilt_data_dir = ".build/RimeStaging";
    traits.staging_dir = ".build/RimeStaging";
    traits.distribution_name = "LinguaFlow";
    traits.distribution_code_name = "linguaflow";
    traits.distribution_version = "0.1";
    traits.app_name = "rime.linguaflow-probe";
    traits.min_log_level = 2;
    traits.log_dir = "";

    api->setup(&traits);
    api->initialize(&traits);

    RimeSessionId session = api->create_session();
    if (!session || !api->select_schema(session, "linguaflow_pinyin")) {
        fprintf(stderr, "Unable to create a LinguaFlow Rime session.\n");
        api->finalize();
        return 2;
    }
    if (!api->set_input(session, input)) {
        fprintf(stderr, "Unable to set Rime input: %s\n", input);
        api->destroy_session(session);
        api->finalize();
        return 3;
    }

    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(session, &context)) {
        fprintf(stderr, "Rime returned no context for: %s\n", input);
        api->destroy_session(session);
        api->finalize();
        return 4;
    }

    printf("input=%s preedit=%s candidates=%d\n",
           input,
           context.composition.preedit ? context.composition.preedit : "",
           context.menu.num_candidates);
    for (int index = 0; index < context.menu.num_candidates; ++index) {
        RimeCandidate candidate = context.menu.candidates[index];
        printf("%d\t%s\t%s\n",
               index + 1,
               candidate.text ? candidate.text : "",
               candidate.comment ? candidate.comment : "");
    }

    api->free_context(&context);
    api->destroy_session(session);
    api->finalize();
    return 0;
}
