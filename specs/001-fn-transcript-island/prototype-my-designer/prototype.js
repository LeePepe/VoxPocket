// 独立外观原型：仅模拟文案；A 是当前截图，B 是 my-designer 新备选。
const $ = (id) => document.getElementById(id);
const island = document.querySelector('.island');
const shortText = '把刚才讨论的想法整理一下，明天我们一起确认下一步的计划。';
let timer;
let variant = new URLSearchParams(location.search).get('variant') === 'A' ? 'A' : 'B';
const labels = {listening:'正在聆听',empty:'正在聆听',transcribing:'正在转写',refining:'正在润色',done:'处理完成',error:'录音出错'};

function stopPlayback() { clearInterval(timer); timer = undefined; $('play').innerHTML = '播放识别过程 <span aria-hidden="true">↗</span>'; }
function showText(text) {
  const split = Math.max(0, text.length - 17);
  $('earlier').textContent = text.slice(0, split);
  $('latest').textContent = text.slice(split);
  requestAnimationFrame(() => { $('transcript').scrollTop = $('transcript').scrollHeight; });
}
function render() {
  const state = $('state').value;
  island.dataset.state = state;
  $('status-label').textContent = labels[state];
  $('elapsed').textContent = state === 'done' ? '✓' : state === 'error' ? '!' : '00:08';
  $('hint').innerHTML = state === 'listening' ? '松开 <kbd>fn</kbd> 结束' : state === 'error' ? '请重新按住 fn 重试' : '保留识别原文';
  $('detail').textContent = state === 'listening' ? '实时识别' : state === 'error' ? '请检查麦克风权限' : '请稍候';
  showText(state === 'error' ? '暂时无法开始录音，请检查麦克风权限后重试。' : $('long-text').checked ? ('先把需要讨论的内容记录下来，再逐项整理。\n'.repeat(18) + shortText) : shortText);
  document.body.classList.toggle('no-notch', !$('has-notch').checked);
  $('scene-caption').textContent = `${$('has-notch').checked ? '有刘海屏幕' : '无刘海屏幕'} · ${labels[state]} · 模拟预览`;
  $('demo-status').textContent = '模拟文字与波形 · 未连接麦克风或粘贴功能';
}
function setVariant(next) {
  stopPlayback(); variant = next;
  const url = new URL(location.href); url.searchParams.set('variant', variant); history.replaceState(null, '', url);
  document.body.classList.toggle('variant-a', variant === 'A');
  $('variant-label').textContent = variant === 'A' ? 'A — 当前 SwiftUI 截图' : 'B — my-designer 备选';
  $('demo-status').textContent = variant === 'A' ? 'A 为上一版真实 SwiftUI 截图，放入同一桌面场景作对照。' : 'B 为独立 HTML 交互概念稿，尚未接入 SwiftUI。';
}
for (const id of ['state','long-text','has-notch']) $(id).addEventListener('change', () => { stopPlayback(); render(); });
for (const id of ['prev','next']) $(id).addEventListener('click', () => setVariant(variant === 'A' ? 'B' : 'A'));
document.addEventListener('keydown', (event) => {
  if (!['ArrowLeft','ArrowRight'].includes(event.key) || event.target.closest('input,textarea,select,[contenteditable],[tabindex="0"]')) return;
  event.preventDefault(); setVariant(variant === 'A' ? 'B' : 'A');
});
$('play').addEventListener('click', () => {
  if (timer) { stopPlayback(); $('demo-status').textContent = '模拟播放已暂停。'; return; }
  $('state').value = 'listening'; $('long-text').checked = false; render(); showText('');
  $('play').textContent = '暂停播放'; $('demo-status').textContent = '正在逐字播放模拟识别结果，不使用麦克风。';
  let count = 0;
  timer = setInterval(() => {
    showText(shortText.slice(0, ++count));
    $('elapsed').textContent = `00:${String(Math.floor(count / 5)).padStart(2,'0')}`;
    if (count >= shortText.length) { stopPlayback(); $('demo-status').textContent = '模拟识别已结束，可切换转写或润色状态。'; }
  }, 140);
});
render(); setVariant(variant);
