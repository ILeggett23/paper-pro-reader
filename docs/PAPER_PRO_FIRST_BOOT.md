# Paper Pro RC3 live-ink retest

Run this focused test before resuming the longer qualification. Do not mark
live ink PASS unless it is visible before pen lift on the physical panel.

| Step | Action | PASS | Record on FAIL |
| --- | --- | --- | --- |
| 1 | Enable Ink Mode | `INK` status appears | Missing status or touch regression |
| 2 | Draw one slow horizontal line | Ink visibly follows while the tip remains down | Video; whether all ink waited for lift |
| 3 | Draw several letters at normal speed | Continuous visible writing; no missing live segments | Video, gaps, latency, ghosting |
| 4 | Undo once | Last stroke disappears immediately | Delay or stale pixels |
| 5 | Draw again and use eraser once | Eraser removes the intended stroke | Wrong stroke, delayed refresh |
| 6 | Exit and relaunch | Remaining ink persists and undone/erased ink stays absent | Any restored deleted stroke |
| 7 | Turn one EPUB page and return | Finger touch and reading position still work | Touch or navigation regression |

If live ink passes, continue with `PAPER_PRO_AB_TESTS.md`. Dictionary remains
inconclusive until an English StarDict dictionary is installed and verified.
