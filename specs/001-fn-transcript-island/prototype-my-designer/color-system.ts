/**
 * Color system — Web/TS port of the SwiftUI `makePrimaryPalette`.
 *
 * SAME math (HSB derivation + WCAG on-color), SAME preset seeds, SAME token
 * names as visual-design-modernization/references/color-system.md. One seed
 * drives the whole primary set; semantic colors are FIXED; neutrals come from
 * Radix slate or Tailwind neutral.
 *
 * This is the single source of truth for web. Do not hardcode hex in components.
 */

// ── Color helpers ───────────────────────────────────────────────────────────

const clamp = (x: number): number => Math.min(1, Math.max(0, x));

/** Parse #RRGGBB → [r,g,b] in 0..1. */
function hexToRgb(hex: string): [number, number, number] {
  const s = hex.replace("#", "");
  const v = parseInt(s, 16);
  return [((v >> 16) & 0xff) / 255, ((v >> 8) & 0xff) / 255, (v & 0xff) / 255];
}

/** RGB(0..1) → HSB/HSV (h in 0..1). Matches NSColor.getHue semantics. */
function rgbToHsb(r: number, g: number, b: number): { h: number; s: number; b: number } {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  let h = 0;
  if (d !== 0) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h /= 6;
    if (h < 0) h += 1;
  }
  const s = max === 0 ? 0 : d / max;
  return { h, s, b: max };
}

/** HSB(h,s,b in 0..1) → CSS `hsl(...)` — kept as HSL for CSS-var friendliness. */
function hsbToCss(h: number, s: number, br: number): string {
  // HSB → RGB → then emit rgb() (exact; avoids HSB/HSL confusion).
  const i = Math.floor(h * 6);
  const f = h * 6 - i;
  const p = br * (1 - s);
  const q = br * (1 - f * s);
  const t = br * (1 - (1 - f) * s);
  let r = 0;
  let g = 0;
  let b = 0;
  switch (i % 6) {
    case 0: [r, g, b] = [br, t, p]; break;
    case 1: [r, g, b] = [q, br, p]; break;
    case 2: [r, g, b] = [p, br, t]; break;
    case 3: [r, g, b] = [p, q, br]; break;
    case 4: [r, g, b] = [t, p, br]; break;
    default: [r, g, b] = [br, p, q]; break;
  }
  const to255 = (x: number) => Math.round(clamp(x) * 255);
  return `rgb(${to255(r)} ${to255(g)} ${to255(b)})`;
}

/** WCAG relative luminance from sRGB 0..1. */
function relLuminance(r: number, g: number, b: number): number {
  const lin = (x: number) => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4);
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

/** Choose black or white foreground for the higher contrast on `hex`. */
function onColor(hex: string): string {
  const [r, g, b] = hexToRgb(hex);
  const L = relLuminance(r, g, b);
  return 1.05 / (L + 0.05) >= (L + 0.05) / 0.05 ? "#ffffff" : "#000000";
}

// ── Preset seeds (identical to SwiftUI) ─────────────────────────────────────

export const SEEDS = {
  blue: "#0090FF", // neutral / professional / data (default)
  purple: "#8E4EC6", // creative / AI
  teal: "#12A594", // health / finance
  orange: "#F76B15", // alert / energy
  appleBlue: "#007AFF", // Apple systemBlue
} as const;

export type SeedName = keyof typeof SEEDS;

// ── Primary palette derivation (mirrors makePrimaryPalette) ──────────────────

export interface PrimaryPalette {
  primary: string;
  primaryHover: string;
  primaryActive: string;
  primarySubtle: string;
  primaryMuted: string;
  primaryBorder: string;
  primaryText: string;
  onPrimary: string;
  onPrimarySubtle: string;
  ring: string;
}

/** One seed hex → the whole primary token set, matching the SwiftUI logic. */
export function makePrimaryPalette(seedHex: string, isDark: boolean): PrimaryPalette {
  const [r, g, b] = hexToRgb(seedHex);
  const { h, s, b: br } = rgbToHsb(r, g, b);
  const c = (hh: number, ss: number, bb: number) => hsbToCss(hh, clamp(ss), clamp(bb));

  if (isDark) {
    const primary = c(h, s - 0.05, br + 0.06);
    return {
      primary,
      primaryHover: c(h, s, br + 0.08),
      primaryActive: c(h, s, br + 0.14),
      primarySubtle: c(h, s * 0.45, 0.18),
      primaryMuted: c(h, s * 0.5, 0.26),
      primaryBorder: c(h, s * 0.55, 0.36),
      primaryText: c(h, s * 0.7, br + 0.28),
      onPrimary: onColor(seedHex),
      onPrimarySubtle: c(h, s * 0.7, br + 0.28),
      ring: c(h, s - 0.05, br + 0.06),
    };
  }
  const primary = seedHex.startsWith("#") ? c(h, s, br) : seedHex;
  return {
    primary,
    primaryHover: c(h, s, br - 0.08),
    primaryActive: c(h, s, br - 0.14),
    primarySubtle: c(h, s * 0.18, 0.97),
    primaryMuted: c(h, s * 0.4, 0.9),
    primaryBorder: c(h, s * 0.55, 0.8),
    primaryText: c(h, Math.min(1, s + 0.1), br - 0.2),
    onPrimary: onColor(seedHex),
    onPrimarySubtle: c(h, Math.min(1, s + 0.1), br - 0.2),
    ring: c(h, s, br),
  };
}

// ── On-brand chart palette (same offsets as SwiftUI) ─────────────────────────

const CHART_OFFSETS = [0, -15, 40, 95, 130, 175, -70, 210];

export function chartPalette(seedHex: string, isDark: boolean): string[] {
  const [r, g, b] = hexToRgb(seedHex);
  const seedHue = rgbToHsb(r, g, b).h * 360;
  return CHART_OFFSETS.map((off) => {
    const h = (((seedHue + off) % 360) + 360) % 360 / 360;
    return isDark ? hsbToCss(h, 0.66, 0.82) : hsbToCss(h, 0.72, 0.62);
  });
}

// ── Neutral palettes (fixed hex, from color-system.md) ───────────────────────

export interface Neutrals {
  bg: string;
  card: string;
  inner: string;
  text1: string;
  text2: string;
  text3: string;
  border: string;
}

export const NEUTRAL = {
  slate: {
    light: { bg: "#F9F9FB", card: "#FFFFFF", inner: "#F0F0F3", text1: "#1C2024", text2: "#60646C", text3: "#80838D", border: "#D9D9E0" },
    dark: { bg: "#111113", card: "#18191B", inner: "#212225", text1: "#EDEEF0", text2: "#B0B4BA", text3: "#777B84", border: "#363A3F" },
  },
  neutral: {
    light: { bg: "#FAFAFA", card: "#FFFFFF", inner: "#F5F5F5", text1: "#171717", text2: "#525252", text3: "#737373", border: "#E5E5E5" },
    dark: { bg: "#171717", card: "#262626", inner: "#2E2E2E", text1: "#FAFAFA", text2: "#A3A3A3", text3: "#737373", border: "#404040" },
  },
} as const;

export type NeutralName = keyof typeof NEUTRAL;

// ── Semantic colors (FIXED — never seed-derived) ─────────────────────────────

export const SEMANTIC = {
  light: { success: "#34C759", warning: "#FF9500", danger: "#FF3B30" },
  dark: { success: "#30D158", warning: "#FF9F0A", danger: "#FF453A" },
} as const;

// ── Emit everything as CSS custom properties ─────────────────────────────────

/**
 * Build the full CSS-variable map for a (seed, neutral, mode) combination.
 * Apply to document.documentElement.style or serialize into a :root block.
 */
export function buildTokens(
  seedHex: string,
  neutral: NeutralName,
  isDark: boolean,
): Record<string, string> {
  const p = makePrimaryPalette(seedHex, isDark);
  const n: Neutrals = NEUTRAL[neutral][isDark ? "dark" : "light"];
  const sem = SEMANTIC[isDark ? "dark" : "light"];
  const charts = chartPalette(seedHex, isDark);

  const vars: Record<string, string> = {
    "--bg": n.bg,
    "--card": n.card,
    "--inner": n.inner,
    "--text-1": n.text1,
    "--text-2": n.text2,
    "--text-3": n.text3,
    "--border": n.border,
    "--primary": p.primary,
    "--primary-hover": p.primaryHover,
    "--primary-active": p.primaryActive,
    "--primary-subtle": p.primarySubtle,
    "--primary-muted": p.primaryMuted,
    "--primary-border": p.primaryBorder,
    "--primary-text": p.primaryText,
    "--on-primary": p.onPrimary,
    "--on-primary-subtle": p.onPrimarySubtle,
    "--ring": p.ring,
    "--success": sem.success,
    "--warning": sem.warning,
    "--danger": sem.danger,
  };
  charts.forEach((c, i) => {
    vars[`--chart-${i + 1}`] = c;
  });
  return vars;
}
