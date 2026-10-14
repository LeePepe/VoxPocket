# Conceptual model: test coverage inventory

This feature has no persistent product data. The following records define planning and evidence only.

## Test artifact

| Field | Meaning |
|---|---|
| `path` | Repository-relative test file or target source directory. |
| `kind` | `python-script`, `python-unittest`, `ruby-test`, `bash-contract-test`, `zsh-suite`, `xcode-target`, or `manifest`. |
| `owner_scope` | Explicit `_root support` scope or the `VoxPocketApp` repository layer. |
| `discovery_rule` | Stable pattern/target membership that selects the artifact. |
| `required_lane` | Required PR check that executes or validates it. |
| `executor` | Direct command/interface used by the lane. |
| `evidence` | Log path/name, test summary, and exact tested SHA. |
| `disposition` | `executed`, `validated-local-tool`, or pre-existing `platform-skip`. |

### Invariants

1. Every scoped `Test artifact` has one authoritative `required_lane`.
2. An empty discovery set is an error.
3. Local manifest tooling cannot claim `executed` required-PR coverage.
4. A platform skip is valid only when the test bundle executed and the skip predates this feature.
5. No artifact may move to `removed` or `weakened` without the PR declaration and required Owner approval.
6. The three baseline `scripts/gates/tests/test_*.py` artifacts and `scripts/ci/kimi-review.contract.test.sh` retain disposition `executed` and their required-policy bindings. The Kimi artifact has kind `bash-contract-test`, `_root support` ownership, and the direct `bash` executor. D-002 is inapplicable to these execution edges.

## Coverage evidence

| Field | Meaning |
|---|---|
| `head_sha` | Exact PR `headRefOid` to which evidence applies. |
| `check_name` | Existing required check name. |
| `command` | Executed test/discovery command. |
| `discovered_paths` | Sorted matched paths plus directly invoked artifact paths printed before execution. |
| `result` | Pass/fail plus counts; Xcode includes bundle and skip summaries. |
| `log_reference` | CI step/log or `.xcresult` reference. |

Evidence is invalid after any push that changes `head_sha`.

## Local tooling disposition

| Field | Value |
|---|---|
| `component` | `scripts/test-executor/**` + `tests/manifests/*.tests.manifest.json` |
| `status` | Retained live local tooling |
| `required_ci_authority` | No |
| `required_ci_validation` | zsh syntax + manifest validation |
| `prohibited_ci_entry` | `run_pr.sh`, `run_nightly.sh`, `link_local_dependencies.sh` |

No database, schema migration, serialization change, or runtime entity is introduced.
