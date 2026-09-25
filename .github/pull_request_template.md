<!--
PR goals: base = default branch; one purpose; one layer scope where possible;
independently mergeable. Stacked PR? After its base merges, retarget to main and
`git rebase --onto origin/main <old-base-tip>` before merging (squash merges
otherwise make the stacked branch conflict).
-->

## Existing behaviour

<!-- What the code does today that this PR touches, including behaviour that must stay unchanged. -->

## Intent

<!-- What changes and why. Link the task/issue/spec. -->

## Compatibility

<!-- API, data, config and UX compatibility; migrations; how to roll back. Write "no change" if so. -->

## Removed or weakened tests or policy

<!-- Follow docs/repository-policy.md#review-and-execution-boundaries: list removed/skipped/weakened tests or assertions with reasons and retained/replacement coverage; list protected changes with their reason and approver. Ordinary in-scope test maintenance needs no Owner approval. Write "none" if none. -->

## Test evidence

<!-- `scripts/verify` result and the tested SHA (the PR head). A new push invalidates this. -->
- Command:
- Result:
- Tested SHA:
