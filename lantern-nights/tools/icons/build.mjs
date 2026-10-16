// Builds the Lantern Nights icon set.
//
//   node tools/icons/build.mjs          -> writes assets/icons/svg/*.svg and assets/icons/png/*.png
//
// Icons are white glyphs with a dark outline on a 128x128 grid. In Roblox,
// ImageColor3 tints the white fill while the dark outline stays dark.
// Each icon is a list of base shapes drawn in two passes (all outlines first,
// then all fills) so overlapping shapes merge into one silhouette, then
// "detail" marks drawn in the outline colour on top.
//
// PNG rendering needs Playwright + Chromium (`npm i -g playwright`).

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SVG_DIR = join(ROOT, "assets", "icons", "svg");
const PNG_DIR = join(ROOT, "assets", "icons", "png");
const PNG_SIZE = 256;

const INK = "#0E0F1F";
const OUTLINE = 14; // total outline thickness around a fill (7px each side at 128)

// Shape helpers. `fill` shapes are closed SVG elements; `line` shapes are
// stroked paths with a given width (shackles, handles, rays…).
const fill = (el) => ({ kind: "fill", el });
const line = (d, width) => ({ kind: "line", d, width });

function polygonPoints(points) {
  return points.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(" ");
}

function star(cx, cy, outer, inner, count) {
  const pts = [];
  for (let i = 0; i < count * 2; i++) {
    const r = i % 2 === 0 ? outer : inner;
    const a = -Math.PI / 2 + (i * Math.PI) / count;
    pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  return `<polygon points="${polygonPoints(pts)}"/>`;
}

function gear(cx, cy, outer, inner, teeth) {
  const pts = [];
  const step = (Math.PI * 2) / teeth;
  for (let i = 0; i < teeth; i++) {
    const a = i * step;
    pts.push([cx + inner * Math.cos(a - step * 0.5), cy + inner * Math.sin(a - step * 0.5)]);
    pts.push([cx + outer * Math.cos(a - step * 0.22), cy + outer * Math.sin(a - step * 0.22)]);
    pts.push([cx + outer * Math.cos(a + step * 0.22), cy + outer * Math.sin(a + step * 0.22)]);
  }
  return `<polygon points="${polygonPoints(pts)}"/>`;
}

function rays(cx, cy, r1, r2, count) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const a = (i * Math.PI * 2) / count;
    const x1 = cx + r1 * Math.cos(a), y1 = cy + r1 * Math.sin(a);
    const x2 = cx + r2 * Math.cos(a), y2 = cy + r2 * Math.sin(a);
    out.push(line(`M${x1.toFixed(2)} ${y1.toFixed(2)} L${x2.toFixed(2)} ${y2.toFixed(2)}`, 10));
  }
  return out;
}

// name -> { shapes, detail, transform }
const ICONS = {
  Health: {
    shapes: [fill(`<path d="M64 110 C28 84 12 66 12 44 C12 27 25 16 40 16 C51 16 59 23 64 32 C69 23 77 16 88 16 C103 16 116 27 116 44 C116 66 100 84 64 110 Z"/>`)],
    detail: `<path d="M34 40 C34 33 39 29 45 29" fill="none" stroke="${INK}" stroke-width="6" stroke-linecap="round" opacity="0.35"/>`,
  },
  Stamina: {
    shapes: [fill(`<polygon points="74,10 28,72 60,72 50,118 100,50 68,50 80,10"/>`)],
  },
  Hunger: {
    shapes: [
      fill(`<g transform="rotate(45 40 88)"><rect x="33" y="70" width="14" height="38" rx="4"/><circle cx="32" cy="108" r="9"/><circle cx="48" cy="108" r="9"/></g>`),
      fill(`<ellipse cx="76" cy="52" rx="40" ry="31" transform="rotate(-40 76 52)"/>`),
    ],
    detail: `<path d="M64 36 C72 30 84 30 92 38" fill="none" stroke="${INK}" stroke-width="6" stroke-linecap="round" opacity="0.35"/>`,
  },
  Warmth: {
    shapes: [fill(`<path d="M64 118 C36 118 20 100 20 78 C20 56 40 44 44 20 C57 31 62 44 61 56 C68 49 72 41 72 30 C92 45 108 63 108 82 C108 103 91 118 64 118 Z"/>`)],
    detail: `<path d="M64 108 C52 108 46 100 46 92 C46 82 56 76 58 66 C66 74 82 82 82 94 C82 102 76 108 64 108 Z" fill="${INK}" opacity="0.3"/>`,
  },
  Embers: {
    shapes: [fill(`<circle cx="64" cy="64" r="48"/>`)],
    detail: `<circle cx="64" cy="64" r="31" fill="none" stroke="${INK}" stroke-width="6"/><path d="M64 46 C72 56 74 62 70 70 C68 76 60 78 56 72 C53 66 58 58 64 46 Z" fill="${INK}"/>`,
  },
  Moonstones: {
    shapes: [fill(`<polygon points="38,18 90,18 116,48 64,114 12,48"/>`)],
    detail: `<polyline points="12,48 116,48" fill="none" stroke="${INK}" stroke-width="6" stroke-linejoin="round"/><polyline points="38,18 52,48 64,114 76,48 90,18" fill="none" stroke="${INK}" stroke-width="6" stroke-linejoin="round"/>`,
  },
  Stardust: {
    shapes: [
      fill(`<path d="M58 8 C63 40 76 52 108 58 C76 64 63 76 58 108 C53 76 40 64 8 58 C40 52 53 40 58 8 Z"/>`),
      fill(`<path d="M100 82 C102 94 106 98 118 100 C106 102 102 106 100 118 C98 106 94 102 82 100 C94 98 98 94 100 82 Z"/>`),
    ],
  },
  Backpack: {
    shapes: [
      line(`M48 36 V26 A10 10 0 0 1 58 16 H70 A10 10 0 0 1 80 26 V36`, 10),
      fill(`<rect x="24" y="32" width="80" height="84" rx="20"/>`),
    ],
    detail: `<rect x="40" y="70" width="48" height="30" rx="8" fill="none" stroke="${INK}" stroke-width="6"/><line x1="40" y1="54" x2="88" y2="54" stroke="${INK}" stroke-width="6" stroke-linecap="round"/>`,
  },
  Craft: {
    transform: "rotate(-35 64 64) translate(0 6)",
    shapes: [fill(`<rect x="55" y="40" width="18" height="74" rx="7"/>`), fill(`<rect x="26" y="14" width="76" height="34" rx="9"/>`)],
    detail: `<line x1="44" y1="14" x2="44" y2="48" stroke="${INK}" stroke-width="5" opacity="0.35"/>`,
  },
  Build: {
    shapes: [
      fill(`<rect x="12" y="20" width="50" height="28" rx="5"/>`),
      fill(`<rect x="66" y="20" width="50" height="28" rx="5"/>`),
      fill(`<rect x="12" y="52" width="24" height="28" rx="5"/>`),
      fill(`<rect x="40" y="52" width="50" height="28" rx="5"/>`),
      fill(`<rect x="94" y="52" width="22" height="28" rx="5"/>`),
      fill(`<rect x="12" y="84" width="50" height="28" rx="5"/>`),
      fill(`<rect x="66" y="84" width="50" height="28" rx="5"/>`),
    ],
    detail: `<path d="M12 50 H116 M12 82 H116 M64 20 V48 M38 52 V80 M92 52 V80 M64 84 V112" stroke="${INK}" stroke-width="6"/>`,
  },
  Pets: {
    shapes: [
      fill(`<ellipse cx="64" cy="86" rx="32" ry="26"/>`),
      fill(`<ellipse cx="28" cy="54" rx="12" ry="15" transform="rotate(-20 28 54)"/>`),
      fill(`<ellipse cx="50" cy="30" rx="12" ry="15" transform="rotate(-8 50 30)"/>`),
      fill(`<ellipse cx="78" cy="30" rx="12" ry="15" transform="rotate(8 78 30)"/>`),
      fill(`<ellipse cx="100" cy="54" rx="12" ry="15" transform="rotate(20 100 54)"/>`),
    ],
  },
  Book: {
    shapes: [fill(`<path d="M64 30 C50 20 30 17 12 21 V104 C30 99 50 101 64 111 C78 101 98 99 116 104 V21 C98 17 78 20 64 30 Z"/>`)],
    detail: `<path d="M64 30 V111" stroke="${INK}" stroke-width="6"/><path d="M26 42 C36 40 44 41 52 45 M26 60 C36 58 44 59 52 63 M76 45 C84 41 92 40 102 42 M76 63 C84 59 92 58 102 60" fill="none" stroke="${INK}" stroke-width="5" stroke-linecap="round" opacity="0.4"/>`,
  },
  Quests: {
    shapes: [
      fill(`<rect x="28" y="18" width="70" height="92" rx="8"/>`),
      fill(`<rect x="20" y="12" width="82" height="18" rx="9"/>`),
      fill(`<rect x="26" y="98" width="82" height="18" rx="9"/>`),
    ],
    detail: `<path d="M44 46 H82 M44 62 H82 M44 78 H70" stroke="${INK}" stroke-width="6" stroke-linecap="round"/>`,
  },
  Gift: {
    shapes: [
      fill(`<ellipse cx="48" cy="28" rx="17" ry="11" transform="rotate(-25 48 28)"/>`),
      fill(`<ellipse cx="80" cy="28" rx="17" ry="11" transform="rotate(25 80 28)"/>`),
      fill(`<rect x="18" y="54" width="92" height="60" rx="8"/>`),
      fill(`<rect x="10" y="36" width="108" height="24" rx="7"/>`),
    ],
    detail: `<path d="M64 36 V114 M10 60 H118" stroke="${INK}" stroke-width="6"/><rect x="56" y="36" width="16" height="78" fill="${INK}" opacity="0.25"/>`,
  },
  Crown: {
    shapes: [fill(`<polygon points="12,38 40,64 64,22 88,64 116,38 104,104 24,104"/>`)],
    detail: `<path d="M28 88 H100" stroke="${INK}" stroke-width="6" stroke-linecap="round"/><circle cx="64" cy="70" r="7" fill="${INK}"/>`,
  },
  Trade: {
    shapes: [
      fill(`<polygon points="14,28 80,28 80,12 116,40 80,68 80,52 14,52"/>`),
      fill(`<polygon points="114,82 48,82 48,66 12,94 48,122 48,106 114,106"/>`),
    ],
  },
  Settings: {
    shapes: [fill(gear(64, 64, 54, 40, 8))],
    detail: `<circle cx="64" cy="64" r="16" fill="${INK}"/>`,
  },
  Close: {
    shapes: [
      fill(`<rect x="52" y="10" width="24" height="108" rx="10" transform="rotate(45 64 64)"/>`),
      fill(`<rect x="52" y="10" width="24" height="108" rx="10" transform="rotate(-45 64 64)"/>`),
    ],
  },
  Lock: {
    shapes: [line(`M40 60 V44 A24 24 0 0 1 88 44 V60`, 14), fill(`<rect x="20" y="54" width="88" height="62" rx="14"/>`)],
    detail: `<circle cx="64" cy="80" r="9" fill="${INK}"/><rect x="59" y="82" width="10" height="20" rx="4" fill="${INK}"/>`,
  },
  Star: {
    shapes: [fill(star(64, 68, 56, 24, 5))],
  },
  Home: {
    shapes: [fill(`<polygon points="64,12 118,60 102,60 102,114 26,114 26,60 10,60"/>`)],
    detail: `<rect x="52" y="76" width="24" height="38" rx="5" fill="${INK}"/>`,
  },
  Shop: {
    shapes: [line(`M44 50 V38 A20 20 0 0 1 84 38 V50`, 11), fill(`<path d="M18 44 H110 L102 112 Q101 118 95 118 H33 Q27 118 26 112 Z"/>`)],
    detail: `<circle cx="44" cy="62" r="6" fill="${INK}"/><circle cx="84" cy="62" r="6" fill="${INK}"/>`,
  },
  Check: { shapes: [line(`M22 66 L52 96 L106 34`, 22)] },
  Plus: { shapes: [line(`M64 20 V108 M20 64 H108`, 22)] },
  Minus: { shapes: [line(`M20 64 H108`, 22)] },
  Sword: {
    transform: "rotate(45 64 64)",
    shapes: [
      fill(`<polygon points="64,-2 81,16 81,78 47,78 47,16"/>`),
      fill(`<rect x="56" y="86" width="16" height="24" rx="5"/>`),
      fill(`<circle cx="64" cy="116" r="11"/>`),
      fill(`<rect x="26" y="74" width="76" height="17" rx="8"/>`),
    ],
    detail: `<path d="M64 14 V74" stroke="${INK}" stroke-width="5" opacity="0.35"/>`,
  },
  Shield: {
    shapes: [fill(`<path d="M64 10 L110 26 V58 C110 88 92 108 64 120 C36 108 18 88 18 58 V26 Z"/>`)],
    detail: `<path d="M64 26 L94 37 V58 C94 80 82 94 64 103 Z" fill="${INK}" opacity="0.3"/>`,
  },
  Moon: {
    shapes: [fill(`<path d="M80 12 A54 54 0 1 0 116 86 A42 42 0 0 1 80 12 Z"/>`)],
    detail: `<circle cx="44" cy="60" r="7" fill="${INK}" opacity="0.3"/><circle cx="62" cy="90" r="5" fill="${INK}" opacity="0.3"/>`,
  },
  Sun: {
    shapes: [...rays(64, 64, 40, 56, 8), fill(`<circle cx="64" cy="64" r="28"/>`)],
  },
  Travel: {
    shapes: [fill(`<path d="M64 120 C64 120 24 78 24 50 A40 40 0 0 1 104 50 C104 78 64 120 64 120 Z"/>`)],
    detail: `<circle cx="64" cy="50" r="15" fill="${INK}"/>`,
  },
  Trophy: {
    shapes: [
      line(`M34 30 H18 V40 C18 54 28 60 38 60`, 9),
      line(`M94 30 H110 V40 C110 54 100 60 90 60`, 9),
      fill(`<path d="M32 14 H96 V44 C96 66 82 80 64 80 C46 80 32 66 32 44 Z"/>`),
      fill(`<rect x="55" y="76" width="18" height="20" rx="3"/>`),
      fill(`<rect x="34" y="94" width="60" height="20" rx="6"/>`),
    ],
    detail: `<path d="M54 30 L64 24 L74 30 L72 42 L64 48 L56 42 Z" fill="${INK}" opacity="0.3"/>`,
  },
  Info: {
    shapes: [fill(`<circle cx="64" cy="64" r="52"/>`)],
    detail: `<circle cx="64" cy="38" r="8" fill="${INK}"/><rect x="56" y="54" width="16" height="44" rx="6" fill="${INK}"/>`,
  },
  Alert: {
    shapes: [line(`M64 18 L112 104 H16 Z`, 14), fill(`<polygon points="64,18 112,104 16,104"/>`)],
    detail: `<rect x="57" y="46" width="14" height="34" rx="6" fill="${INK}"/><circle cx="64" cy="92" r="7.5" fill="${INK}"/>`,
  },
  Party: {
    shapes: [
      fill(`<circle cx="88" cy="40" r="15"/>`),
      fill(`<path d="M66 110 C66 84 74 70 88 70 C104 70 116 84 116 110 Z"/>`),
      fill(`<circle cx="44" cy="42" r="19"/>`),
      fill(`<path d="M10 114 C10 84 24 68 44 68 C64 68 78 84 78 114 Z"/>`),
    ],
  },
  Emote: {
    shapes: [fill(`<circle cx="64" cy="64" r="52"/>`)],
    detail: `<circle cx="45" cy="52" r="8" fill="${INK}"/><circle cx="83" cy="52" r="8" fill="${INK}"/><path d="M38 74 C48 96 80 96 90 74" fill="none" stroke="${INK}" stroke-width="8" stroke-linecap="round"/>`,
  },
  Lantern: {
    shapes: [
      line(`M46 22 A18 18 0 0 1 82 22`, 9),
      fill(`<rect x="36" y="20" width="56" height="16" rx="6"/>`),
      fill(`<rect x="28" y="34" width="72" height="64" rx="16"/>`),
      fill(`<rect x="36" y="96" width="56" height="18" rx="6"/>`),
    ],
    detail: `<path d="M64 88 C54 88 49 81 49 74 C49 65 57 61 60 52 C66 58 79 64 79 74 C79 82 73 88 64 88 Z" fill="${INK}" opacity="0.4"/>`,
  },
};

function shapeMarkup(shape, pass) {
  if (shape.kind === "fill") return shape.el;
  const width = pass === "outline" ? shape.width + OUTLINE : shape.width;
  return `<path d="${shape.d}" fill="none" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round"/>`;
}

function buildSvg(icon) {
  const outline = icon.shapes.map((s) => shapeMarkup(s, "outline")).join("");
  const body = icon.shapes.map((s) => shapeMarkup(s, "fill")).join("");
  const transform = icon.transform ? ` transform="${icon.transform}"` : "";
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-8 -8 144 144" width="128" height="128">`,
    `<g${transform}>`,
    `<g fill="${INK}" stroke="${INK}" stroke-width="${OUTLINE}" stroke-linejoin="round">${outline}</g>`,
    `<g fill="#FFFFFF" stroke="#FFFFFF">${body}</g>`,
    icon.detail ? `<g>${icon.detail}</g>` : "",
    `</g></svg>`,
  ].join("");
}

// Fill-pass shapes must not carry a stroke unless they are `line`s, so the
// silhouette edge stays crisp; lines need the white stroke to draw at all.
function fixFillPass(svg) {
  return svg.replace(`<g fill="#FFFFFF" stroke="#FFFFFF">`, `<g fill="#FFFFFF" stroke="#FFFFFF" stroke-width="0">`);
}

mkdirSync(SVG_DIR, { recursive: true });
mkdirSync(PNG_DIR, { recursive: true });

const svgs = {};
for (const [name, icon] of Object.entries(ICONS)) {
  // Lines set their own stroke-width attribute, which overrides the group's 0.
  const svg = fixFillPass(buildSvg(icon));
  svgs[name] = svg;
  writeFileSync(join(SVG_DIR, `${name}.svg`), svg + "\n");
}
console.log(`wrote ${Object.keys(svgs).length} SVGs to ${SVG_DIR}`);

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.log("playwright not installed; skipping PNG render");
  process.exit(0);
}

const browser = await chromium.launch(
  process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {},
);
const page = await browser.newPage({ viewport: { width: PNG_SIZE, height: PNG_SIZE } });
for (const [name, svg] of Object.entries(svgs)) {
  const sized = svg.replace(`width="128" height="128"`, `width="${PNG_SIZE}" height="${PNG_SIZE}"`);
  await page.setContent(`<html><body style="margin:0;background:transparent">${sized}</body></html>`);
  await page.locator("svg").screenshot({ path: join(PNG_DIR, `${name}.png`), omitBackground: true });
}

// Contact sheet for review (on both a dark and a light backdrop, tinted).
const tints = ["#FFFFFF", "#FF7A6B", "#FBE45B", "#4FDDB0", "#6CC1F5", "#B98CFF", "#FFB940"];
const cells = Object.entries(svgs)
  .map(([name, svg], i) => {
    const tinted = svg.replaceAll(`fill="#FFFFFF"`, `fill="${tints[i % tints.length]}"`).replaceAll(`stroke="#FFFFFF"`, `stroke="${tints[i % tints.length]}"`);
    return `<figure><div>${tinted.replace(`width="128" height="128"`, `width="72" height="72"`)}</div><figcaption>${name}</figcaption></figure>`;
  })
  .join("");
await page.setViewportSize({ width: 960, height: 720 });
await page.setContent(`<html><body style="margin:0;padding:16px;background:#16182E;font:600 12px sans-serif;color:#BFC3E6">
<div style="display:grid;grid-template-columns:repeat(9,1fr);gap:8px">${cells}</div>
<style>figure{margin:0;text-align:center}figure div{background:#1F2240;border:2px solid #3A3F70;border-radius:12px;padding:8px}</style></body></html>`);
await page.screenshot({ path: join(ROOT, "assets", "icons", "contact-sheet.png"), fullPage: true });
await browser.close();
console.log(`rendered PNGs to ${PNG_DIR}`);
