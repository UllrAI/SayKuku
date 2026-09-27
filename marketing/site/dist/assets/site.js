// Preset interaction examples adapted from the supplied SayKuku.html. No audio is recorded or sent.
(() => {
  'use strict';
  const $ = (selector, root=document) => root.querySelector(selector);
  const $$ = (selector, root=document) => [...root.querySelectorAll(selector)];
  const menu = $('#menu-toggle');
  menu?.addEventListener('click', () => {
    const open = menu.getAttribute('aria-expanded') !== 'true';
    menu.setAttribute('aria-expanded', String(open));
    $('#nav-links').classList.toggle('is-open', open);
  });
  $('#nav-links')?.addEventListener('click', event => {
    if (event.target.closest('a')) {
      menu?.setAttribute('aria-expanded', 'false');
      $('#nav-links').classList.remove('is-open');
    }
  });
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) { entry.target.classList.add('in-view'); observer.unobserve(entry.target); }
    }, {threshold: 0.08});
    $$('.reveal').forEach(node => observer.observe(node));
  } else $$('.reveal').forEach(node => node.classList.add('in-view'));
  if (!$('#fn-key')) return;
  const language = 'zh';
  const copy = {
    pillTap: '按一下 Fn，想法就到位。', pillHold: '按住 Fn，说完就松开。', pillAgent: 'Voice Agent 已就位，双击 Fn 试试。',
    pillTranslate: '听懂了，正在翻译。', pillReceived: '收到了，整理成文字。', pillDone: '翻译好了，还可以接着说。',
    pillWritten: '已写入演示窗口。', pillInput: '正在演示语音输入…', pillAgentDemo: '正在演示 Voice Agent…',
    pillHoldDemo: '听写示例 · 松开结束', pillTapDemo: '听写示例 · 再点 Fn 结束', pillShort: '明白，再短一点。',
    pillShortDone: '短一点，也清楚一点。', setHold: '已切换为按住说话，上方 Fn 演示也已同步。', setTap: '已切换为单击开始 / 单击结束。',
    announceDemo: '正在播放预设的语音交互示例。', announceTranslation: '英文翻译已生成，可以替换、复制或继续改写。',
    announceInput: '语音输入演示完成：'
  };
  const tr = key => copy[key] ?? key;
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const state = {mode:'input', trigger:'tap', phase:'idle', timers:[], typing:null, runId:0};
  let toastTimer, lastTap=0, tapTimer, holdTimer, held=false, pointerActive=false, keyboardHandledUntil=0;
  const originalChinese = '周五下午三点，和团队聊聊新设计。';
  const originalEnglish = 'Let’s talk about the new design this Friday at 3.';
  const transcribed = '周五下午三点，和团队聊聊新设计。';
  const transcribedEnglish = 'Let’s talk about the new design this Friday at 3 pm.';
  const translation = 'Let’s get together this Friday at 3 to talk about the new design.';
  const fn = $('#fn-key'), pill = $('#recording-pill');
  function announce(text){$('#demo-announcement').textContent=text;}
  function toast(text){clearTimeout(toastTimer);$('#toast').textContent=text;$('#toast').classList.add('visible');toastTimer=setTimeout(()=>$('#toast').classList.remove('visible'),2800);}
  function later(fn,delay){const id=setTimeout(fn,delay);state.timers.push(id);return id;}
  function cancelRun(){state.timers.forEach(clearTimeout);state.timers=[];clearInterval(state.typing);state.typing=null;state.runId++;}
  function updatePill(label,phase='idle'){state.phase=phase;$('#pill-label').textContent=label;pill.classList.toggle('is-listening',phase==='listening');pill.classList.toggle('is-thinking',phase==='thinking');}
  function typeText(el,text,done){clearInterval(state.typing);if(reduced){el.textContent=text;done?.();return;}el.textContent='';let i=0;state.typing=setInterval(()=>{i++;el.textContent=text.slice(0,i);if(i>=text.length){clearInterval(state.typing);state.typing=null;done?.();}},25);}
  function setMode(mode, notify=true){
    cancelRun();state.mode=mode;$('#agent-result').hidden=true;$('#typing-caret').hidden=false;
    $$('#demo [data-demo-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.demoMode===mode)));
    $('#demo-text').classList.remove('selected');
    if(mode==='agent'){
      $('#demo-text').textContent=language === 'en' ? originalEnglish : originalChinese;$('#demo-text').classList.add('selected');$('#typing-caret').hidden=true;
      $('#document-label').textContent=language === 'en' ? 'SELECTED TEXT · HAND IT TO KUKU' : 'SELECTED TEXT · 这段文字，交给 KUKU';$('#document-title').textContent=language === 'en' ? 'Friday design chat' : '周五的设计讨论';
      $('#mode-name').textContent='Fn × 2 · Voice Agent';$('#hero-note-text').textContent=language === 'en' ? '“Translate this naturally into English.”' : '“翻成英文，语气自然一点。”';
      $('#demo-footer-text').textContent=language === 'en' ? 'Use the selected text' : '使用你选中的这一段';updatePill(tr('pillAgent'));
    }else{
      $('#demo-text').innerHTML=language === 'en' ? 'Turn the thought in your head,<br>into words in front of you.' : '把脑海里的想法，<br>变成眼前的文字。';
      $('#document-label').textContent='JUST A THOUGHT, UNTIL YOU SAY IT.';$('#document-title').textContent=language === 'en' ? 'The next thing to do' : '下一件想做的事';
      $('#mode-name').textContent=language === 'en' ? 'Fn · Voice Input' : 'Fn · 语音输入';$('#hero-note-text').textContent=language === 'en' ? 'Say the thought as it comes.' : '脑子里的那句，直接说就好。';$('#demo-footer-text').textContent=language === 'en' ? 'Stay in the window you use' : '留在你正在使用的窗口';
      updatePill(state.trigger==='hold'?tr('pillHold'):tr('pillTap'));
    }
  }
  function finishRecording(){
    if(state.phase!=='listening')return;
    cancelRun();updatePill(state.mode==='agent'?tr('pillTranslate'):tr('pillReceived'),'thinking');
    later(()=>{
      if(state.mode==='agent'){
        $('#agent-result').hidden=false;typeText($('#agent-result-text'),translation,()=>{updatePill(tr('pillDone'),'done');announce(tr('announceTranslation'));});
      }else{
        $('#demo-text').classList.remove('selected');typeText($('#demo-text'),language === 'en' ? transcribedEnglish : transcribed,()=>{updatePill(tr('pillWritten'),'done');$('#demo-footer-text').textContent=language === 'en' ? 'Written into this demo window' : '仅写入这个演示窗口';announce(tr('announceInput')+(language === 'en' ? transcribedEnglish : transcribed));});
      }
    },reduced?150:650);
  }
  function beginRecording(autoFinish=false){
    cancelRun();$('#agent-result').hidden=true;
    if(state.mode==='input'){$('#demo-text').textContent='';$('#typing-caret').hidden=false;$('#hero-note-text').textContent=language === 'en' ? '“Friday at 3, with the design team…”' : '“周五下午三点，和设计团队……”';}
    else{$('#demo-text').textContent=language === 'en' ? originalEnglish : originalChinese;$('#demo-text').classList.add('selected');$('#typing-caret').hidden=true;}
    updatePill(state.mode==='agent'?tr('pillAgentDemo'):autoFinish?tr('pillInput'):state.trigger==='hold'?tr('pillHoldDemo'):tr('pillTapDemo'),'listening');announce(tr('announceDemo'));
    if(autoFinish||state.mode==='agent')later(finishRecording,reduced?350:1550);
    else later(finishRecording,9000); // Bound the demo; never leave it recording indefinitely.
  }
  function tapAction(){if(state.phase==='listening'){finishRecording();return;}if(state.phase==='thinking')return;beginRecording(state.mode==='agent');}
  function doubleAction(){setMode('agent');beginRecording(true);}
  function registerTap(){
    const now=performance.now();
    if(lastTap&&now-lastTap<290){clearTimeout(tapTimer);lastTap=0;doubleAction();return;}
    lastTap=now;clearTimeout(tapTimer);
    tapTimer=setTimeout(()=>{lastTap=0;if(state.mode==='agent')toast('双击 Fn，体验 Voice Agent。');else if(state.trigger==='tap')tapAction();else toast('当前是按住输入。长按屏幕 Fn，或快速双击进入 Voice Agent。');},290);
  }
  fn.addEventListener('pointerdown',e=>{
    if(e.button!==0)return;pointerActive=true;held=false;fn.focus({preventScroll:true});fn.classList.add('pressed');
    try{fn.setPointerCapture(e.pointerId);}catch(_){}
    if(state.trigger==='hold'&&state.mode==='input')holdTimer=setTimeout(()=>{held=true;clearTimeout(tapTimer);lastTap=0;beginRecording(false);},180);
  });
  fn.addEventListener('pointerup',()=>{
    if(!pointerActive)return;pointerActive=false;clearTimeout(holdTimer);fn.classList.remove('pressed');
    if(held){held=false;finishRecording();}else registerTap();
  });
  fn.addEventListener('pointercancel',()=>{pointerActive=false;held=false;clearTimeout(holdTimer);fn.classList.remove('pressed');if(state.phase==='listening')setMode(state.mode);});
  fn.addEventListener('keydown',e=>{
    if(e.key===' '||e.key==='Enter'){e.preventDefault();if(e.repeat)return;keyboardHandledUntil=performance.now()+600;fn.classList.add('pressed');if(state.trigger==='hold'&&state.mode==='input'){held=true;beginRecording(false);}else registerTap();}
  });
  fn.addEventListener('keyup',e=>{if(e.key===' '||e.key==='Enter'){e.preventDefault();keyboardHandledUntil=performance.now()+600;fn.classList.remove('pressed');if(held){held=false;finishRecording();}}});
  // Assistive technology may synthesize a click without a pointer sequence.
  fn.addEventListener('click',e=>{if(e.detail===0&&!held&&performance.now()>keyboardHandledUntil){if(state.trigger==='hold')beginRecording(true);else registerTap();}});
  $$('#demo [data-demo-mode]').forEach(b=>b.addEventListener('click',()=>{clearTimeout(tapTimer);lastTap=0;setMode(b.dataset.demoMode);}));
  $('#demo-reset').addEventListener('click',()=>{clearTimeout(tapTimer);lastTap=0;setMode(state.mode);});
  document.addEventListener('keydown',e=>{if(e.key==='Escape'){clearTimeout(tapTimer);lastTap=0;setMode(state.mode);fn.classList.remove('pressed');}});
  $$('[data-demo-try]').forEach(b=>b.addEventListener('click',()=>{
    clearTimeout(tapTimer);lastTap=0;setMode('input');$('#demo').scrollIntoView({behavior:reduced?'instant':'smooth',block:'center'});
    fn.classList.remove('key-attention');void fn.offsetWidth;fn.classList.add('key-attention');
    fn.focus({preventScroll:true});later(()=>beginRecording(true),reduced?0:400);
  }));
  function setTrigger(trigger,notify=true){
    state.trigger=trigger;$$('[data-trigger]').forEach(b=>{const on=b.dataset.trigger===trigger;b.setAttribute('aria-checked',String(on));b.tabIndex=on?0:-1;});
    $('#trigger-description').textContent=trigger==='hold'?(language === 'en' ? 'Hold to speak, release to finish. It follows your instinct.' : '按住时说话，松开就完成。跟着直觉，不用多想。'):(language === 'en' ? 'Tap once to start, again to stop. Go at your own pace.' : '点一下开始，再点一下结束。按你的节奏来。');
    $('#key-caption').textContent=trigger==='hold'?'HOLD TO TALK':'CLICK TO TRY';
    if(state.phase==='idle'||state.phase==='done')setMode(state.mode);
    if(notify)toast(trigger==='hold'?tr('setHold'):tr('setTap'));
  }
  $$('[data-trigger]').forEach(b=>{b.addEventListener('click',()=>setTrigger(b.dataset.trigger));b.addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();const target=state.trigger==='tap'?'hold':'tap';setTrigger(target);$(`[data-trigger="${target}"]`).focus();}});});
  async function copyText(text){
    try{
      if(navigator.clipboard&&window.isSecureContext)await navigator.clipboard.writeText(text);
      else{const t=document.createElement('textarea');t.value=text;t.setAttribute('readonly','');t.style.cssText='position:fixed;left:-9999px;top:0';document.body.appendChild(t);t.select();const ok=document.execCommand('copy');t.remove();if(!ok)throw new Error('Clipboard unavailable');}
      toast('已复制，可以粘贴到你的文字里。');
    }catch(_){toast('浏览器未允许复制，请选中文本后使用 ⌘C / Ctrl+C。');}
  }
  $('#copy-agent').addEventListener('click',()=>copyText($('#agent-result-text').textContent));
  $('#copy-chat').addEventListener('click',()=>copyText($('#chat-answer-text').textContent));
  $('#replace-text').addEventListener('click',()=>{$('#demo-text').textContent=$('#agent-result-text').textContent;$('#demo-text').classList.remove('selected');$('#agent-result').hidden=true;$('#demo-footer-text').textContent=language === 'en' ? 'Only the demo text was replaced' : '只替换演示窗口中的文字';updatePill(language === 'en' ? 'Replaced. Keep going.' : '替换完成。下一句，继续。','done');announce(language === 'en' ? 'The translation replaced the demo text.' : '翻译已替换演示窗口中的原文。');});
  $('#followup-agent').addEventListener('click',()=>{cancelRun();updatePill(tr('pillShort'),'thinking');later(()=>typeText($('#agent-result-text'),'Let’s discuss the new design this Friday.',()=>updatePill(tr('pillShortDone'),'done')),450);});
  const answers={short:'Let’s discuss the new design at 3 this Friday.',casual:'Let’s chat about the new design at 3 on Friday.',reset:'Let’s get together this Friday at 3 to talk about the new design.'};
  $$('[data-rewrite]').forEach(b=>b.addEventListener('click',()=>{$$('[data-rewrite]').forEach(x=>x.classList.toggle('active',x===b&&b.dataset.rewrite!=='reset'));$('#chat-answer-text').textContent=answers[b.dataset.rewrite];$('.chat-answer').classList.remove('flash');void $('.chat-answer').offsetWidth;$('.chat-answer').classList.add('flash');}));
  const switches = $$('.privacy-card .switch');
  switches.forEach(button => button.addEventListener('click', () => {
    button.setAttribute('aria-checked', String(button.getAttribute('aria-checked') !== 'true'));
    $('#context-count').textContent = `网页演示：已允许 ${switches.filter(item => item.getAttribute('aria-checked') === 'true').length} 项上下文`;
  }));
  $('#context-count').textContent = '网页演示：已允许 3 项上下文';
})();
