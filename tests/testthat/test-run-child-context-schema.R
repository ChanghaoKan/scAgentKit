# Aggregate-schema unit inputs only: these do not create a saved run or claim
# a fabricated parent approval. Real approved-parent creation is tested in the
# separate fresh child-context integration suite.
child_context_schema_snapshot <- function() {
  hash <- scAgentKit:::.sc_run_hash("aggregate unit control")
  list(schema = "scagentkit.child-parent-context.v1",
    source = list(project_id = "unit-parent", revision = 0L, input_hash = hash,
      output_hash = hash, scope_hash = hash, review_hash = NULL, decision_id = NULL,
      source_kind = "not_recorded",
      annotation_column = NULL, scientific_result = NULL),
    species = "human", tissue = "synthetic", scope = list(list(parentClusterId = "01", cellCount = 40L)),
    annotations = list(list(parentClusterId = "01", cellCount = 40L,
      labels = list(), review_status = "unreviewed", identity_status = "unreviewed", confidence = NULL)),
    identity_status = "unreviewed")
}
child_context_schema_fixture <- function() {
  counts <- Matrix::Matrix(matrix(rep(c(2, 0, 5, 1), 80), nrow = 8,
    dimnames = list(paste0("ContextGene", 1:8), paste0("privateCell", 1:40))), sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts)
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- log1p(counts)
  object$seurat_clusters <- rep(c("01", "NA"), each = 20L)
  object$private_metadata <- "PRIVATE_METADATA_SENTINEL"
  markers <- data.frame(cluster = rep(c("01", "NA"), each = 2L),
    gene = c("ContextGene1", "ContextGene2", "ContextGene3", "ContextGene4"),
    avg_log2FC = c(2, 3, 4, 5), pct.1 = .8, pct.2 = .2, p_val_adj = .001)
  reference <- data.frame(cell_type = c("ParentCell", "OtherLineage", "ParentCell", "OtherLineage"),
    marker = c("ContextGene1", "ContextGene2", "ContextGene3", "ContextGene4"),
    species = "human", tissue = "synthetic")
  list(object = object, markers = markers, reference = reference,
    context = list(species = "human", tissue = "synthetic"))
}

test_that("child context has strict bounded editable fields and monotonic identity", {
  initial <- scAgentKit:::.sc_run_child_context_initial(child_context_schema_snapshot())
  expect_identical(initial$generation, 0L)
  expect_identical(initial$effective$identity_status, "unreviewed")
  first <- scAgentKit:::.sc_run_child_context_patch(initial,
    list(lineage_hint = "ParentCell", identity_status = "labeled"))
  second <- scAgentKit:::.sc_run_child_context_patch(first, list(lineage_hint = "OtherLineage"))
  restored <- scAgentKit:::.sc_run_child_context_patch(second, list(lineage_hint = "ParentCell"))
  expect_identical(first$effective, restored$effective)
  expect_identical(restored$generation, 3L)
  expect_false(identical(first$hash, restored$hash))
  expect_identical(restored$previous_hash, second$hash)
  expect_identical(initial$parent_snapshot, restored$parent_snapshot)
  expect_error(scAgentKit:::.sc_run_child_context_patch(initial, list(parent_snapshot = list())), "Unsupported")
  expect_error(scAgentKit:::.sc_run_child_context_patch(initial, list(species = "mouse")), "Unsupported")
  expect_error(scAgentKit:::.sc_run_child_context_patch(initial, list(enabled = NA)), "TRUE or FALSE")
  expect_error(scAgentKit:::.sc_run_child_context_patch(initial, list(lineage_hint = "")), "nonempty|non-empty")
  expect_error(scAgentKit:::.sc_run_child_context_patch(initial, list(lineage_hint = paste(rep("x", 201), collapse = ""))), "bounded")
  expect_error(scAgentKit:::.sc_run_child_context_patch(initial, list(identity_status = "labeled")), "lineage_hint")
  expect_error(scAgentKit:::.sc_run_child_context_patch(initial, list(identity_status = "certain")), "identity_status")
  tampered <- first; tampered$effective$lineage_hint <- "Changed"
  expect_error(scAgentKit:::.sc_run_child_context_public(tampered), "fingerprint")
  corrupted <- child_context_schema_snapshot(); corrupted$source$local_path <- "/private/project"
  expect_error(scAgentKit:::.sc_run_child_context_initial(corrupted), "unsupported")
  cleared <- scAgentKit:::.sc_run_child_context_patch(first,
    list(lineage_hint = NULL, identity_status = "unknown", tissue = NULL, notes = NULL))
  expect_null(cleared$effective$lineage_hint)
  expect_null(cleared$effective$tissue)
  expect_identical(names(cleared$effective), names(initial$effective))
})

test_that("parent context leaves independent DB scoring and marker evidence unchanged", {
  fixture <- child_context_schema_fixture(); original <- fixture$object
  initial <- scAgentKit:::.sc_run_child_context_initial(child_context_schema_snapshot())
  hint <- scAgentKit:::.sc_run_child_context_patch(initial,
    list(lineage_hint = "ParentCell", identity_status = "labeled"))
  options <- list(label_relations = data.frame(child = c("ParentCell", "OtherLineage"),
    parent = c("Lineage A", "Lineage B"), lineage = c("A", "B")))
  base <- scAgentKit:::.sc_run_annotation_evidence(fixture$object, fixture$markers,
    fixture$context, fixture$reference, reference_review = options)
  scoped <- scAgentKit:::.sc_run_annotation_evidence(fixture$object, fixture$markers,
    fixture$context, fixture$reference, reference_review = options, annotation_context = hint)
  expect_identical(fixture$object, original)
  expect_identical(scoped$summary$clusters, base$summary$clusters)
  expect_identical(scoped$private$candidates, base$private$candidates)
  expect_identical(scoped$private$candidates_all, base$private$candidates_all)
  expect_identical(scoped$private$reference_evidence, base$private$reference_evidence)
  expect_identical(scoped$summary$child_context$hash, hint$hash)
  candidate <- scoped$private$child_context$database_assessments[[1]]$candidates
  foreign <- Filter(function(row) row$label == "OtherLineage", candidate)[[1]]
  expect_identical(foreign$assessment$status, "explicit_cross_lineage_warning")
  expect_false(foreign$assessment$blocking)
  proposal <- list(schema = "scagentkit.annotation.v1", annotations = lapply(scoped$summary$clusters,
    function(row) list(clusterId = row$clusterId, label = "OtherLineage", confidence = "medium",
      rationale = "A current supplied marker overrides the soft context in this schema control.",
      markers = list(row$markers[[1]]$gene))))
  expect_s3_class(scAgentKit:::.sc_run_annotation_response_validate(proposal, scoped), "sc_run_annotation_proposal")
  unmapped <- scAgentKit:::.sc_run_child_context_assessment("OtherLineage", hint)
  expect_identical(unmapped$status, "unresolved_parent_label_difference")
  expect_false(unmapped$blocking)
  disabled <- scAgentKit:::.sc_run_child_context_patch(hint, list(enabled = FALSE))
  expect_identical(scAgentKit:::.sc_run_child_context_assessment("OtherLineage", disabled)$status,
    "no_resolved_parent_expectation")
})

test_that("child aggregate request discloses soft context and does not serialize private IDs", {
  fixture <- child_context_schema_fixture()
  value <- scAgentKit:::.sc_run_child_context_initial(child_context_schema_snapshot())
  first <- scAgentKit:::.sc_run_child_context_patch(value,
    list(lineage_hint = "ParentCell", identity_status = "labeled"))
  second <- scAgentKit:::.sc_run_child_context_patch(first, list(lineage_hint = "OtherLineage"))
  third <- scAgentKit:::.sc_run_child_context_patch(second, list(lineage_hint = "ParentCell"))
  request <- function(context) {
    evidence <- scAgentKit:::.sc_run_annotation_evidence(fixture$object, fixture$markers,
      fixture$context, fixture$reference, annotation_context = context)
    scAgentKit:::.sc_run_request("annotation", evidence$summary, list(context = fixture$context))
  }
  one <- request(first); restored <- request(third)
  provider <- list(name = "mock", external = FALSE)
  expect_false(identical(scAgentKit:::.sc_run_request_hash(one, provider),
                        scAgentKit:::.sc_run_request_hash(restored, provider)))
  expect_match(one$system_prompt, "soft context|soft hypotheses")
  expect_match(one$system_prompt, "not.*whitelist|never.*whitelist")
  expect_match(one$system_prompt, "evidence may override")
  expect_match(one$system_prompt, "not absent or low expression")
  payload <- jsonlite::fromJSON(one$user_prompt, simplifyVector = FALSE)
  expect_identical(payload$evidence$child_context$generation, 1L)
  for (private in c("privateCell", "PRIVATE_METADATA_SENTINEL", "cell_id", "reviewer", "/private/project"))
    expect_false(grepl(private, one$user_prompt, fixed = TRUE))
  changed_tissue <- scAgentKit:::.sc_run_child_context_patch(first, list(tissue = "corrected tissue"))
  corrected <- request(changed_tissue)
  expect_identical(jsonlite::fromJSON(corrected$user_prompt, simplifyVector = FALSE)$context$tissue,
                   "corrected tissue")
  expect_identical(fixture$context$tissue, "synthetic")
})
