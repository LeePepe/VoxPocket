// 从技能原始模板派生预览色彩；不改变 seed 数学或新增组件内颜色。
import { buildTokens, SEEDS } from './color-system.ts';
import { writeFileSync } from 'node:fs';

const dark = buildTokens(SEEDS.blue, 'slate', true);
const light = buildTokens(SEEDS.blue, 'slate', false);
const tokens = { ...dark, '--device-ink': '#000000' };
for (const [key, value] of Object.entries(light)) tokens[key.replace('--', '--desktop-')] = value;
const css = ':root {\n' + Object.entries(tokens).map(([key, value]) => `  ${key}: ${value};`).join('\n') + '\n}\n';
writeFileSync(new URL('palette.css', import.meta.url), css);
