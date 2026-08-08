/* Rating pass: one variant at a time, keyboard first.
 *
 * The queue is fetched once and held in memory, and each judgement is POSTed
 * the moment it is made. Batching them up to send at the end would put a
 * session's worth of opinion behind one request that a closed tab loses. */

const $ = (id) => document.getElementById(id);

let items = [];
let cursor = 0;
let tags = new Set();
let tagDefs = [];
let groupOrder = [];
let familyDefs = [];

function prefix() {
  return encodeURIComponent($("prefix").value.trim());
}

/* Requests are tagged and only the newest is allowed to land. The unfiltered
 * queue is the biggest and therefore the slowest, so typing a filter right
 * after load reliably let the stale full list resolve last and overwrite the
 * filtered one -- the queue would show the right first item under the wrong
 * count, having quietly thrown the filter away. */
let queueToken = 0;

async function loadQueue(keepPlace) {
  const token = ++queueToken;
  const rated = $("showRated").checked ? "1" : "0";
  const response = await fetch(`/api/rate/queue?rated=${rated}&prefix=${prefix()}`);
  const data = await response.json();
  if (token !== queueToken) return;
  tagDefs = data.tags;
  groupOrder = data.groups || [];
  familyDefs = data.families || [];
  items = data.items;
  if (!keepPlace) cursor = 0;
  buildTags();
  buildFamilies();
  show();
  loadBoard();
}

function buildTags() {
  if ($("tags").childElementCount) return;
  $("tags").innerHTML = "";
  // Rendered in groups, because several tags answer the same question and the
  // choice between them is which SHADE of a fault, not which fault.
  for (const group of groupOrder) {
    const wrap = document.createElement("div");
    wrap.className = "taggroup";
    wrap.innerHTML = `<span class="grouplabel">${group}</span>`;
    for (const tag of tagDefs.filter((t) => t.group === group)) {
      const button = document.createElement("button");
      // Declared server-side. First-letter shortcuts stopped working once the
      // set grew blank/busy and face/flat.
      button.dataset.tag = tag.id;
      button.dataset.shortcut = tag.key;
      button.title = tag.help;
      button.innerHTML = `<kbd>${tag.key}</kbd> ${tag.id}`;
      button.onclick = () => toggleTag(tag.id);
      wrap.appendChild(button);
    }
    $("tags").appendChild(wrap);
  }
}

function buildFamilies() {
  const host = $("families");
  host.innerHTML = "";
  for (const f of familyDefs) {
    const button = document.createElement("button");
    button.dataset.prefix = f.prefix;
    button.title = `${f.rated} of ${f.total} rated`;
    button.innerHTML = `${f.prefix} <b>${f.unrated}</b>`;
    if (!f.unrated) button.classList.add("done");
    button.onclick = () => {
      const box = $("prefix");
      // Clicking the active batch clears it, so the whole queue is one click
      // away rather than needing the text cleared by hand.
      box.value = box.value === f.prefix ? "" : f.prefix;
      loadQueue(false);
    };
    host.appendChild(button);
  }
  paintFamilies();
}

function paintFamilies() {
  const current = $("prefix").value.trim();
  for (const button of $("families").children) {
    button.classList.toggle("on", button.dataset.prefix === current);
  }
}

function toggleTag(id) {
  if (tags.has(id)) tags.delete(id); else tags.add(id);
  paintTags();
}

function paintTags() {
  // querySelectorAll, not .children: the buttons now live inside per-group
  // wrappers, so iterating direct children finds the wrappers and silently
  // toggles nothing.
  for (const button of $("tags").querySelectorAll("button")) {
    button.classList.toggle("on", tags.has(button.dataset.tag));
  }
}

/* The room preview is the point of the pane, so a missing one is built rather
 * than hidden. The request is fired once per item and the result cached back
 * onto it, because rendering it shells out to the engine and takes seconds --
 * re-requesting on every arrow-key step would make the queue unusable. */
async function showContext(item) {
  const note = $("contextNote");
  if (item.context) {
    const url = `url("${item.context}")`;
    $("roomLeft").style.backgroundImage = url;
    $("roomRight").style.backgroundImage = url;
    $("contextLabel").textContent =
      item.contextLabel || `in the room — ${item.facets.heightMap}`;
    $("rooms").hidden = false;
    note.textContent = "";
    return;
  }
  $("rooms").hidden = true;
  if (item.contextFailed) {
    note.textContent = item.contextFailed;
    return;
  }
  note.textContent = "building the room preview...";
  const response = await fetch("/api/rate/context", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ run: item.run, variant: item.variant }),
  });
  const data = await response.json();
  // The queue may have moved on while the engine was running; only paint if
  // this item is still the one on screen.
  if (data.ok) {
    item.context = data.context;
    item.contextLabel = data.label;
  } else {
    item.contextFailed = `no room preview: ${data.error || "failed"}`;
  }
  if (items[cursor] === item) showContext(item);
}

function show() {
  const item = items[cursor];
  const has = Boolean(item);
  $("rate").querySelector(".stage").hidden = !has;
  if (!has) {
    $("facets").innerHTML =
      '<span class="empty">Nothing left to rate. Tick "include already rated" to revisit, or run a batch.</span>';
    $("progress").textContent = "";
    return;
  }

  $("tile").src = item.image;
  const base = item.base;
  $("baseFigure").hidden = !base;
  if (base) {
    $("base").src = base.image;
    $("baseLabel").textContent = `approved base tile — ${base.run}#${base.variant}`;
  } else {
    $("base").removeAttribute("src");
  }
  $("raw").src = item.raw;
  $("rawFigure").hidden = !item.raw;
  showContext(item);

  const tiled = $("tiled");
  tiled.style.backgroundImage = `url("${item.image}")`;
  // A wall joins left-to-right only; repeating it vertically would advertise a
  // seam along an edge that is authored to stay put, and invite a score for it.
  tiled.classList.toggle("axis-x", item.tileAxes === "x");
  tiled.style.backgroundRepeat = item.tileAxes === "x" ? "repeat-x" : "repeat";
  $("tiledLabel").textContent =
    item.tileAxes === "x" ? "tiled across" : "tiled both ways";

  const facets = item.facets;
  $("facets").innerHTML = [
    `<b>${item.name}</b> <span>v${item.variant}</span>`,
    base ? `<span>base</span> ${base.run}#${base.variant}` : "",
    `<span>model</span> ${facets.model}`,
    `<span>lora</span> ${facets.lora}`,
    `<span>depth</span> ${facets.depthWeight ?? "-"}`,
    `<span>geometry</span> ${facets.heightMap}`,
    `<span>seam</span> ${facets.seam ?? "-"} / ${facets.centre ?? "-"}`,
    facets.blank ? `<b class="flagged">dead margin ${facets.blankEdge}</b>` : "",
  ].filter(Boolean).join(" &nbsp; ");

  tags = new Set(item.judgement ? item.judgement.tags : []);
  // Shown when revisiting, so an existing note can be read and corrected
  // rather than silently overwritten by the next score.
  $("note").value = (item.judgement && item.judgement.note) || "";
  paintTags();
  for (const button of $("scores").children) {
    button.classList.toggle(
      "was", Boolean(item.judgement) && item.judgement.score === Number(button.dataset.score));
  }
  $("progress").textContent = `${cursor + 1} / ${items.length}`;
}

async function score(value) {
  const item = items[cursor];
  if (!item) return;
  const note = $("note").value.trim();
  item.judgement = { score: value, tags: [...tags], note };
  await fetch("/api/rate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      run: item.run, variant: item.variant, score: value, tags: [...tags], note,
    }),
  });
  tags = new Set();
  // Cleared with the tags: a note belongs to the tile it was written about, and
  // carrying it to the next one would attribute a fault to an innocent image.
  $("note").value = "";
  advance(1);
  loadBoard();
}

function advance(step) {
  cursor = Math.min(Math.max(cursor + step, 0), Math.max(items.length - 1, 0));
  show();
}

async function loadBoard() {
  // The board is scoped to the same filter as the queue: while rating one
  // experiment, a table averaging it together with every earlier sweep answers
  // a question nobody asked.
  const data = await (await fetch(`/api/rate/leaderboard?prefix=${prefix()}`)).json();
  const blocks = [];
  for (const [facet, rows] of Object.entries(data)) {
    if (!rows.length) continue;
    const body = rows.map((row) => `
      <tr><td>${row.value}</td>
          <td class="num">${row.score.toFixed(2)}</td>
          <td class="num">${row.n}</td>
          <td class="num">${row.seamRatio === null ? "-" : row.seamRatio.toFixed(2)}</td>
          <td class="tally">${Object.entries(row.tags)
            .map(([tag, count]) => `${tag}&times;${count}`).join(" ") || ""}</td></tr>`).join("");
    blocks.push(`<table><caption>${facet}</caption>
      <tr><th>value</th><th>stars</th><th>n</th><th>seam</th><th>why not</th></tr>
      ${body}</table>`);
  }
  $("board").innerHTML = blocks.length
    ? `<div class="boards">${blocks.join("")}</div>`
    : '<p class="empty">No scores yet.</p>';
}

// Enter and Escape leave the note field. Without this the guard below traps the
// rater: while the note has focus every digit is text, so there is no way back
// to scoring without reaching for the mouse -- and this page is driven at speed
// from the keyboard.
$("note").addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === "Escape") {
    event.preventDefault();
    $("note").blur();
  }
});

document.addEventListener("keydown", (event) => {
  if (event.target.tagName === "INPUT") return;
  if (event.key >= "0" && event.key <= "6") return score(Number(event.key));
  if (event.key === " ") { event.preventDefault(); return advance(1); }
  if (event.key === "ArrowRight") return advance(1);
  if (event.key === "ArrowLeft") return advance(-1);
  const button = [...$("tags").querySelectorAll("button")]
    .find((candidate) => candidate.dataset.shortcut === event.key);
  if (button) toggleTag(button.dataset.tag);
});

for (const button of $("scores").children) {
  button.onclick = () => score(Number(button.dataset.score));
}
$("skip").onclick = () => advance(1);
$("back").onclick = () => advance(-1);
$("showRated").onchange = () => loadQueue(false);
$("prefix").onchange = () => { paintFamilies(); loadQueue(false); };

loadQueue(false);
