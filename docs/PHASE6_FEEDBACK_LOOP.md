# Phase 6 hardware feedback loop

Phase 6 remains open after RC1 Stage A. Every returned finding is classified:

- `INSTALL`
- `CRASH`
- `INPUT`
- `MARKER`
- `REFRESH`
- `LAYOUT`
- `NETWORK`
- `AI`
- `PERSISTENCE`
- `PERFORMANCE`
- `UNKNOWN`

For each failure:

1. Preserve the candidate version, commit, firmware, checksum, reproduction
   steps, photo/video, and diagnostic log.
2. Reproduce with source tests, fixtures, packaged runtime, or the smallest
   safe emulator approximation.
3. Identify the narrowest responsible layer. Start in product code; do not
   change A-class code without physical evidence of an engine blocker.
4. Implement the smallest fix and a focused regression test.
5. Run critical Phase 1–5 regressions and package validation.
6. Produce a uniquely identified RC2/RC3 artifact without overwriting prior
   checksums or evidence.
7. Give the user only the finding-specific retest plus launch/exit, EPUB/PDF,
   and persistence smoke checks.
8. Update `PAPER_PRO_QUALIFICATION.md` only with evidence the user explicitly
   reports.

Vague symptoms do not justify broad rewrites. Ask for the diagnostic excerpt,
exact last action, repeatability, orientation, document type, Wi-Fi state, and
whether the stock UI recovered.
