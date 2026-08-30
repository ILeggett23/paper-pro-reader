# Paper Pro Reader qualification matrix

RC: `0.6.0-rc1`. This matrix deliberately contains no physical PASS result.
Update it only from the user's returned physical report.

| Area | Automated/CI | Emulator/runtime | Physical Paper Pro |
| --- | --- | --- | --- |
| Package architecture/contents | PENDING RC CI | NOT APPLICABLE | NOT TESTED |
| Installation via AppLoad | source-verified | NOT APPLICABLE | NOT TESTED |
| Launch / exit to stock UI | package scripts inspected | macOS runtime only | NOT TESTED |
| EPUB open/render/navigation | PASS | PASS | NOT TESTED |
| PDF open/render/navigation | PASS | PASS | NOT TESTED |
| Position restore | PASS | PASS | NOT TESTED |
| Selection/highlight/bookmark | PASS | PASS | NOT TESTED |
| StarDict/Define | PASS | PASS | NOT TESTED |
| Vocabulary/Notes | PASS | PASS | NOT TESTED |
| Marker capture | mocked PASS | emulator fixture PASS | NOT TESTED |
| Pressure field | automated PASS | mocked only | NOT TESTED |
| Eraser/Undo/Redo | PASS | mocked PASS | NOT TESTED |
| Touch + Marker concurrency | source-verified | simulated only | NOT TESTED |
| Ink persistence EPUB/PDF | PASS | PASS | NOT TESTED |
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
| Firmware/QTFB compatibility | source-verified assumptions | NOT PROVABLE | NOT TESTED |

Overall physical state: **PHYSICAL PAPER PRO VALIDATION PENDING USER TEST**.
