# Run with Rscript --vanilla tools/environment/restore.R CACHE EMPTY_LIBRARY
# Uses only local, hash-verified archives. Does not call install.packages/remotes.
args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==2L)
if (as.character(getRversion())!='4.5.2') stop('This recipe requires exact R 4.5.2; no cross-version migration.')
cache <- normalizePath(args[1],mustWork=TRUE)
lib <- args[2]
if (dir.exists(lib) && length(list.files(lib,all.files=TRUE,no..=TRUE))) stop('Target library must be empty.')
dir.create(lib,recursive=TRUE,showWarnings=FALSE); lib <- normalizePath(lib)
base_lib <- .Library
initial <- installed.packages(lib.loc=base_lib)
if (any(is.na(initial[,'Priority']) | !initial[,'Priority'] %in% c('base','recommended'))) stop('Base library has non-base dependencies; use the clean container.')
Sys.setenv(R_PROFILE='/dev/null',R_PROFILE_USER='/dev/null',R_ENVIRON='/dev/null',R_ENVIRON_USER='/dev/null',R_INSTALL_VANILLA='true',R_LIBS=lib,R_LIBS_SITE=lib,R_LIBS_USER=lib)
.libPaths(c(lib,base_lib),include.site=FALSE)
# Reverify every archive immediately before installation; no network operation.
script_arg <- grep('^--file=',commandArgs(),value=TRUE)
if (length(script_arg)!=1L) stop('Invoke this script with Rscript --vanilla.')
audit_script <- file.path(dirname(normalizePath(sub('^--file=','',script_arg))), 'audit.py')
python <- Sys.which('python3')
if (!nzchar(python) || system2(python,c(shQuote(audit_script),shQuote(cache)))!=0L) stop('Source/dependency audit failed.')
expected_base <- read.delim(file.path(cache,'verified-base-library.tsv'),colClasses='character')
if (!setequal(rownames(initial),expected_base$package) || any(initial[expected_base$package,'Version']!=expected_base$version)) stop('Base/recommended versions differ from the verified container.')
# Python performs SHA256 verification and dependency ordering before R executes.
manifest <- file.path(cache,'verified-install-order.tsv')
if (!file.exists(manifest)) stop('Run audit.py first to verify bytes and create dependency order.')
rows <- read.delim(manifest,colClasses='character',check.names=FALSE)
for (i in seq_len(nrow(rows))) {
 archive <- file.path(cache,rows$file[i])
 status <- system2(file.path(R.home('bin'),'R'),c('CMD','INSTALL','--no-multiarch',paste0('--library=',shQuote(lib)),shQuote(archive)))
 if (status!=0L) stop('Local archive installation failed: ',rows$package[i])
}
ip <- installed.packages(lib.loc=lib)
if (!setequal(rownames(ip),rows$package) || any(ip[rows$package,'Version']!=rows$version)) stop('Installed versions differ from lock.')
loadNamespace('scAgentKit')
source(system.file('examples','simple-analysis.R',package='scAgentKit'))
result <- simple_analysis_after(tempfile('restore-offline-'))
stopifnot(inherits(result,'Seurat'),ncol(result)>0)
print(sessionInfo());cat('Exact source recipe installation and offline software example passed.\n')
