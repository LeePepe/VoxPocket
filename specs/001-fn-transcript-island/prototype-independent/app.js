// 仅使用技能的原始色系模板；所有文案均为预设的虚构演示数据。
const lightTokens = VoxColors.buildTokens(VoxColors.SEEDS.blue, 'slate', false);
for (const key of ['inner', 'card', 'text-1', 'text-2', 'border']) {
  document.documentElement.style.setProperty(`--light-${key}`, lightTokens[`--${key}`]);
}
const $ = (selector) => document.querySelector(selector);
const shortText = '我想做一个更安静的语音工具，按下 Fn，就能把想法留下来。';
const longText = '我想做一个更安静的语音工具，按下 Fn，就能把想法留下来。\n\n窗口不用很大，也不要挡住正在写的东西。它只需要让我知道，现在正在听，刚才说的话已经被接住了。\n\n如果中途停下来思考，文字就安静地等在原处。说完以后，先让我看一眼，再决定要不要放进文稿。\n\n长一点的想法也应该完整保留。上面的内容可以回看，下面的新句子仍然清楚。工具不催促，也不替我做决定。';
let scene = 'live';
let isLong = false;
let playing = false;
let timers = [];
let inserted = false;
const states = {
  waiting: { label: '准备好了', caption: '', tip: '取消', primary: '开始说话' },
  live: { label: '正在聆听', caption: '实时转写', tip: '取消', primary: '结束转写' },
  processing: { label: '正在整理', caption: '最后一句，正在确认', tip: '取消', primary: '处理中…' },
  done: { label: '转写完成', caption: '文字已就绪', tip: '收起', primary: '插入模拟文稿' },
  error: { label: '连接中断', caption: '已保留的文字', tip: '收起', primary: '重新尝试' },
};
function announce(text) { $('#announcement').textContent = text; }
function stopPlayback() {
  timers.forEach(clearTimeout); timers = []; playing = false;
  document.body.classList.remove('is-playing');
  $('#play-control').textContent = '▷ 播放演示';
  $('#play-control').setAttribute('aria-pressed', 'false');
}
function setScene(next, { automatic = false } = {}) {
  if (!automatic) stopPlayback();
  scene = next; inserted = false;
  const state = states[scene];
  $('.island').dataset.state = scene;
  $('#status-label').textContent = state.label;
  $('#text-caption').textContent = state.caption;
  $('#footer-tip').innerHTML = `<kbd>esc</kbd> ${state.tip}`;
  $('#primary').innerHTML = `${scene === 'live' || scene === 'waiting' ? '<kbd>fn</kbd>' : ''}<span>${state.primary}</span><span aria-hidden="true">${scene === 'processing' ? '·' : '↵'}</span>`;
  $('#primary').disabled = scene === 'processing';
  $('#secondary').hidden = !['done', 'error'].includes(scene);
  $('#secondary').textContent = '复制文字';
  $('#error-help').hidden = scene !== 'error';
  $('#duration').textContent = scene === 'waiting' ? '00:00' : isLong ? '00:42' : '00:08';
  renderText();
  document.querySelectorAll('[data-scene]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.scene === scene)));
  announce(state.label);
}
function renderText() {
  const text = $('#transcript');
  if (scene === 'waiting') text.textContent = '想说什么，就从这里开始。';
  else if (isLong) { text.textContent = longText; text.style.whiteSpace = 'pre-line'; }
  else {
    text.style.whiteSpace = 'normal';
    text.innerHTML = `我想做一个更安静的语音工具，<br>按下 Fn，<span class="${scene === 'live' ? 'latest' : ''}">就能把想法留下来。</span>${scene === 'live' ? '<span class="live-caret" aria-hidden="true"></span>' : ''}`;
  }
  $('.transcript-scroll').scrollTop = 0;
}
function simulateFn() {
  if (scene === 'waiting' || scene === 'done' || scene === 'error') setScene('live');
  else if (scene === 'live') {
    setScene('processing');
    timers.push(setTimeout(() => setScene('done', { automatic: true }), 1200));
  }
}
function insertText() {
  $('#document-output').textContent = isLong ? longText : shortText;
  $('#document-output').style.maxHeight = '96px';
  $('#document-output').style.overflowY = 'auto';
  $('#primary').innerHTML = '<span>已插入模拟文稿</span><span aria-hidden="true">✓</span>';
  $('#primary').disabled = true; inserted = true;
  announce('已插入页面内的模拟文稿，没有写入任何外部应用。');
}
$('#primary').addEventListener('click', () => {
  if (scene === 'done') insertText();
  else simulateFn();
});
$('#secondary').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(isLong ? longText : shortText);
    $('#secondary').textContent = '已复制 ✓'; announce('演示文字已复制');
  } catch {
    const range = document.createRange(); range.selectNodeContents($('#transcript'));
    const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    $('#secondary').textContent = '按 ⌘C 复制'; announce('浏览器禁止剪贴板访问，已选中文字，请按 Command C 复制');
  }
});
document.querySelectorAll('[data-scene]').forEach(button => button.addEventListener('click', () => setScene(button.dataset.scene)));
$('#fn-control').addEventListener('click', simulateFn);
$('#long-control').addEventListener('click', () => {
  isLong = !isLong; $('#long-control').setAttribute('aria-pressed', String(isLong));
  setScene(scene === 'waiting' ? 'live' : scene);
});
$('#play-control').addEventListener('click', () => {
  if (playing) { stopPlayback(); return; }
  stopPlayback(); playing = true; isLong = false;
  $('#long-control').setAttribute('aria-pressed', 'false');
  document.body.classList.add('is-playing');
  $('#play-control').textContent = 'Ⅱ 暂停演示';
  $('#play-control').setAttribute('aria-pressed', 'true');
  setScene('waiting', { automatic: true });
  timers.push(setTimeout(() => {
    setScene('live', { automatic: true });
    const fragments = ['我想做一个', '我想做一个更安静的语音工具，', '我想做一个更安静的语音工具，按下 Fn，', shortText];
    fragments.forEach((fragment, index) => timers.push(setTimeout(() => {
      $('#transcript').textContent = fragment;
      $('#duration').textContent = `00:0${index * 2 + 2}`;
    }, index * 1250)));
  }, 1400));
  timers.push(setTimeout(() => setScene('processing', { automatic: true }), 7100));
  timers.push(setTimeout(() => { setScene('done', { automatic: true }); stopPlayback(); }, 8500));
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') { setScene('waiting'); announce('已收起到等待状态'); }
  if (event.code === 'Space' && !event.repeat && !['BUTTON', 'INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) {
    event.preventDefault(); simulateFn();
  }
});
// 通过 URL 参数可稳定捕获五种状态，不启动动画。
const initial = new URLSearchParams(location.search).get('state');
if (initial && states[initial]) setScene(initial);
