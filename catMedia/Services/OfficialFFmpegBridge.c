#include "OfficialFFmpegBridge.h"
#include <stdio.h>
#include <unistd.h>

extern int ffmpeg_main(int argc, char **argv) __attribute__((weak_import));
extern int ffprobe_main(int argc, char **argv) __attribute__((weak_import));

/* fftools globals that are not fully reset by ffmpeg_cleanup/ffprobe exit paths. */
extern void **input_files;
extern int nb_input_files;
extern void **output_files;

extern int nb_output_files;
extern void **filtergraphs;
extern int nb_filtergraphs;
extern void **decoders;
extern int nb_decoders;
extern void *progress_avio;
extern FILE *vstats_file;
extern char *vstats_filename;

typedef int (*catmedia_main_function)(int argc, char **argv);

static volatile unsigned long long catmedia_bridge_call_counter = 0;

static unsigned long long catmedia_next_call_id(void) {
    return __sync_add_and_fetch(&catmedia_bridge_call_counter, 1);
}

static void catmedia_bridge_log(unsigned long long call_id, const char *tool, const char *step, int argc, char *argv[]) {
    char buffer[512];
    const char *argv0 = "(null)";
    if (argv != 0 && argc > 0 && argv[0] != 0) {
        argv0 = argv[0];
    }

    int written = snprintf(
        buffer,
        sizeof(buffer),
        "[catMedia][Bridge][%llu] %s %s (argc=%d argv0=%s)\n",
        call_id,
        tool,
        step,
        argc,
        argv0
    );

    if (written > 0) {
        size_t length = (size_t)written;
        if (length >= sizeof(buffer)) {
            length = sizeof(buffer) - 1;
        }
        (void)write(STDERR_FILENO, buffer, length);
    }
}

static void catmedia_bridge_log_exit(unsigned long long call_id, const char *tool, int exit_code) {
    char buffer[256];
    int written = snprintf(
        buffer,
        sizeof(buffer),
        "[catMedia][Bridge][%llu] %s STEP 4: returned exit=%d\n",
        call_id,
        tool,
        exit_code
    );

    if (written > 0) {
        size_t length = (size_t)written;
        if (length >= sizeof(buffer)) {
            length = sizeof(buffer) - 1;
        }
        (void)write(STDERR_FILENO, buffer, length);
    }
}

static void catmedia_reset_fftools_state(unsigned long long call_id, const char *tool) {
    input_files = 0;
    nb_input_files = 0;

    output_files = 0;
    nb_output_files = 0;

    filtergraphs = 0;
    nb_filtergraphs = 0;

    decoders = 0;
    nb_decoders = 0;

    progress_avio = 0;
    vstats_file = 0;
    vstats_filename = 0;

    catmedia_bridge_log(call_id, tool, "STEP 2A: reset fftools globals", 0, 0);
}

int catmedia_ffmpeg_execute(int argc, char *argv[]) {
    unsigned long long call_id = catmedia_next_call_id();
    catmedia_bridge_log(call_id, "ffmpeg", "STEP 1: entry", argc, argv);

    catmedia_main_function ffmpeg_entry = ffmpeg_main;
    if (ffmpeg_entry == 0) {
        catmedia_bridge_log(call_id, "ffmpeg", "STEP 2: ffmpeg_main symbol missing", argc, argv);
        return -127;
    }

    catmedia_reset_fftools_state(call_id, "ffmpeg");
    catmedia_bridge_log(call_id, "ffmpeg", "STEP 3: calling ffmpeg_main", argc, argv);
    const int exit_code = ffmpeg_entry(argc, argv);
    catmedia_bridge_log_exit(call_id, "ffmpeg", exit_code);

    return exit_code;
}

int catmedia_ffprobe_execute(int argc, char *argv[]) {
    unsigned long long call_id = catmedia_next_call_id();
    catmedia_bridge_log(call_id, "ffprobe", "STEP 1: entry", argc, argv);

    catmedia_main_function ffprobe_entry = ffprobe_main;
    if (ffprobe_entry == 0) {
        catmedia_bridge_log(call_id, "ffprobe", "STEP 2: ffprobe_main symbol missing", argc, argv);
        return -127;
    }

    catmedia_reset_fftools_state(call_id, "ffprobe");
    catmedia_bridge_log(call_id, "ffprobe", "STEP 3: calling ffprobe_main", argc, argv);
    const int exit_code = ffprobe_entry(argc, argv);
    catmedia_bridge_log_exit(call_id, "ffprobe", exit_code);

    return exit_code;
}

const char *catmedia_ffmpeg_bridge_backend(void) {
    catmedia_main_function ffmpeg_entry = ffmpeg_main;
    catmedia_main_function ffprobe_entry = ffprobe_main;

    if (ffmpeg_entry != 0 && ffprobe_entry != 0) {
        return "official-ffmpeg-main-symbols";
    }

    return "missing-ffmpeg-symbols";
}
