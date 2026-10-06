"use strict";
// Read-only presentation of supplied coordinates and marker statistics.
// Selection is a local callback; this helper has no persistence or transport.
(() => {
  const palette = ["#759bd1", "#e4a675", "#73b3aa", "#9881c8", "#ce899d", "#9bad6e", "#3d67d7", "#bc9b5e", "#799da6"];
  const ns = "http://www.w3.org/2000/svg";
  function node(tag, attrs = {}, text) {
    const result = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) result.setAttribute(key, String(value));
    if (text !== undefined && text !== null) result.textContent = String(text);
    return result;
  }
  function svgNode(tag, attrs = {}, text) {
    const result = document.createElementNS(ns, tag);
    for (const [key, value] of Object.entries(attrs)) result.setAttribute(key, String(value));
    if (text !== undefined && text !== null) result.textContent = String(text);
    return result;
  }
  const validId = value => typeof value === "string" || (typeof value === "number" && Number.isFinite(value));
  const suppliedText = value => value === undefined ? "—" : value !== null && typeof value === "object" ? JSON.stringify(value) : String(value);
  const numericText = value => value === undefined || value === null || value === "" ? "—" : suppliedText(value);

  function embedding(target, {points, clusters, name = "Embedding", title, selectedCluster, onSelect, showAll = true} = {}) {
    target.replaceChildren();
    const embeddingName = name === undefined || name === null || name === "" ? "Embedding" : String(name);
    target.append(node("h3", {class: "embedding-title", "data-testid": "embedding-title"}, embeddingName));
    const unavailable = message => {
      target.append(node("p", {class: "embedding-empty", "data-testid": "embedding-unavailable"}, message));
      return target;
    };
    if (!Array.isArray(points) || !points.length) return unavailable("Embedding unavailable. No coordinates were supplied; choose a cluster from the list to review its exact cell scope.");
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (const point of points) {
      if (!point || !validId(point.cellId) || !validId(point.clusterId) || typeof point.x !== "number" || typeof point.y !== "number" || !Number.isFinite(point.x) || !Number.isFinite(point.y)) {
        return unavailable("Embedding unavailable. Supplied coordinates or cell/cluster IDs are missing or invalid; no coordinates have been generated or substituted.");
      }
      x0 = Math.min(x0, point.x); x1 = Math.max(x1, point.x);
      y0 = Math.min(y0, point.y); y1 = Math.max(y1, point.y);
    }
    if (!Number.isFinite(x1 - x0) || !Number.isFinite(y1 - y0)) return unavailable("Embedding unavailable. The supplied coordinate range cannot be displayed; no coordinates have been generated or substituted.");
    target.append(node("p", {class: "microcopy", "data-testid": "embedding-detail"}, "Actual exported coordinates · each point is one cell"));
    // The existing workbench's SVG geometry, without any projection or sampling.
    const width = 640, height = 350, pad = 38;
    const scaleX = x => pad + 9 + (x - x0) / (x1 - x0 || 1) * (width - pad * 2 - 18);
    const scaleY = y => height - pad - 8 - (y - y0) / (y1 - y0 || 1) * (height - pad * 2 - 10);
    const hasSelection = selectedCluster !== undefined && selectedCluster !== null;
    const selected = point => hasSelection && String(point.clusterId) === String(selectedCluster);
    const svg = svgNode("svg", {viewBox: `0 0 ${width} ${height}`, role: "img", "aria-label": `Real ${embeddingName}: ${points.length} cells${hasSelection ? `, cluster ${selectedCluster} selected` : ""}`});
    svg.append(svgNode("title", {}, title === undefined || title === null ? `${embeddingName}, ${points.length} cells` : title));
    svg.append(svgNode("line", {x1: pad, y1: height - pad, x2: width - pad, y2: height - pad, class: "umap-axis"}), svgNode("line", {x1: pad, y1: pad, x2: pad, y2: height - pad, class: "umap-axis"}));
    svg.append(svgNode("text", {x: width / 2, y: height - 8, "text-anchor": "middle", class: "umap-axis-text"}, `${embeddingName} 1`), svgNode("text", {x: 12, y: height / 2, transform: `rotate(-90 12 ${height / 2})`, "text-anchor": "middle", class: "umap-axis-text"}, `${embeddingName} 2`));
    const suppliedClusters = Array.isArray(clusters) ? clusters.filter(cluster => cluster && validId(cluster.id)) : [];
    const colors = new Map(suppliedClusters.map((cluster, index) => [String(cluster.id), palette[index % palette.length]]));
    for (const point of [...points].sort((a, b) => Number(selected(a)) - Number(selected(b)))) {
      const isSelected = selected(point);
      const circle = svgNode("circle", {cx: scaleX(point.x), cy: scaleY(point.y), r: isSelected ? 2.05 : 1.6, fill: isSelected || showAll ? colors.get(String(point.clusterId)) || "#dce2ed" : "#dce2ed", opacity: isSelected ? .9 : .72, class: "umap-point", "data-cluster": point.clusterId, "data-cell-id": point.cellId});
      circle.append(svgNode("title", {}, `${point.cellId} · cluster ${point.clusterId}`));
      if (typeof onSelect === "function") circle.addEventListener("click", () => onSelect(point.clusterId));
      svg.append(circle);
    }
    const chart = node("div", {class: "umap-chart", "data-testid": "embedding-chart"}); chart.append(svg); target.append(chart);
    const legend = node("div", {class: "umap-legend", "data-testid": "embedding-legend"});
    for (const cluster of suppliedClusters) {
      const item = node("span", {"data-cluster": cluster.id});
      const dot = node("i"); dot.style.background = colors.get(String(cluster.id));
      item.append(dot, node("span", {}, `C${cluster.id}${cluster.cellCount !== undefined && cluster.cellCount !== null ? ` · ${suppliedText(cluster.cellCount)} cells` : ""}`));
      if (cluster.sourceLabels !== undefined && cluster.sourceLabels !== null) item.append(node("small", {class: "source-note"}, `Source labels: ${suppliedText(cluster.sourceLabels)}`));
      legend.append(item);
    }
    target.append(legend);
    return target;
  }

  function markers(target, rows, {species} = {}) {
    target.replaceChildren();
    const suppliedRows = Array.isArray(rows) ? rows : [];
    const geneCards = globalThis.ScGeneCards;
    if (geneCards && typeof geneCards.note === "function") target.append(node("p", {class: "markers-note", "data-testid": "marker-gene-links-note"}, geneCards.note(species)));
    target.append(node("p", {class: "markers-note"}, `Showing all ${suppliedRows.length} supplied marker rows in their original order. Values and source retain the supplied table; missing statistics are shown as —. pct.1 and pct.2 are supplied detected fractions. An absent gene here does not establish non-expression.`));
    if (!suppliedRows.length) {
      target.append(node("p", {class: "empty-evidence", "data-testid": "markers-unavailable"}, "No marker table was supplied for this cluster. No expression absence can be inferred from this empty table."));
      return target;
    }
    const columns = [["gene", "Gene"], ["avgLog2FC", "avg log2FC"], ["pct1", "pct.1"], ["pct2", "pct.2"], ["pctDiff", "Δ detection (supplied)"], ["pAdj", "Adjusted p"], ["source", "Source"]];
    // Retain additional supplied columns as literal data, rather than dropping
    // a statistic merely because the existing table did not name that column.
    const known = new Set(columns.map(([key]) => key));
    for (const row of suppliedRows) if (row && typeof row === "object") for (const key of Object.keys(row)) if (!known.has(key)) {known.add(key); columns.push([key, key]);}
    const table = node("table"), head = node("thead"), heading = node("tr"), body = node("tbody");
    for (const [, label] of columns) heading.append(node("th", {scope: "col"}, label));
    head.append(heading); table.append(head, body);
    for (const row of suppliedRows) {
      const tr = node("tr", {"data-testid": "marker-row"});
      for (const [key] of columns) {
        const value = row?.[key], cell = node("td", {class: key === "source" ? "source-note" : key === "gene" ? "" : "number", "data-column": key});
        if (key === "gene") cell.append(geneCards && typeof geneCards.render === "function" ? geneCards.render(value, species) : node("strong", {}, suppliedText(value)));
        else cell.textContent = key === "source" ? suppliedText(value) : numericText(value);
        tr.append(cell);
      }
      body.append(tr);
    }
    const wrap = node("div", {class: "table-wrap"}); wrap.append(table); target.append(wrap);
    return target;
  }
  globalThis.ScEvidenceDisplay = Object.freeze({embedding, markers});
})();
