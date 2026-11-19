// Kothon core: on-device Bengali dictation. C API for Swift and JNI.
#ifndef KOTHON_CORE_H
#define KOTHON_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KothonEngine KothonEngine;

typedef struct {
    uint8_t digits;               // 0 = ০১২ (Bengali), 1 = 012 (Latin), 2 = keep words
    bool remove_fillers;          // drop উম, হুম...
    bool english_words_in_english;// "meeting-এ" instead of "মিটিংয়ে"
    bool punctuation;             // । , ? from the MuRIL model, if loaded
    bool no_timestamps;           // true for the Whisper fine-tune
    bool cpu_only;                // iOS: true while the app is in the background (no GPU there)
} KothonOptions;

// Load a GGUF model, on the CPU or GPU (the other copy loads on demand).
// punct_dir may be NULL. NULL on failure, with *err_out set.
KothonEngine *kothon_engine_new(const char *model_path, const char *punct_dir, bool cpu_only,
                                char **err_out);

// 16 kHz mono float samples in, UTF-8 text out. NULL on failure, with *err_out set.
char *kothon_transcribe(const KothonEngine *engine, const float *pcm, size_t n_samples,
                        const KothonOptions *options, char **err_out);

// Rule-based cleanup only (numbers, fillers, English words).
char *kothon_post_process(const char *text, const KothonOptions *options);

// Free the GPU (cpu = false) or CPU copy of the model; it reloads when next needed.
void kothon_engine_unload(const KothonEngine *engine, bool cpu);

// CPU threads (0 = library default) and Accelerate on/off; the CPU copy reloads.
void kothon_engine_set_cpu(const KothonEngine *engine, int32_t n_threads, bool accel);

void kothon_engine_free(KothonEngine *engine);
void kothon_string_free(char *s);

// Speech detection (Silero VAD v6.2, same as the desktop app).
typedef struct KothonVad KothonVad;
KothonVad *kothon_vad_new(const char *path, char **err_out);
// false: no speech, transcribe nothing. true: speech is in [*start, *end).
// vad may be NULL for a loudness-only check.
bool kothon_vad_speech(const KothonVad *vad, const float *pcm, size_t n_samples,
                       size_t *start, size_t *end);
void kothon_vad_free(KothonVad *vad);

#ifdef __cplusplus
}
#endif
#endif
