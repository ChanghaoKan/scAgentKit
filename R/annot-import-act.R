#' Import an explicit local ACT marker reference without network access
#' @param path Local CSV/TSV/TXT/XLSX file. No file is downloaded automatically.
#' @param species Explicit human or mouse scope.
#' @param tissue Required nonempty literal tissue filter, case insensitive.
#' @param columns Named character vector mapping species,tissue,cell_type,marker,
#'   pmid to actual source headers. Defaults to those exact canonical headers.
#' @param source_version,source_date Publisher version and ISO date if known;
#'   NULL records unavailable rather than inventing an ACT release.
#' @param sha256 Optional expected local file SHA256; not publisher authentication.
#' @param sheet Explicit source sheet name/index for XLSX; no guessed first sheet.
#' @return Scoped local reference retaining original PMID strings/source rows,
#'   observed SHA256, unverified publisher provenance and ACT independent source.
#' @export
annot_import_act <- function(path=NULL,species,tissue,columns=NULL,
                             source_version=NULL,source_date=NULL,sha256=NULL,sheet=NULL) {
  if(is.null(path))stop(paste("The default ACT reference is unavailable without a verified local file.",
    "The official HTTPS source could not be securely retrieved during validation; do not bypass certificate warnings.",
    "Use a lawfully held original ACT CSV/TSV/XLSX file, or wait for valid publisher HTTPS at https://xteam.xbio.top/ACT/download.jsp.",
    "Map its species, tissue, cell_type, marker and pmid headers explicitly; local import never authenticates a publisher URL."),call.=FALSE)
  .sc_project_string(path,"ACT path")
  if(missing(species)||!is.character(species)||length(species)!=1L||is.na(species)||!species%in%c("human","mouse"))
    stop("Choose the actual ACT species: human or mouse.",call.=FALSE)
  if(missing(tissue)||!is.character(tissue)||length(tissue)!=1L||is.na(tissue)||!nzchar(trimws(tissue))||tolower(trimws(tissue))=="all")
    stop("Choose one actual ACT tissue; an all-tissue fallback is not supported.",call.=FALSE)
  tissue<-trimws(tissue)
  path<-normalizePath(path,mustWork=TRUE)
  if(dir.exists(path)||file.info(path)$size>128*1024^2)
    stop("ACT path must be a readable local table up to 128 MiB; no records are silently truncated.",call.=FALSE)
  observed<-digest::digest(file=path,algo="sha256")
  if(!is.null(sha256)&&(!is.character(sha256)||length(sha256)!=1L||is.na(sha256)||!identical(sha256,observed)))
    stop("The local ACT SHA256 does not match. Check the selected source file before import.",call.=FALSE)
  for(value in list(source_version,source_date))if(!is.null(value)).sc_project_string(value,"ACT source version/date")
  if(!is.null(source_date)&&(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$",source_date)||is.na(tryCatch(as.Date(source_date),error=function(e)as.Date(NA)))))
    stop("ACT source_date must be a known publisher date in YYYY-MM-DD format, or NULL if unknown.",call.=FALSE)
  required<-c("species","tissue","cell_type","marker","pmid")
  if(is.null(columns))columns<-stats::setNames(required,required)
  if(!is.character(columns)||is.null(names(columns))||anyDuplicated(names(columns))||!setequal(names(columns),required)||
      anyNA(columns)||any(!nzchar(columns))||anyDuplicated(unname(columns)))
    stop("columns must map each of species, tissue, cell_type, marker and pmid once to distinct actual source headers.",call.=FALSE)
  extension<-tolower(tools::file_ext(path))
  raw<-if(extension=="xlsx") {
    if(!requireNamespace("readxl",quietly=TRUE))stop("Configure the optional readxl dependency to read the original ACT XLSX file, or supply a faithful UTF-8 TSV export.",call.=FALSE)
    sheets<-readxl::excel_sheets(path)
    if(is.null(sheet)||length(sheet)!=1L||is.na(sheet)||
       !(is.character(sheet)&&sheet%in%sheets||is.numeric(sheet)&&is.finite(sheet)&&sheet==floor(sheet)&&sheet>=1&&sheet<=length(sheets)))
      stop("Select an explicit ACT XLSX sheet name/index and map its actual headers; no first sheet is guessed.",call.=FALSE)
    sheet<-if(is.numeric(sheet))sheets[[sheet]] else sheet
    as.data.frame(readxl::read_excel(path,sheet=sheet,col_types="text"),stringsAsFactors=FALSE)
  } else if(extension%in%c("csv","tsv","txt"))
    utils::read.table(path,header=TRUE,sep=if(extension=="csv")"," else "\t",quote="\"",comment.char="",check.names=FALSE,
      colClasses="character",na.strings=character(),fileEncoding="UTF-8",stringsAsFactors=FALSE)
  else stop("Supply ACT as local CSV, TSV/TXT (tab separated), or XLSX; do not rename another format.",call.=FALSE)
  if(anyDuplicated(names(raw))||!all(unname(columns)%in%names(raw)))
    stop("The ACT file headers do not match columns. Inspect its actual header and map species, tissue, cell_type, marker and pmid; official headers have not been assumed.",call.=FALSE)
  out<-as.data.frame(raw[,unname(columns[required]),drop=FALSE],stringsAsFactors=FALSE);names(out)<-required
  for(key in required)out[[key]]<-as.character(out[[key]])
  out$source_row<-seq_len(nrow(out))+1L
  for(key in required)out[[paste0("act_",key,"_original")]]<-out[[key]]
  for(key in c("species","tissue","cell_type","marker"))if(anyNA(out[[key]])||any(!nzchar(trimws(out[[key]]))))
    stop("ACT ",key," includes blank/missing values. Repair its explicit source mapping before import.",call.=FALSE)
  out$species<-.sc_run_species_values(out$species)
  if(anyNA(out$species)||any(!nzchar(out$species)))stop("ACT species contains unsupported labels; supply explicit human/mouse values without guessing orthologs.",call.=FALSE)
  out$tissue<-trimws(out$tissue);out$cell_type<-trimws(out$cell_type);out$marker<-trimws(out$marker)
  keep<-out$species==species&grepl(tolower(tissue),tolower(out$tissue),fixed=TRUE)&tolower(out$tissue)!="all"
  out<-out[keep,,drop=FALSE]
  out$source<-rep("ACT",nrow(out))
  out<-.explode_markers(out);rownames(out)<-NULL
  attr(out,"reference_source")<-"ACT"
  attr(out,"source_mode")<-"explicit_local_ACT_import_unverified_publisher"
  attr(out,"source_sheet")<-if(extension=="xlsx")sheet else NULL
  attr(out,"source_path")<-path;attr(out,"source_sha256")<-observed
  attr(out,"source_md5")<-unname(tools::md5sum(path))
  attr(out,"source_url")<-NA_character_;attr(out,"source_url_verified")<-FALSE
  attr(out,"requested_url")<-"https://xteam.xbio.top/ACT/download.jsp"
  attr(out,"source_version")<-if(is.null(source_version))"unversioned-user-local-input" else source_version
  attr(out,"source_date")<-if(is.null(source_date))NA_character_ else source_date
  attr(out,"imported_at")<-format(Sys.time(),tz="UTC",usetz=TRUE)
  attr(out,"license")<-"unknown-not-verified-for-redistribution"
  attr(out,"n_input_rows")<-nrow(raw);attr(out,"species")<-species;attr(out,"tissue_filter")<-tissue
  attr(out,"scope_status")<-if(nrow(out))"matched" else "zero_matches"
  attr(out,"scope_notice")<-if(nrow(out))"Local ACT rows match the explicit species/tissue filter. Original PMID strings and source rows are retained; overlap is descriptive evidence." else
    "No ACT records match the selected species and tissue. Check the scope or source file; no all-tissue fallback was used."
  out
}
