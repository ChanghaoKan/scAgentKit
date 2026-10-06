# Local review replay uses original JSON bytes for hashes. It writes no files.
.sc_review_fail <- function(code, message, path = "") {
  stop(structure(list(message = message, call = NULL, code = code, path = path),
    class = c("sc_review_validation_error", "error", "condition")))
}
.sc_review_sha <- function(bytes) digest::digest(bytes, algo = "sha256", serialize = FALSE)
.sc_review_text_sha <- function(text) .sc_review_sha(charToRaw(enc2utf8(text)))
.sc_review_timestamp <- function(x) {
  .sc_review_string(x, "event.createdAt", 100L)
  pattern <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$"
  if (!grepl(pattern, x)) .sc_review_fail("invalid_timestamp", "Expected a canonical RFC3339 timestamp.", "event.createdAt")
  fields <- as.integer(c(substr(x, 1, 4), substr(x, 6, 7), substr(x, 9, 10), substr(x, 12, 13), substr(x, 15, 16), substr(x, 18, 19)))
  year <- fields[1]; month <- fields[2]; day <- fields[3]
  days <- c(31, if (year %% 4 == 0 && (year %% 100 != 0 || year %% 400 == 0)) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
  bad <- year < 1 || month < 1 || month > 12 || day < 1 || day > days[pmax(1, pmin(12, month))] || fields[4] > 23 || fields[5] > 59 || fields[6] > 59
  if (!endsWith(x, "Z")) {
    zone <- tail(strsplit(x, "", fixed = TRUE)[[1L]], 6L)
    bad <- bad || as.integer(paste0(zone[2:3], collapse = "")) > 23 || as.integer(paste0(zone[5:6], collapse = "")) > 59
  }
  if (bad) .sc_review_fail("invalid_timestamp", "Invalid RFC3339 date, time or offset.", "event.createdAt")
  invisible(x)
}
.sc_review_string <- function(x, path, max = 4096L) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x)) || nchar(x, type = "chars") > max)
    .sc_review_fail("invalid_string", paste0(path, " must be a nonempty literal string."), path)
  x
}
.sc_review_hash <- function(x, path) {
  .sc_review_string(x, path, 64L)
  if (!grepl("^[a-f0-9]{64}$", x)) .sc_review_fail("invalid_hash", "Expected lowercase SHA256.", path)
  x
}

# Retain array/object types and nulls, and reject duplicate decoded keys.
# jsonlite alone silently accepts duplicate object keys.
.sc_review_json <- function(text, path = "JSON", integer_sequence = FALSE) {
  if (!is.character(text) || length(text) != 1L || is.na(text) ||
      is.na(iconv(text, from = "UTF-8", to = "UTF-8"))) .sc_review_fail("invalid_json", "Invalid UTF-8 JSON.", path)
  bytes <- charToRaw(text); codes <- as.integer(bytes); n <- length(bytes); pos <- 1L
  # Byte offsets keep Unicode-heavy projects linear. Repeated UTF-8 substr()
  # scans from the start and becomes quadratic for otherwise ordinary bundles.
  char <- function() if (pos <= n) codes[pos] else -1L
  bad <- function(message = "Invalid JSON syntax.") .sc_review_fail("invalid_json", message, path)
  skip <- function() while (pos <= n && char() %in% c(32L, 10L, 13L, 9L)) pos <<- pos + 1L
  string <- function() {
    start <- pos; pos <<- pos + 1L
    while (pos <= n) {
      token <- char()
      if (token == 92L) { pos <<- pos + 2L; next }
      if (token == 34L) {
        pos <<- pos + 1L
        out <- tryCatch(jsonlite::fromJSON(rawToChar(bytes[start:(pos - 1L)]), simplifyVector = FALSE), error = function(e) bad())
        if (!is.character(out) || length(out) != 1L || is.na(iconv(out, from = "UTF-8", to = "UTF-8"))) bad()
        return(out)
      }
      if (token < 32L) bad()
      pos <<- pos + 1L
    }
    bad()
  }
  value <- function(depth = 0L, sequence = FALSE) {
    if (depth > 64L) bad("JSON nesting exceeds local limit.")
    skip(); token <- char()
    if (token == 34L) return(string())
    if (token %in% c(123L, 91L)) {
      object <- token == 123L; end <- if (object) 125L else 93L
      pos <<- pos + 1L; skip(); out <- list(); keys <- character()
      if (char() != end) repeat {
        skip()
        if (object) {
          if (char() != 34L) bad()
          key <- string()
          if (key %in% keys) .sc_review_fail("duplicate_key", "Duplicate JSON object key.", path)
          keys <- c(keys, key); skip()
          if (char() != 58L) bad()
          pos <<- pos + 1L
        }
        out[length(out) + 1L] <- list(value(depth + 1L, object && identical(key, "sequence"))); skip()
        if (char() == end) break
        if (char() != 44L) bad()
        pos <<- pos + 1L
      }
      if (char() != end) bad()
      pos <<- pos + 1L
      if (object) names(out) <- keys
      class(out) <- if (object) "sc_review_object" else "sc_review_array"
      return(out)
    }
    if (pos > n) bad()
    remaining <- rawToChar(bytes[pos:min(n, pos + 1023L)])
    for (literal in c("true", "false", "null")) if (startsWith(remaining, literal)) {
      pos <<- pos + nchar(literal)
      return(switch(literal, true = TRUE, false = FALSE, null = NULL))
    }
    match <- regexpr("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?", remaining, useBytes = TRUE)
    if (match[1L] != 1L) bad()
    count <- attr(match, "match.length"); literal <- substr(remaining, 1L, count)
    if (integer_sequence && sequence && !grepl("^[0-9]+$", literal)) bad("Event sequence must use a JSON integer token.")
    number <- as.numeric(literal)
    if (!is.finite(number)) bad("Nonfinite JSON number.")
    pos <<- pos + count; number
  }
  out <- value(); skip()
  if (pos <= n) bad()
  out
}
.sc_review_object <- function(x, path, required = character(), allowed = NULL) {
  if (!inherits(x, "sc_review_object") || !all(required %in% names(x)) ||
      (!is.null(allowed) && any(!names(x) %in% allowed))) .sc_review_fail("invalid_structure", paste0("Invalid fields at ", path, "."), path)
  x
}
.sc_review_array <- function(x, path) {
  if (!inherits(x, "sc_review_array")) .sc_review_fail("invalid_structure", paste0(path, " must be an array."), path)
  x
}
.sc_review_number <- function(x, path, integer = FALSE, fraction = FALSE) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) ||
      (integer && (x < 0 || x != floor(x))) || (fraction && (x < 0 || x > 1)))
    .sc_review_fail("invalid_number", "Expected a finite number within the declared range.", path)
  x
}
.sc_review_ids <- function(x, path, nonempty = TRUE) {
  .sc_review_array(x, path)
  ids <- vapply(x, .sc_review_string, character(1), path = path, max = 1024L)
  if ((nonempty && !length(ids)) || anyDuplicated(ids)) .sc_review_fail("invalid_ids", "Missing or duplicate IDs.", path)
  ids
}
.sc_review_read <- function(path, limit = 32 * 1024^2) {
  size <- file.info(path)$size
  if (!isTRUE(file_test("-f", path)) || length(size) != 1L || is.na(size) || size < 0 || size > limit) .sc_review_fail("file_limit", "Missing regular file or byte limit exceeded.", path)
  con <- file(path, "rb"); on.exit(close(con)); readBin(con, "raw", n = size)
}
.sc_review_file_json <- function(path, integer_sequence = FALSE) .sc_review_json(rawToChar(.sc_review_read(path)), path, integer_sequence)
.sc_review_relative <- function(path) {
  .sc_review_string(path, "asset path", 1024L)
  parts <- strsplit(path, "/", fixed = TRUE)[[1L]]
  if (grepl("[\\\\:]", path) || startsWith(path, "/") || endsWith(path, "/") || any(parts %in% c("", ".", "..")) || grepl("[[:cntrl:]]", path))
    .sc_review_fail("unsafe_path", "Unsafe project asset path.", path)
  path
}
.sc_review_project_entries <- function(root) {
  entries <- character(); pending <- ""
  while (length(pending)) {
    relative <- pending[1L]; pending <- pending[-1L]
    children <- list.files(file.path(root, relative), all.files = TRUE,
      full.names = FALSE, recursive = FALSE, no.. = TRUE)
    children <- if (nzchar(relative)) file.path(relative, children) else children
    entries <- c(entries, children)
    if (length(entries) > 1000L || any(nzchar(Sys.readlink(file.path(root, children)))))
      .sc_review_fail("unsafe_project", "Project contains symlinks or too many entries.", "project")
    pending <- c(pending, children[dir.exists(file.path(root, children))])
  }
  entries
}
.sc_review_load_project <- function(project) {
  .sc_review_string(project, "project directory", 8192L)
  if (!dir.exists(project)) .sc_review_fail("project_directory", "Supply a project directory; safely import ZIP files through the local workbench first.", "project")
  root <- normalizePath(project, winslash = "/", mustWork = TRUE)
  entries <- .sc_review_project_entries(root)
  manifest <- .sc_review_file_json(file.path(root, "manifest.json"))
  fields <- c("schema", "projectId", "sourceFingerprint", "bundleDigest", "files")
  .sc_review_object(manifest, "manifest", fields, fields)
  if (!identical(manifest$schema, "scagentkit.project-bundle.v1")) .sc_review_fail("unsupported_schema", "Unsupported project bundle schema.", "manifest.schema")
  .sc_review_string(manifest$projectId, "manifest.projectId", 256L)
  .sc_review_hash(manifest$sourceFingerprint, "manifest.sourceFingerprint"); .sc_review_hash(manifest$bundleDigest, "manifest.bundleDigest")
  files <- .sc_review_array(manifest$files, "manifest.files"); paths <- character(); total <- 0
  for (entry in files) {
    .sc_review_object(entry, "manifest file", c("path", "bytes", "sha256"), c("path", "bytes", "sha256"))
    path <- .sc_review_relative(entry$path)
    if (path %in% paths || path == "manifest.json") .sc_review_fail("duplicate_asset", "Duplicate project asset.", path)
    paths <- c(paths, path)
    if (!is.numeric(entry$bytes) || length(entry$bytes) != 1L || !is.finite(entry$bytes) || entry$bytes < 0 || entry$bytes != floor(entry$bytes) || entry$bytes > 64 * 1024^2)
      .sc_review_fail("file_limit", "Invalid asset size.", path)
    total <- total + entry$bytes
    if (total > 128 * 1024^2) .sc_review_fail("file_limit", "Project byte limit exceeded.", path)
    .sc_review_hash(entry$sha256, paste0(path, ".sha256"))
    bytes <- .sc_review_read(file.path(root, path), 64 * 1024^2)
    if (length(bytes) != entry$bytes || !identical(.sc_review_sha(bytes), entry$sha256)) .sc_review_fail("asset_checksum", "Asset size or checksum disagrees with manifest.", path)
  }
  actual <- entries[!dir.exists(file.path(root, entries))]
  if (!setequal(actual, c("manifest.json", paths)) || !"project.json" %in% paths) .sc_review_fail("unlisted_asset", "Unlisted or missing project files.", "manifest.files")
  bytes <- .sc_review_read(file.path(root, "project.json"))
  if (!identical(.sc_review_sha(bytes), manifest$bundleDigest)) .sc_review_fail("bundle_digest", "Project snapshot digest mismatch.", "project.json")
  data <- .sc_review_json(rawToChar(bytes), "project.json")
  project_fields <- c("schema", "projectId", "displayName", "identity", "cells", "clusters", "embedding", "markers", "candidates", "models", "parameters", "provenance", "directed")
  .sc_review_object(data, "project", project_fields, c(project_fields, "sourceAnnotation"))
  if (!identical(data$schema, "scagentkit.project.v1") || !identical(data$projectId, manifest$projectId)) .sc_review_fail("project_identity", "Project ID or schema mismatch.", "project")
  .sc_review_string(data$displayName, "project.displayName")
  identity_fields <- c("algorithm", "fingerprint", "assay", "countsLayer", "normalizedLayer", "clusterColumn", "cellCount", "featureCount", "cellsHash", "featuresHash", "membershipHash", "countsHash", "dataHash")
  identity <- .sc_review_object(data$identity, "project.identity", identity_fields, identity_fields)
  if (!identical(identity$algorithm, "scagentkit.source.v1") || !identical(identity$fingerprint, manifest$sourceFingerprint)) .sc_review_fail("source_identity", "Source identity is unsupported or inconsistent.", "project.identity")
  for (name in c("fingerprint", "cellsHash", "featuresHash", "membershipHash", "countsHash")) .sc_review_hash(identity[[name]], paste0("identity.", name))
  for (name in c("assay", "countsLayer", "clusterColumn")) .sc_review_string(identity[[name]], paste0("identity.", name), 256L)
  if (!is.null(identity$normalizedLayer)) .sc_review_string(identity$normalizedLayer, "identity.normalizedLayer", 256L)
  if (is.null(identity$normalizedLayer)) {
    if (!is.null(identity$dataHash)) .sc_review_fail("source_identity", "Counts-only dataHash must be null.", "identity.dataHash")
  } else .sc_review_hash(identity$dataHash, "identity.dataHash")
  for (name in c("cellCount", "featureCount")) {
    count <- identity[[name]]
    if (!is.numeric(count) || length(count) != 1L || !is.finite(count) || count < 1 || count != floor(count)) .sc_review_fail("invalid_structure", "Invalid source dimensions.", paste0("identity.", name))
  }
  cells <- .sc_review_array(data$cells, "project.cells"); cell_ids <- cluster_ids <- character(length(cells))
  for (i in seq_along(cells)) {
    .sc_review_object(cells[[i]], "project cell", c("cellId", "clusterId", "qc"), c("cellId", "clusterId", "qc"))
    .sc_review_object(cells[[i]]$qc, "cell.qc")
    cell_ids[i] <- .sc_review_string(cells[[i]]$cellId, "cellId", 1024L)
    cluster_ids[i] <- .sc_review_string(cells[[i]]$clusterId, "clusterId", 1024L)
  }
  if (!length(cell_ids) || anyDuplicated(cell_ids) || length(cell_ids) != identity$cellCount) .sc_review_fail("invalid_ids", "Project cells are duplicated or incomplete.", "project.cells")
  scopes <- list()
  for (cluster in .sc_review_array(data$clusters, "project.clusters")) {
    .sc_review_object(cluster, "project cluster", c("id", "cellIds"), c("id", "cellIds"))
    id <- .sc_review_string(cluster$id, "cluster.id", 1024L)
    if (id %in% names(scopes)) .sc_review_fail("invalid_ids", "Duplicate cluster ID.", "project.clusters")
    scope <- .sc_review_ids(cluster$cellIds, "cluster.cellIds")
    if (!setequal(scope, cell_ids[cluster_ids == id])) .sc_review_fail("scope_mismatch", "Cluster and cell membership disagree.", id)
    scopes[[id]] <- scope
  }
  if (!setequal(names(scopes), unique(cluster_ids))) .sc_review_fail("scope_mismatch", "Cluster index incomplete.", "project.clusters")
  if (!is.null(data$embedding)) {
    embedding <- .sc_review_object(data$embedding, "project.embedding", c("name", "points"), c("name", "points"))
    .sc_review_string(embedding$name, "embedding.name")
    seen <- character()
    for (point in .sc_review_array(embedding$points, "embedding.points")) {
      .sc_review_object(point, "embedding point", c("cellId", "x", "y"), c("cellId", "x", "y"))
      id <- .sc_review_string(point$cellId, "embedding.cellId", 1024L)
      if (!id %in% cell_ids || id %in% seen) .sc_review_fail("scope_mismatch", "Embedding has duplicate or foreign cells.", "embedding.points")
      seen <- c(seen, id); .sc_review_number(point$x, "embedding.x"); .sc_review_number(point$y, "embedding.y")
    }
    if (!setequal(seen, cell_ids)) .sc_review_fail("scope_mismatch", "Embedding must cover every cell.", "embedding.points")
  }
  for (name in c("markers", "candidates", "models")) .sc_review_array(data[[name]], paste0("project.", name))
  markers_seen <- calls_seen <- character()
  for (marker in data$markers) {
    fields <- c("clusterId", "gene", "avgLog2FC", "pct1", "pct2", "pAdj", "source")
    .sc_review_object(marker, "marker", fields, fields)
    if (!is.character(marker$clusterId) || !marker$clusterId %in% names(scopes)) .sc_review_fail("scope_mismatch", "Marker refers to unknown cluster.", "markers")
    .sc_review_string(marker$gene, "marker.gene"); .sc_review_string(marker$source, "marker.source")
    key <- paste0(nchar(marker$clusterId), ":", marker$clusterId, marker$gene)
    if (key %in% markers_seen) .sc_review_fail("duplicate_evidence", "Duplicate cluster marker.", "markers")
    markers_seen <- c(markers_seen, key); .sc_review_number(marker$avgLog2FC, "marker.avgLog2FC")
    for (name in c("pct1", "pct2", "pAdj")) .sc_review_number(marker[[name]], paste0("marker.", name), fraction = TRUE)
  }
  for (candidate in data$candidates) {
    fields <- c("clusterId", "label", "score", "overlap", "referenceSize", "markers", "source")
    .sc_review_object(candidate, "candidate", fields, fields)
    if (!is.character(candidate$clusterId) || !candidate$clusterId %in% names(scopes)) .sc_review_fail("scope_mismatch", "Candidate refers to unknown cluster.", "candidates")
    .sc_review_string(candidate$label, "candidate.label"); .sc_review_string(candidate$source, "candidate.source")
    .sc_review_number(candidate$score, "candidate.score", fraction = TRUE)
    .sc_review_number(candidate$overlap, "candidate.overlap", integer = TRUE)
    .sc_review_number(candidate$referenceSize, "candidate.referenceSize", integer = TRUE)
    if (candidate$overlap > candidate$referenceSize) .sc_review_fail("invalid_number", "Candidate overlap exceeds reference size.", "candidates")
    .sc_review_ids(candidate$markers, "candidate.markers", FALSE)
  }
  for (model in data$models) {
    fields <- c("clusterId", "callId", "provider", "mode", "strictStatus", "strict", "posthoc", "rawText", "source")
    .sc_review_object(model, "model", fields, fields)
    if (!is.character(model$clusterId) || !model$clusterId %in% names(scopes)) .sc_review_fail("scope_mismatch", "Model refers to unknown cluster.", "models")
    for (name in c("callId", "provider", "mode", "source")) .sc_review_string(model[[name]], paste0("model.", name))
    if (model$callId %in% calls_seen) .sc_review_fail("duplicate_evidence", "Duplicate model call ID.", "models")
    calls_seen <- c(calls_seen, model$callId)
    if (!is.character(model$strictStatus) || !model$strictStatus %in% c("not_run", "valid", "format_rejected", "network_failed")) .sc_review_fail("invalid_status", "Unknown strict model status.", "models")
    .sc_review_object(model$strict, "model.strict"); .sc_review_object(model$posthoc, "model.posthoc")
    if ("status" %in% names(model$strict) && !identical(model$strict$status, model$strictStatus)) .sc_review_fail("invalid_status", "Strict status fields disagree.", "models")
    if (model$strictStatus == "valid") .sc_review_string(model$strict$label, "model.strict.label")
    if (!is.null(model$rawText) && (!is.character(model$rawText) || length(model$rawText) != 1L)) .sc_review_fail("invalid_structure", "Model raw response must be text or null.", "models")
  }
  if ("sourceAnnotation" %in% names(data)) {
    annotation <- .sc_review_object(data$sourceAnnotation, "sourceAnnotation", c("column", "role", "values"), c("column", "role", "values"))
    .sc_review_string(annotation$column, "sourceAnnotation.column")
    if (!identical(annotation$role, "source_context")) .sc_review_fail("source_context", "Original annotation must be source context.", "sourceAnnotation.role")
    seen <- character()
    for (row in .sc_review_array(annotation$values, "sourceAnnotation.values")) {
      .sc_review_object(row, "source annotation row", c("cellId", "value"), c("cellId", "value"))
      if (!is.character(row$cellId) || !row$cellId %in% cell_ids || row$cellId %in% seen) .sc_review_fail("scope_mismatch", "Source annotation has duplicate or foreign cells.", "sourceAnnotation.values")
      if (!is.null(row$value) && (!is.character(row$value) || length(row$value) != 1L)) .sc_review_fail("source_context", "Source annotations preserve nullable strings.", "sourceAnnotation.values")
      seen <- c(seen, row$cellId)
    }
    if (!setequal(seen, cell_ids)) .sc_review_fail("scope_mismatch", "Source annotation must cover every cell.", "sourceAnnotation.values")
  }
  .sc_review_object(data$parameters, "project.parameters"); .sc_review_object(data$provenance, "project.provenance")
  directed <- .sc_review_object(data$directed, "project.directed", c("panel", "clusters"), c("panel", "clusters"))
  if (!identical(directed$panel, "T_NK.v1")) .sc_review_fail("unsupported_schema", "Unknown directed panel.", "directed.panel")
  .sc_review_object(directed$clusters, "directed.clusters"); assets <- "project.json"
  for (id in names(directed$clusters)) {
    if (!id %in% names(scopes)) .sc_review_fail("scope_mismatch", "Directed asset targets unknown cluster.", id)
    asset <- .sc_review_object(directed$clusters[[id]], "directed asset", c("path", "sha256"), c("path", "sha256"))
    path <- .sc_review_relative(asset$path); .sc_review_hash(asset$sha256, "directed asset SHA")
    idx <- match(path, paths)
    if (path == "project.json" || !endsWith(path, ".json") || is.na(idx) || !identical(asset$sha256, files[[idx]]$sha256)) .sc_review_fail("asset_checksum", "Directed asset reference is inconsistent.", path)
    content <- .sc_review_file_json(file.path(root, path))
    .sc_review_object(content, "directed expression", c("schema_version", "source", "scope", "cells"))
    if (!identical(content$schema_version, "scAgentKit.directed_expression.v2")) .sc_review_fail("unsupported_schema", "Unknown directed expression schema.", path)
    source <- .sc_review_object(content$source, "directed source", c("object_fingerprint", "assay", "layers"))
    layers <- .sc_review_object(source$layers, "directed source layers", c("counts", "data"), c("counts", "data"))
    if (!identical(source$object_fingerprint, manifest$sourceFingerprint) || !identical(source$assay, "RNA") ||
        !identical(source$assay, identity$assay) || !identical(layers$counts, identity$countsLayer) || !identical(layers$data, identity$normalizedLayer))
      .sc_review_fail("source_identity", "Directed assay, layers or fingerprint differ from the project.", path)
    scope <- .sc_review_object(content$scope, "directed scope", c("cluster_id", "n_cells", "cell_ids"))
    expected <- scopes[[id]][order(enc2utf8(scopes[[id]]), method = "radix")]
    if (!identical(scope$cluster_id, id) || !identical(scope$n_cells, as.numeric(length(expected))) ||
        !identical(unname(.sc_review_ids(scope$cell_ids, "directed cell_ids")), unname(expected)))
      .sc_review_fail("scope_mismatch", "Directed expression scope differs from the exact cluster.", path)
    seen <- character()
    for (row in .sc_review_array(content$cells, "directed cells")) {
      .sc_review_object(row, "directed observation", c("cell_id", "counts", "normalized"))
      cell <- .sc_review_string(row$cell_id, "directed cell_id", 1024L)
      if (!cell %in% expected || cell %in% seen || ("cluster_id" %in% names(row) && !identical(row$cluster_id, id)))
        .sc_review_fail("scope_mismatch", "Directed observation has duplicate or foreign cells.", path)
      seen <- c(seen, cell)
      for (field in c("counts", "normalized")) {
        values <- .sc_review_object(row[[field]], paste0("directed ", field))
        for (value in values) if (!is.null(value)) {
          .sc_review_number(value, "directed measurement", integer = field == "counts")
          if (value < 0) .sc_review_fail("invalid_number", "Directed measurements cannot be negative.", path)
        }
      }
    }
    if (!setequal(seen, expected)) .sc_review_fail("scope_mismatch", "Directed observations do not cover their exact scope.", path)
    assets <- c(assets, path)
  }
  if (!setequal(paths, assets) || anyDuplicated(assets)) .sc_review_fail("unlisted_asset", "Unreferenced or duplicate assets.", "manifest.files")
  list(manifest = manifest, identity = identity, cell_ids = cell_ids, cluster_ids = cluster_ids, scopes = scopes)
}
.sc_review_load_journal <- function(journal, project) {
  .sc_review_string(journal, "journal file", 8192L); data <- .sc_review_file_json(journal, integer_sequence = TRUE)
  fields <- c("schema", "projectId", "sourceFingerprint", "bundleDigest", "events", "artifacts")
  .sc_review_object(data, "journal", fields, fields)
  if (!identical(data$schema, "scagentkit.review-journal.v1")) .sc_review_fail("unsupported_schema", "Legacy PBMC handoffs have no generic source identity and cannot be written back.", "journal.schema")
  for (name in c("projectId", "sourceFingerprint", "bundleDigest")) if (!identical(data[[name]], project$manifest[[name]])) .sc_review_fail("journal_identity", "Journal belongs to a different source or snapshot.", paste0("journal.", name))
  artifacts <- .sc_review_object(data$artifacts, "journal.artifacts"); artifact_contents <- list()
  if (length(artifacts) > 1000L) .sc_review_fail("file_limit", "Too many artifacts.", "journal.artifacts")
  for (key in names(artifacts)) {
    .sc_review_string(key, "artifact key", 512L)
    artifact <- .sc_review_object(artifacts[[key]], "artifact", c("payload", "sha256"), c("payload", "sha256"))
    .sc_review_string(artifact$payload, "artifact.payload", 8 * 1024^2); .sc_review_hash(artifact$sha256, "artifact.sha256")
    if (!identical(.sc_review_text_sha(artifact$payload), artifact$sha256)) .sc_review_fail("artifact_checksum", "Artifact payload checksum mismatch.", key)
    content <- .sc_review_json(artifact$payload, "artifact.payload")
    .sc_review_object(content, "artifact.payload"); artifact_contents[[key]] <- content
  }
  envelopes <- .sc_review_array(data$events, "journal.events")
  if (length(envelopes) > 10000L) .sc_review_fail("file_limit", "Too many events.", "journal.events")
  prev <- paste(rep("0", 64L), collapse = ""); ids <- requests <- character(); active <- parsed <- list()
  key_for <- function(scope) paste0(nchar(scope$clusterId, type = "bytes"), ":", scope$clusterId, ":", scope$dimension)
  for (i in seq_along(envelopes)) {
    envelope <- .sc_review_object(envelopes[[i]], "envelope", c("sequence", "payload", "prevHash", "hash"), c("sequence", "payload", "prevHash", "hash"))
    if (!identical(envelope$sequence, as.numeric(i)) || !identical(envelope$prevHash, prev)) .sc_review_fail("history_chain", "Invalid sequence or predecessor hash.", as.character(i))
    .sc_review_string(envelope$payload, "event.payload", 2 * 1024^2); .sc_review_hash(envelope$hash, "event.hash")
    if (!identical(.sc_review_text_sha(paste0(prev, "\n", envelope$payload)), envelope$hash)) .sc_review_fail("history_chain", "Original payload bytes disagree with history hash.", as.character(i))
    event <- .sc_review_json(envelope$payload, paste0("event[", i, "]"), integer_sequence = TRUE); kind <- event$kind
    common <- c("id", "sequence", "kind", "createdAt", "requestId", "requestDigest", "reason", "scope")
    extra <- if (identical(kind, "decision")) c("label", "status", "supersedes") else if (identical(kind, "undo")) "targetEventId" else character()
    if (!length(extra)) .sc_review_fail("event_kind", "Unsupported event kind.", as.character(i))
    .sc_review_object(event, "event", c(common, extra), c(common, extra, if (identical(kind, "decision")) "evidenceRefs"))
    if (!identical(event$sequence, as.numeric(i))) .sc_review_fail("history_chain", "Payload sequence mismatch.", as.character(i))
    .sc_review_string(event$id, "event.id", 512L); .sc_review_string(event$requestId, "event.requestId", 160L)
    if (event$id %in% ids || event$requestId %in% requests) .sc_review_fail("duplicate_event", "Duplicate event or request IDs.", as.character(i))
    ids <- c(ids, event$id); requests <- c(requests, event$requestId)
    .sc_review_hash(event$requestDigest, "event.requestDigest")
    .sc_review_timestamp(event$createdAt); .sc_review_string(event$reason, "event.reason", 4000L)
    scope_fields <- c("datasetId", "revision", "sourceFingerprint", "clusterId", "dimension", "cellIds")
    scope <- .sc_review_object(event$scope, "event.scope", scope_fields, scope_fields)
    if (!identical(scope$datasetId, data$projectId) || !identical(scope$revision, data$bundleDigest) || !identical(scope$sourceFingerprint, data$sourceFingerprint) ||
        !is.character(scope$clusterId) || length(scope$clusterId) != 1L || !scope$clusterId %in% names(project$scopes) ||
        !is.character(scope$dimension) || length(scope$dimension) != 1L || !scope$dimension %in% c("type", "state", "QC"))
      .sc_review_fail("scope_mismatch", "Event targets another source, cluster or dimension.", as.character(i))
    scope_ids <- .sc_review_ids(scope$cellIds, "scope.cellIds")
    if (!identical(unname(scope_ids), unname(scope_ids[order(enc2utf8(scope_ids), method = "radix")]))) .sc_review_fail("invalid_ids", "Journal scope cell IDs must be sorted.", as.character(i))
    if (!setequal(scope_ids, project$scopes[[scope$clusterId]])) .sc_review_fail("scope_mismatch", "Event cell-ID set must exactly cover its declared cluster.", as.character(i))
    if ("evidenceRefs" %in% names(event)) {
      refs <- .sc_review_ids(event$evidenceRefs, "event.evidenceRefs", FALSE)
      if (length(refs) > 8L) .sc_review_fail("file_limit", "At most eight evidence references are permitted.", as.character(i))
      if (any(!refs %in% names(artifacts))) .sc_review_fail("missing_artifact", "Event references missing artifacts.", as.character(i))
      for (reference in refs) {
        content <- artifact_contents[[reference]]; claims_list <- list(content)
        if ("scope" %in% names(content)) claims_list <- append(claims_list, list(content$scope))
        if (inherits(content$provisional, "sc_review_object") && "scope" %in% names(content$provisional)) claims_list <- append(claims_list, list(content$provisional$scope))
        expected <- list(projectId = scope$datasetId, datasetId = scope$datasetId, revision = scope$revision,
          sourceFingerprint = scope$sourceFingerprint, clusterId = scope$clusterId, cellIds = scope_ids, dimension = scope$dimension)
        for (claims in claims_list) {
          .sc_review_object(claims, "artifact scope")
          for (name in intersect(names(expected), names(claims))) {
            actual <- if (name == "cellIds") .sc_review_ids(claims[[name]], "artifact.cellIds") else claims[[name]]
            if (!identical(unname(actual), unname(expected[[name]]))) .sc_review_fail("artifact_scope", "Evidence artifact claims differ from the decision scope.", as.character(i))
          }
        }
      }
    }
    key <- key_for(scope); stack <- active[[key]]; if (is.null(stack)) stack <- integer()
    if (kind == "decision") {
      .sc_review_string(event$label, "event.label", 160L)
      if (!is.character(event$status) || length(event$status) != 1L || !event$status %in% c("proposed", "reviewed", "accepted")) .sc_review_fail("event_status", "Unsupported workflow status.", as.character(i))
      previous <- if (length(stack)) parsed[[tail(stack, 1L)]]$id else NULL
      if (!identical(event$supersedes, previous)) .sc_review_fail("history_conflict", "Decision must supersede the current active decision.", as.character(i))
      stack <- c(stack, i)
    } else {
      .sc_review_string(event$targetEventId, "event.targetEventId", 512L)
      if (!length(stack) || !identical(event$targetEventId, parsed[[tail(stack, 1L)]]$id)) .sc_review_fail("undo_conflict", "Undo must target the current active decision in this exact scope.", as.character(i))
      stack <- head(stack, -1L)
    }
    active[[key]] <- stack; parsed[[i]] <- event; prev <- envelope$hash
  }
  list(events = parsed, active = active, key_for = key_for)
}
.sc_review_columns <- function(columns, metadata) {
  if (!is.character(columns) || !length(columns) || is.null(names(columns)) || anyNA(columns) || anyNA(names(columns)) ||
      anyDuplicated(names(columns)) || any(!names(columns) %in% c("type", "state", "QC")) || any(!nzchar(trimws(columns))) || any(nchar(columns, type = "bytes") > 128L))
    .sc_review_fail("invalid_columns", "columns must map unique type/state/QC dimensions to new names.", "columns")
  suffixes <- c("", "_review_state", "_workflow_status", "_decision_id", "_source_fingerprint", "_bundle_digest")
  targets <- unlist(lapply(unname(columns), paste0, suffixes), use.names = FALSE)
  if (anyDuplicated(targets) || any(targets %in% colnames(metadata))) .sc_review_fail("column_collision", "All label and companion columns must be new and mutually distinct.", "columns")
  targets
}

#' Validate a portable human review against its original Seurat object
#' @param object Seurat or AgentSeurat wrapping exactly one Seurat object.
#' @param journal Path to a generic review-journal JSON file.
#' @param project Path to its verified evidence project directory.
#' @param columns Named vector mapping type, state or QC dimensions to new label
#'   columns. Companion names are derived by appending documented suffixes.
#' @return List with valid, structured errors/warnings, per-cell mapping,
#'   coverage, target columns and source identity. No input is changed.
#' @export
sc_review_validate <- function(object, journal, project, columns = c(type = "review_type")) {
  issues <- function() data.frame(code = character(), message = character(), path = character(), stringsAsFactors = FALSE)
  report <- list(valid = FALSE, errors = issues(), warnings = issues(), mapping = data.frame(), coverage = data.frame(), columns = character(), identity = NULL)
  tryCatch({
    seu <- .sc_project_unwrap(object); report$columns <- .sc_review_columns(columns, seu@meta.data)
    source <- .sc_review_load_project(project)
    current <- .sc_project_identity(seu, source$identity$assay, source$identity$countsLayer, source$identity$normalizedLayer, source$identity$clusterColumn)
    public <- c("algorithm", "fingerprint", "assay", "countsLayer", "normalizedLayer", "clusterColumn", "cellCount", "featureCount", "cellsHash", "featuresHash", "membershipHash", "countsHash", "dataHash")
    report$identity <- current[public]
    equal <- vapply(public, function(name) isTRUE(all.equal(current[[name]], source$identity[[name]], check.attributes = FALSE)), logical(1))
    if (!all(equal)) .sc_review_fail("source_mismatch", paste0("Object source differs: ", paste(public[!equal], collapse = ", "), "."), "object")
    cells <- colnames(seu)
    if (anyDuplicated(cells) || !setequal(cells, source$cell_ids)) .sc_review_fail("cell_set_mismatch", "Object must have exactly the exported cell-ID set.", "object")
    clusters <- source$cluster_ids[match(cells, source$cell_ids)]
    if (!identical(unname(as.character(seu@meta.data[cells, source$identity$clusterColumn])), unname(clusters))) .sc_review_fail("membership_mismatch", "Per-cell cluster membership changed.", "object")
    history <- .sc_review_load_journal(journal, source); mappings <- coverage <- list()
    for (dimension in names(columns)) {
      result <- data.frame(cellId = cells, clusterId = clusters, dimension = dimension, column = unname(columns[[dimension]]), label = NA_character_,
        reviewState = "unreviewed", workflowStatus = NA_character_, decisionId = NA_character_, sourceFingerprint = source$manifest$sourceFingerprint,
        bundleDigest = source$manifest$bundleDigest, stringsAsFactors = FALSE)
      for (cluster in names(source$scopes)) {
        stack <- history$active[[history$key_for(list(clusterId = cluster, dimension = dimension))]]
        if (!length(stack)) next
        event <- history$events[[tail(stack, 1L)]]; rows <- result$clusterId == cluster
        result$workflowStatus[rows] <- event$status; result$decisionId[rows] <- event$id
        if (event$status == "accepted") {
          result$label[rows] <- event$label
          result$reviewState[rows] <- if (identical(event$label, "unknown")) "abstained" else "labeled"
        } else result$reviewState[rows] <- "deferred"
      }
      mappings[[dimension]] <- result; states <- c("labeled", "abstained", "deferred", "unreviewed")
      coverage[[dimension]] <- data.frame(dimension = dimension, state = states,
        cells = vapply(states, function(state) as.integer(sum(result$reviewState == state)), integer(1)), totalCells = length(cells), stringsAsFactors = FALSE)
    }
    report$mapping <- do.call(rbind, mappings); rownames(report$mapping) <- NULL
    report$coverage <- do.call(rbind, coverage); rownames(report$coverage) <- NULL
    if (any(report$mapping$reviewState != "labeled")) report$warnings <- data.frame(code = "partial_review", message = "Abstained, deferred or unreviewed cells remain explicit; only current accepted decisions write labels.", path = "journal", stringsAsFactors = FALSE)
    report$valid <- TRUE; report
  }, error = function(error) {
    report$errors <- data.frame(code = if (inherits(error, "sc_review_validation_error")) error$code else "invalid_input", message = conditionMessage(error),
      path = if (inherits(error, "sc_review_validation_error")) error$path else "input", stringsAsFactors = FALSE)
    report
  })
}

#' Apply verified review decisions to new metadata columns
#' @inheritParams sc_review_validate
#' @return A modified copy of the same object kind. Existing metadata, identities,
#'   assays, reductions and wrapper history are preserved. Save separately.
#' @export
sc_review_apply <- function(object, journal, project, columns = c(type = "review_type")) {
  report <- sc_review_validate(object, journal, project, columns)
  if (!isTRUE(report$valid)) stop(structure(list(message = paste0("Review writeback refused: ", paste(report$errors$message, collapse = "; ")), call = NULL, report = report), class = c("sc_review_apply_error", "error", "condition")))
  seu <- .sc_project_unwrap(object); metadata <- seu@meta.data
  for (dimension in names(columns)) {
    mapping <- report$mapping[report$mapping$dimension == dimension, , drop = FALSE]
    mapping <- mapping[match(rownames(metadata), mapping$cellId), , drop = FALSE]
    if (anyNA(mapping$cellId)) .sc_review_fail("cell_set_mismatch", "Metadata cannot align by exact cell ID.", "object")
    fields <- c("label", "reviewState", "workflowStatus", "decisionId", "sourceFingerprint", "bundleDigest")
    suffixes <- c("", "_review_state", "_workflow_status", "_decision_id", "_source_fingerprint", "_bundle_digest")
    for (i in seq_along(fields)) metadata[[paste0(unname(columns[[dimension]]), suffixes[i])]] <- mapping[[fields[i]]]
  }
  seu@meta.data <- metadata
  if (inherits(object, "Seurat")) return(seu)
  output <- object
  if (inherits(output@data, "Seurat")) output@data <- seu else output@data[[1L]] <- seu
  output
}
