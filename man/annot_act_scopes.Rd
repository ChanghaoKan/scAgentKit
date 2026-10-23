\name{annot_act_scopes}
\alias{annot_act_scopes}
\title{List exact tissue scopes in the pinned ACT snapshot}
\usage{annot_act_scopes(species)}
\arguments{\item{species}{Explicit human or mouse scope.}}
\value{Data frame with literal tissue keys and source-row counts before marker expansion.}
\description{Verifies the pinned offline snapshot and lists its scopes. It does not select a scope, broaden study tissue or infer aliases or species.}
