#!/usr/bin/env node
// Production SVG rendering in installed Chrome; no server, R, provider or network.
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import {createRequire} from "node:module";
import {fileURLToPath} from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const require = createRequire(import.meta.url);
const {chromium} = require(process.env.SCAGENTKIT_PLAYWRIGHT || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
const browser = await chromium.launch({executablePath: process.env.SCAGENTKIT_CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true});
const report = {actualChrome: true, actualR: false, paidCalls: 0, networkRequests: [], benchmark: [], assertions: []};
try {
  const context = await browser.newContext();
  await context.route("**/*", route => {report.networkRequests.push(route.request().url()); return route.abort();});
  const source = await fs.readFile(path.join(root, "workbench/static/evidence-display.js"), "utf8");
  for (const [version, content] of [["current", source]]) {
    const page = await context.newPage();
    await page.setContent('<div id="plot" style="width:640px"></div>'); await page.addScriptTag({content});
    // Warm up first paint and report five samples rather than one startup-sensitive measurement.
    await page.evaluate(async () => {ScEvidenceDisplay.embedding(document.querySelector("#plot"), {points: [{cellId: "warmup", clusterId: "0", x: 0, y: 0}]}); await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));});
    for (const count of [1000, 5000, 10000]) for (let sample = 0; sample < 5; sample++) {
      const timing = await page.evaluate(async count => {
        const points = Array.from({length: count}, (_, i) => ({cellId: String(i), clusterId: String(i % 30), x: Math.sin(i) * (i % 17), y: Math.cos(i) * (i % 17)}));
        const start = performance.now(); ScEvidenceDisplay.embedding(document.querySelector("#plot"), {points, clusters: Array.from({length: 30}, (_, i) => ({id: String(i)}))});
        const construction = performance.now() - start;
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        return {constructionMilliseconds: construction, throughPaintMilliseconds: performance.now() - start, pointsRendered: document.querySelectorAll("circle").length, jsHeapUsedBytes: performance.memory?.usedJSHeapSize ?? null};
      }, count);
      assert.equal(timing.pointsRendered, count); report.benchmark.push({version, cells: count, sample, ...timing});
    }
    {
      const result = await page.evaluate(() => {
        const target = document.querySelector("#plot");
        const points = [[0, 0], [1, 0], [0, 1], [-1, 0], [0, -1]].map(([x, y], i) => ({cellId: String(i), clusterId: String(i), x, y}));
        ScEvidenceDisplay.embedding(target, {points, clusters: points.map(p => ({id: p.clusterId})), selectedCluster: "1", savedLabels: points.map(p => ({cellId: p.cellId, value: Number(p.cellId) < 3 ? "T" : "B"})), labelColumn: "sc_annotation"});
        const xy = [...target.querySelectorAll("circle")].map(c => ({id: c.dataset.cellId, x: c.cx.baseVal.value, y: c.cy.baseVal.value}));
        const control = target.querySelector("select"); control.value = "label"; control.dispatchEvent(new Event("change"));
        return {xy, equalLabels: target.querySelector('[data-cell-id="0"]').getAttribute("fill") === target.querySelector('[data-cell-id="1"]').getAttribute("fill"), selected: target.querySelector('[data-cell-id="1"]').getAttribute("stroke"), legend: target.querySelector('[data-testid="embedding-legend"]').textContent};
      });
      const center = result.xy.find(p => p.id === "0");
      for (const point of result.xy.filter(p => p.id !== "0")) assert.equal(Math.hypot(point.x - center.x, point.y - center.y), 132);
      assert.equal(result.equalLabels, true); assert.equal(result.selected, "#172b4d"); assert.equal(result.legend, "BT");
      report.assertions.push("unit-circle-equal-pixel-radii", "saved-per-cell-label-switch", "selection-outline-preserved");
      if (process.argv[2]) await page.screenshot({path: path.resolve(process.argv[2]).replace(/\.json$/, ".png")});
    }
    await page.close();
  }
  assert.deepEqual(report.networkRequests, []);
  if (process.argv[2]) await fs.writeFile(path.resolve(process.argv[2]), JSON.stringify(report, null, 2) + "\n");
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
} finally {await browser.close();}
