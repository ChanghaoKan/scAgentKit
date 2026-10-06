review_fixture <- function() {
  counts <- matrix(c(2,0,1,4,0,3,2,0,3,1,0,2,1,0,4,2), nrow = 4,
    dimnames = list(paste0("GENE", 1:4), c("001", "1", "cell x", "cell-y")))
  seu <- Seurat::CreateSeuratObject(Matrix::Matrix(counts, sparse = TRUE))
  seu$seurat_clusters <- c("NA", "001", "1", "NA")
  seu$original <- factor(c("alpha", NA, "beta", "alpha"), levels = c("unused", "beta", "alpha"))
  SeuratObject::Idents(seu) <- factor(c("a", "b", "c", "a"), levels = c("c", "b", "a", "unused"))
  root <- tempfile("project-review-"); dir.create(root)
  project <- file.path(root, "bundle")
  sc_project_export(seu, project, "test project", normalized_layer = NULL, reduction = NULL)
  manifest <- jsonlite::fromJSON(file.path(project, "manifest.json"), simplifyVector = FALSE)
  journal <- list(schema = "scagentkit.review-journal.v1", projectId = manifest$projectId,
    sourceFingerprint = manifest$sourceFingerprint, bundleDigest = manifest$bundleDigest,
    events = list(), artifacts = structure(list(), names = character()))
  list(seu = seu, project = project, journal = journal, path = file.path(root, "review.json"), root = root)
}
review_write <- function(fixture, journal = fixture$journal) {
  writeLines(jsonlite::toJSON(journal, auto_unbox = TRUE, null = "null", digits = NA), fixture$path, useBytes = TRUE)
  fixture$path
}
review_event <- function(fixture, cluster = "NA", label = "my label", status = "accepted", dimension = "type", reason = "local evidence reviewed") {
  i <- length(fixture$journal$events) + 1L
  previous <- NULL
  # Test fixtures use this helper for straightforward decision sequences.
  for (envelope in fixture$journal$events) {
    event <- jsonlite::fromJSON(envelope$payload, simplifyVector = FALSE)
    if (identical(event$kind, "decision") && identical(event$scope$clusterId, cluster) && identical(event$scope$dimension, dimension)) previous <- event$id
  }
  cells <- colnames(fixture$seu)[as.character(fixture$seu$seurat_clusters) == cluster]
  list(id = paste0("event-", i), sequence = i, kind = "decision", createdAt = "2026-10-03T12:00:00Z",
    requestId = paste0("request-", i), requestDigest = paste(rep("a", 64), collapse = ""), reason = reason,
    scope = list(datasetId = fixture$journal$projectId, revision = fixture$journal$bundleDigest,
      sourceFingerprint = fixture$journal$sourceFingerprint, clusterId = cluster, dimension = dimension,
      cellIds = as.list(cells)), label = label, status = status, supersedes = previous)
}
review_append <- function(fixture, event) {
  payload <- as.character(jsonlite::toJSON(event, auto_unbox = TRUE, null = "null", digits = NA))
  previous <- if (length(fixture$journal$events)) tail(fixture$journal$events, 1)[[1]]$hash else paste(rep("0", 64), collapse = "")
  fixture$journal$events <- append(fixture$journal$events, list(list(sequence = length(fixture$journal$events) + 1L,
    payload = payload, prevHash = previous, hash = .sc_review_text_sha(paste0(previous, "\n", payload)))))
  fixture
}
review_undo <- function(fixture, target, cluster = "NA", dimension = "type") {
  event <- review_event(fixture, cluster, dimension = dimension)
  event$kind <- "undo"; event$label <- event$status <- event$supersedes <- NULL
  event$targetEventId <- target
  review_append(fixture, event)
}
review_expect_invalid <- function(fixture, object = fixture$seu, code = NULL, journal = fixture$journal, columns = c(type = "review_type")) {
  path <- review_write(fixture, journal)
  report <- sc_review_validate(object, path, fixture$project, columns)
  expect_false(report$valid, info = paste(report$errors$message, collapse = "; "))
  if (!is.null(code)) expect_equal(report$errors$code, code)
  expect_error(sc_review_apply(object, path, fixture$project, columns), "refused")
  invisible(report)
}

test_that("review adds ID-aligned columns and preserves the original object", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  before <- f$seu
  f <- review_append(f, review_event(f, "NA", "unknown"))
  f <- review_append(f, review_event(f, "001", "custom <script> label"))
  f <- review_append(f, review_event(f, "1", "pending", "reviewed"))
  path <- review_write(f); report <- sc_review_validate(f$seu, path, f$project)
  expect_true(report$valid, info = paste(report$errors$message, collapse = "; "))
  expect_equal(report$coverage$cells, c(1L, 2L, 1L, 0L))
  out <- sc_review_apply(f$seu, path, f$project)
  expect_identical(f$seu, before)
  expect_identical(out@meta.data[, colnames(before@meta.data), drop = FALSE], before@meta.data)
  expect_identical(SeuratObject::Idents(out), SeuratObject::Idents(before))
  expect_identical(out@assays, before@assays); expect_identical(out@reductions, before@reductions)
  expect_identical(unname(out$review_type), c("unknown", "custom <script> label", NA_character_, "unknown"))
  expect_identical(unname(out$review_type_review_state), c("abstained", "labeled", "deferred", "abstained"))
  expect_identical(levels(out$original), levels(before$original))
})

test_that("partial review and undo distinguish all workflow states", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  f <- review_append(f, review_event(f, "NA", "first"))
  f <- review_append(f, review_event(f, "NA", "second", "proposed"))
  out <- sc_review_apply(f$seu, review_write(f), f$project)
  expect_true(all(is.na(out$review_type)))
  expect_identical(unname(out$review_type_review_state), c("deferred", "unreviewed", "unreviewed", "deferred"))
  f <- review_undo(f, "event-2")
  out <- sc_review_apply(f$seu, review_write(f), f$project)
  expect_identical(unname(out$review_type), c("first", NA_character_, NA_character_, "first"))
  f <- review_undo(f, "event-1")
  out <- sc_review_apply(f$seu, review_write(f), f$project)
  expect_true(all(out$review_type_review_state == "unreviewed"))
  f <- review_undo(f, "event-1")
  review_expect_invalid(f, code = "undo_conflict")
})

test_that("cell and gene reordering and unrelated metadata do not stale identity", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  f <- review_append(f, review_event(f, "001", "accepted")); path <- review_write(f)
  counts <- SeuratObject::LayerData(f$seu, assay = "RNA", layer = "counts")
  reordered <- Seurat::CreateSeuratObject(counts[rev(rownames(counts)), rev(colnames(counts)), drop = FALSE])
  reordered@meta.data <- f$seu@meta.data[colnames(reordered), , drop = FALSE]
  expect_identical(colnames(reordered), rev(colnames(f$seu)))
  expect_identical(rownames(reordered), rev(rownames(f$seu)))
  reordered$irrelevant <- seq_len(ncol(reordered))
  report <- sc_review_validate(reordered, path, f$project)
  expect_true(report$valid, info = paste(report$errors$message, collapse = "; "))
  out <- sc_review_apply(reordered, path, f$project)
  expect_identical(colnames(out), rev(colnames(f$seu)))
  expect_identical(unname(out$review_type[match("1", colnames(out))]), "accepted")
  expect_identical(out$irrelevant, reordered$irrelevant)
})

test_that("same barcodes with changed expression, membership or features are refused", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  changed <- f$seu; counts <- SeuratObject::LayerData(changed, assay = "RNA", layer = "counts"); counts[1,1] <- counts[1,1] + 1
  SeuratObject::LayerData(changed, assay = "RNA", layer = "counts") <- counts
  review_expect_invalid(f, changed, "source_mismatch")
  changed <- f$seu; changed$seurat_clusters[1] <- "001"
  review_expect_invalid(f, changed, "source_mismatch")
  review_expect_invalid(f, f$seu[-1, ], "source_mismatch")
  review_expect_invalid(f, f$seu[, -1], "source_mismatch")
})

test_that("normalized values are checked and the default assay cannot redirect review", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  f$seu <- Seurat::NormalizeData(f$seu, verbose = FALSE)
  unlink(f$project, recursive = TRUE)
  sc_project_export(f$seu, f$project, "test project", reduction = NULL)
  manifest <- jsonlite::fromJSON(file.path(f$project, "manifest.json"), simplifyVector = FALSE)
  f$journal$sourceFingerprint <- manifest$sourceFingerprint; f$journal$bundleDigest <- manifest$bundleDigest
  expect_true(sc_review_validate(f$seu, review_write(f), f$project)$valid)
  changed <- f$seu; data <- SeuratObject::LayerData(changed, assay = "RNA", layer = "data"); data[1,1] <- data[1,1] + 0.1
  SeuratObject::LayerData(changed, assay = "RNA", layer = "data") <- data
  review_expect_invalid(f, changed, "source_mismatch")
  changed <- f$seu; changed[["other"]] <- SeuratObject::CreateAssay5Object(counts = SeuratObject::LayerData(changed, assay = "RNA", layer = "counts"))
  SeuratObject::DefaultAssay(changed) <- "other"
  expect_true(sc_review_validate(changed, review_write(f), f$project)$valid)
})

test_that("actual missing membership and invalid inputs fail without mutation", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  changed <- f$seu; changed$seurat_clusters[1] <- NA_character_
  review_expect_invalid(f, changed)
  expect_false(sc_review_validate(NULL, f$path, f$project)$valid)
  expect_false(sc_review_validate(f$seu, "missing.json", f$project)$valid)
  expect_false(sc_review_validate(f$seu, review_write(f), paste0(f$project, ".zip"))$valid)
})

test_that("every new column is checked atomically and dimensions stay separate", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  f <- review_append(f, review_event(f, "NA", "cycling", "accepted", "state"))
  out <- sc_review_apply(f$seu, review_write(f), f$project, c(type = "new_type", state = "new_state", QC = "new_qc"))
  expect_true(all(out$new_type_review_state == "unreviewed"))
  expect_identical(unname(out$new_state), c("cycling", NA_character_, NA_character_, "cycling"))
  changed <- f$seu; changed$review_type_bundle_digest <- "occupied"; before <- changed
  review_expect_invalid(f, changed, "column_collision")
  expect_identical(changed, before)
  review_expect_invalid(f, columns = c(type = "same", state = "same_review_state"), code = "column_collision")
  review_expect_invalid(f, columns = c(bogus = "new"), code = "invalid_columns")
})

test_that("malformed scope, history, statuses and old schemas are rejected", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  event <- review_event(f); event$scope$cellIds <- list("001")
  review_expect_invalid(review_append(f, event), code = "scope_mismatch")
  event <- review_event(f); event$scope$cellIds <- list("001", "001")
  review_expect_invalid(review_append(f, event), code = "invalid_ids")
  event <- review_event(f); event$status <- "true"
  review_expect_invalid(review_append(f, event), code = "event_status")
  event <- review_event(f); event$supersedes <- "future"
  review_expect_invalid(review_append(f, event), code = "history_conflict")
  valid <- review_append(f, review_event(f)); valid$journal$events[[1]]$payload <- paste0(valid$journal$events[[1]]$payload, " ")
  review_expect_invalid(valid, code = "history_chain")
  old <- f$journal; old$schema <- "scagentkit.handoff.v2"
  review_expect_invalid(f, journal = old, code = "unsupported_schema")
  other <- f$journal; other$sourceFingerprint <- paste(rep("b", 64), collapse = "")
  review_expect_invalid(f, journal = other, code = "journal_identity")
})

test_that("strict JSON rejects duplicate decoded keys, array confusion and bad artifacts", {
  expect_error(.sc_review_json('{"a":1,"\\u0061":2}'), "Duplicate")
  expect_error(.sc_review_json('{"sequence":1.0}', integer_sequence = TRUE), "JSON integer")
  expect_error(.sc_review_json('{"sequence":1e0}', integer_sequence = TRUE), "JSON integer")
  expect_error(.sc_review_json('{"é":1,"\\u00e9":2}'), "Duplicate")
  expect_identical(.sc_review_json('{"标签":"细胞 α","ids":["001","NA"]}')$标签, "细胞 α")
  expect_error(.sc_review_json('[NaN]'), "Invalid")
  expect_error(.sc_review_json('{"x":01}'), "Invalid")
  expect_error(.sc_review_json('{"x":1,}'), "Invalid")
  expect_error(.sc_review_json('["bad\nstring"]'), "Invalid")
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  journal <- f$journal; journal$events <- structure(list(), names = character())
  review_expect_invalid(f, journal = journal, code = "invalid_structure")
  journal <- f$journal; journal$artifacts <- list(evidence = list(payload = '{}', sha256 = paste(rep("c", 64), collapse = "")))
  review_expect_invalid(f, journal = journal, code = "artifact_checksum")
  event <- review_event(f); event$evidenceRefs <- list("missing")
  review_expect_invalid(review_append(f, event), code = "missing_artifact")
})

test_that("artifact scopes, sorted IDs and timestamps match the generic store contract", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  event <- review_event(f); event$scope$cellIds <- rev(event$scope$cellIds)
  review_expect_invalid(review_append(f, event), code = "invalid_ids")
  event <- review_event(f); event$createdAt <- "2026-02-30T12:00:00Z"
  review_expect_invalid(review_append(f, event), code = "invalid_timestamp")
  event <- review_event(f); event$createdAt <- "2026-10-03"
  review_expect_invalid(review_append(f, event), code = "invalid_timestamp")
  event <- review_event(f); event$requestDigest <- "not a sha"
  review_expect_invalid(review_append(f, event), code = "invalid_hash")
  payload <- '{"scope":{"clusterId":"001"}}'
  f$journal$artifacts <- list(evidence = list(payload = payload, sha256 = .sc_review_text_sha(payload)))
  event <- review_event(f); event$evidenceRefs <- list("evidence")
  review_expect_invalid(review_append(f, event), code = "artifact_scope")
  payload <- '{"scope":{"clusterId":"NA"},"provisional":{"scope":{"clusterId":"001"}}}'
  f$journal$artifacts$evidence <- list(payload = payload, sha256 = .sc_review_text_sha(payload))
  review_expect_invalid(review_append(f, event), code = "artifact_scope")
  payload <- '{"scope":{"clusterId":"NA","dimension":"type"}}'
  f$journal$artifacts$evidence <- list(payload = payload, sha256 = .sc_review_text_sha(payload))
  f <- review_append(f, event)
  expect_true(sc_review_validate(f$seu, review_write(f), f$project)$valid)
})

test_that("project checksums, symlinks and unlisted files fail closed", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  writeLines("extra", file.path(f$project, "unlisted.txt"))
  review_expect_invalid(f, code = "unlisted_asset")
  unlink(file.path(f$project, "unlisted.txt"))
  asset <- file.path(f$project, "project.json"); original <- readBin(asset, "raw", file.info(asset)$size)
  con <- file(asset, "ab"); writeBin(charToRaw(" "), con); close(con)
  review_expect_invalid(f, code = "asset_checksum")
  con <- file(asset, "wb"); writeBin(original, con); close(con)
  if (.Platform$OS.type == "unix") {
    file.symlink(asset, file.path(f$project, "link.json"))
    review_expect_invalid(f, code = "unsafe_project")
  }
})

test_that("declared directed expression also requires the exact source and cell scope", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  f$seu <- Seurat::NormalizeData(f$seu, verbose = FALSE)
  f$project <- file.path(f$root, "directed bundle")
  sc_project_export(f$seu, f$project, "test project", reduction = NULL, directed_clusters = "NA")
  manifest <- jsonlite::fromJSON(file.path(f$project, "manifest.json"), simplifyVector = FALSE)
  f$journal$sourceFingerprint <- manifest$sourceFingerprint; f$journal$bundleDigest <- manifest$bundleDigest
  expect_true(sc_review_validate(f$seu, review_write(f), f$project)$valid)
  project_path <- file.path(f$project, "project.json")
  project <- jsonlite::fromJSON(project_path, simplifyVector = FALSE)
  asset_path <- file.path(f$project, project$directed$clusters[["NA"]]$path)
  asset <- jsonlite::fromJSON(asset_path, simplifyVector = FALSE); asset$scope$cluster_id <- "001"
  writeLines(.sc_project_json(asset), asset_path, useBytes = TRUE)
  asset_hash <- .sc_project_sha_file(asset_path); project$directed$clusters[["NA"]]$sha256 <- asset_hash
  writeLines(.sc_project_json(project), project_path, useBytes = TRUE)
  for (i in seq_along(manifest$files)) {
    path <- file.path(f$project, manifest$files[[i]]$path)
    manifest$files[[i]]$sha256 <- .sc_project_sha_file(path); manifest$files[[i]]$bytes <- file.info(path)$size
  }
  manifest$bundleDigest <- .sc_project_sha_file(project_path)
  writeLines(.sc_project_json(manifest), file.path(f$project, "manifest.json"), useBytes = TRUE)
  f$journal$bundleDigest <- manifest$bundleDigest
  review_expect_invalid(f, code = "scope_mismatch")
})

test_that("AgentSeurat wrapping a single object keeps all wrapper history", {
  f <- review_fixture(); on.exit(unlink(f$root, recursive = TRUE))
  f <- review_append(f, review_event(f, "NA", "my label")); wrapper <- AgentSeurat(f$seu, initial_script = "original load")
  before <- wrapper; out <- sc_review_apply(wrapper, review_write(f), f$project)
  expect_s4_class(out, "AgentSeurat"); expect_identical(wrapper, before)
  for (slot in setdiff(methods::slotNames(wrapper), "data")) expect_identical(methods::slot(out, slot), methods::slot(wrapper, slot))
  expect_identical(unname(out@data$review_type), c("my label", NA_character_, NA_character_, "my label"))
  wrapper <- AgentSeurat(list(single = f$seu)); before <- wrapper
  out <- sc_review_apply(wrapper, review_write(f), f$project)
  expect_identical(names(out@data), "single"); expect_identical(wrapper, before)
  expect_identical(unname(out@data[[1]]$review_type), c("my label", NA_character_, NA_character_, "my label"))
})
