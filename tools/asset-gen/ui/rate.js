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

function prefix() {
  return encodeURIComponent($("prefix").value.trim());
}

async function loadQueue(keepPlace) {
  const rated = $("showRated").checked ? "1" : "0";
  const response = await fetch(`/api/rate/queue?rated=${rated}&prefix=${prefix()}`);
  const data = await response.json();
  tagDefs = data.tags;
  items = data.items;
  if (!keepPlace) cursor = 0;
  buildTags();
  show();
  loadBoard();
}

function buildTags() {
  if ($("tags").childElementCount) return;
  $("tags").innerHTML = "";
  tagDefs.forEach((tag, index) => {
    const button = document.createElement("button");
    // The shortcut is the tag's own first letter where that is unambiguous,
    // which is every tag in the current set; the index is only the fallback.
    const shortcut = tag.id[0];
    button.dataset.tag = tag.id;
    button.dataset.shortcut = shortcut;
    button.title = tag.help;
    button.innerHTML = `<kbd>${shortcut}</kbd> ${tag.id}`;
    button.onclick = () => toggleTag(tag.id);
    $("tags").appendChild(button);
    void index;
  });
}

function toggleTag(id) {
  if (tags.has(id)) tags.delete(id); else tags.add(id);
  paintTags();
}

function paintTags() {
  for (const button of $("tags").children) {
    button.classList.toggle("on", tags.has(button.dataset.tag));
  }
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
  $("raw").src = item.raw;
  $("rawFigure").hidden = !item.raw;
  $("context").src = item.context || "";
  $("contextFigure").hidden = !item.context;

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
    `<span>model</span> ${facets.model}`,
    `<span>lora</span> ${facets.lora}`,
    `<span>depth</span> ${facets.depthWeight ?? "-"}`,
    `<span>geometry</span> ${facets.heightMap}`,
    `<span>seam</span> ${facets.seam ?? "-"} / ${facets.centre ?? "-"}`,
  ].join(" &nbsp; ");

  tags = new Set(item.judgement ? item.judgement.tags : []);
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
  item.judgement = { score: value, tags: [...tags] };
  await fetch("/api/rate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      run: item.run, variant: item.variant, score: value, tags: [...tags],
    }),
  });
  tags = new Set();
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

document.addEventListener("keydown", (event) => {
  if (event.target.tagName === "INPUT") return;
  if (event.key >= "1" && event.key <= "5") return score(Number(event.key));
  if (event.key === " ") { event.preventDefault(); return advance(1); }
  if (event.key === "ArrowRight") return advance(1);
  if (event.key === "ArrowLeft") return advance(-1);
  const button = [...$("tags").children]
    .find((candidate) => candidate.dataset.shortcut === event.key);
  if (button) toggleTag(button.dataset.tag);
});

for (const button of $("scores").children) {
  button.onclick = () => score(Number(button.dataset.score));
}
$("skip").onclick = () => advance(1);
$("back").onclick = () => advance(-1);
$("showRated").onchange = () => loadQueue(false);
$("prefix").onchange = () => loadQueue(false);

loadQueue(false);
