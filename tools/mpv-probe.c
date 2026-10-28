// Development-only libmpv probe. Not linked into or bundled with SakuraPlayer.
#include "client.h"
#include "render.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static int check(int result, const char *operation) {
    if (result >= 0) return 1;
    fprintf(stderr, "%s: %s\n", operation, mpv_error_string(result));
    return 0;
}

static int roundtrip(mpv_handle *mpv, const char *property, double expected) {
    double actual = 0;
    return check(mpv_set_property(mpv, property, MPV_FORMAT_DOUBLE, &expected), property)
        && check(mpv_get_property(mpv, property, MPV_FORMAT_DOUBLE, &actual), property)
        && fabs(actual - expected) < 0.0001;
}

static int render(mpv_render_context *ctx, unsigned char *pixels) {
    int size[] = {320, 180};
    size_t stride = 320 * 4;
    int block = 0;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_SW_SIZE, size},
        {MPV_RENDER_PARAM_SW_FORMAT, "rgb0"},
        {MPV_RENDER_PARAM_SW_STRIDE, &stride},
        {MPV_RENDER_PARAM_SW_POINTER, pixels},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block},
        {0, NULL}
    };
    return mpv_render_context_render(ctx, params);
}

static int pump(mpv_handle *mpv, mpv_render_context *ctx, unsigned char *pixels,
                mpv_event_id wanted, double timeout) {
    double deadline = now() + timeout;
    while (now() < deadline) {
        mpv_event *event = mpv_wait_event(mpv, 0.01);
        if (event->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *end = event->data;
            if (end && end->error < 0) return check(end->error, "decode");
        }
        if (mpv_render_context_update(ctx) & MPV_RENDER_UPDATE_FRAME) {
            if (!check(render(ctx, pixels), "software render")) return 0;
        }
        if (event->event_id == wanted) return 1;
    }
    fprintf(stderr, "Timed out waiting for %s\n", mpv_event_name(wanted));
    return 0;
}

static int verify_tracks(mpv_handle *mpv, mpv_render_context *ctx, unsigned char *pixels) {
    int64_t count = 0, lastAudio = -1, subtitle = -1;
    int audioCount = 0;
    if (!check(mpv_get_property(mpv, "track-list/count", MPV_FORMAT_INT64, &count), "track count")) return 0;
    for (int i = 0; i < count; ++i) {
        char property[64];
        snprintf(property, sizeof(property), "track-list/%d/type", i);
        char *type = mpv_get_property_string(mpv, property);
        snprintf(property, sizeof(property), "track-list/%d/id", i);
        int64_t id = -1;
        mpv_get_property(mpv, property, MPV_FORMAT_INT64, &id);
        if (type && !strcmp(type, "audio")) { ++audioCount; lastAudio = id; }
        if (type && !strcmp(type, "sub")) subtitle = id;
        mpv_free(type);
    }
    if (audioCount > 1) {
        int64_t selected = -1;
        if (!check(mpv_set_property(mpv, "aid", MPV_FORMAT_INT64, &lastAudio), "select audio")
            || !check(mpv_get_property(mpv, "aid", MPV_FORMAT_INT64, &selected), "selected audio")
            || selected != lastAudio) return 0;
        printf("audio-track-switch=PASS count=%d selected=%lld\n", audioCount, (long long)selected);
    }
    if (subtitle >= 0) {
        if (!check(mpv_set_property(mpv, "sid", MPV_FORMAT_INT64, &subtitle), "select subtitle")) return 0;
        const char *seek[] = {"seek", "0.5", "absolute+exact", NULL};
        if (!check(mpv_command(mpv, seek), "subtitle seek")
            || !pump(mpv, ctx, pixels, MPV_EVENT_PLAYBACK_RESTART, 10)) return 0;
        char *text = mpv_get_property_string(mpv, "sub-text");
        int hasText = text && strstr(text, "Sakura ASS probe");
        mpv_free(text);
        if (!hasText || !check(render(ctx, pixels), "subtitle render")) return 0;
        unsigned char *withSubtitle = malloc(320 * 180 * 4);
        if (!withSubtitle) return 0;
        memcpy(withSubtitle, pixels, 320 * 180 * 4);
        mpv_set_property_string(mpv, "sub-visibility", "no");
        double deadline = now() + 0.1;
        while (now() < deadline) mpv_wait_event(mpv, 0.01);
        int ok = check(render(ctx, pixels), "subtitle off render");
        size_t changed = 0;
        for (size_t i = 0; i < 320 * 180 * 4; ++i) changed += pixels[i] != withSubtitle[i];
        free(withSubtitle);
        printf("ass-text=%s subtitle-render-changed-bytes=%zu\n", hasText ? "PASS" : "FAIL", changed);
        if (!ok || !changed) return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: mpv-probe /absolute/path/to/generated-fixture\n");
        return 2;
    }
    mpv_handle *mpv = mpv_create();
    mpv_render_context *ctx = NULL;
    unsigned char *pixels = calloc(320 * 180, 4);
    int result = 1;
    if (!mpv || !pixels) goto done;
    const char *options[][2] = {
        {"config", "no"}, {"load-scripts", "no"}, {"ytdl", "no"},
        {"vo", "libmpv"}, {"ao", "null"}, {"hwdec", "no"},
        {"pause", "yes"}, {"idle", "yes"}, {"keep-open", "yes"},
        {"sub-auto", "no"}, {"audio-file-auto", "no"}, {"osd-level", "0"},
        {"terminal", "no"}
    };
    for (size_t i = 0; i < sizeof(options) / sizeof(options[0]); ++i) {
        if (!check(mpv_set_option_string(mpv, options[i][0], options[i][1]), options[i][0])) goto done;
    }
    if (!check(mpv_initialize(mpv), "initialize")) goto done;
    mpv_render_param params[] = {{MPV_RENDER_PARAM_API_TYPE, MPV_RENDER_API_TYPE_SW}, {0, NULL}};
    if (!check(mpv_render_context_create(&ctx, mpv, params), "render context")) goto done;
    char *version = mpv_get_property_string(mpv, "mpv-version");
    printf("runtime=%s client-api=%lu.%lu\n", version ? version : "unknown",
           mpv_client_api_version() >> 16, mpv_client_api_version() & 0xffff);
    mpv_free(version);
    if (!roundtrip(mpv, "audio-delay", 0.25) || !roundtrip(mpv, "audio-delay", -0.25)
        || !roundtrip(mpv, "audio-delay", 0) || !roundtrip(mpv, "sub-delay", 0.5)
        || !roundtrip(mpv, "sub-delay", -0.5) || !roundtrip(mpv, "sub-delay", 0)) goto done;
    double started = now();
    const char *load[] = {"loadfile", argv[1], NULL};
    if (!check(mpv_command(mpv, load), "loadfile")
        || !pump(mpv, ctx, pixels, MPV_EVENT_FILE_LOADED, 10)) goto done;
    double loaded = now() - started;
    double duration = 0;
    if (!check(mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &duration), "duration")
        || duration <= 0) goto done;
    // A short unpaused interval starts both decoders. Null audio is intentionally
    // inaudible; this does not prove real-device output or A/V synchronization.
    if (!check(mpv_set_property_string(mpv, "pause", "no"), "play")
        || !pump(mpv, ctx, pixels, MPV_EVENT_PLAYBACK_RESTART, 10)) goto done;
    mpv_set_property_string(mpv, "pause", "yes");
    const char *seek[] = {"seek", "0.5", "absolute+exact", NULL};
    started = now();
    if (!check(mpv_command(mpv, seek), "seek")
        || !pump(mpv, ctx, pixels, MPV_EVENT_PLAYBACK_RESTART, 10)) goto done;
    double seekTime = now() - started;
    if (!verify_tracks(mpv, ctx, pixels)) goto done;
    char *tracks = mpv_get_property_string(mpv, "track-list/count");
    char *codec = mpv_get_property_string(mpv, "video-codec");
    char *audio = mpv_get_property_string(mpv, "audio-codec-name");
    char *hwdec = mpv_get_property_string(mpv, "hwdec-current");
    printf("PASS duration=%.3f tracks=%s video=%s audio=%s hwdec=%s load=%.3fs seek=%.3fs\n",
           duration, tracks ? tracks : "unknown", codec ? codec : "none",
           audio ? audio : "none", hwdec ? hwdec : "none", loaded, seekTime);
    mpv_free(tracks);
    mpv_free(codec);
    mpv_free(audio);
    mpv_free(hwdec);
    result = 0;
done:
    if (ctx) mpv_render_context_free(ctx);
    if (mpv) mpv_terminate_destroy(mpv);
    free(pixels);
    return result;
}
