// Quill C ABI copied from MaximeRivest/quill v0.1.0 at
// 39262ee0bef69915e3ead3ac218d5973916f422a.
// Copyright (c) 2026 Maxime Rivest. MIT license; see LICENSE.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#define QUILL_CONTENT_MONO  0
#define QUILL_CONTENT_COLOR 1

int quill_init(void);
int quill_width(void);
int quill_height(void);
int quill_stride(void);
int quill_format(void);
unsigned char* quill_buffer(void);
unsigned long quill_swap_ex(int x, int y, int w, int h,
    int mode, int full_refresh, int content_type);
unsigned long quill_swap(int x, int y, int w, int h, int mode, int full_refresh);
unsigned long quill_swap_mono_fast(int x, int y, int w, int h);
unsigned long quill_swap_mono_quality(int x, int y, int w, int h);
unsigned long quill_swap_color(int x, int y, int w, int h);
unsigned long quill_swap_color_full(int x, int y, int w, int h);
void quill_process_events(void);

#ifdef __cplusplus
}
#endif
