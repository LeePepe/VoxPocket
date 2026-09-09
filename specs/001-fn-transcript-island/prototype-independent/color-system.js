(() => {
  var __defProp = Object.defineProperty;
  var __returnValue = (v) => v;
  function __exportSetter(name, newValue) {
    this[name] = __returnValue.bind(null, newValue);
  }
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, {
        get: all[name],
        enumerable: true,
        configurable: true,
        set: __exportSetter.bind(all, name)
      });
  };

  // color-system.ts
  var exports_color_system = {};
  __export(exports_color_system, {
    makePrimaryPalette: () => makePrimaryPalette,
    chartPalette: () => chartPalette,
    buildTokens: () => buildTokens,
    SEMANTIC: () => SEMANTIC,
    SEEDS: () => SEEDS,
    NEUTRAL: () => NEUTRAL
  });
  var clamp = (x) => Math.min(1, Math.max(0, x));
  function hexToRgb(hex) {
    const s = hex.replace("#", "");
    const v = parseInt(s, 16);
    return [(v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255];
  }
  function rgbToHsb(r, g, b) {
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const d = max - min;
    let h = 0;
    if (d !== 0) {
      if (max === r)
        h = (g - b) / d % 6;
      else if (max === g)
        h = (b - r) / d + 2;
      else
        h = (r - g) / d + 4;
      h /= 6;
      if (h < 0)
        h += 1;
    }
    const s = max === 0 ? 0 : d / max;
    return { h, s, b: max };
  }
  function hsbToCss(h, s, br) {
    const i = Math.floor(h * 6);
    const f = h * 6 - i;
    const p = br * (1 - s);
    const q = br * (1 - f * s);
    const t = br * (1 - (1 - f) * s);
    let r = 0;
    let g = 0;
    let b = 0;
    switch (i % 6) {
      case 0:
        [r, g, b] = [br, t, p];
        break;
      case 1:
        [r, g, b] = [q, br, p];
        break;
      case 2:
        [r, g, b] = [p, br, t];
        break;
      case 3:
        [r, g, b] = [p, q, br];
        break;
      case 4:
        [r, g, b] = [t, p, br];
        break;
      default:
        [r, g, b] = [br, p, q];
        break;
    }
    const to255 = (x) => Math.round(clamp(x) * 255);
    return `rgb(${to255(r)} ${to255(g)} ${to255(b)})`;
  }
  function relLuminance(r, g, b) {
    const lin = (x) => x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  }
  function onColor(hex) {
    const [r, g, b] = hexToRgb(hex);
    const L = relLuminance(r, g, b);
    return 1.05 / (L + 0.05) >= (L + 0.05) / 0.05 ? "#ffffff" : "#000000";
  }
  var SEEDS = {
    blue: "#0090FF",
    purple: "#8E4EC6",
    teal: "#12A594",
    orange: "#F76B15",
    appleBlue: "#007AFF"
  };
  function makePrimaryPalette(seedHex, isDark) {
    const [r, g, b] = hexToRgb(seedHex);
    const { h, s, b: br } = rgbToHsb(r, g, b);
    const c = (hh, ss, bb) => hsbToCss(hh, clamp(ss), clamp(bb));
    if (isDark) {
      const primary2 = c(h, s - 0.05, br + 0.06);
      return {
        primary: primary2,
        primaryHover: c(h, s, br + 0.08),
        primaryActive: c(h, s, br + 0.14),
        primarySubtle: c(h, s * 0.45, 0.18),
        primaryMuted: c(h, s * 0.5, 0.26),
        primaryBorder: c(h, s * 0.55, 0.36),
        primaryText: c(h, s * 0.7, br + 0.28),
        onPrimary: onColor(seedHex),
        onPrimarySubtle: c(h, s * 0.7, br + 0.28),
        ring: c(h, s - 0.05, br + 0.06)
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
      ring: c(h, s, br)
    };
  }
  var CHART_OFFSETS = [0, -15, 40, 95, 130, 175, -70, 210];
  function chartPalette(seedHex, isDark) {
    const [r, g, b] = hexToRgb(seedHex);
    const seedHue = rgbToHsb(r, g, b).h * 360;
    return CHART_OFFSETS.map((off) => {
      const h = ((seedHue + off) % 360 + 360) % 360 / 360;
      return isDark ? hsbToCss(h, 0.66, 0.82) : hsbToCss(h, 0.72, 0.62);
    });
  }
  var NEUTRAL = {
    slate: {
      light: { bg: "#F9F9FB", card: "#FFFFFF", inner: "#F0F0F3", text1: "#1C2024", text2: "#60646C", text3: "#80838D", border: "#D9D9E0" },
      dark: { bg: "#111113", card: "#18191B", inner: "#212225", text1: "#EDEEF0", text2: "#B0B4BA", text3: "#777B84", border: "#363A3F" }
    },
    neutral: {
      light: { bg: "#FAFAFA", card: "#FFFFFF", inner: "#F5F5F5", text1: "#171717", text2: "#525252", text3: "#737373", border: "#E5E5E5" },
      dark: { bg: "#171717", card: "#262626", inner: "#2E2E2E", text1: "#FAFAFA", text2: "#A3A3A3", text3: "#737373", border: "#404040" }
    }
  };
  var SEMANTIC = {
    light: { success: "#34C759", warning: "#FF9500", danger: "#FF3B30" },
    dark: { success: "#30D158", warning: "#FF9F0A", danger: "#FF453A" }
  };
  function buildTokens(seedHex, neutral, isDark) {
    const p = makePrimaryPalette(seedHex, isDark);
    const n = NEUTRAL[neutral][isDark ? "dark" : "light"];
    const sem = SEMANTIC[isDark ? "dark" : "light"];
    const charts = chartPalette(seedHex, isDark);
    const vars = {
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
      "--danger": sem.danger
    };
    charts.forEach((c, i) => {
      vars[`--chart-${i + 1}`] = c;
    });
    return vars;
  }

  // palette-entry.ts
  globalThis.VoxColors = exports_color_system;
})();
