import * as VoxColors from './color-system';
// 本地 file:// 预览使用经典脚本，原始模板不作修改。
(globalThis as typeof globalThis & { VoxColors: typeof VoxColors }).VoxColors = VoxColors;
