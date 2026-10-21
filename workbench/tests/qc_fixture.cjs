// Complete synthetic current QC records for offline interface tests.
// Counts and IDs are declared fixture evidence; this does not run QC science.
function qcPreviewFixture(proposal, before, retained = before) {
  const cells = Array.from({length: before}, (_, index) => "fixture-cell-" + index);
  const rules = proposal.rules, rule_ids = rules.map((_, index) => "rule" + (index + 1));
  return {schema: "scagentkit.qc.preview.v1", evidence_hash: "d".repeat(64),
    canonical_parameters: {proposal: JSON.parse(JSON.stringify(proposal))},
    retention: {before, retained, removed: before - retained},
    keep_cells: cells.slice(0, retained), remove_cells: cells.slice(retained),
    keep_cell_hash: "a".repeat(64), remove_cell_hash: "b".repeat(64),
    rule_logic: {remove_if: proposal.remove_if, rule_ids, prefilter_removed: 0,
      prior_removed: rules.length ? 0 : before - retained,
      prior_excluded_cells: rules.length ? [] : cells.slice(retained),
      quality_removed: rules.length ? before - retained : 0, final_retained: retained},
    filter_impacts: [], overlap: {filter_ids: rule_ids, counts: []}, patterns: []};
}
module.exports = {qcPreviewFixture};
