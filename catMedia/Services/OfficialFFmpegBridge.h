#ifndef CATMEDIA_OFFICIAL_FFMPEG_BRIDGE_H
#define CATMEDIA_OFFICIAL_FFMPEG_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

int catmedia_ffmpeg_execute(int argc, char *argv[]);
int catmedia_ffprobe_execute(int argc, char *argv[]);
const char *catmedia_ffmpeg_bridge_backend(void);

#ifdef __cplusplus
}
#endif

#endif
