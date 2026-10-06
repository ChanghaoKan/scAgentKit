reference_evidence_fixture <- function() {
  genes <- c("G1", "G2", "G3", "g3", "FCGR3A", "MRC1", "LOW", "U1", "U2")
  cells <- c("001", "1", "NA", "cell space", "A", "B")
  counts <- Matrix::Matrix(matrix(rep(1:3, length.out = length(genes) * length(cells)),
    nrow = length(genes), dimnames = list(genes, cells)), sparse = TRUE)
  seu <- Seurat::CreateSeuratObject(counts = counts, min.cells = 0, min.features = 0)
  seu$literal_cluster <- c("001", "001", "NA", "NA", "cell group", "cell group")
  seu$old_annotation <- factor(c("Old", NA, "Old", "Other", "Other", "Old"))
  table <- data.frame(cluster = c("001", "001", "001", "001", "NA", "cell group"),
    gene = c("G1", "G1", "G2", "CD16", "G3", "g3"), stringsAsFactors = FALSE)
  reference <- data.frame(cell_type = c("T cell", "T cell", "T cell", "T cell", "B cell",
      "Myeloid", "Myeloid", "Mouse T", "Liver cell", "Universal", "Case sensitive"),
    marker = c("G1", "G1", "G2", "G2", "G3", "CD16", "FCGR3A", "G1", "G1", "G1", "g3"),
    species = c(rep("human", 7), "mouse", "human", "human", "human"),
    tissue = c(rep("blood", 8), "liver", "all", "blood"), stringsAsFactors = FALSE)
  list(seu = seu, table = table, reference = reference,
       context = list(species = " HUMAN ", tissue = " Blood "))
}

reference_evidence_run <- function(fixture, reference = fixture$reference, options = NULL,
                                   context = fixture$context) {
  scAgentKit:::.sc_run_reference_evidence(fixture$seu, fixture$table, context, reference,
                                        "literal_cluster", options)
}

reference_evidence_cluster <- function(evidence, id = "001") {
  Filter(function(x) identical(x$clusterId, id), evidence$per_cluster)[[1]]
}

reference_joint_fixture <- function(label = "T cell", markers = list("G1")) {
  fixture <- reference_evidence_fixture()
  local <- reference_evidence_run(fixture, options = list(symbol_aliases = c(CD16 = "FCGR3A")))
  supplied <- list(clusterId = "001", cellCount = 2L, markers = list(
    list(clusterId = "001", gene = "G1", avgLog2FC = 2, pct1 = .8, pct2 = .1, pAdj = .001,
         source = "Seurat::FindAllMarkers")))
  row <- list(clusterId = "001", label = label, confidence = "medium",
              rationale = "Reviewed saved marker evidence.", markers = markers)
  list(row = row, supplied = supplied, local = local, source = list(kind = "manual"))
}

reference_joint_run <- function(fixture, options = NULL, historical = NULL) {
  scAgentKit:::.sc_run_joint_evidence(fixture$row, fixture$supplied, fixture$local,
                                    fixture$source, historical, options)
}

test_that("reference options are explicit, typed and reject ambiguous declarations", {
  defaults <- scAgentKit:::.sc_run_reference_options()
  expect_identical(defaults$top_n, 5L)
  expect_identical(defaults$ai_mode, "independent")
  expect_equal(nrow(defaults$label_relations), 0L)
  expect_error(scAgentKit:::.sc_run_reference_options(list(top_n = 0)), "positive integer")
  expect_error(scAgentKit:::.sc_run_reference_options(list(top_n = 1.5)), "positive integer")
  expect_error(scAgentKit:::.sc_run_reference_options(list(ai_mode = "automatic")), "independent or guided")
  expect_error(scAgentKit:::.sc_run_reference_options(list(symbol_aliases = c("G1"))), "named character")
  expect_error(scAgentKit:::.sc_run_reference_options(list(symbol_aliases = c(A = "B", B = "A"))), "Cyclic")
  expect_error(scAgentKit:::.sc_run_reference_options(list(label_map = c("T" = "A", " t " = "B"))), "unique")
  expect_error(scAgentKit:::.sc_run_reference_options(list(label_relations =
    data.frame(child = c("A", "B"), parent = c("B", "A")))), "Cyclic")
  expect_error(scAgentKit:::.sc_run_reference_options(list(label_relations =
    data.frame(child = c("A", "B"), parent = c("P", "P"), lineage = c("L1", "L2")))), "Conflicting")
  expect_error(scAgentKit:::.sc_run_reference_options(list(provenance = list(api_key = "fake"))), "Unsupported")
  expect_error(scAgentKit:::.sc_run_reference_options(list(provenance = list(original_sha256 = "short"))), "SHA256")
  expect_identical(scAgentKit:::.sc_run_reference_resolve("CD16", c(CD16 = "Fc", Fc = "FCGR3A")), "FCGR3A")
})

test_that("scoped reference scores unique canonical symbols and preserves source object", {
  fixture <- reference_evidence_fixture()
  before <- digest::digest(fixture$seu, algo = "sha256")
  evidence <- reference_evidence_run(fixture, options = list(symbol_aliases = c(CD16 = "FCGR3A")))
  expect_identical(digest::digest(fixture$seu, algo = "sha256"), before)
  expect_identical(colnames(fixture$seu), c("001", "1", "NA", "cell space", "A", "B"))
  expect_identical(names(evidence$matches), names(scAgentKit:::.empty_reference_matches()))
  expect_identical(evidence$provenance$status, "matched")
  expect_false(any(evidence$all_matches$cell_type %in% c("Mouse T", "Liver cell")))
  expect_equal(evidence$provenance$scope$tissue_all_rows, 1L)
  expect_equal(evidence$provenance$duplicate_pair_count, 3L)
  cluster <- reference_evidence_cluster(evidence)
  t_cell <- Filter(function(x) x$label == "T cell", cluster$all_candidates)[[1]]
  myeloid <- Filter(function(x) x$label == "Myeloid", cluster$all_candidates)[[1]]
  expect_equal(t_cell$referenceSize, 2L)
  expect_equal(t_cell$overlap, 2L)
  expect_equal(t_cell$score, 1)
  expect_identical(t_cell$formula, "unique hits / unique reference genes")
  expect_identical(unlist(myeloid$markers), "FCGR3A")
  expect_equal(myeloid$referenceSize, 1L)
  expect_equal(cluster$marker_symbols$duplicate_count, 1L)
  expect_identical(cluster$marker_symbols$alias_resolutions, list(list(original = "CD16", canonical = "FCGR3A")))
  expect_identical(evidence$provenance$license, "unknown")
  expect_false(evidence$provenance$scoring$calibrated_probability)
  case_cluster <- reference_evidence_cluster(evidence, "cell group")
  expect_true(any(vapply(case_cluster$candidates, function(x) x$label == "Case sensitive", logical(1))))
  expect_false(any(vapply(case_cluster$candidates, function(x) x$label == "B cell", logical(1))))
})

test_that("human mouse tissue missing scope and empty references remain distinct", {
  fixture <- reference_evidence_fixture()
  mouse <- reference_evidence_run(fixture, context = list(species = "mouse", tissue = "blood"))
  expect_identical(unique(mouse$all_matches$cell_type), "Mouse T")
  mismatch <- reference_evidence_run(fixture, fixture$reference[fixture$reference$tissue != "all", ],
    context = list(species = "human", tissue = "heart"))
  expect_identical(mismatch$provenance$status, "scope_mismatch")
  expect_equal(nrow(mismatch$matches), 0L)
  unscoped <- fixture$reference; unscoped$species <- NULL
  attr(unscoped, "species") <- "human"
  unavailable <- reference_evidence_run(fixture, unscoped)
  expect_identical(unavailable$provenance$status, "scope_unavailable")
  expect_identical(unavailable$provenance$scope$unavailable_columns, list("species"))
  expect_equal(nrow(unavailable$all_matches), 0L)
  expect_identical(reference_evidence_run(fixture, context = list(tissue = "blood"))$provenance$status,
                   "scope_unavailable")
  empty <- reference_evidence_run(fixture, fixture$reference[FALSE, ])
  expect_identical(empty$provenance$status, "empty_reference")
  expect_identical(reference_evidence_run(fixture, NULL)$provenance$status, "not_supplied")
  expect_true(all(vapply(empty$per_cluster, function(x) length(x$all_candidates) == 0L, logical(1))))
})

test_that("unmeasured and absent top-marker genes never become negative evidence", {
  fixture <- reference_evidence_fixture()
  ref <- data.frame(cell_type = "Unresolved", marker = c("UNMEASURED", "LOW"), species = "human", tissue = "blood")
  evidence <- reference_evidence_run(fixture, ref)
  candidate <- reference_evidence_cluster(evidence)$all_candidates[[1]]
  expect_equal(candidate$score, 0)
  expect_equal(candidate$referenceSize, 2L)
  expect_identical(candidate$unmeasuredGenes, list("UNMEASURED"))
  expect_identical(candidate$notInTopMarkers, list("LOW"))
  joint <- reference_joint_fixture(); joint$local <- evidence
  reviewed <- reference_joint_run(joint)
  expect_identical(reviewed$comparison$status, "missing_information")
  expect_identical(reviewed$counterevidence$status, "not_supplied")
  expect_length(reviewed$counterevidence$records, 0L)
})

test_that("reference provenance includes readable file SHA and actual CM2 attributes", {
  fixture <- reference_evidence_fixture()
  path <- tempfile(fileext = ".csv"); on.exit(unlink(path), add = TRUE)
  utils::write.csv(fixture$reference, path, row.names = FALSE)
  loaded <- annot_load_reference(path)
  attr(loaded, "source_version") <- "CellMarker2.0"
  attr(loaded, "marker_column") <- "Symbol"
  attr(loaded, "source_url") <- "https://example.invalid/pinned-source"
  attr(loaded, "cancer_only") <- FALSE
  evidence <- reference_evidence_run(fixture, loaded, options = list(provenance =
    list(license = "not_established_do_not_redistribute", retrieved_at = "2026-10-04")))
  expect_identical(evidence$provenance$source_sha256, digest::digest(file = path, algo = "sha256"))
  expect_identical(evidence$provenance$source_md5, attr(loaded, "source_md5"))
  expect_identical(evidence$provenance$source_version, "CellMarker2.0")
  expect_identical(evidence$provenance$marker_column, "Symbol")
  expect_false(evidence$provenance$adapter$cancer_only)
  expect_identical(evidence$provenance$license, "not_established_do_not_redistribute")
  expect_identical(evidence$provenance$retrieved_at, "2026-10-04")
  replay <- reference_evidence_run(fixture, loaded, options = list(provenance =
    list(license = "not_established_do_not_redistribute", retrieved_at = "2026-10-04")))
  expect_identical(replay, evidence)
})

test_that("corrupt references and foreign cluster tables fail without mutation", {
  fixture <- reference_evidence_fixture(); before <- digest::digest(fixture, algo = "sha256")
  corrupt <- fixture$reference; corrupt$marker[1] <- NA_character_
  expect_error(reference_evidence_run(fixture, corrupt), "non-empty")
  expect_error(reference_evidence_run(fixture, list()), "data frame")
  corrupt <- fixture$reference; corrupt$species <- seq_len(nrow(corrupt))
  expect_error(reference_evidence_run(fixture, corrupt), "scope columns")
  foreign <- fixture; foreign$table$cluster[1] <- "not a cluster"
  expect_error(reference_evidence_run(foreign), "current cluster IDs")
  expect_identical(digest::digest(fixture, algo = "sha256"), before)
})

test_that("ties survive top-n limits and lower-ranked label support stays visible", {
  fixture <- reference_evidence_fixture()
  ref <- data.frame(cell_type = c("T cell", "T cell", "Universal", "Lower", "Lower"),
    marker = c("G1", "G2", "G1", "G1", "UNMEASURED"), species = "human", tissue = "blood")
  local <- reference_evidence_run(fixture, ref, options = list(top_n = 1))
  cluster <- reference_evidence_cluster(local)
  expect_length(cluster$candidates, 1L)
  expect_equal(sum(vapply(cluster$all_candidates, `[[`, logical(1), "tiedBest")), 2L)
  joint <- reference_joint_fixture("T cell"); joint$local <- local
  out <- reference_joint_run(joint, options = list(top_n = 1))
  expect_identical(out$comparison$status, "missing_information")
  expect_identical(out$comparison$reason, "best_label_tie")
  expect_true(out$comparison$ambiguous)
  mapped <- reference_joint_run(joint, options = list(top_n = 1, label_map = c(Universal = "T cell")))
  expect_identical(mapped$comparison$status, "mapped_name")
  expect_false(mapped$comparison$ambiguous)
  expect_true(mapped$comparison$raw_label_tie)
  joint$row$label <- "Lower"
  own <- Filter(function(x) x$label == "Lower", reference_joint_run(joint)$comparison$related_candidates)[[1]]
  expect_identical(own$status, "exact_label")
  expect_equal(own$score, .5)
})

test_that("naming ancestry and lineage classification require explicit declarations", {
  joint <- reference_joint_fixture(" T CELL ")
  # Keep only one best candidate to isolate naming classification.
  joint$local$per_cluster[[1]]$all_candidates <- Filter(function(x) x$label == "T cell",
    joint$local$per_cluster[[1]]$all_candidates)
  expect_identical(reference_joint_run(joint)$comparison$status, "exact_label")
  joint$row$label <- "T lymphocyte"
  expect_identical(reference_joint_run(joint)$comparison$status, "unresolved_label_difference")
  expect_identical(reference_joint_run(joint, list(label_map = c("T lymphocyte" = "T cell")))$comparison$status,
                   "mapped_name")
  joint$row$label <- "CD4 T cell"
  relations <- data.frame(child = "CD4 T cell", parent = "T cell")
  expect_identical(reference_joint_run(joint, list(label_relations = relations))$comparison$status, "granularity")
  joint$row$label <- "B cell"
  expect_identical(reference_joint_run(joint)$comparison$status, "unresolved_label_difference")
  relations <- data.frame(child = c("T cell", "B cell"), parent = c("T lineage", "B lineage"),
                          lineage = c("T", "B"))
  expect_identical(reference_joint_run(joint, list(label_relations = relations))$comparison$status,
                   "lineage_disagreement")
  relations$lineage[2] <- NA_character_
  expect_identical(reference_joint_run(joint, list(label_relations = relations))$comparison$status,
                   "unresolved_label_difference")
  sibling <- scAgentKit:::.sc_run_joint_label_relation("CD4", "CD8",
    scAgentKit:::.sc_run_reference_options(list(label_relations =
      data.frame(child = c("CD4", "CD8"), parent = "T", lineage = "T"))))
  expect_identical(sibling$status, "unresolved_label_difference")
})

test_that("joint evidence preserves supplied stats and only explicit counterevidence", {
  joint <- reference_joint_fixture()
  joint$row$markers <- list("G1", "NOT_SUPPLIED")
  joint$supplied$counterevidence <- list(list(gene = "G2", source = "analyst supplied assessment",
    finding = "Explicit recorded evidence; not inferred from missing markers."))
  joint$source$configured_provider <- list(name = "mock", model = "offline", api_key = "fake secret")
  out <- reference_joint_run(joint)
  expect_identical(out$current$citations[[1]]$statistics, joint$supplied$markers[[1]])
  expect_identical(out$current$citations[[2]]$status, "unavailable")
  expect_null(out$current$citations[[2]]$statistics)
  expect_identical(out$counterevidence$records, joint$supplied$counterevidence)
  expect_false("api_key" %in% names(out$current$source$configured_provider))
  expect_null(out$dependency$dependent_on_database)
  expect_identical(out$dependency$actual_mode, "not_dispatched")
  guided <- reference_joint_run(joint, list(ai_mode = "guided"))
  expect_null(guided$dependency$dependent_on_database)
  expect_identical(guided$dependency$mode, "guided")
  joint$source$reference_dependency <- "guided"
  actual <- reference_joint_run(joint, list(ai_mode = "guided"))
  expect_true(actual$dependency$dependent_on_database)
  expect_false(identical(scAgentKit:::.sc_run_hash(out), scAgentKit:::.sc_run_hash(guided)))
  joint$row$label <- "Unknown"; joint$row$markers <- list()
  expect_identical(reference_joint_run(joint)$comparison$status, "missing_information")
  expect_length(reference_joint_run(joint)$current$citations, 0L)
  joint$supplied$clusterId <- "different"
  expect_error(reference_joint_run(joint), "cluster binding")
})

test_that("historical imports are visible and comparison requires verified scope", {
  joint <- reference_joint_fixture("Unknown", list())
  history_row <- joint$row; history_row$label <- "T cell"; history_row$markers <- list("OLD_MARKER")
  historical <- list(annotations = list(history_row), provenance = list(kind = "historical_model_response",
    provider = "grok", model = "recorded model", response_sha256 = paste(rep("a", 64), collapse = ""),
    source_object_sha256 = paste(rep("b", 64), collapse = ""), scope_status = "unverified",
    reference_dependency = "unknown", declaration = "caller_import_not_new_request"))
  out <- reference_joint_run(joint, historical = historical)
  expect_identical(out$historical$status, "supplied")
  expect_false(out$historical$eligible_for_comparison)
  expect_identical(out$comparison$source, "current_proposal")
  expect_identical(out$historical$row$citations[[1]]$status, "unavailable")
  expect_null(out$historical$row$citations[[1]]$statistics)
  historical$provenance$scope_status <- "verified"
  verified <- reference_joint_run(joint, historical = historical)
  expect_true(verified$historical$eligible_for_comparison)
  expect_identical(verified$comparison$source, "historical_model_response")
  expect_false(identical(scAgentKit:::.sc_run_hash(out), scAgentKit:::.sc_run_hash(verified)))
  historical$provenance$scope_status <- "mismatch"
  expect_false(reference_joint_run(joint, historical = historical)$historical$eligible_for_comparison)
  historical$annotations <- rep(historical$annotations, 2)
  expect_error(reference_joint_run(joint, historical = historical), "Duplicate historical")
  single <- list(row = history_row, source = list(kind = "model"), provenance = historical$provenance)
  single$provenance$scope_status <- "verified"
  expect_true(reference_joint_run(joint, historical = single)$historical$eligible_for_comparison)
  single$row <- NULL
  expect_identical(reference_joint_run(joint, historical = single)$historical$status, "cluster_not_supplied")
})
