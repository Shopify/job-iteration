# Agent instructions

## Changelog

When updating `CHANGELOG.md`:

- Read the current changelog and follow the format of its most recent entries.
- Add release notes under `## Main (unreleased)` in the appropriate existing
  subsection: `Breaking Changes`, `Changes`, `Features`, or `Bug fixes`.
- Keep those subsections in this order: `Breaking Changes` → `Changes` →
  `Features` → `Bug fixes`. When unused subsections are omitted, preserve the
  relative order of the remaining headings.
- If a `Security fixes` subsection is used, keep it before `Bug fixes`, as in
  the existing changelog. Its position relative to the other headings is not
  established by the current examples.
- Start each entry with the linked PR number, followed by ` - ` and a concise
  description of the user-visible change:

  ```markdown
  - [PR_NUMBER](https://github.com/Shopify/job-iteration/pull/PR_NUMBER) - Short description of the change.
  ```

- Replace both occurrences of `PR_NUMBER` with the actual PR number. Use the
  number alone as the link label, without a `#` prefix. Do not guess the number.
  If it is not available during drafting, finalize the link after creating the
  PR and before handing it off; do not leave a placeholder or an unlinked entry.
- Replace a subsection's `nil` placeholder when adding its first entry. Keep
  `nil` in the other empty subsections, and preserve existing entries and blank
  lines between headings and content.
- Leave previously released version sections unchanged when adding a release
  note for a new change.
