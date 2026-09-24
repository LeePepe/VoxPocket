# Declared test removal or weakening

Removing, skipping or weakening a test or assertion needs Owner approval. To declare one,
add `docs/test-weakening/<branch-or-topic>.md` in the same PR. It must name every affected
test file path and give the reason. List it in the PR template section "Removed or weakened
tests or policy" as well.

`.github/CODEOWNERS` owns this directory, so the `main protection` ruleset (code-owner review
required) makes the Owner approve the PR. `scripts/gates/check_test_weakening.py` (pre-push
and `Lint & policy`) fails any loss that has no such file, and fails closed if the CODEOWNERS
entry is missing. Moving an assertion verbatim to another test file is not a loss.
