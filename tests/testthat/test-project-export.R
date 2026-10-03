project_export_fixture <- function(embedding = TRUE) {
  counts <- Matrix::Matrix(
    matrix(c(2, 0, 1, 3, 0, 0, 2, 1, 1, 0, 0, 2, 3, 0, 1, 0),
           nrow = 4,
           dimnames = list(c("CD3D", "CD3E", "KLRD1", "Other gene"),
                           c("001", "1", "NA", "cell space"))),
    sparse = TRUE
  )
  object <- Seurat::CreateSeuratObject(counts = counts, assay = "RNA")
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- log1p(counts)
  object$seurat_clusters <- c("T alpha", "T alpha", "NA", "01")
  object$percent.mt <- c(0, 1, 2, 3)
  object$private_note <- rep("must not be exported", 4)
  object$source_label <- factor(c("T", "T", "unknown", NA_character_),
                                levels = c("T", "unknown", "unused"))
  if (embedding) {
    coordinates <- matrix(c(0, 1, 2, 3, 4, 5, 6, 7), ncol = 2,
                          dimnames = list(colnames(object), c("UMAP_1", "UMAP_2")))
    object[["umap"]] <- SeuratObject::CreateDimReducObject(
      embeddings = coordinates, key = "UMAP_", assay = "RNA"
    )
  }
  object
}

project_export_identity <- function(object, ...) {
  scAgentKit:::.sc_project_identity(
    object, assay = "RNA", counts_layer = "counts",
    normalized_layer = "data", cluster_column = "seurat_clusters", ...
  )
}

project_export_json <- function(path, name = "project.json") {
  jsonlite::fromJSON(file.path(path, name), simplifyVector = FALSE)
}

project_export_text <- function(path, name = "project.json") {
  paste(readLines(file.path(path, name), warn = FALSE), collapse = "\n")
}

test_that("source identity is canonical across object order and sparse forms", {
  object <- project_export_fixture()
  original <- project_export_identity(object)
  hashes <- c("fingerprint", "cellsHash", "featuresHash", "membershipHash",
              "countsHash", "dataHash")
  expect_true(all(vapply(original[hashes], function(x) {
    is.character(x) && length(x) == 1L && grepl("^[a-f0-9]{64}$", x)
  }, logical(1))))
  expect_identical(original$algorithm, "scagentkit.source.v1")
  expect_equal(original$cellCount, ncol(object))
  expect_equal(original$featureCount, nrow(object))
  expect_identical(original$assay, "RNA")
  expect_identical(original$countsLayer, "counts")
  expect_identical(original$normalizedLayer, "data")
  expect_identical(original$clusterColumn, "seurat_clusters")

  reordered <- object[rev(rownames(object)), rev(colnames(object))]
  reordered$private_note <- "changed irrelevant metadata"
  expect_identical(project_export_identity(reordered)[hashes], original[hashes])

  equivalent <- object
  equivalent[["RNA"]]@layers$counts <- methods::as(
    equivalent[["RNA"]]@layers$counts, "TsparseMatrix"
  )
  equivalent[["RNA"]]@layers$data <- as.matrix(equivalent[["RNA"]]@layers$data)
  expect_true(methods::validObject(equivalent))
  expect_identical(project_export_identity(equivalent)[hashes], original[hashes])
  row_sparse <- object
  row_sparse[["RNA"]]@layers$counts <- methods::as(row_sparse[["RNA"]]@layers$counts, "RsparseMatrix")
  expect_identical(project_export_identity(row_sparse)[hashes], original[hashes])
  old_assay <- object
  suppressWarnings(old_assay[["RNA"]] <- SeuratObject::CreateAssayObject(
    counts = SeuratObject::LayerData(object, assay = "RNA", layer = "counts")
  ))
  SeuratObject::LayerData(old_assay, assay = "RNA", layer = "data") <- SeuratObject::LayerData(object, assay = "RNA", layer = "data")
  expect_identical(project_export_identity(old_assay)[hashes], original[hashes])

  with_zero <- object
  matrix <- with_zero[["RNA"]]@layers$counts
  positions <- Matrix::summary(matrix)
  with_zero[["RNA"]]@layers$counts <- Matrix::sparseMatrix(
    i = c(positions$i, 2L), j = c(positions$j, 1L),
    x = c(positions$x, 0), dims = dim(matrix), dimnames = dimnames(matrix)
  )
  expect_true(any(with_zero[["RNA"]]@layers$counts@x == 0))
  expect_identical(project_export_identity(with_zero)[hashes], original[hashes])

  wrapped <- AgentSeurat(object)
  expect_identical(project_export_identity(wrapped)[hashes], original[hashes])
})

test_that("expression values, feature IDs and membership enter source identity", {
  object <- project_export_fixture()
  original <- project_export_identity(object)
  counts_changed <- object
  counts_changed[["RNA"]]@layers$counts@x[1] <-
    counts_changed[["RNA"]]@layers$counts@x[1] + 1
  counts_identity <- project_export_identity(counts_changed)
  expect_false(identical(counts_identity$fingerprint, original$fingerprint))
  expect_false(identical(counts_identity$countsHash, original$countsHash))
  expect_identical(counts_identity$dataHash, original$dataHash)

  data_changed <- object
  data_changed[["RNA"]]@layers$data@x[1] <-
    data_changed[["RNA"]]@layers$data@x[1] + 0.125
  data_identity <- project_export_identity(data_changed)
  expect_false(identical(data_identity$fingerprint, original$fingerprint))
  expect_false(identical(data_identity$dataHash, original$dataHash))
  expect_identical(data_identity$countsHash, original$countsHash)

  membership_changed <- object
  membership_changed$seurat_clusters[1] <- "other cluster"
  membership_identity <- project_export_identity(membership_changed)
  expect_false(identical(membership_identity$fingerprint, original$fingerprint))
  expect_false(identical(membership_identity$membershipHash, original$membershipHash))
  expect_identical(membership_identity$countsHash, original$countsHash)

  renamed_counts <- SeuratObject::LayerData(object, assay = "RNA", layer = "counts")
  renamed_data <- SeuratObject::LayerData(object, assay = "RNA", layer = "data")
  rownames(renamed_counts)[4] <- rownames(renamed_data)[4] <- "Different gene"
  features_changed <- Seurat::CreateSeuratObject(counts = renamed_counts)
  SeuratObject::LayerData(features_changed, assay = "RNA", layer = "data") <- renamed_data
  features_changed$seurat_clusters <- object$seurat_clusters
  expect_false(identical(project_export_identity(features_changed)$fingerprint,
                         original$fingerprint))
})

test_that("identity records the explicitly selected assay, layers and membership column", {
  object <- project_export_fixture()
  original <- project_export_identity(object)
  object$alternate_clusters <- object$seurat_clusters
  SeuratObject::LayerData(object, assay = "RNA", layer = "rawCounts") <-
    SeuratObject::LayerData(object, assay = "RNA", layer = "counts")
  expect_identical(project_export_identity(object)$fingerprint, original$fingerprint)
  selected_layer <- scAgentKit:::.sc_project_identity(
    object, "RNA", "rawCounts", "data", "seurat_clusters"
  )
  selected_column <- scAgentKit:::.sc_project_identity(
    object, "RNA", "counts", "data", "alternate_clusters"
  )
  counts_only <- scAgentKit:::.sc_project_identity(
    object, "RNA", "counts", NULL, "seurat_clusters"
  )
  expect_identical(selected_layer$countsHash, original$countsHash)
  expect_false(identical(selected_layer$fingerprint, original$fingerprint))
  expect_identical(selected_column$membershipHash, original$membershipHash)
  expect_false(identical(selected_column$fingerprint, original$fingerprint))
  expect_null(counts_only$dataHash)
  expect_false(identical(counts_only$fingerprint, original$fingerprint))
})

test_that("identity uses every object cell and rejects missing or split layers", {
  object <- project_export_fixture()
  partial <- object
  partial[["FULL"]] <- SeuratObject::CreateAssay5Object(
    counts = SeuratObject::LayerData(object, assay = "RNA", layer = "counts")
  )
  SeuratObject::DefaultAssay(partial) <- "FULL"
  suppressWarnings(partial[["RNA"]] <- subset(partial[["RNA"]], cells = colnames(object)[1:3]))
  expect_identical(colnames(partial), colnames(object))
  expect_error(project_export_identity(partial), "cell|scope|coverage", ignore.case = TRUE)

  missing_counts <- object
  suppressWarnings(SeuratObject::LayerData(missing_counts, assay = "RNA", layer = "counts") <- NULL)
  expect_error(project_export_identity(missing_counts), "counts|layer", ignore.case = TRUE)

  missing_data <- object
  SeuratObject::LayerData(missing_data, assay = "RNA", layer = "data") <- NULL
  expect_error(project_export_identity(missing_data), "data|layer", ignore.case = TRUE)
  counts_only <- scAgentKit:::.sc_project_identity(
    missing_data, "RNA", "counts", NULL, "seurat_clusters"
  )
  expect_null(counts_only$normalizedLayer)
  expect_equal(counts_only$cellCount, 4)

  split_object <- object
  split_object[["RNA"]] <- split(split_object[["RNA"]], f = c("a", "a", "b", "b"))
  expect_error(project_export_identity(split_object), "JoinLayers|split|join", ignore.case = TRUE)

  missing_membership <- object
  missing_membership$seurat_clusters[1] <- NA_character_
  expect_error(project_export_identity(missing_membership), "cluster|membership|missing", ignore.case = TRUE)
  missing_column <- object
  missing_column$seurat_clusters <- NULL
  expect_error(project_export_identity(missing_column), "cluster|membership", ignore.case = TRUE)
  expect_error(project_export_identity(AgentSeurat(list(a = object, b = object))),
               "single|one|Seurat", ignore.case = TRUE)
})

test_that("counts must be genuine finite nonnegative integers", {
  object <- project_export_fixture()
  for (value in c(0.5, -1, Inf, NaN)) {
    invalid <- object
    invalid[["RNA"]]@layers$counts@x[1] <- value
    expect_error(project_export_identity(invalid),
                 "count|finite|integer|nonnegative", ignore.case = TRUE)
  }
  invalid_data <- object
  invalid_data[["RNA"]]@layers$data@x[1] <- Inf
  expect_error(project_export_identity(invalid_data), "finite|data|normalized", ignore.case = TRUE)
  expect_error(scAgentKit:::.sc_project_identity(object, "RNA", "data", NULL, "seurat_clusters"),
               "genuine|raw counts", ignore.case = TRUE)
  expect_error(scAgentKit:::.sc_project_identity(object, "RNA", "counts", "counts", "seurat_clusters"),
               "distinct|raw counts", ignore.case = TRUE)
})

test_that("portable export preserves exact IDs and verifies its file bytes", {
  object <- project_export_fixture()
  before <- object
  path <- tempfile("project-")
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  result <- sc_project_export(object, path, project_id = "study-A",
                              parameters = list(resolution = 0.5),
                              provenance = list(note = "local fixture"))
  expect_identical(object, before)
  expect_identical(result$projectId, "study-A")
  expect_identical(result$sourceFingerprint, project_export_identity(object)$fingerprint)
  project <- project_export_json(path)
  manifest <- project_export_json(path, "manifest.json")
  expect_identical(project$schema, "scagentkit.project.v1")
  expect_identical(manifest$schema, "scagentkit.project-bundle.v1")
  expect_identical(project$projectId, "study-A")
  expect_identical(project$displayName, "study-A")
  expect_identical(manifest$sourceFingerprint, result$sourceFingerprint)
  expect_identical(project$identity$fingerprint, result$sourceFingerprint)
  expect_identical(manifest$bundleDigest, result$bundleDigest)
  expect_identical(result$bundleDigest,
                   digest::digest(file = file.path(path, "project.json"), algo = "sha256"))
  expect_setequal(vapply(project$cells, `[[`, character(1), "cellId"), colnames(object))
  expect_setequal(vapply(project$clusters, `[[`, character(1), "id"), c("T alpha", "NA", "01"))
  for (cluster in project$clusters) {
    expect_setequal(unlist(cluster$cellIds, use.names = FALSE),
                    colnames(object)[object$seurat_clusters == cluster$id])
  }
  expect_setequal(vapply(project$embedding$points, `[[`, character(1), "cellId"), colnames(object))
  expect_identical(project$parameters$resolution, 0.5)
  expect_identical(project$provenance$note, "local fixture")
  for (entry in manifest$files) {
    asset_path <- file.path(path, entry$path)
    expect_true(file.exists(asset_path))
    expect_equal(entry$bytes, unname(file.info(asset_path)$size))
    expect_identical(entry$sha256, digest::digest(file = asset_path, algo = "sha256"))
  }
  expect_false(any(grepl("\\.(rds|RDS)$", list.files(path, recursive = TRUE))))
})

test_that("snapshot parameters change bundle identity independently of expression identity", {
  object <- project_export_fixture()
  first_path <- tempfile("project-snapshot-a-")
  second_path <- tempfile("project-snapshot-b-")
  on.exit(unlink(c(first_path, second_path), recursive = TRUE), add = TRUE)
  first <- sc_project_export(object, first_path, project_id = "same-source",
                             parameters = list(resolution = 0.4))
  second <- sc_project_export(object, second_path, project_id = "same-source",
                              parameters = list(resolution = 0.8))
  expect_identical(first$sourceFingerprint, second$sourceFingerprint)
  expect_false(identical(first$bundleDigest, second$bundleDigest))
})

test_that("metadata is allowlisted and optional evidence stays empty or null", {
  object <- project_export_fixture(embedding = FALSE)
  path <- tempfile("project-")
  explicit_path <- tempfile("project-context-")
  on.exit(unlink(c(path, explicit_path), recursive = TRUE), add = TRUE)
  sc_project_export(object, path, project_id = "no-embedding", reduction = NULL)
  project <- project_export_json(path)
  expect_null(project$embedding)
  expect_length(project$markers, 0)
  expect_length(project$candidates, 0)
  expect_length(project$models, 0)
  expect_length(project$directed$clusters, 0)
  text <- project_export_text(path)
  for (field in c("markers", "candidates", "models")) {
    expect_match(text, paste0('"', field, '"\\s*:\\s*\\['))
  }
  expect_false(grepl("must not be exported|private_note|source_label|unused", text))
  for (cell in project$cells) {
    expect_setequal(names(cell$qc), c("nCount_RNA", "nFeature_RNA", "percent.mt"))
    expect_false("sourceAnnotation" %in% names(cell))
  }

  sc_project_export(object, explicit_path, project_id = "source-context", reduction = NULL,
                    source_annotation = "source_label", metadata_allowlist = "percent.mt")
  context <- project_export_json(explicit_path)
  for (cell in context$cells) expect_identical(names(cell$qc), "percent.mt")
  expect_false(grepl("must not be exported|private_note|unused", project_export_text(explicit_path)))
  expect_match(project_export_text(explicit_path), '"sourceAnnotation"')
})

test_that("one-cell collections remain JSON arrays", {
  object <- project_export_fixture()[, "001", drop = FALSE]
  path <- tempfile("project-single-")
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  sc_project_export(object, path, project_id = "single")
  text <- project_export_text(path)
  for (field in c("cells", "clusters", "cellIds", "points", "markers", "candidates", "models")) {
    expect_match(text, paste0('"', field, '"\\s*:\\s*\\['))
  }
  project <- project_export_json(path)
  expect_length(project$cells, 1)
  expect_identical(project$cells[[1]]$cellId, "001")
  expect_identical(project$clusters[[1]]$cellIds, list("001"))
})

test_that("supplied evidence stays in exact one-record arrays", {
  object <- project_export_fixture()
  path <- tempfile("project-supplied-")
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  marker <- data.frame(clusterId = "T alpha", gene = "CD3D", avgLog2FC = 1.5,
                       pct1 = .5, pct2 = .25, pAdj = .01, source = "provided")
  candidate <- data.frame(clusterId = "T alpha", label = "T cell", score = .8,
                          overlap = 1, referenceSize = 3, markers = I(list("CD3D")), source = "provided")
  model <- list(list(clusterId = "T alpha", callId = "offline-1", provider = "local",
                     mode = "strict", strictStatus = "not_run", strict = NULL,
                     posthoc = NULL, rawText = "", source = "provided"))
  sc_project_export(object, path, "supplied", marker_table = marker, candidate_table = candidate, model_records = model)
  project <- project_export_json(path)
  expect_length(project$markers, 1)
  expect_length(project$candidates, 1)
  expect_length(project$models, 1)
  expect_identical(project$candidates[[1]]$markers, list("CD3D"))
  expect_identical(project$models[[1]]$strictStatus, "not_run")
  expect_null(project$models[[1]]$strict)
  expect_identical(project$models[[1]]$rawText, "")
  for (field in c("markers", "candidates", "models")) expect_match(project_export_text(path), paste0('"', field, '"\\s*:\\s*\\['))
  marker$clusterId <- "foreign"
  bad_path <- tempfile("project-bad-record-")
  expect_error(sc_project_export(object, bad_path, "bad-record", marker_table = marker), "foreign cluster")
  expect_false(dir.exists(bad_path))
  model[[1]]["rawText"] <- list(NULL)
  null_path <- tempfile("project-null-model-")
  on.exit(unlink(null_path, recursive = TRUE), add = TRUE)
  sc_project_export(object, null_path, "null-model", model_records = model)
  expect_null(project_export_json(null_path)$models[[1]]$rawText)
  model[[1]]$strictStatus <- "valid"
  expect_error(sc_project_export(object, tempfile("bad-model-"), "invalid-model", model_records = model), "valid strict")
  candidate$score <- 1.1
  expect_error(sc_project_export(object, tempfile("bad-candidate-"), "invalid-candidate", candidate_table = candidate), "\\[0,1\\]")
})

test_that("JSON preflight rejects damaged nested values before publishing", {
  object <- project_export_fixture()
  for (parameters in list(list(nested = list(value = Inf)), list(nested = list(value = NaN)),
                          list(nested = list(value = 2^53)), list(nested = structure(list(1, 2), names = c("duplicate", "duplicate"))))) {
    path <- tempfile("project-invalid-json-")
    expect_error(sc_project_export(object, path, "invalid-json", parameters = parameters), "finite|representable|unique")
    expect_false(dir.exists(path))
  }
  object$source_numeric <- c(1, 2, NA, 0)
  path <- tempfile("project-numeric-context-")
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  sc_project_export(object, path, "numeric-context", source_annotation = "source_numeric")
  annotations <- project_export_json(path)$sourceAnnotation$values
  values <- setNames(lapply(annotations, `[[`, "value"), vapply(annotations, `[[`, character(1), "cellId"))
  expect_identical(values[["001"]], "1")
  expect_null(values[["NA"]])
})

test_that("selected duplicate metadata names fail instead of choosing the first", {
  object <- project_export_fixture()
  duplicate_cluster <- object
  duplicate_cluster@meta.data$additional <- duplicate_cluster$seurat_clusters
  names(duplicate_cluster@meta.data)[ncol(duplicate_cluster@meta.data)] <- "seurat_clusters"
  expect_error(project_export_identity(duplicate_cluster), "ambiguous")
  duplicate_qc <- object
  duplicate_qc@meta.data$additional <- duplicate_qc$percent.mt
  names(duplicate_qc@meta.data)[ncol(duplicate_qc@meta.data)] <- "percent.mt"
  path <- tempfile("duplicate-qc-")
  expect_error(sc_project_export(duplicate_qc, path, "duplicate-qc"), "ambiguous")
  expect_false(dir.exists(path))
})

test_that("metadata opt-in and actual missing directed QC remain explicit", {
  object <- project_export_fixture()
  object$percent.mt[1] <- NA_real_
  object$nCount_RNA[1] <- NA_real_
  default_path <- tempfile("project-default-qc-")
  explicit_path <- tempfile("project-explicit-qc-")
  on.exit(unlink(c(default_path, explicit_path), recursive = TRUE), add = TRUE)
  sc_project_export(object, default_path, "default-qc", directed_clusters = "T alpha")
  expect_false(grepl("orig.ident|must not be exported", project_export_text(default_path)))
  project <- project_export_json(default_path)
  expression <- jsonlite::fromJSON(file.path(default_path, project$directed$clusters[["T alpha"]]$path), simplifyVector = FALSE)
  cell <- expression$cells[[which(vapply(expression$cells, `[[`, character(1), "cell_id") == "001")]]
  expect_null(cell$qc$nCount_RNA)
  expect_null(cell$qc$percent.mt)
  expect_null(cell$low_depth)
  sc_project_export(object, explicit_path, "explicit-qc", metadata_allowlist = c("orig.ident"), directed_clusters = "T alpha")
  expect_match(project_export_text(explicit_path), "orig.ident")
  explicit <- project_export_json(explicit_path)
  for (record in explicit$cells) expect_identical(names(record$qc), "orig.ident")
  asset <- jsonlite::fromJSON(file.path(explicit_path, explicit$directed$clusters[["T alpha"]]$path), simplifyVector = FALSE)
  for (record in asset$cells) {
    expect_null(record$qc$nCount_RNA)
    expect_null(record$qc$nFeature_RNA)
    expect_true(is.character(record$qc$orig.ident))
  }
})

test_that("explicit directed assets keep actual zero and missing measurements distinct", {
  object <- project_export_fixture()
  path <- tempfile("project-directed-")
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  result <- sc_project_export(object, path, project_id = "directed",
                              directed_clusters = "T alpha")
  project <- project_export_json(path)
  expect_identical(names(project$directed$clusters), "T alpha")
  asset <- project$directed$clusters[["T alpha"]]
  expression <- jsonlite::fromJSON(file.path(path, asset$path), simplifyVector = FALSE)
  expect_identical(asset$sha256,
                   digest::digest(file = file.path(path, asset$path), algo = "sha256"))
  expect_identical(expression$schema_version, "scAgentKit.directed_expression.v2")
  expect_identical(expression$source$object_fingerprint, result$sourceFingerprint)
  expect_false("rds_sha256" %in% names(expression$source))
  expect_setequal(unlist(expression$scope$cell_ids), c("001", "1"))
  expect_identical(expression$scope$cluster_id, "T alpha")
  expect_equal(expression$scope$n_cells, 2)
  for (cell in expression$cells) {
    expect_equal(cell$counts$CD3E, 0)
    expect_equal(cell$normalized$CD3E, 0)
    expect_null(cell$counts$CD3G)
    expect_null(cell$normalized$CD3G)
    expect_equal(cell$counts$CD3D,
                 as.numeric(SeuratObject::LayerData(object, layer = "counts")["CD3D", cell$cell_id]))
    expect_equal(cell$normalized$CD3D,
                 as.numeric(SeuratObject::LayerData(object, layer = "data")["CD3D", cell$cell_id]))
  }
  panel <- setNames(expression$panel, vapply(expression$panel, `[[`, character(1), "gene"))
  expect_identical(panel$CD3E$measurement_status, "measured")
  expect_equal(panel$CD3E$detected_n, 0)
  expect_equal(panel$CD3E$normalized$detected$n, 0)
  expect_identical(panel$CD3G$measurement_status, "missing")
  expect_null(panel$CD3G$detected_n)
  expect_null(panel$CD3G$raw_counts)
  manifest <- project_export_json(path, "manifest.json")
  expect_true(asset$path %in% vapply(manifest$files, `[[`, character(1), "path"))
})

test_that("counts-only exports preserve manual review and report directed tools unavailable", {
  object <- project_export_fixture()
  SeuratObject::LayerData(object, assay = "RNA", layer = "data") <- NULL
  path <- tempfile("project-counts-")
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  sc_project_export(object, path, project_id = "counts-only", normalized_layer = NULL,
                    directed_clusters = "T alpha")
  project <- project_export_json(path)
  expect_null(project$identity$normalizedLayer)
  expect_null(project$identity$dataHash)
  expect_length(project$cells, ncol(object))
  expect_length(project$directed$clusters, 0)
  expect_identical(project$parameters$directedUnavailable$clusterIds, list("T alpha"))
  expect_match(project$parameters$directedUnavailable$reason, "no normalized layer")
  expect_setequal(list.files(path, recursive = TRUE), c("manifest.json", "project.json"))
})

test_that("export refuses overwrites and archives contain verified bundle assets", {
  object <- project_export_fixture()
  path <- tempfile("project-archive-")
  on.exit(unlink(c(path, paste0(path, ".zip")), recursive = TRUE), add = TRUE)
  result <- sc_project_export(object, path, project_id = "archive", archive = TRUE)
  expect_true(is.character(result$archive) && length(result$archive) == 1L)
  expect_true(file.exists(result$archive))
  expect_setequal(utils::unzip(result$archive, list = TRUE)$Name,
                  c("manifest.json", "project.json"))
  prior_digest <- digest::digest(file = file.path(path, "project.json"), algo = "sha256")
  expect_error(sc_project_export(object, path, project_id = "archive"), "exist|overwrite", ignore.case = TRUE)
  expect_identical(digest::digest(file = file.path(path, "project.json"), algo = "sha256"), prior_digest)

  archive_conflict <- tempfile("project-archive-conflict-")
  writeLines("keep this file", paste0(archive_conflict, ".zip"))
  on.exit(unlink(c(archive_conflict, paste0(archive_conflict, ".zip")), recursive = TRUE), add = TRUE)
  expect_error(sc_project_export(object, archive_conflict, project_id = "archive", archive = TRUE),
               "exist|overwrite", ignore.case = TRUE)
  expect_identical(readLines(paste0(archive_conflict, ".zip")), "keep this file")
  expect_false(dir.exists(archive_conflict))

  invalid_path <- tempfile("project-invalid-")
  on.exit(unlink(invalid_path, recursive = TRUE), add = TRUE)
  expect_error(sc_project_export(object, invalid_path, project_id = ""), "project|empty", ignore.case = TRUE)
  expect_error(sc_project_export(object, invalid_path, project_id = "folder/study"), "project|path", ignore.case = TRUE)
  expect_error(sc_project_export(object, invalid_path, project_id = "invalid", directed_clusters = "unknown"),
               "cluster|scope", ignore.case = TRUE)
  expect_error(sc_project_export(project_export_fixture(embedding = FALSE), invalid_path, project_id = "invalid"),
               "umap|reduction|embedding", ignore.case = TRUE)
  expect_false(dir.exists(invalid_path))
})

test_that("preparation rejects duplicate matrix IDs before Seurat renames them", {
  counts <- SeuratObject::LayerData(project_export_fixture(), assay = "RNA", layer = "counts")
  duplicate_features <- counts
  rownames(duplicate_features)[2] <- rownames(duplicate_features)[1]
  expect_error(sc_project_prepare(duplicate_features), "duplicate|unique", ignore.case = TRUE)
  duplicate_cells <- counts
  colnames(duplicate_cells)[2] <- colnames(duplicate_cells)[1]
  expect_error(sc_project_prepare(duplicate_cells), "duplicate|unique", ignore.case = TRUE)
  bad_counts <- counts
  bad_counts@x[1] <- 0.5
  expect_error(sc_project_prepare(bad_counts), "count|integer", ignore.case = TRUE)
})

test_that("explicit preparation analyzes a copy and retains low-depth cells", {
  set.seed(17)
  counts <- matrix(stats::rpois(60 * 24, lambda = 3), nrow = 60,
                   dimnames = list(paste0("Gene", seq_len(60)),
                                   c("001", paste0("cell", 2:24))))
  counts[, 1] <- 0
  counts[1, 1] <- 1
  counts <- Matrix::Matrix(counts, sparse = TRUE)
  object <- Seurat::CreateSeuratObject(counts = counts)
  object$original_label <- factor(rep(c("T", "B"), 12), levels = c("T", "B", "unused"))
  object$original_label[2] <- NA
  original <- object
  prepare <- function(input) {
    suppressWarnings(sc_project_prepare(
      input, nfeatures = 30, npcs = 3, dims = 1:3,
      resolution = 0.4, seed = 17, run_umap = FALSE
    ))
  }
  prepared <- prepare(object)
  expect_s4_class(prepared, "Seurat")
  expect_identical(object, original)
  expect_identical(colnames(prepared), colnames(object))
  expect_equal(SeuratObject::LayerData(prepared, assay = "RNA", layer = "counts"), counts)
  expect_identical(prepared$original_label, object$original_label)
  expect_true(all(c("counts", "data", "scale.data") %in% SeuratObject::Layers(prepared[["RNA"]])))
  expect_true("pca" %in% names(prepared@reductions))
  expect_false("umap" %in% names(prepared@reductions))
  expect_length(prepared$seurat_clusters, 24)
  expect_false(anyNA(prepared$seurat_clusters))
  expect_true("001" %in% colnames(prepared))
  expect_equal(prepared@misc$sc_project_prepare$seed, 17)
  expect_identical(prepared@misc$sc_project_prepare$run_umap, FALSE)

  wrapped <- AgentSeurat(object)
  wrapped_before <- wrapped
  wrapped_prepared <- prepare(wrapped)
  expect_s4_class(wrapped_prepared, "AgentSeurat")
  expect_identical(wrapped, wrapped_before)
  expect_identical(colnames(wrapped_prepared@data), colnames(object))
  expect_equal(wrapped_prepared@params$project_prepare$seed, 17)

  matrix_prepared <- prepare(counts)
  expect_s4_class(matrix_prepared, "Seurat")
  expect_identical(colnames(matrix_prepared), colnames(counts))
  expect_identical(rownames(matrix_prepared), rownames(counts))
})
