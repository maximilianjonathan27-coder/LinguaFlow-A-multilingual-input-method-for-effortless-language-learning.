#include "LFRimeBridge.h"
#include "rime_api.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef RimeApi *(*LFRimeGetApiFunction)(void);

// X11-compatible key symbol expected by librime's process_key API.
#define LF_RIME_KEY_BACKSPACE 0xff08

static pthread_mutex_t lf_rime_lock = PTHREAD_MUTEX_INITIALIZER;
static void *lf_rime_library = NULL;
static RimeApi *lf_rime_api = NULL;
static RimeSessionId lf_rime_session = 0;
static bool lf_rime_exit_handler_registered = false;
static char lf_rime_error[512] = "librime has not been initialized";

static void LFRimeSetError(const char *message) {
    snprintf(lf_rime_error, sizeof(lf_rime_error), "%s", message ? message : "unknown error");
}

static void *LFRimeOpenLibrary(void) {
    const char *override = getenv("LINGUAFLOW_RIME_LIBRARY");
    if (override && override[0]) {
        void *handle = dlopen(override, RTLD_NOW | RTLD_LOCAL);
        if (handle) {
            return handle;
        }
    }
    const char *paths[] = {
        "/opt/homebrew/opt/librime/lib/librime.1.dylib",
        "/usr/local/opt/librime/lib/librime.1.dylib",
        "librime.1.dylib",
        NULL,
    };
    for (int index = 0; paths[index] != NULL; ++index) {
        void *handle = dlopen(paths[index], RTLD_NOW | RTLD_LOCAL);
        if (handle) {
            return handle;
        }
    }
    LFRimeSetError(dlerror());
    return NULL;
}

static bool LFRimeReplaceInput(const char *input) {
    lf_rime_api->clear_composition(lf_rime_session);
    return lf_rime_api->set_input(lf_rime_session, input);
}

// Reconcile the persistent librime session with the requested full input.
// Ordinary typing and trailing backspace only send the changed key. Cursor
// edits, stale asynchronous requests, or any rejected incremental event fall
// back to set_input, keeping behavior identical to the previous implementation.
static bool LFRimeApplyInputIncrementally(const char *input) {
    if (!lf_rime_api->get_input || !lf_rime_api->process_key) {
        return LFRimeReplaceInput(input);
    }

    const char *current = lf_rime_api->get_input(lf_rime_session);
    if (!current) {
        return LFRimeReplaceInput(input);
    }
    if (strcmp(current, input) == 0) {
        return true;
    }

    size_t current_length = strlen(current);
    size_t target_length = strlen(input);
    size_t common_length = 0;
    size_t shorter_length = current_length < target_length
        ? current_length
        : target_length;
    while (common_length < shorter_length
           && current[common_length] == input[common_length]) {
        ++common_length;
    }

    bool applied = true;
    if (common_length == current_length) {
        for (size_t index = current_length; index < target_length; ++index) {
            unsigned char key = (unsigned char)input[index];
            if (key > 0x7f || !lf_rime_api->process_key(lf_rime_session, key, 0)) {
                applied = false;
                break;
            }
        }
    } else if (common_length == target_length) {
        for (size_t index = target_length; index < current_length; ++index) {
            if (!lf_rime_api->process_key(
                    lf_rime_session,
                    LF_RIME_KEY_BACKSPACE,
                    0)) {
                applied = false;
                break;
            }
        }
    } else {
        applied = false;
    }

    const char *updated = applied ? lf_rime_api->get_input(lf_rime_session) : NULL;
    if (!updated || strcmp(updated, input) != 0) {
        return LFRimeReplaceInput(input);
    }
    return true;
}

static void LFRimeShutdown(void) {
    pthread_mutex_lock(&lf_rime_lock);
    if (lf_rime_api) {
        if (lf_rime_session) {
            lf_rime_api->destroy_session(lf_rime_session);
            lf_rime_session = 0;
        }
        lf_rime_api->cleanup_all_sessions();
        lf_rime_api->finalize();
        lf_rime_api = NULL;
    }
    pthread_mutex_unlock(&lf_rime_lock);
}

bool LFRimeInitialize(
    const char *shared_data_dir,
    const char *user_data_dir,
    const char *schema_id
) {
    pthread_mutex_lock(&lf_rime_lock);
    if (lf_rime_api && lf_rime_session) {
        pthread_mutex_unlock(&lf_rime_lock);
        return true;
    }

    lf_rime_library = LFRimeOpenLibrary();
    if (!lf_rime_library) {
        pthread_mutex_unlock(&lf_rime_lock);
        return false;
    }
    LFRimeGetApiFunction get_api = (LFRimeGetApiFunction)dlsym(
        lf_rime_library,
        "rime_get_api"
    );
    if (!get_api || !(lf_rime_api = get_api())) {
        LFRimeSetError("librime does not expose rime_get_api");
        pthread_mutex_unlock(&lf_rime_lock);
        return false;
    }

    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = shared_data_dir;
    traits.user_data_dir = user_data_dir;
    traits.prebuilt_data_dir = shared_data_dir;
    traits.distribution_name = "LinguaFlow";
    traits.distribution_code_name = "linguaflow";
    traits.distribution_version = "0.3-librime-experiment";
    traits.app_name = "rime.linguaflow";
    traits.min_log_level = 2;
    traits.log_dir = "";

    lf_rime_api->setup(&traits);
    lf_rime_api->initialize(&traits);
    if (!lf_rime_exit_handler_registered) {
        atexit(LFRimeShutdown);
        lf_rime_exit_handler_registered = true;
    }
    lf_rime_session = lf_rime_api->create_session();
    if (!lf_rime_session) {
        LFRimeSetError("librime could not create a session");
        pthread_mutex_unlock(&lf_rime_lock);
        return false;
    }
    if (!lf_rime_api->select_schema(lf_rime_session, schema_id)) {
        LFRimeSetError("librime could not select the LinguaFlow schema");
        lf_rime_api->destroy_session(lf_rime_session);
        lf_rime_session = 0;
        pthread_mutex_unlock(&lf_rime_lock);
        return false;
    }

    LFRimeSetError("");
    pthread_mutex_unlock(&lf_rime_lock);
    return true;
}

int LFRimeGetCandidates(
    const char *input,
    int limit,
    LFRimeCandidateItem **items
) {
    if (!items || !input || limit <= 0) {
        return 0;
    }
    *items = NULL;
    pthread_mutex_lock(&lf_rime_lock);
    if (!lf_rime_api || !lf_rime_session) {
        LFRimeSetError("librime is unavailable");
        pthread_mutex_unlock(&lf_rime_lock);
        return 0;
    }

    if (!LFRimeApplyInputIncrementally(input)) {
        LFRimeSetError("librime rejected the input");
        pthread_mutex_unlock(&lf_rime_lock);
        return 0;
    }

    LFRimeCandidateItem *result = calloc((size_t)limit, sizeof(LFRimeCandidateItem));
    if (!result) {
        LFRimeSetError("unable to allocate candidate storage");
        pthread_mutex_unlock(&lf_rime_lock);
        return 0;
    }

    int count = 0;
    RimeCandidateListIterator iterator = {0};
    if (lf_rime_api->candidate_list_begin(lf_rime_session, &iterator)) {
        while (count < limit && lf_rime_api->candidate_list_next(&iterator)) {
            result[count].text = strdup(
                iterator.candidate.text ? iterator.candidate.text : ""
            );
            result[count].comment = strdup(
                iterator.candidate.comment ? iterator.candidate.comment : ""
            );
            ++count;
        }
        lf_rime_api->candidate_list_end(&iterator);
    }

    if (count == 0) {
        free(result);
        result = NULL;
    }
    *items = result;
    pthread_mutex_unlock(&lf_rime_lock);
    return count;
}

void LFRimeFreeCandidates(LFRimeCandidateItem *items, int count) {
    if (!items) {
        return;
    }
    for (int index = 0; index < count; ++index) {
        free(items[index].text);
        free(items[index].comment);
    }
    free(items);
}

const char *LFRimeLastError(void) {
    return lf_rime_error;
}
