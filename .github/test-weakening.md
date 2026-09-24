# Test weakening ledger

Removing, skipping or weakening a test or assertion needs Owner approval. Declare each
affected test file by adding one line below in the same PR:

`- <test file path>: <reason> (approved: @<owner>)`

This file is under `/.github/`, which CODEOWNERS assigns to the Owner, so the `main
protection` ruleset (code-owner review required) makes the Owner approve the PR. Also name
each file in the PR template section "Removed or weakened tests or policy".
`scripts/gates/check_test_weakening.py` (pre-push and `Lint & policy`) blocks any loss
without a new line here. Moving an assertion verbatim to another test file is not a loss.

## Entries
