"use strict";
// Display-only links from a fixed, versioned local official mapping snapshot.
// No species inference or remote gene request. Anchors navigate only on click.
(() => {
  const aliases = {
    human: ["human", "homo sapiens", "homo_sapiens", "homo-sapiens", "h. sapiens", "h.sapiens", "hsapiens", "9606"],
    mouse: ["mouse", "mus musculus", "mus_musculus", "mus-musculus", "m. musculus", "m.musculus", "mmusculus", "10090"]
  };
  function species(value) {
    if (typeof value !== "string" || !value.trim()) return {kind: "unknown", label: "species undeclared"};
    const canonical = value.trim().toLowerCase();
    for (const [kind, names] of Object.entries(aliases)) if (names.includes(canonical)) return {kind, label: kind};
    return {kind: "other", label: "other declared species"};
  }
  function encodedSymbol(gene) {
    if (typeof gene !== "string" || !gene.trim() || gene.length > 200 || /^[.]{1,2}$/.test(gene) || /[\x00-\x1f\x7f]/.test(gene)) return null;
    try {
      return encodeURIComponent(gene).replace(/[!'()*]/g, char => "%" + char.charCodeAt(0).toString(16).toUpperCase());
    } catch { return null; } // Malformed UTF-16 remains inert display text.
  }
  function destination(gene, declaredSpecies) {
    // Mouse has several possible destinations. Never choose one implicitly.
    const encoded = species(declaredSpecies).kind === "human" ? encodedSymbol(gene) : null;
    return encoded === null ? null : "https://www.genecards.org/card/" + encoded;
  }
  const entryFields = ["mgi_id", "mouse_symbol", "mouse_ncbi_gene_id", "aliases", "human_candidates", "alias_source_id"];
  const candidateFields = ["human_symbol", "human_ncbi_gene_id", "hgnc_id", "relation", "source_id", "source_line", "source_group_id"];
  const relations = new Set(["one_to_one_ortholog", "homology_group_candidate"]);
  const symbols = new Map(), aliasIndex = new Map();
  let mapInfo = Object.freeze({status: "unavailable", snapshot_id: null, entries: 0, alias_entries: 0, sources: Object.freeze([]), limitations: Object.freeze([])});
  function add(index, symbol, entry) {
    if (!index.has(symbol)) index.set(symbol, []);
    if (!index.get(symbol).some(value => value.mgi_id === entry.mgi_id)) index.get(symbol).push(entry);
  }
  function requireValue(condition) {if (!condition) throw new Error("Invalid local mouse mapping snapshot");}
  function digitId(value, nullable = false) {return (nullable && value === null) || typeof value === "string" && /^[1-9][0-9]*$/.test(value) && value.length <= 20;}
  function string(value, limit = 1000) {return typeof value === "string" && value.length > 0 && value.length <= limit && !/[\x00-\x1f\x7f]/.test(value);}
  function loadMapping() {
    const data = globalThis.ScMouseOrthologData;
    if (data === undefined) return;
    try {
      requireValue(data && data.schema === "scagentkit.mouse-ortholog-map.v1" && string(data.snapshot_id, 200));
      requireValue(JSON.stringify(data.entry_fields) === JSON.stringify(entryFields) && JSON.stringify(data.candidate_fields) === JSON.stringify(candidateFields));
      requireValue(Array.isArray(data.sources) && data.sources.length > 0 && data.sources.length <= 100);
      const sourceIds = new Set(), sources = data.sources.map(source => {
        requireValue(source && string(source.id, 200) && !sourceIds.has(source.id) && string(source.title) && string(source.url, 2000) && /^[a-f0-9]{64}$/.test(source.sha256) && Number.isSafeInteger(source.bytes) && source.bytes > 0);
        requireValue(string(source.fetched_at_utc, 200) && (source.last_modified === null || string(source.last_modified, 200)) && string(source.license));
        sourceIds.add(source.id);
        return Object.freeze({id: source.id, title: source.title, url: source.url, last_modified: source.last_modified, fetched_at_utc: source.fetched_at_utc, sha256: source.sha256, bytes: source.bytes, license: source.license});
      });
      requireValue(Array.isArray(data.entries) && data.entries.length > 0 && data.entries.length <= 50000);
      requireValue(Array.isArray(data.limitations) && data.limitations.every(value => string(value, 4000)));
      const ids = new Set(); let aliasEntries = 0;
      for (const row of data.entries) {
        requireValue(Array.isArray(row) && row.length === entryFields.length);
        const [mgiId, mouseSymbol, mouseNcbiId, aliases, candidates, aliasSource] = row;
        requireValue(typeof mgiId === "string" && /^MGI:[1-9][0-9]*$/.test(mgiId) && mgiId.length <= 30 && !ids.has(mgiId));
        requireValue(encodedSymbol(mouseSymbol) !== null && digitId(mouseNcbiId, true));
        requireValue(Array.isArray(aliases) && aliases.length <= 500 && aliases.every(value => encodedSymbol(value) !== null));
        requireValue(aliases.length ? sourceIds.has(aliasSource) : aliasSource === null);
        requireValue(Array.isArray(candidates) && candidates.length <= 500);
        const humanCandidates = candidates.map(candidate => {
          requireValue(Array.isArray(candidate) && candidate.length === candidateFields.length);
          const [humanSymbol, humanNcbiId, hgncId, relation, sourceId, sourceLine, sourceGroupId] = candidate;
          requireValue(encodedSymbol(humanSymbol) !== null && digitId(humanNcbiId) && (hgncId === null || typeof hgncId === "string" && /^HGNC:[1-9][0-9]*$/.test(hgncId) && hgncId.length <= 30));
          requireValue(relations.has(relation) && sourceIds.has(sourceId) && Number.isSafeInteger(sourceLine) && sourceLine > 0 && (sourceGroupId === null || string(sourceGroupId, 200)));
          return Object.freeze({human_symbol: humanSymbol, human_ncbi_gene_id: humanNcbiId, hgnc_id: hgncId, relation, source_id: sourceId, source_line: sourceLine, source_group_id: sourceGroupId});
        });
        const entry = Object.freeze({mgi_id: mgiId, mouse_symbol: mouseSymbol, mouse_ncbi_gene_id: mouseNcbiId, aliases: Object.freeze([...new Set(aliases)]), human_candidates: Object.freeze(humanCandidates), alias_source_id: aliasSource});
        ids.add(mgiId); add(symbols, mouseSymbol, entry);
        for (const alias of entry.aliases) add(aliasIndex, alias, entry);
        if (entry.aliases.length) aliasEntries++;
      }
      for (const index of [symbols, aliasIndex]) for (const [key, value] of index) index.set(key, Object.freeze(value));
      mapInfo = Object.freeze({status: "available", snapshot_id: data.snapshot_id, entries: ids.size, alias_entries: aliasEntries, sources: Object.freeze(sources), limitations: Object.freeze([...data.limitations])});
    } catch {
      // Partial or malformed mappings never retain partially accepted links.
      symbols.clear(); aliasIndex.clear();
      mapInfo = Object.freeze({status: "invalid", snapshot_id: null, entries: 0, alias_entries: 0, sources: Object.freeze([]), limitations: Object.freeze([])});
    }
  }
  loadMapping();
  function mappingInfo() {return mapInfo;}
  function lookup(gene, declaredSpecies) {
    const kind = species(declaredSpecies).kind;
    let status = kind !== "mouse" ? "unsupported_species" : encodedSymbol(gene) === null ? "invalid_symbol" : mapInfo.status !== "available" ? "mapping_" + mapInfo.status : "unmapped";
    let records = Object.freeze([]), matchType = null;
    if (status === "unmapped") {
      if (symbols.has(gene)) {records = symbols.get(gene); matchType = "symbol";}
      else if (aliasIndex.has(gene)) {records = aliasIndex.get(gene); matchType = "alias";}
      if (records.length) status = "matched";
    }
    return Object.freeze({status, query: typeof gene === "string" ? gene : null, match_type: matchType, mouse_records: records, ambiguous: records.length > 1 || records.some(record => new Set(record.human_candidates.map(value => value.human_ncbi_gene_id)).size > 1), snapshot_id: mapInfo.snapshot_id});
  }
  function note(declaredSpecies) {
    const value = species(declaredSpecies);
    if (value.kind === "human") return "Human GeneCards lookups open in a new tab only when a gene is clicked; entry existence is not verified. The clicked symbol is sent to GeneCards. No gene list is uploaded or fetched.";
    if (value.kind === "mouse") {
      const coverage = mapInfo.status === "available" ? "Local official snapshot " + mapInfo.snapshot_id + ": " + mapInfo.entries + " mouse records; official aliases for " + mapInfo.alias_entries + " records only. Exact symbols take priority over case-sensitive official aliases. Every supplied human candidate is shown; homology-group candidates are distinct from recorded one-to-one orthologs." : "The local official mouse mapping is " + (mapInfo.status === "invalid" ? "invalid" : "unavailable") + "; mouse links stay unavailable.";
      return coverage + " GeneCards focuses on human entries and can include mouse ortholog information; MGI opens the mouse record. Links open only when clicked, sending one mapped symbol or MGI ID to that site. No gene list is uploaded or fetched; entry existence and external content are not verified.";
    }
    return (value.kind === "unknown" ? "Species is undeclared." : "This declared species has no supported GeneCards mapping.") + " GeneCards is a human gene database; no direct link or species inference is offered.";
  }
  function anchor(text, href, attributes = {}) {
    const result = document.createElement("a"); result.textContent = text;
    result.setAttribute("href", href); result.setAttribute("target", "_blank"); result.setAttribute("rel", "noopener noreferrer"); result.setAttribute("referrerpolicy", "no-referrer");
    for (const [name, value] of Object.entries(attributes)) result.setAttribute(name, value);
    return result;
  }
  function mouseLinks(wrapper, gene) {
    const result = lookup(gene, "mouse"), label = document.createElement("small"); label.setAttribute("class", "gene-lookup-label");
    wrapper.setAttribute("data-gene-match", result.status);
    if (result.status !== "matched") {
      label.textContent = result.status === "unmapped" ? "mouse · no exact symbol or official alias in this local snapshot; no ortholog absence inferred" : result.status === "invalid_symbol" ? "mouse · unusable lookup symbol" : "mouse · local official mapping " + (mapInfo.status === "invalid" ? "invalid" : "unavailable");
      wrapper.append(label); return;
    }
    label.textContent = "mouse · " + (result.match_type === "alias" ? "official alias" : "exact official symbol") + (result.ambiguous ? " · multiple candidates retained" : "");
    wrapper.append(label);
    for (const record of result.mouse_records) {
      const row = document.createElement("span"); row.setAttribute("class", "gene-lookup-mouse-record"); row.setAttribute("data-mgi-id", record.mgi_id);
      const mouseLabel = "Mouse " + record.mouse_symbol + " · MGI ↗";
      row.append(anchor(mouseLabel, "https://www.informatics.jax.org/accession/" + encodeURIComponent(record.mgi_id), {"data-gene-lookup-kind": "mgi", "data-mgi-id": record.mgi_id, "aria-label": mouseLabel + ", new tab; external entry not verified", title: "Open the recorded mouse MGI accession; local mapping " + mapInfo.snapshot_id}));
      for (const candidate of record.human_candidates) {
        const relationship = candidate.relation === "one_to_one_ortholog" ? "recorded one-to-one ortholog" : "homology-group candidate";
        const humanLabel = "Human " + candidate.human_symbol + " · GeneCards ↗ · " + relationship;
        row.append(anchor(humanLabel, destination(candidate.human_symbol, "human"), {"data-gene-lookup-kind": "human-ortholog", "data-gene-symbol": candidate.human_symbol, "data-ortholog-relation": candidate.relation, "aria-label": humanLabel + ", new tab; external entry not verified", title: "Official mapping source " + candidate.source_id + ", row " + candidate.source_line + "; " + relationship + "; snapshot " + mapInfo.snapshot_id}));
      }
      if (!record.human_candidates.length) {const empty = document.createElement("small"); empty.textContent = "No human candidate supplied in this snapshot"; row.append(empty);}
      wrapper.append(row);
    }
  }
  function render(gene, declaredSpecies) {
    const value = species(declaredSpecies), wrapper = document.createElement("span"), href = destination(gene, declaredSpecies);
    wrapper.setAttribute("class", "gene-lookup"); wrapper.setAttribute("data-gene-species", value.kind);
    const symbol = document.createElement(href ? "a" : "span");
    symbol.textContent = typeof gene === "string" ? gene : "Unavailable gene";
    if (href) {
      symbol.setAttribute("href", href); symbol.setAttribute("target", "_blank");
      symbol.setAttribute("rel", "noopener noreferrer"); symbol.setAttribute("referrerpolicy", "no-referrer");
      symbol.setAttribute("data-gene-symbol", gene);
      symbol.setAttribute("aria-label", gene + " · human GeneCards lookup, new tab; entry not verified");
      symbol.setAttribute("title", "Open human GeneCards lookup; this entry has not been verified");
    }
    if (value.kind === "mouse") {wrapper.append(symbol); mouseLinks(wrapper, gene); return wrapper;}
    const label = document.createElement("small"); label.setAttribute("class", "gene-lookup-label");
    label.textContent = href ? "human · GeneCards ↗" : value.kind === "human" ? "human · link unavailable" : value.label + " · no GeneCards mapping";
    wrapper.append(symbol, label); return wrapper;
  }
  function list(genes, declaredSpecies) {
    const result = document.createElement("span"), values = genes == null ? [] : Array.isArray(genes) ? genes : [genes];
    if (!values.length) result.textContent = "none";
    values.forEach((gene, index) => {if (index) result.append(document.createTextNode(", ")); result.append(render(gene, declaredSpecies));});
    return result;
  }
  globalThis.ScGeneCards = Object.freeze({species, destination, note, render, list, lookup, mappingInfo});
})();
