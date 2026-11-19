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
} KothonOptions;

// Load a GGUF model. punct_dir may be NULL. NULL on failure, with *err_out set.
KothonEngine *kothon_engine_new(const char *model_path, const char *punct_dir, char **err_out);

// 16 kHz mono float samples in, UTF-8 text out. NULL on failure, with *err_out set.
char *kothon_transcribe(const KothonEngine *engine, const float *pcm, size_t n_samples,
                        const KothonOptions *options, char **err_out);

// Rule-based cleanup only (numbers, fillers, English words).
char *kothon_post_process(const char *text, const KothonOptions *options);

void kothon_engine_free(KothonEngine *engine);
void kothon_string_free(char *s);

#ifdef __cplusplus
}
#endif
#endif
