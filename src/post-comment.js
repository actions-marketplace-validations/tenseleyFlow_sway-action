// post-comment.js — read the markdown report the entrypoint wrote and
// post (or edit-in-place) a PR comment carrying it.
//
// Called from action.yml via actions/github-script@v7. The github-script
// action injects `github`, `context`, and `core` — we accept them as a
// single object so the call site is `await post({ github, context, core })`.
//
// Edit-in-place uses a hidden HTML marker in the comment body. Finding
// the prior comment by marker rather than by author lets the action
// work with both bot-account tokens (GITHUB_TOKEN) and user-PAT tokens
// without special-casing the login.

"use strict";

const fs = require("fs");

// Hidden marker the action stamps onto every comment it posts. Edits
// in place when a comment with this marker already exists. Pinned to
// a literal string (no env interpolation) so future edits stay
// findable even if action inputs change.
const MARKER = "<!-- sway-action:report -->";

const MAX_COMMENT_BYTES = 60 * 1024;
// GitHub's hard cap is 65536 chars; leave headroom for the marker +
// truncation footer + verdict header so a "barely-fits" report doesn't
// silently drop the trailing rows.

module.exports = async function postSwayComment({ github, context, core }) {
  const markdownPath = process.env.SWAY_MARKDOWN_PATH || resolveMarkdownPath();
  if (!markdownPath || !fs.existsSync(markdownPath)) {
    core.warning(
      `sway-action: no markdown report at ${markdownPath || "<unset>"}; skipping PR comment.`,
    );
    return;
  }

  const verdict = process.env.SWAY_VERDICT || "unknown";
  const score = process.env.SWAY_SCORE || "";

  let body = fs.readFileSync(markdownPath, "utf8");
  body = composeBody({ marker: MARKER, verdict, score, body });

  if (body.length > MAX_COMMENT_BYTES) {
    const head = body.slice(0, MAX_COMMENT_BYTES - 200);
    body =
      head +
      `\n\n…\n\n_Report truncated to ${MAX_COMMENT_BYTES} bytes; download the full artifact for the rest._\n`;
  }

  const pr = context.payload.pull_request;
  if (!pr) {
    core.warning("sway-action: not a pull_request event; skipping comment.");
    return;
  }

  const issueNumber = pr.number;
  const { owner, repo } = context.repo;

  // Page through existing comments to find one carrying our marker.
  // 100/page is GitHub's max; we stop after the first match.
  let existingId = null;
  for await (const { data: page } of github.paginate.iterator(
    github.rest.issues.listComments,
    { owner, repo, issue_number: issueNumber, per_page: 100 },
  )) {
    const hit = page.find((c) => typeof c.body === "string" && c.body.includes(MARKER));
    if (hit) {
      existingId = hit.id;
      break;
    }
  }

  if (existingId) {
    await github.rest.issues.updateComment({
      owner,
      repo,
      comment_id: existingId,
      body,
    });
    core.info(`sway-action: edited existing PR comment #${existingId}`);
  } else {
    const { data: created } = await github.rest.issues.createComment({
      owner,
      repo,
      issue_number: issueNumber,
      body,
    });
    core.info(`sway-action: created PR comment #${created.id}`);
  }
};

function resolveMarkdownPath() {
  // Composite-action steps don't share env between steps the way bash
  // scripts do, so we fall back to the canonical path the entrypoint
  // sets via $GITHUB_OUTPUT. The post-comment step references this via
  // the explicit env mapping in action.yml — see SWAY_MARKDOWN_PATH.
  return null;
}

function composeBody({ marker, verdict, score, body }) {
  // Strip a leading "# sway report" if the markdown renderer wrote one
  // — we're about to write our own header that includes the verdict
  // emoji, and stacking two H1s reads badly in PR comments.
  let stripped = body.replace(/^#\s+sway[^\n]*\n+/i, "");

  const emoji = { pass: "✅", warn: "⚠️", fail: "❌", error: "💥" }[verdict] || "ℹ️";
  const scorePart = score ? ` — score **${score}**` : "";
  const header = `${marker}\n## ${emoji} sway: \`${verdict}\`${scorePart}\n\n`;
  return header + stripped;
}
