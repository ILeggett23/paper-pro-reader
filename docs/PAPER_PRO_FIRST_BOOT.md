# Paper Pro RC4 live-ink and layer-isolation retest

Run this focused test before resuming the longer qualification. Do not mark
live ink PASS unless it is visible before pen lift on the physical panel.

| Step | Action | PASS | Record on FAIL |
| --- | --- | --- | --- |
| 1 | Enable Ink Mode and draw one slow line | Ink follows the tip before lift | Video; latency and missing segments |
| 2 | Write `testing ink` at normal speed | Continuous live ink with low latency | Video, gaps, ghosting |
| 3 | Open Tools while ink exists | No ink is painted over the menu | Photo of menu |
| 4 | Open and close another modal | No ink is painted over the modal | Photo before/after close |
| 5 | Undo one stroke | Stroke disappears immediately | Delayed or residual stroke |
| 6 | Erase one stroke | Stroke disappears immediately | Persisted vs visible discrepancy |
| 7 | Turn a page with a finger and return | No finger/page-turn regression | Missed/delayed gesture |
| 8 | Exit and relaunch | Persistence and deletion state are correct | Any restored deleted stroke |

If RC4 passes, continue with `PAPER_PRO_AB_TESTS.md`. Dictionary remains
inconclusive until an English StarDict dictionary is installed and verified.
