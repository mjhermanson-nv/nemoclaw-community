// SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../extension/sidepanel.js"), "utf8");
const html = fs.readFileSync(path.join(__dirname, "../extension/sidepanel.html"), "utf8");
assert.match(source, /\/api\/plugins\/ask-nemoclaw\/conversations/);
assert.doesNotMatch(source, /requestsBrandingReview|REVIEW_ENDPOINT|REVIEW_FIELDS|GOOGLE_DOC_PATTERN|window\.confirm/);
assert.match(source, /askNemoClawConversationId/);
assert.match(source, /Idempotency-Key/);
assert.match(source, /captureContext\(\)/);
assert.match(source, /chrome\.tabs\.captureVisibleTab/);
assert.match(source, /viewport_image: viewportImage/);
assert.match(source, /Available page text \+ visible viewport/);
assert.match(source, /page_text: pageText \|\| null/);
assert.doesNotMatch(source, /empty_page/);
assert.match(source, /status\.scrollIntoView/);
assert.ok(html.indexOf('id="messages"') < html.indexOf('id="status-card"'));
assert.match(source, /refreshPageAndCreateConversation/);
assert.match(source, /await refreshActivePage\(false\)[\s\S]*await createConversation\(\)/);
assert.match(source, /redirect: "manual"/);
assert.match(source, /response\.type === "opaqueredirect"/);
assert.match(source, /response\.headers\.get\("content-type"\)\?\.includes\("text\/html"\)/);
assert.match(source, /NemoClaw did not respond within 20 seconds/);
assert.match(source, /Loading conversations/);
assert.match(source, /checkNemoClawConnection/);
assert.match(source, /Connected to NemoClaw/);
assert.match(source, /Sign-in required/);
assert.match(source, /chrome\.permissions\.request/);
assert.match(source, /askNemoClawOrigin/);
assert.match(source, /chrome\.tabs\.create\(\{ url: `\$\{nemoClawOrigin\}\/` \}\)/);
assert.match(html, /id="settings-button"/);
assert.match(html, /credentials remain in the normal NemoHermes browser session/);
assert.doesNotMatch(source, /storage\.(?:local|sync)\.set\([^)]*(?:page_text|result|messages)/s);
const start = source.indexOf("function parseMarkdownBlocks");
const end = source.indexOf("function appendInlineMarkdown", start);
assert.ok(start >= 0 && end > start);

const context = {};
vm.runInNewContext(
  `${source.slice(start, end)}\nglobalThis.parseMarkdown = parseMarkdownBlocks;`,
  context
);

const markdown = `## Technical Review

**Required:** Correct the product name.

- First issue
- [x] Verified item
- [ ] Open item

| Issue | Fix |
| --- | --- |
| Name | Standardize it |
`;
const blocks = context.parseMarkdown(markdown);
assert.deepEqual(Array.from(blocks, block => block.type), ["heading", "paragraph", "list", "table"]);
assert.equal(blocks[2].items[1].checked, true);
assert.equal(blocks[2].items[2].checked, false);
assert.equal(blocks[3].rows[0][1], "Standardize it");

const captureStart = source.indexOf("function captureFromPage");
const captureEnd = source.indexOf("async function captureContext", captureStart);
const captureContext = {
  document: { title: "Example", body: { innerText: "Visible browser text" } },
  getSelection: () => ({ toString: () => "Selected text" }),
  MAX_VIEWPORT_IMAGE_EDGE: 2048,
  MAX_VIEWPORT_IMAGE_PIXELS: 4000000
};
vm.runInNewContext(
  `${source.slice(captureStart, captureEnd)}\nglobalThis.capture = captureFromPage; globalThis.scale = scaledViewportDimensions;`,
  captureContext
);
const captured = captureContext.capture(10, 8);
assert.equal(captured.page_text, "Visible br");
assert.equal(captured.page_text_truncated, true);
assert.equal(captured.selected_text, "Selected");
const scaled = captureContext.scale(3840, 2160);
assert.ok(scaled.width <= 2048);
assert.ok(scaled.width * scaled.height <= 4000000);

console.log("side-panel response normalization: OK");
