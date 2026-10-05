export type Lang = 'zh' | 'en';

// Pill strings mirror Localizable.xcstrings so the overlay reads like the app.
const zh = {
  hookA: ['想法', '很快。'],
  hookB: ['打', '字', '太', '慢', '。'],
  press: ['按一下 Fn，', '直接说。'],
  spoken: ['周五的评审', '改到', '下午四点，', '材料', '我今晚', '发你。'],
  mail: {app: '邮件', to: '收件人', toValue: '设计组', subject: '主题', subjectValue: '评审时间调整', greeting: '大家好，'},
  land: '说完，字就落在光标处。',
  montage: [
    {app: '聊天', peer: '小林', bubble: '我快到了，你在哪？', text: '到楼下了，你慢慢来。'},
    {app: '笔记', title: '周末', text: '买牛奶、鸡蛋和咖啡豆。'},
    {app: '提交说明', title: 'main', text: '修复暗色模式下首页的对比度'},
  ],
  double: ['连按两次 Fn，', '说出你的要求。'],
  agent: {
    app: '聊天',
    peer: '项目群',
    bubble: '会议三点开始，大家准时哦',
    selected: '晚点到 你们先开 十分钟',
    command: ['改得', '客气', '一点'],
    result: '不好意思，我会晚到十分钟左右，大家先开始，不用等我。',
  },
  pill: {
    listening: '正在听…',
    transcribing: '正在识别…',
    inserted: '已输入',
    understanding: '正在理解…',
    running: '正在执行 · 改得客气一点',
    done: '已完成',
    undo: '撤销',
  },
  verbs: ['改写', '翻译', '起草', '提问'],
  finale: {
    line: '让想法，脱口而出。',
    url: 'say.anikuku.com',
    meta: 'macOS 14+ · App 免费开源 · 自备 Qwen API Key',
  },
  disclaimer: '界面为功能示意，非实际录屏',
};

export type Copy = typeof zh;

const en: Copy = {
  hookA: ['Ideas', 'are fast.'],
  hookB: ['Typ', 'ing ', 'is ', 'slo', 'w.'],
  press: ['Press Fn.', 'Just say it.'],
  spoken: ['Let’s move', 'Friday’s review', 'to 4 pm.', 'I’ll send', 'the deck', 'tonight.'],
  mail: {app: 'Mail', to: 'To', toValue: 'Design team', subject: 'Subject', subjectValue: 'Review time change', greeting: 'Hi all,'},
  land: 'It lands where you type.',
  montage: [
    {app: 'Chat', peer: 'Sam', bubble: 'Almost there. Where are you?', text: 'Downstairs now. Take your time.'},
    {app: 'Notes', title: 'Weekend', text: 'Pick up milk, eggs and coffee beans.'},
    {app: 'Commit message', title: 'main', text: 'Fix home page contrast in dark mode'},
  ],
  double: ['Double-press Fn.', 'Say what you need.'],
  agent: {
    app: 'Chat',
    peer: 'Project team',
    bubble: 'Kickoff at 3. See you all there!',
    selected: 'running late start w/o me 10 min',
    command: ['Make it', 'more', 'polite.'],
    result: 'Sorry, I’m running about 10 minutes late. Please start without me.',
  },
  pill: {
    listening: 'Listening…',
    transcribing: 'Transcribing…',
    inserted: 'Inserted',
    understanding: 'Understanding…',
    running: 'Running · Make it more polite',
    done: 'Done',
    undo: 'Undo',
  },
  verbs: ['Rewrite.', 'Translate.', 'Draft.', 'Ask.'],
  finale: {
    line: 'Just Say It.',
    url: 'say.anikuku.com',
    meta: 'macOS 14+ · Free and open source · Bring your own Qwen API key',
  },
  disclaimer: 'Simulated UI, not a screen recording',
};

export const COPY: Record<Lang, Copy> = {zh, en};

/** Every glyph a version draws, so fonts can be loaded before the first frame. */
export const glyphs = (copy: Copy) => {
  const text: string[] = [];
  const walk = (value: unknown) => {
    if (typeof value === 'string') text.push(value);
    else if (value && typeof value === 'object') Object.values(value).forEach(walk);
  };
  walk(copy);
  return [...new Set(text.join('') + 'SayKukufn⌃⌥⇧0123456789')].join('');
};
