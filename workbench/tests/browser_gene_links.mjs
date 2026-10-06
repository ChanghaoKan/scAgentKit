#!/usr/bin/env node
// Actual local mapping and production helper in native Chrome. All external
// popup destinations are fulfilled locally: no remote content or biology test.
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import http from "node:http";
import crypto from "node:crypto";
import {createRequire} from "node:module";
import {fileURLToPath} from "node:url";
const args = {};
for (let i = 2; i < process.argv.length; i += 2) {assert(process.argv[i]?.startsWith("--") && process.argv[i + 1]); args[process.argv[i].slice(2)] = process.argv[i + 1];}
assert(args.output, "Supply --output for a new evidence directory");
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), ".."), output = path.resolve(args.output);
await fs.mkdir(output, {recursive: true});
const reportFile = path.join(output, "gene-links-browser-report.json");
assert.equal(await fs.access(reportFile).then(() => true, () => false), false, "Preserve earlier receipts");
const sha256 = value => crypto.createHash("sha256").update(value).digest("hex");
const source = await fs.readFile(path.join(root, "static/gene-links.js")), mapping = await fs.readFile(path.join(root, "static/ortholog-map.js"));
const report = {schema: "scagentkit.gene-links.native-browser.v2", startedAtUTC: new Date().toISOString(), sourceRoot: root,
  source_sha256: sha256(source), map_sha256: sha256(mapping), driver_sha256: sha256(await fs.readFile(fileURLToPath(import.meta.url))),
  actualChrome: false, actualR: false, mouseScientificValidation: false, checks: [], localRequests: [], interceptedExternalRequests: [], popupClicks: [], pageErrors: [],
  actualExternalFetches: 0, remoteContentRead: false, paidAPICalls: 0, costUSD: 0,
  cleanup: {browserClosed: false, serverClosed: false, ownedProfileRemoved: false},
  limitations: ["Native local helper fixture; not a live project or mouse scientific validation.", "External click destinations are locally intercepted; no remote MGI or GeneCards content is read.", "No existing browser profile, project, analysis or display service is used."]};
const encoded = value => encodeURIComponent(value).replace(/[!'()*]/g, char => "%" + char.charCodeAt(0).toString(16).toUpperCase());
const humanGene = 'A/B?x=1&y=2#frag% "\'()!*', hostileGene = '<img src=x onerror="window.unexpectedXSS=1">';
const fixtures = [
  {id: "lyz2", gene: "Lyz2", species: "mouse", checked: false},
  {id: "alias", gene: "Lysm", species: "Mus musculus", checked: true},
  {id: "case-mismatch", gene: "LysM", species: "mouse", checked: false},
  {id: "adh1", gene: "Adh1", species: "mouse", checked: true},
  {id: "h2-ab1", gene: "H2-Ab1", species: "10090", checked: false},
  {id: "human", gene: humanGene, species: "human", checked: true},
  {id: "human-tp53", gene: "TP53", species: "human", checked: false},
  {id: "missing", gene: "TP53", checked: true},
  {id: "hostile-human", gene: hostileGene, species: "human", checked: false},
  {id: "hostile-mouse", gene: hostileGene, species: "mouse", checked: true}
];
const fixture = `<!doctype html><meta charset="utf-8"><title>Local mouse gene-link display acceptance</title>
<style>body{font:16px system-ui;max-width:1050px;margin:24px auto}label{display:block;padding:12px;border-bottom:1px solid #ddd}.gene-lookup-mouse-record{display:block;margin-left:24px}a{margin:0 8px}small{margin-left:8px;color:#555}</style>
<script src="/ortholog-map.js"></script><script src="/gene-links.js"></script>
<h1>Local mapping display test</h1><p>No mouse scientific validation. External clicks are intercepted locally; no remote content is read.</p><main id="markers"></main><p id="notice"></p>
<script>
for (const fixture of ${JSON.stringify(fixtures).replace(/</g, "\\u003c")}) {
  const label = document.createElement("label"); label.id = fixture.id;
  const citation = document.createElement("input"); citation.type = "checkbox"; citation.checked = fixture.checked;
  citation.setAttribute("data-cited-marker", fixture.gene); label.append(citation, ScGeneCards.render(fixture.gene, fixture.species));
  document.getElementById("markers").append(label);
}
document.getElementById("notice").textContent = ScGeneCards.note("mouse");
</script>`;
const assets = new Map([["/", fixture], ["/ortholog-map.js", mapping], ["/gene-links.js", source], ["/favicon.ico", ""]]);
const server = http.createServer((request, response) => {
  if (request.method !== "GET" || !assets.has(request.url)) {response.writeHead(404).end(); return;}
  response.setHeader("Content-Type", request.url.endsWith(".js") ? "application/javascript" : "text/html"); response.end(assets.get(request.url));
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const origin = "http://127.0.0.1:" + server.address().port; report.origin = origin;
let context, profile;
const check = async (name, fn) => {await fn(); report.checks.push({name, passed: true});};
try {
  const require = createRequire(import.meta.url), {chromium} = require(args.playwright || "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright");
  const env = {...process.env};
  for (const key of Object.keys(env)) if (/(?:API[_-]?KEY|ACCESS[_-]?TOKEN|AUTH[_-]?TOKEN|PASSWORD|SECRET|CREDENTIAL)/i.test(key)) delete env[key];
  profile = await fs.mkdtemp(path.join(output, "owned-chrome-profile-")); report.ownedProfile = profile;
  context = await chromium.launchPersistentContext(profile, {headless: true, executablePath: args.chrome || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", env, viewport: {width: 1100, height: 1050}, timeout: 30000});
  context.setDefaultTimeout(15000); context.setDefaultNavigationTimeout(15000);
  report.actualChrome = true; report.chromeVersion = context.browser()?.version() || "native persistent Chrome";
  await context.route("**/*", async route => {
    const request = route.request();
    if (request.url().startsWith(origin + "/")) {report.localRequests.push({url: request.url(), method: request.method(), resourceType: request.resourceType()}); return route.continue();}
    report.interceptedExternalRequests.push({url: request.url(), method: request.method(), resourceType: request.resourceType(), navigation: request.isNavigationRequest(), referer: request.headers().referer ?? null, disposition: "fulfilled-locally-no-remote-fetch"});
    return route.fulfill({status: 200, contentType: "text/html", body: '<!doctype html><title>External navigation intercepted locally</title><p>No remote page was fetched.</p>'});
  });
  context.on("page", newPage => newPage.on("pageerror", error => report.pageErrors.push(error.message)));
  const page = await context.newPage(); await page.goto(origin, {waitUntil: "networkidle"});
  const snapshot = await page.evaluate(() => ({mapping: ScGeneCards.mappingInfo(),
    lookups: Object.fromEntries(["Lyz2", "Lysm", "LysM", "Adh1", "H2-Ab1"].map(gene => [gene, ScGeneCards.lookup(gene, "mouse")])),
    anchors: Array.from(document.querySelectorAll("a"), anchor => ({fixture: anchor.closest("label").id, text: anchor.textContent, href: anchor.getAttribute("href"), kind: anchor.getAttribute("data-gene-lookup-kind"), gene: anchor.getAttribute("data-gene-symbol"), mgi: anchor.getAttribute("data-mgi-id"), relation: anchor.getAttribute("data-ortholog-relation"), target: anchor.target, rel: anchor.rel, referrerpolicy: anchor.referrerPolicy})),
    citations: Array.from(document.querySelectorAll("input"), input => ({marker: input.getAttribute("data-cited-marker"), checked: input.checked}))}));
  report.actualSnapshot = snapshot;
  await fs.writeFile(path.join(output, "actual-local-map-snapshot.json"), JSON.stringify(snapshot, null, 2) + "\n");
  await check("actual local snapshot loads before the production display helper", async () => {
    assert.equal(snapshot.mapping.status, "available"); assert.equal(snapshot.mapping.snapshot_id, "mgi-mouse-human-2026-10-05.v1"); assert.equal(snapshot.mapping.entries, 20183);
    assert.deepEqual(report.localRequests.filter(request => request.resourceType === "script").map(request => new URL(request.url).pathname), ["/ortholog-map.js", "/gene-links.js"]);
  });
  await check("Lyz2 retains the literal marker, MGI:96897 and LYZ recorded candidate", async () => {
    const result = snapshot.lookups.Lyz2; assert.equal(result.match_type, "symbol"); assert.equal(result.mouse_records.length, 1); assert.equal(result.mouse_records[0].mgi_id, "MGI:96897");
    assert.deepEqual(result.mouse_records[0].human_candidates.map(candidate => [candidate.human_symbol, candidate.relation]), [["LYZ", "homology_group_candidate"]]);
    assert.equal(await page.locator("#lyz2 .gene-lookup > span").first().textContent(), "Lyz2");
  });
  await check("official alias Lysm matches while case-different LysM remains unmapped", async () => {
    assert.equal(snapshot.lookups.Lysm.match_type, "alias"); assert.equal(snapshot.lookups.Lysm.mouse_records[0].mgi_id, "MGI:96897"); assert.equal(snapshot.lookups.LysM.status, "unmapped");
    assert.equal(await page.locator("#case-mismatch a").count(), 0); assert.match(await page.locator("#case-mismatch").innerText(), /no ortholog absence inferred/);
    assert.equal(await page.locator("#alias .gene-lookup > span").first().textContent(), "Lysm");
  });
  await check("Adh1 displays all three human candidates without selecting an ortholog", async () => {
    assert.equal(snapshot.lookups.Adh1.ambiguous, true); assert.deepEqual(snapshot.lookups.Adh1.mouse_records[0].human_candidates.map(candidate => candidate.human_symbol), ["ADH1A", "ADH1B", "ADH1C"]);
    assert.deepEqual(snapshot.anchors.filter(anchor => anchor.fixture === "adh1" && anchor.kind === "human-ortholog").map(anchor => anchor.gene), ["ADH1A", "ADH1B", "ADH1C"]); assert.match(await page.locator("#adh1").innerText(), /multiple candidates retained/);
  });
  await check("H2-Ab1 displays both recorded human candidates", async () => {
    assert.equal(snapshot.lookups["H2-Ab1"].ambiguous, true); assert.deepEqual(snapshot.lookups["H2-Ab1"].mouse_records[0].human_candidates.map(candidate => candidate.human_symbol), ["HLA-DQB1", "HLA-DQB2"]);
    assert.deepEqual(snapshot.anchors.filter(anchor => anchor.fixture === "h2-ab1" && anchor.kind === "human-ortholog").map(anchor => anchor.gene), ["HLA-DQB1", "HLA-DQB2"]);
  });
  await check("human direct lookup stays unchanged and metacharacters remain one encoded path", async () => {
    assert.equal(await page.locator("#human-tp53 a").getAttribute("href"), "https://www.genecards.org/card/TP53");
    assert.equal(await page.locator("#human a").getAttribute("href"), "https://www.genecards.org/card/" + encoded(humanGene));
    const url = new URL(await page.locator("#human a").getAttribute("href")); assert.equal(url.search, ""); assert.equal(url.hash, ""); assert.equal(decodeURIComponent(url.pathname.slice(6)), humanGene);
  });
  await check("missing species stays inert without inference", async () => {assert.equal(await page.locator("#missing a").count(), 0); assert.match(await page.locator("#missing").innerText(), /species undeclared/);});
  await check("hostile labels stay inert text in human and mouse displays", async () => {
    assert.equal(await page.locator("img").count(), 0); assert.equal(await page.evaluate(() => window.unexpectedXSS), undefined); assert.equal(await page.locator("#hostile-human a").textContent(), hostileGene); assert.equal(await page.locator("#hostile-mouse a").count(), 0);
  });
  await check("every anchor has fixed encoded destination and safe new-tab attributes", async () => {
    for (const anchor of snapshot.anchors) {
      assert.equal(anchor.target, "_blank"); assert.equal(anchor.rel, "noopener noreferrer"); assert.equal(anchor.referrerpolicy, "no-referrer");
      const url = new URL(anchor.href); assert.equal(url.protocol, "https:"); assert.equal(url.search, ""); assert.equal(url.hash, "");
      if (anchor.kind === "mgi") {assert.equal(url.origin, "https://www.informatics.jax.org"); assert.equal(anchor.href, "https://www.informatics.jax.org/accession/" + encoded(anchor.mgi));}
      else {assert.equal(url.origin, "https://www.genecards.org"); assert.equal(anchor.href, "https://www.genecards.org/card/" + encoded(anchor.gene));}
      if (anchor.kind === "human-ortholog") assert.equal(anchor.relation, "homology_group_candidate");
    }
  });
  await check("load and refresh make zero automatic external requests", async () => {assert.equal(report.interceptedExternalRequests.length, 0); await page.reload({waitUntil: "networkidle"}); assert.equal(report.interceptedExternalRequests.length, 0);});
  await page.screenshot({path: path.join(output, "gene-links-before-click.png"), fullPage: true});
  const clicks = snapshot.anchors.filter(anchor => ["lyz2", "alias", "adh1", "h2-ab1", "human"].includes(anchor.fixture)); assert.equal(clicks.length, 12);
  for (const [index, clicked] of clicks.entries()) {
    const before = report.interceptedExternalRequests.length, anchor = page.locator("#" + clicked.fixture + " a").filter({hasText: clicked.text}); assert.equal(await anchor.count(), 1);
    const popupPromise = page.waitForEvent("popup"); await anchor.click(); const popup = await popupPromise;
    await popup.waitForURL(clicked.href); await popup.waitForLoadState("domcontentloaded");
    assert.equal(report.interceptedExternalRequests.length, before + 1);
    const request = report.interceptedExternalRequests.at(-1); assert.equal(request.url, clicked.href); assert.equal(request.method, "GET"); assert.equal(request.navigation, true); assert.equal(request.referer, null);
    assert.equal(popup.url(), clicked.href); assert.equal(await popup.evaluate(() => window.opener === null), true); assert.equal(page.url(), origin + "/");
    assert.deepEqual(await page.locator("input").evaluateAll(inputs => inputs.map(input => ({marker: input.getAttribute("data-cited-marker"), checked: input.checked}))), snapshot.citations);
    report.popupClicks.push({index: index + 1, ...clicked, observedURL: popup.url(), openerNull: true, citationCheckboxesUnchanged: true, originalPageUnchanged: true, remoteFetch: false}); await popup.close();
  }
  report.checks.push({name: "all eleven mouse destination clicks and encoded human click preserve citations and have no opener", passed: true});
  await check("refresh after clicks adds zero external requests", async () => {const before = report.interceptedExternalRequests.length; await page.reload({waitUntil: "networkidle"}); assert.equal(report.interceptedExternalRequests.length, before);});
  await check("no POST, API, analysis or page error occurs", async () => {assert(report.localRequests.every(request => request.method === "GET")); assert.deepEqual(report.pageErrors, []); assert.equal(report.actualR, false); assert.equal(report.actualExternalFetches, 0);});
  report.passed = true;
} catch (error) {report.passed = false; report.error = error.stack; process.exitCode = 1;}
finally {
  try {await context?.close(); report.cleanup.browserClosed = true;} catch (error) {report.cleanup.browserError = error.message; process.exitCode = 1;}
  try {await new Promise(resolve => server.close(resolve)); report.cleanup.serverClosed = true;} catch (error) {report.cleanup.serverError = error.message; process.exitCode = 1;}
  try {if (profile) await fs.rm(profile, {recursive: true, force: true}); report.cleanup.ownedProfileRemoved = true;} catch (error) {report.cleanup.profileError = error.message; process.exitCode = 1;}
  report.completedAtUTC = new Date().toISOString(); if (!Object.values(report.cleanup).every(value => value === true)) report.passed = false;
  await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + "\n");
}
console.log(JSON.stringify({reportFile, passed: report.passed, checks: report.checks.length, popupClicks: report.popupClicks.length, source_sha256: report.source_sha256, map_sha256: report.map_sha256, actualExternalFetches: report.actualExternalFetches, cleanup: report.cleanup}));
