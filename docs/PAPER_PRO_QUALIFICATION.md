# Paper Pro Reader qualification matrix

RC: `0.6.0-rc3`. RC1/RC2 evidence is retained; RC3 has no physical PASS result.
Update it only from the user's returned physical report.

| Area | Automated/CI | Emulator/runtime | Physical Paper Pro |
| --- | --- | --- | --- |
| Package architecture/contents | AUTOMATED RC CI ONLY | NOT APPLICABLE | NOT TESTED |
| Installation via AppLoad | source-verified | NOT APPLICABLE | RC1 and RC2 PASS |
| Launch / exit to stock UI | package scripts inspected | macOS runtime only | RC2 PASS |
| Quickstart render/refresh | PASS | PASS | RC2 PASS |
| Finger tap/swipe/link routing | RC2 regression | simulated UIManager stack | RC2 PASS |
| EPUB open/render/navigation | PASS | PASS | RC2 PASS |
| PDF open/render/navigation | PASS | PASS | NOT TESTED |
| Position restore | PASS | PASS | RC2 PASS |
| Selection/highlight/bookmark | PASS | PASS | RC2 selection PASS; highlight/bookmark NOT TESTED |
| StarDict/Define | PASS | PASS | INCONCLUSIVE — local dictionary not verified |
| Vocabulary/Notes | PASS | PASS | RC2 note create/persistence PASS; vocabulary NOT TESTED |
| Marker capture | mocked PASS | emulator fixture PASS | RC2 PASS |
| Live active-stroke rendering | RC3 regression | framebuffer simulation only | RC2 FAIL — visible only after pen lift; RC3 RETEST REQUIRED |
| Pressure field | automated PASS | mocked only | NOT TESTED |
| Eraser/Undo/Redo | PASS | mocked PASS | RC2 undo/eraser PASS; redo NOT TESTED |
| Touch + Marker concurrency | RC2 regression | simulated only | RC2 touch and Marker separately PASS; simultaneous NOT TESTED |
| Ink persistence EPUB/PDF | PASS | PASS | RC2 EPUB ink persistence PASS; PDF NOT TESTED |
| Gallery 3 refresh/ghosting | NOT TESTED | NOT PROVABLE | NOT TESTED |
| Typed AI | mocked backend PASS | localhost PASS | NOT TESTED |
| Handwritten AI | mocked multimodal PASS | localhost PASS | NOT TESTED |
| Offline queue/restart | PASS | PASS | NOT TESTED |
| AI History/conversations | PASS | framebuffer visual | NOT TESTED |
| Full Study | PASS | framebuffer visual | NOT TESTED |
| Sleep/wake | NOT TESTED | NOT PROVABLE | NOT TESTED |
| Device restart/reconnect | storage PASS | simulated | NOT TESTED |
| Upgrade preserving data | archive analysis | NOT APPLICABLE | NOT TESTED |
| Rollback/uninstall | documented | NOT APPLICABLE | NOT TESTED |
| Battery/heat/performance | NOT TESTED | NOT PROVABLE | NOT TESTED |
| Firmware/QTFB compatibility | source-verified assumptions | NOT PROVABLE | OS 3.27.3.0 launch/touch/reading PASS; RC2 live fast refresh FAIL |

Overall physical state: **BLOCKED — RC2 LIVE ACTIVE-STROKE RENDERING FAILURE; RC3 RETEST REQUIRED**.
