// Simulador do app masterSync para Mac. Telas e textos seguem o app real (Sidebar, DashboardChrome, SMS, Arquivos…).
// Dados de exemplo; nada aqui fala com um aparelho de verdade.
(function () {
  var root = document.getElementById('sim');
  if (!root) return;

  var ICON = {
    overview: 'M8 2h8a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zM11 18h2',
    conversation: 'M8 9h8M8 13h5M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.5A8 8 0 1 1 21 12z',
    sms: 'M5 4h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9l-5 4V6a2 2 0 0 1 1-2z',
    notifications: 'M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.94 1.94 0 0 0 3.4 0',
    gallery: 'M5 4h14a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zM4 16l5-5 4 4 3-3 4 4M15.5 9h.01',
    files: 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
    remote: 'M5 3l14 7-6 2-2 6zM13 12l5 5',
    apps: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z',
    calls: 'M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z',
    webcam: 'M3 7h12v10H3zM15 10l6-3v10l-6-3',
    settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
    dnd: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM8 12h8',
    silent: 'M11 5L6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6',
    ring: 'M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z',
    hotspot: 'M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7',
    torch: 'M8 2h8v5l-2 3v12h-4V10L8 7zM12 13v2',
    lock: 'M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4',
    clipboard: 'M8 3h8v4H8zM16 5h2a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2',
    devices: 'M8 2h8a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zM11 18h2'
  };
  function svg(name, size, sw) {
    return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="' + (sw || 1.8) + '" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + ICON[name] + '"/></svg>';
  }
  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function pad(n) { return String(n).padStart(2, '0'); }
  function now() { var d = new Date(); return pad(d.getHours()) + ':' + pad(d.getMinutes()); }

  var NAV = [['overview', 'Visão geral'], ['conversation', 'Conversa'], ['sms', 'SMS'], ['notifications', 'Notificações'], ['gallery', 'Fotos'], ['files', 'Arquivos'], ['remote', 'Controle remoto'], ['apps', 'Apps']];
  var TITLE = { overview: 'Visão geral', conversation: 'Conversa', sms: 'SMS', notifications: 'Notificações', gallery: 'Fotos', files: 'Arquivos', remote: 'Controle remoto', apps: 'Apps', clipboard: 'Área de transferência', devices: 'Dispositivos', settings: 'Configurações' };
  var SUB = { overview: 'Tudo do seu celular, num só lugar', conversation: 'Conversa e arquivos com o celular', sms: 'Leia e responda SMS pelo Mac', notifications: 'Espelhadas em tempo real', gallery: 'Fotos e vídeos do celular', files: 'Enviados e recebidos', remote: 'Controle o celular pelo Mac', apps: 'Abra os apps do celular no Mac', clipboard: 'Copiado nos dois aparelhos', devices: 'Celulares conectados e pareamento', settings: 'Aparência, atalhos e conexão' };
  var QC = [['dnd', 'Não perturbe'], ['silent', 'Silencioso'], ['ring', 'Tocar celular'], ['hotspot', 'Hotspot'], ['torch', 'Lanterna'], ['lock', 'Bloquear']];
  var QC_NAMES = { dnd: 'Não perturbe', silent: 'Silencioso', hotspot: 'Hotspot', torch: 'Lanterna' };

  var NOTIF_POOL = [
    { app: 'Instagram', title: 'marina.lopes', text: 'curtiu sua foto', letter: 'I', color: '#b8457a' },
    { app: 'iFood', title: 'Pedido a caminho', text: 'Chega em 15–25 min', letter: 'i', color: '#c23b32' },
    { app: 'Telegram', title: 'Grupo da faculdade', text: 'Pedro: alguém tem o slide de ontem?', letter: 'T', color: '#2477b8' },
    { app: 'Google Agenda', title: 'Almoço com a equipe', text: 'Em 15 min · Restaurante Central', letter: 'G', color: '#b35a0a' }
  ];
  var CLIP_POOL = ['Rua das Flores, 120 — Apto 34', 'https://maps.app.goo.gl/centro', 'Senha do Wi‑Fi da sala: visitantes2026'];
  var FILE_POOL = [['Apresentacao_final.pdf', '4,2 MB'], ['Fotos_viagem.zip', '18 MB'], ['Contrato_assinado.pdf', '860 KB']];

  var GALLERY = [
    ['IMG_2104.jpg', 'photo', 'Hoje', 'linear-gradient(160deg,#8e3b3b,#e07a6a)', 0],
    ['IMG_2103.jpg', 'photo', 'Hoje', 'linear-gradient(160deg,#5e6b1f,#b9d16a)', 1],
    ['IMG_2102.jpg', 'photo', 'Hoje', 'linear-gradient(160deg,#1d5c4e,#6fd6b4)', 0],
    ['VID_2101.mp4', 'video', 'Hoje', 'linear-gradient(160deg,#2e2f7a,#7c82e6)', 0, '0:42'],
    ['IMG_2100.jpg', 'photo', 'Hoje', 'linear-gradient(160deg,#6a2350,#e07ab5)', 0],
    ['Screenshot_1158.png', 'shot', 'Hoje', 'linear-gradient(180deg,#e9ecf2,#b9c0cc)', 0],
    ['IMG_2098.jpg', 'photo', 'Ontem', 'linear-gradient(160deg,#7a4a1a,#f0b36a)', 1],
    ['IMG_2097.jpg', 'photo', 'Ontem', 'linear-gradient(160deg,#173a5c,#5fa2e0)', 0],
    ['VID_2096.mp4', 'video', 'Ontem', 'linear-gradient(160deg,#3a1f5c,#a77be6)', 0, '1:15'],
    ['IMG_2095.jpg', 'photo', 'Ontem', 'linear-gradient(160deg,#2f4a2a,#8ccb7a)', 0],
    ['Screenshot_0931.png', 'shot', 'Ontem', 'linear-gradient(180deg,#1e2230,#444b60)', 0],
    ['IMG_2090.jpg', 'photo', 'Terça', 'linear-gradient(160deg,#5c1f1f,#c4664f)', 0],
    ['IMG_2089.jpg', 'photo', 'Terça', 'linear-gradient(160deg,#1a4d57,#64c3cf)', 1],
    ['IMG_2088.jpg', 'photo', 'Terça', 'linear-gradient(160deg,#4d3a1a,#cfae64)', 0]
  ].map(function (r, i) { return { idx: i, name: r[0], kind: r[1], day: r[2], g: r[3], fav: !!r[4], dur: r[5] || '' }; });

  var s = {
    section: 'overview',
    qc: { dnd: false, silent: false, ring: false, hotspot: false, torch: false, lock: false },
    soundMac: true,
    notifs: [
      { id: 1, app: 'WhatsApp', title: 'Rafa', text: 'Bora no futebol quinta? Tô montando o time', time: '12:12', letter: 'W', color: '#b8457a' },
      { id: 2, app: 'Google Agenda', title: 'Revisão de design em 30 min', text: 'Sala 3B · Google Meet', time: '11:47', letter: 'G', color: '#b35a0a' },
      { id: 3, app: 'Nubank', title: 'Pix recebido', text: 'Você recebeu R$ 120,00 de Júlia Martins', time: '11:13', letter: 'N', color: '#7a3fc4' },
      { id: 4, app: 'Gmail', title: 'Ana Souza', text: 'Re: Assets finais — tudo aprovado pelo cliente', time: '10:40', letter: 'G', color: '#4e62d6' }
    ],
    nextId: 10, notifIdx: 0, clipIdx: 0, fileIdx: 0,
    threads: [
      { id: 'lucas', name: 'Lucas Andrade', ini: 'LA', number: '+55 11 99999-0000', color: '#b35a0a', when: '12:15', unread: false, msgs: [
        { out: false, text: 'Conseguiu ver o protótipo?', time: '12:05' },
        { out: true, text: 'Vi sim! Ficou muito bom, só ajustaria o onboarding.', time: '12:10' },
        { out: false, text: 'Fechado. Te mando a versão nova até as 16h', time: '12:14' }] },
      { id: 'code', name: '29104', ini: '#', number: 'Código curto', color: '#6a5fd0', when: 'Ontem', unread: true, msgs: [
        { out: false, text: 'Seu código de verificação é 482913. Não compartilhe com ninguém.', time: 'Ontem' }] },
      { id: 'nubank', name: 'NUBANK', ini: 'N', number: 'Mensagem do banco', color: '#7a7a12', when: '22/11', unread: false, msgs: [
        { out: false, text: 'Compra aprovada R$ 38,90 em PADARIA CENTRAL.', time: '22/11' }] }
    ],
    smsSel: 'lucas', typing: false,
    drafts: { sms: '', convo: '' },
    convo: [
      { mine: false, text: 'Foto do quadro da reunião', time: '11:02' },
      { mine: false, file: 'IMG_2091.jpg', size: '1,9 MB', time: '11:02' },
      { mine: true, text: 'Lista de compras: café, leite e pão', time: '11:20' }
    ],
    galTab: 'all', lb: null,
    transfers: [
      { id: 1, name: 'Roteiro_viagem.docx', out: true, size: '312 KB', meta: '15:40 · Celular · Download/MasterSync', progress: 100 },
      { id: 2, name: 'IMG_2087.HEIC', out: false, size: '2,8 MB', meta: '14:02 · Mac · Downloads', progress: 100 }
    ],
    fileTab: 'all', openOnReceive: false, zipFolders: true, otpAuto: true, remote: false,
    apps: [
      { id: 'wa', name: 'WhatsApp', letter: 'W', color: '#1e8c4e', pinned: true },
      { id: 'sp', name: 'Spotify', letter: 'S', color: '#14783f', pinned: true },
      { id: 'nu', name: 'Nubank', letter: 'N', color: '#7a3fc4', pinned: true },
      { id: 'ig', name: 'Instagram', letter: 'I', color: '#b8457a', pinned: false },
      { id: 'if', name: 'iFood', letter: 'i', color: '#c23b32', pinned: false },
      { id: 'mp', name: 'Maps', letter: 'M', color: '#2c7bc4', pinned: false },
      { id: 'tg', name: 'Telegram', letter: 'T', color: '#2477b8', pinned: false },
      { id: 'wz', name: 'Waze', letter: 'W', color: '#1f86a8', pinned: false },
      { id: 'yt', name: 'YouTube', letter: 'Y', color: '#c4271f', pinned: false },
      { id: 'gm', name: 'Gmail', letter: 'G', color: '#b5261e', pinned: false }
    ],
    clip: [{ text: 'Reunião às 15h na sala 3B', from: 'Celular', when: 'há 4 min' }, { text: 'contato@estudio.com.br', from: 'Mac', when: 'há 22 min' }],
    otp: null, scan: null, toast: null
  };

  var timers = [];
  function later(fn, ms) { var id = setTimeout(fn, ms); timers.push(id); return id; }
  var toastTimer, otpTimer, xferTick = null, scanTick = null;
  function toast(text) { clearTimeout(toastTimer); s.toast = text; render(); toastTimer = later(function () { s.toast = null; render(); }, 2400); }

  // ---------- views ----------
  function bubble(out, text, time) {
    return '<div class="mb ' + (out ? 'out' : 'in') + '"><div class="t">' + esc(text) + '</div><small class="num">' + esc(time) + '</small></div>';
  }
  function notifRow(n) {
    return '<div class="notif"><span class="ic" style="background:' + n.color + '">' + esc(n.letter) + '</span><div class="b"><div><strong style="font-size:14px">' + esc(n.title) + '</strong> <span class="faint" style="font-size:12px">' + esc(n.app) + '</span></div><div class="m">' + esc(n.text) + '</div></div><span class="tm num">' + esc(n.time) + '</span></div>';
  }
  function photo(p, label) {
    return '<button class="ph" data-act="lb-open" data-i="' + p.idx + '" aria-label="Abrir ' + esc(p.name) + '" style="background:' + p.g + '">' +
      (p.kind === 'video' ? '<span class="tag">' + (label || 'Vídeo') + '</span>' : '') + '</button>';
  }
  function sw(act, on, label) {
    return '<button class="switch" role="switch" aria-checked="' + on + '" aria-label="' + label + '" data-act="' + act + '"><i></i></button>';
  }
  function qrCells() {
    var out = '';
    for (var y = 0; y < 21; y++) for (var x = 0; x < 21; x++) {
      var dark, f = null;
      [[0, 0], [14, 0], [0, 14]].forEach(function (c) { if (x >= c[0] && x < c[0] + 7 && y >= c[1] && y < c[1] + 7) f = c; });
      if (f) { var dx = x - f[0], dy = y - f[1]; dark = dx === 0 || dx === 6 || dy === 0 || dy === 6 || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4); }
      else if ((x === 7 || y === 7 || x === 13 || y === 13) && (x < 8 || y < 8 || (x > 12 && y < 8))) dark = false;
      else dark = ((x * 7 + y * 13 + x * y * 3) % 5) < 2;
      out += '<i style="background:' + (dark ? '#14161b' : '#fff') + '"></i>';
    }
    return out;
  }

  function viewOverview() {
    var qc = QC.map(function (q) {
      var on = s.qc[q[0]];
      return '<button data-act="qc" data-id="' + q[0] + '" aria-pressed="' + on + '" class="' + (on ? 'on' : '') + '"><span class="c">' + svg(q[0], 20) + '</span><span class="l">' + (q[0] === 'ring' && on ? 'Tocando…' : q[1]) + '</span></button>';
    }).join('');
    var top = s.notifs.slice(0, 4).map(notifRow).join('') || '<span class="muted" style="padding:12px 0">Nenhuma notificação agora.</span>';
    var recent = GALLERY.slice(0, 5).map(function (p) { return photo(p); }).join('');
    return '<div class="wrapflex">' +
      '<div class="card col" style="flex:1 1 280px;min-width:0;padding:20px;gap:16px">' +
        '<div class="row" style="align-items:baseline;justify-content:space-between;gap:8px"><span class="big-batt num">82%</span><span class="muted" style="font-size:12.5px">carregando</span></div>' +
        '<span class="bar" style="height:6px"><i style="width:82%"></i></span><hr class="sep">' +
        '<div class="qc">' + qc + '</div><hr class="sep">' +
        '<span class="cap" style="font-size:10px">Som do celular</span>' +
        '<div class="seg2" role="group" aria-label="Som do celular"><button data-act="sound" data-v="mac" class="' + (s.soundMac ? 'on' : '') + '" aria-pressed="' + s.soundMac + '">No Mac</button><button data-act="sound" data-v="phone" class="' + (!s.soundMac ? 'on' : '') + '" aria-pressed="' + !s.soundMac + '">No celular</button></div>' +
      '</div>' +
      '<div class="col" style="flex:1.6 1 320px;min-width:0;gap:16px">' +
        '<div class="card col" style="gap:12px"><div class="row" style="justify-content:space-between;align-items:center"><strong style="font-size:16px">Agora no Pixel 9 Pro</strong><button class="link-btn" style="font-size:13.5px" data-act="go" data-id="notifications">Ver tudo</button></div>' + top + '</div>' +
        '<div class="card col" style="gap:12px"><div class="row" style="justify-content:space-between;align-items:center"><strong style="font-size:16px">Fotos recentes</strong><button class="link-btn" style="font-size:13.5px" data-act="go" data-id="gallery">Ver biblioteca</button></div><div class="photos5">' + recent + '</div></div>' +
      '</div></div>';
  }

  function viewConversation() {
    var msgs = s.convo.map(function (m) {
      if (m.file) return '<div class="mb in"><small>Pixel 9 Pro · ' + m.time + '</small><div class="filecard"><i></i><span class="col"><span class="mono" style="font-size:12.5px">' + esc(m.file) + '</span><small class="muted" style="font-size:11.5px">' + m.size + '</small></span></div></div>';
      return '<div class="mb ' + (m.mine ? 'out' : 'in') + '"><small>' + (m.mine ? 'Mac' : 'Pixel 9 Pro') + ' · ' + m.time + '</small><div class="t">' + esc(m.text) + '</div></div>';
    }).join('');
    return '<div class="chat" style="height:520px"><div class="msgs" id="convoMsgs">' + msgs + '</div>' +
      '<div class="compose"><label class="sr" for="convoIn">Mensagem para o celular</label><input id="convoIn" data-draft="convo" placeholder="Escreva algo para o celular" autocomplete="off" value="' + esc(s.drafts.convo) + '"><button class="send" data-act="convo-send" aria-label="Enviar"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5 12l7-7 7 7"/></svg></button></div></div>';
  }

  function viewSms() {
    var sel = s.threads.filter(function (t) { return t.id === s.smsSel; })[0];
    var list = s.threads.map(function (t) {
      var last = t.msgs[t.msgs.length - 1];
      return '<button class="thread' + (t.id === sel.id ? ' sel' : '') + '" data-act="thread" data-id="' + t.id + '"><span class="av" style="background:' + t.color + '">' + esc(t.ini) + '</span><span class="tx"><span class="l1"><strong style="font-size:14px">' + esc(t.name) + '</strong><small>' + esc(t.when) + '</small></span><span class="l2"><span class="pv' + (t.unread ? ' unread' : '') + '">' + (last.out ? 'Você: ' : '') + esc(last.text) + '</span>' + (t.unread ? '<i class="dot" aria-label="Não lida"></i>' : '') + '</span></span></button>';
    }).join('');
    var msgs = sel.msgs.map(function (m) { return bubble(m.out, m.text, m.time); }).join('') + (s.typing && sel.id === 'lucas' ? '<div class="typing" style="align-self:flex-start;color:var(--muted);font-size:13px;display:block">digitando…</div>' : '');
    return '<div class="wrapflex" style="align-items:stretch"><div class="threads"><label class="search"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4"/></svg><span class="sr">Buscar conversas</span><input placeholder="Buscar"></label>' + list + '</div>' +
      '<div class="chat sms"><div class="head"><span class="av" style="background:' + sel.color + '">' + esc(sel.ini) + '</span><span class="col"><strong style="font-size:15px">' + esc(sel.name) + '</strong><span class="muted" style="font-size:12.5px">' + esc(sel.number) + '</span></span></div>' +
      '<div class="msgs" id="smsMsgs">' + msgs + '</div>' +
      '<div class="compose"><label class="sr" for="smsIn">Mensagem de texto</label><input id="smsIn" data-draft="sms" placeholder="Mensagem de texto" autocomplete="off" value="' + esc(s.drafts.sms) + '"><button class="send" data-act="sms-send" aria-label="Enviar SMS"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5 12l7-7 7 7"/></svg></button></div></div></div>';
  }

  function viewNotifications() {
    var rows = s.notifs.map(function (n) {
      return '<div class="notif card" style="padding:14px 16px;border-radius:18px"><span class="ic" style="background:' + n.color + '">' + esc(n.letter) + '</span><div class="b"><div><strong style="font-size:14px">' + esc(n.title) + '</strong> <span class="faint" style="font-size:12px">' + esc(n.app) + ' · ' + esc(n.time) + '</span></div><div class="muted" style="white-space:normal">' + esc(n.text) + '</div></div><button class="send" style="width:32px;height:32px;background:var(--panel-2);color:var(--muted)" data-act="dismiss" data-id="' + n.id + '" aria-label="Dispensar notificação de ' + esc(n.app) + '"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>';
    }).join('');
    return '<div class="col" style="gap:10px"><div class="row" style="justify-content:space-between;align-items:center;gap:12px"><span class="muted num">' + s.notifs.length + ' no celular agora</span><button class="pill-btn" style="min-height:32px" data-act="clear">Limpar tudo</button></div>' +
      (s.notifs.length ? rows : '<div class="card muted" style="padding:48px 20px;text-align:center">Tudo em dia. Some no celular também.</div>') + '</div>';
  }

  function viewGallery() {
    var tabs = [['all', 'Tudo'], ['photo', 'Fotos'], ['video', 'Vídeos'], ['shot', 'Capturas'], ['fav', 'Favoritas']].map(function (t) {
      return '<button class="tab' + (s.galTab === t[0] ? ' on' : '') + '" role="tab" aria-selected="' + (s.galTab === t[0]) + '" data-act="gtab" data-id="' + t[0] + '">' + t[1] + '</button>';
    }).join('');
    var items = GALLERY.filter(galFilter);
    var days = [];
    items.forEach(function (p) { var g = days.filter(function (d) { return d.day === p.day; })[0]; if (!g) { g = { day: p.day, items: [] }; days.push(g); } g.items.push(p); });
    var groups = days.map(function (g) {
      return '<div class="col" style="gap:8px"><span style="font-size:14px;font-weight:700">' + g.day + ' <span class="faint" style="font-weight:400">· ' + g.items.length + (g.items.length === 1 ? ' item' : ' itens') + '</span></span><div class="gal-grid">' + g.items.map(function (p) { return photo(p, p.dur); }).join('') + '</div></div>';
    }).join('');
    return '<div class="col" style="gap:16px"><div class="tabs" role="tablist" aria-label="Filtro da galeria">' + tabs + '</div>' + groups + '</div>';
  }

  function viewFiles() {
    var tabs = [['all', 'Todas'], ['out', 'Enviadas'], ['in', 'Recebidas']].map(function (t) {
      return '<button class="tab' + (s.fileTab === t[0] ? ' on' : '') + '" role="tab" aria-selected="' + (s.fileTab === t[0]) + '" data-act="ftab" data-id="' + t[0] + '">' + t[1] + '</button>';
    }).join('');
    var list = s.transfers.filter(function (f) { return s.fileTab === 'all' || (s.fileTab === 'out' ? f.out : !f.out); }).map(function (f) {
      var run = f.progress < 100;
      return '<div class="xfer"><span class="ic"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + (f.out ? 'M7 17L17 7M8 7h9v9' : 'M17 7L7 17M16 17H7V8') + '"/></svg></span><span class="mid"><span class="l1"><b>' + esc(f.name) + '</b><span class="num">' + (run ? 'Enviando · ' + f.progress + '%' : (f.out ? 'Enviado' : 'Recebido') + ' · ' + f.size) + '</span></span>' + (run ? '<span class="bar" style="height:4px"><i style="width:' + f.progress + '%"></i></span>' : '') + '<small>' + esc(f.meta) + '</small></span></div>';
    }).join('');
    return '<div class="wrapflex"><div class="col" style="flex:1.6 1 340px;min-width:0;gap:14px">' +
      '<div class="drop"><span class="ic">' + '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5M12 17v-6M9.5 13.5L12 11l2.5 2.5"/></svg></span><span class="tx"><strong style="font-size:14.5px">Arraste arquivos ou pastas para enviar ao celular</strong><small>Conectado · pronto para enviar</small></span><span class="row" style="gap:8px"><button class="pill-btn" data-act="paste">Colar</button><button class="pill-btn primary" data-act="choose">+ Escolher</button></span></div>' +
      '<div class="tabs" role="tablist" aria-label="Filtro de transferências">' + tabs + '</div>' + list + '</div>' +
      '<div class="col" style="flex:1 1 240px;min-width:0;gap:14px">' +
        '<div class="card col" style="gap:12px;padding:16px 18px"><div class="row" style="justify-content:space-between;align-items:baseline"><strong style="font-size:14.5px">Armazenamento do celular</strong><span class="muted" style="font-size:12.5px">76 GB livres</span></div>' +
        '<div class="stack"><i style="width:29.7%;background:#a78bfa"></i><i style="width:20.7%;background:#0bc18d"></i><i style="width:8.6%;background:#6cc24a"></i><i style="width:11.7%;background:#f0904a"></i></div>' +
        '<div class="legend"><span><span class="muted">● Fotos e vídeos</span><b>76 GB</b></span><span><span class="muted">● Música</span><b>53 GB</b></span><span><span class="muted">● WhatsApp</span><b>22 GB</b></span><span><span class="muted">● Outros</span><b>30 GB</b></span></div></div>' +
        '<div class="card" style="padding:6px 18px"><div class="setrow"><span class="tx"><strong>Abrir ao receber</strong><small>Abre o arquivo assim que chega no Mac</small></span>' + sw('toggle-open', s.openOnReceive, 'Abrir ao receber') + '</div><div class="setrow"><span class="tx"><strong>Compactar pastas</strong><small>Pastas são enviadas como .zip</small></span>' + sw('toggle-zip', s.zipFolders, 'Compactar pastas') + '</div></div>' +
      '</div></div>';
  }

  function viewRemote() {
    var on = s.remote;
    var screen = on
      ? '<div class="clk num">12:16</div><span style="font-size:12.5px;opacity:.85;margin-bottom:6px">sexta, 27 de novembro</span><div class="apps">' + s.apps.slice(0, 8).map(function (a) { return '<button data-act="rapp" data-id="' + a.id + '"><span class="c" style="background:' + a.color + '">' + esc(a.letter) + '</span><span style="max-width:52px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">' + esc(a.name) + '</span></button>'; }).join('') + '</div>'
      : '<div class="col" style="flex:1;align-items:center;justify-content:center;gap:10px;text-align:center;color:var(--muted)">' + svg('remote', 28, 1.6) + '<span style="font-size:12.5px">A tela do celular aparece aqui.</span></div>';
    return '<div class="row" style="flex-wrap:wrap;gap:24px;align-items:center;justify-content:center;padding:8px 0"><div class="remote-phone ' + (on ? 'on' : 'off') + '">' + screen + '</div>' +
      '<div class="col" style="flex:0 1 300px;gap:12px"><strong style="font-size:18px;letter-spacing:-.01em">' + (on ? 'Controlando o Pixel 9 Pro' : 'A tela do celular, numa janela do Mac') + '</strong><span class="muted">Mouse, rolagem e teclado direto no Android. Sem pedido de autorização no celular, e a conexão não cai quando ele bloqueia.</span>' +
      '<button class="pill-btn' + (on ? '' : ' primary') + '" style="align-self:flex-start;min-height:40px;padding:0 20px" data-act="remote">' + (on ? 'Encerrar controle' : 'Iniciar controle') + '</button><span class="faint" style="font-size:12px">Usa ADB sem fio e o servidor do scrcpy.</span></div></div>';
  }

  function viewApps() {
    var cards = s.apps.map(function (a) {
      return '<div class="app-card' + (a.pinned ? ' pinned' : '') + '"><button class="big" style="background:' + a.color + '" data-act="open-app" data-id="' + a.id + '" aria-label="Abrir ' + esc(a.name) + '">' + esc(a.letter) + '</button><span style="font-weight:600;text-align:center">' + esc(a.name) + '</span><button class="tab' + (a.pinned ? ' on' : '') + '" style="min-height:28px;padding:0 12px;font-size:12px" aria-pressed="' + a.pinned + '" data-act="pin" data-id="' + a.id + '">' + (a.pinned ? 'Fixado' : 'Fixar') + '</button></div>';
    }).join('');
    return '<div class="col" style="gap:14px"><span class="muted">Fixe um app e ele vira um app do Mac, no Launchpad e no Spotlight, abrindo numa janela própria.</span><div class="app-grid">' + cards + '</div></div>';
  }

  function viewClipboard() {
    return '<div class="col" style="gap:10px"><span class="muted">Copie num aparelho e cole no outro. Os códigos 2FA ficam de fora deste histórico.</span>' +
      s.clip.map(function (c) { return '<div class="card row" style="padding:12px 16px;border-radius:16px;align-items:center;gap:12px"><span style="flex:1;min-width:0">' + esc(c.text) + '</span><span class="faint" style="font-size:12px;white-space:nowrap">' + c.from + ' · ' + c.when + '</span></div>'; }).join('') + '</div>';
  }

  function viewDevices() {
    return '<div class="wrapflex"><div class="card col" style="flex:1 1 300px;padding:18px 20px;gap:12px"><strong style="font-size:15px">Pixel 9 Pro</strong>' +
      '<div class="row" style="justify-content:space-between;gap:12px;padding-top:10px;border-top:1px solid var(--line)"><span class="muted">Conexão</span><span class="acc" style="font-weight:600">Rede local · criptografada</span></div>' +
      '<div class="row" style="justify-content:space-between;gap:12px;padding-top:10px;border-top:1px solid var(--line)"><span class="muted">Identidade</span><span class="mono" style="font-size:12px">certificado fixado</span></div>' +
      '<div class="row" style="justify-content:space-between;gap:12px;padding-top:10px;border-top:1px solid var(--line)"><span class="muted">Controle por Wi‑Fi (ADB)</span><span style="font-weight:600">Ativo</span></div></div>' +
      '<div class="card col" style="flex:1 1 240px;padding:18px 20px;gap:12px;align-items:center;text-align:center"><strong style="font-size:15px">Parear outro celular</strong><div class="qr" role="img" aria-label="QR de pareamento de exemplo">' + qrCells() + '</div><span class="muted" style="font-size:12.5px">No Android: Dispositivos → Ler QR</span></div></div>';
  }

  function viewSettings() {
    var dark = window.getSiteTheme() === 'dark';
    return '<div class="card" style="max-width:560px;padding:6px 20px"><div class="setrow"><span class="tx"><strong>Aparência</strong><small>Tema da janela</small></span><div class="seg2" role="group" aria-label="Aparência" style="border-radius:999px"><button style="border-radius:999px;padding:0 14px" class="' + (dark ? 'on' : '') + '" aria-pressed="' + dark + '" data-act="theme" data-v="dark">Escuro</button><button style="border-radius:999px;padding:0 14px" class="' + (!dark ? 'on' : '') + '" aria-pressed="' + !dark + '" data-act="theme" data-v="light">Claro</button></div></div>' +
      '<div class="setrow"><span class="tx"><strong>Digitalizar</strong><small>Atalho global</small></span><kbd class="kbd">⌃⌥⌘D</kbd></div>' +
      '<div class="setrow"><span class="tx"><strong>Copiar códigos de verificação</strong><small>Fora do histórico, somem em 2 minutos</small></span>' + sw('toggle-otp', s.otpAuto, 'Copiar códigos de verificação') + '</div></div>';
  }

  var VIEWS = { overview: viewOverview, conversation: viewConversation, sms: viewSms, notifications: viewNotifications, gallery: viewGallery, files: viewFiles, remote: viewRemote, apps: viewApps, clipboard: viewClipboard, devices: viewDevices, settings: viewSettings };

  function sidebar() {
    var smsUnread = s.threads.filter(function (t) { return t.unread; }).length;
    var nav = NAV.map(function (n) {
      var badge = n[0] === 'sms' ? smsUnread : (n[0] === 'notifications' ? s.notifs.length : 0);
      var sel = s.section === n[0];
      return '<button class="nav-btn' + (sel ? ' sel' : '') + '" data-act="go" data-id="' + n[0] + '"' + (sel ? ' aria-current="page"' : '') + '>' + svg(n[0], 17) + '<span class="lbl">' + n[1] + '</span>' + (badge ? '<span class="badge num">' + badge + '</span>' : '') + '</button>';
    }).join('');
    var pinned = s.apps.filter(function (a) { return a.pinned; }).slice(0, 5);
    var pins = pinned.length ? '<div class="pin-grid">' + pinned.map(function (a) { return '<button style="background:' + a.color + '" data-act="open-app" data-id="' + a.id + '" aria-label="Abrir ' + esc(a.name) + '" title="' + esc(a.name) + '">' + esc(a.letter) + '</button>'; }).join('') + '</div>' : '<span class="muted" style="font-size:11.5px;padding:0 4px">Nenhum app fixado.</span>';
    var c = s.clip[0];
    return '<aside class="sim-side"><div class="lights" aria-hidden="true"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div>' +
      '<div class="phone-card"><div class="top"><div class="glyph" aria-hidden="true"><i></i></div><div><strong>Pixel 9 Pro</strong><div class="on"><i></i>Conectado · Wi‑Fi</div></div></div><div><div class="batt num"><span>Bateria</span><span>82% · carregando</span></div><span class="bar"><i style="width:82%"></i></span></div></div>' +
      '<nav class="nav" aria-label="Seções">' + nav + '</nav>' +
      '<div class="soon"><span class="cap" style="padding:0 10px 2px;display:block">Em breve</span><div>' + svg('calls', 14) + 'Chamadas</div><div>' + svg('webcam', 14) + 'Webcam</div></div>' +
      '<div class="side-spacer"></div>' +
      '<div class="pinned-head"><span class="cap">Apps fixados</span><button class="link-btn" data-act="go" data-id="apps">Gerenciar</button></div>' + pins +
      '<button class="clip-card" data-act="go" data-id="clipboard"><span class="cap">Área de transferência</span><span class="t">' + esc(c.text) + '</span><small>' + c.from + ' · ' + c.when + '</small></button>' +
      '<div class="foot-nav"><button data-act="go" data-id="devices" class="' + (s.section === 'devices' ? 'sel' : '') + '">' + svg('devices', 14) + 'Dispositivos</button><button data-act="go" data-id="settings" class="' + (s.section === 'settings' ? 'sel' : '') + '">' + svg('settings', 14) + 'Configurações</button></div></aside>';
  }

  function overlays() {
    var out = '';
    if (s.lb !== null) {
      var p = GALLERY[s.lb];
      out += '<div class="lb" role="dialog" aria-label="Visualizador de fotos"><div class="top"><div><b class="mono" style="font-size:13px">' + esc(p.name) + '</b><small>' + p.day + (p.kind === 'video' ? ' · vídeo ' + p.dur : '') + '</small></div><button class="lb-btn" data-act="lb-close" aria-label="Fechar visualizador"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>' +
        '<div class="stage"><button class="lb-btn" data-act="lb-prev" aria-label="Foto anterior"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg></button><div class="img" style="background:' + p.g + '">' + (p.kind === 'video' ? '<span class="play"><svg width="24" height="24" viewBox="0 0 24 24" fill="#fff" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg></span>' : '') + '</div><button class="lb-btn" data-act="lb-next" aria-label="Próxima foto"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg></button></div></div>';
    }
    if (s.otp) out += '<div class="popup otp" role="status"><span class="k">' + svg('lock', 14, 2) + 'Código copiado</span><span class="code num">' + s.otp.code + '</span><span class="muted" style="font-size:12px">SMS do Nubank · sai da área de transferência em 2 min</span></div>';
    if (s.scan) {
      var done = s.scan.done;
      out += '<div class="popup scan" role="status"><div class="row" style="align-items:center;gap:12px"><span class="doc" aria-hidden="true"><i></i><i></i><i></i></span><span class="col" style="flex:1"><strong>' + (done ? 'Página recebida' : 'Digitalizando no celular…') + '</strong><span class="muted" style="font-size:12px">' + (done ? 'Documento_' + now().replace(':', '') + '.pdf' : 'Recebendo página · ' + s.scan.progress + '%') + '</span></span></div>' +
        (done ? '<div class="row" style="gap:6px;flex-wrap:wrap"><button class="pill-btn primary sm" data-act="scan-end" data-m="Salvo em Documentos">Salvar</button><button class="pill-btn sm" data-act="scan-end" data-m="Página copiada">Copiar</button><button class="pill-btn sm" data-act="scan-end" data-m="Digitalização excluída">Excluir</button></div>' : '<span class="bar" style="height:4px"><i style="width:' + s.scan.progress + '%"></i></span>') + '</div>';
    }
    if (s.toast) out += '<div class="toast" role="status">' + esc(s.toast) + '</div>';
    return out;
  }

  function render() {
    // Guarda foco e posição de rolagem, porque o HTML é refeito.
    var active = document.activeElement, focusKey = active && active.dataset && active.dataset.draft;
    var body = root.querySelector('.sim-body'), top = body ? body.scrollTop : 0, sec = body && body.dataset.sec;
    var smsMsgs, convoMsgs;

    var bell = s.notifs.length;
    root.innerHTML =
      '<div class="sim-win">' + sidebar() +
        '<section class="sim-main"><header class="sim-head"><h3>' + TITLE[s.section] + '</h3><span class="sub">' + SUB[s.section] + '</span>' +
          '<button class="bell" data-act="go" data-id="notifications" aria-label="Notificações, ' + bell + ' pendentes">' + svg('notifications', 17) + (bell ? '<span class="badge num">' + bell + '</span>' : '') + '</button></header>' +
          '<div class="sim-body" data-sec="' + s.section + '"><div class="sim-pane">' + VIEWS[s.section]() + '</div></div>' +
          '<div class="sim-bar"><span class="ico" aria-hidden="true">' + svg('overview', 20) + '</span><span class="who"><strong>Pixel 9 Pro</strong><small><i></i>Conectado pela rede local</small></span><span class="num" style="font-size:12.5px;font-weight:600">82%</span><button class="pill-btn" data-act="send-bar">Enviar arquivo</button></div></section>' +
        overlays() + '</div>' +
      '<div class="sim-triggers"><span>Simule no celular:</span><button data-act="fire-otp">Chegou um código 2FA</button><button data-act="fire-notif">Nova notificação</button><button data-act="fire-copy">Copiei um texto</button><button data-act="fire-scan">Digitalizar documento</button></div>' +
      '<p class="note">Simulação com dados de exemplo. Nada aqui se conecta a um aparelho real.</p>';

    var nb = root.querySelector('.sim-body');
    if (sec === s.section) nb.scrollTop = top;
    // A animação de entrada só roda quando algo é novo, não a cada atualização.
    var seen = render.seen || (render.seen = {});
    function fresh(sel, key, val) { var el = root.querySelector(sel); if (el && val && seen[key] !== val) el.classList.add('fresh'); seen[key] = val; }
    fresh('.sim-pane', 'sec', s.section);
    fresh('.popup.otp', 'otp', s.otp && s.otp.code);
    fresh('.popup.scan', 'scan', s.scan ? 'on' : '');
    fresh('.toast', 'toast', s.toast);
    smsMsgs = root.querySelector('#smsMsgs'); if (smsMsgs) smsMsgs.scrollTop = smsMsgs.scrollHeight;
    convoMsgs = root.querySelector('#convoMsgs'); if (convoMsgs) convoMsgs.scrollTop = convoMsgs.scrollHeight;
    if (focusKey) { var el = root.querySelector('[data-draft="' + focusKey + '"]'); if (el) { el.focus(); el.setSelectionRange(el.value.length, el.value.length); } }
  }

  // ---------- ações ----------
  function sendSms() {
    var text = s.drafts.sms.trim(); if (!text) return;
    var t = now(), sel = s.smsSel;
    s.threads.forEach(function (th) { if (th.id === sel) { th.when = t; th.msgs.push({ out: true, text: text, time: t }); } });
    s.drafts.sms = ''; render();
    if (sel === 'lucas') {
      later(function () { s.typing = true; render(); }, 700);
      later(function () {
        var t2 = now();
        s.threads.forEach(function (th) { if (th.id === 'lucas') { th.when = t2; th.unread = !(s.smsSel === 'lucas' && s.section === 'sms'); th.msgs.push({ out: false, text: 'Combinado, valeu! 16h te mando.', time: t2 }); } });
        s.typing = false; render();
      }, 2200);
    }
  }
  function sendConvo() {
    var text = s.drafts.convo.trim(); if (!text) return;
    s.convo.push({ mine: true, text: text, time: now() }); s.drafts.convo = ''; toast('Enviado ao Pixel 9 Pro');
  }
  function addTransfer() {
    var f = FILE_POOL[s.fileIdx % FILE_POOL.length]; s.fileIdx++;
    s.transfers.unshift({ id: ++s.nextId, name: f[0], out: true, size: f[1], meta: now() + ' · Celular · Download/MasterSync', progress: 0 });
    s.fileTab = 'all'; render();
    if (!xferTick) xferTick = setInterval(function () {
      var running = false;
      s.transfers.forEach(function (x) { if (x.progress < 100) { x.progress = Math.min(100, x.progress + 6 + Math.round(Math.random() * 6)); if (x.progress < 100) running = true; } });
      render(); if (!running) { clearInterval(xferTick); xferTick = null; }
    }, 140);
  }
  function fireOtp() {
    if (!s.otpAuto) { toast('Ative “Copiar códigos” em Configurações'); return; }
    var c = String(100000 + Math.floor(Math.random() * 899999));
    s.otp = { code: c.slice(0, 3) + ' ' + c.slice(3) }; render();
    clearTimeout(otpTimer); otpTimer = later(function () { s.otp = null; render(); }, 5200);
  }
  function fireScan() {
    if (scanTick) return; s.scan = { progress: 0, done: false }; render();
    scanTick = setInterval(function () {
      if (!s.scan) { clearInterval(scanTick); scanTick = null; return; }
      s.scan.progress = Math.min(100, s.scan.progress + 9); s.scan.done = s.scan.progress >= 100; render();
      if (s.scan.done) { clearInterval(scanTick); scanTick = null; }
    }, 160);
  }
  function pressQc(id) {
    if (id === 'lock') { s.qc.lock = true; toast('Celular bloqueado'); later(function () { s.qc.lock = false; render(); }, 900); return; }
    if (id === 'ring') { s.qc.ring = true; toast('Tocando o celular…'); later(function () { s.qc.ring = false; render(); }, 3000); return; }
    s.qc[id] = !s.qc[id]; toast(QC_NAMES[id] + (s.qc[id] ? ' ligado' : ' desligado'));
  }
  function galFilter(p) { return s.galTab === 'all' || (s.galTab === 'fav' ? p.fav : p.kind === s.galTab); }
  function lbStep(d) {
    var list = s.lbList && s.lbList.length ? s.lbList : GALLERY.map(function (p) { return p.idx; });
    var i = list.indexOf(s.lb); s.lb = list[(i + d + list.length) % list.length]; render();
  }
  function appById(id) { return s.apps.filter(function (a) { return a.id === id; })[0]; }

  root.addEventListener('click', function (e) {
    var el = e.target.closest('[data-act]'); if (!el) return;
    var act = el.dataset.act, id = el.dataset.id;
    switch (act) {
      case 'go': s.section = id; if (id === 'sms') s.threads.forEach(function (t) { if (t.id === s.smsSel) t.unread = false; }); render(); break;
      case 'qc': pressQc(id); break;
      case 'sound': s.soundMac = el.dataset.v === 'mac'; toast(s.soundMac ? 'Som do celular saindo no Mac' : 'Som de volta no celular'); break;
      case 'thread': s.smsSel = id; s.threads.forEach(function (t) { if (t.id === id) t.unread = false; }); render(); break;
      case 'sms-send': sendSms(); break;
      case 'convo-send': sendConvo(); break;
      case 'dismiss': s.notifs = s.notifs.filter(function (n) { return String(n.id) !== id; }); toast('Dispensada no celular também'); break;
      case 'clear': s.notifs = []; toast('Tudo limpo, no celular também'); break;
      case 'gtab': s.galTab = id; render(); break;
      case 'ftab': s.fileTab = id; render(); break;
      case 'lb-open': s.lb = +el.dataset.i; s.lbList = s.section === 'gallery' ? GALLERY.filter(galFilter).map(function (p) { return p.idx; }) : GALLERY.slice(0, 5).map(function (p) { return p.idx; }); render(); break;
      case 'lb-close': s.lb = null; render(); break;
      case 'lb-prev': lbStep(-1); break;
      case 'lb-next': lbStep(1); break;
      case 'choose': addTransfer(); break;
      case 'send-bar': s.section = 'files'; addTransfer(); break;
      case 'paste': toast('Nada de arquivo na área de transferência'); break;
      case 'toggle-open': s.openOnReceive = !s.openOnReceive; render(); break;
      case 'toggle-zip': s.zipFolders = !s.zipFolders; render(); break;
      case 'toggle-otp': s.otpAuto = !s.otpAuto; render(); break;
      case 'remote': s.remote = !s.remote; render(); break;
      case 'rapp': toast(appById(id).name + ' aberto no celular'); break;
      case 'open-app': toast('Abrindo ' + appById(id).name + ' numa janela própria…'); break;
      case 'pin': appById(id).pinned = !appById(id).pinned; render(); break;
      case 'theme': window.setSiteTheme(el.dataset.v); break;
      case 'fire-otp': fireOtp(); break;
      case 'fire-notif': var p = NOTIF_POOL[s.notifIdx++ % NOTIF_POOL.length]; s.notifs.unshift({ id: ++s.nextId, app: p.app, title: p.title, text: p.text, letter: p.letter, color: p.color, time: now() }); toast(p.app + ': ' + p.title); break;
      case 'fire-copy': s.clip.unshift({ text: CLIP_POOL[s.clipIdx++ % CLIP_POOL.length], from: 'Celular', when: 'agora' }); toast('Copiado do celular. Já pode colar no Mac.'); break;
      case 'fire-scan': fireScan(); break;
      case 'scan-end': s.scan = null; toast(el.dataset.m); break;
    }
  });

  root.addEventListener('input', function (e) { var k = e.target.dataset && e.target.dataset.draft; if (k) s.drafts[k] = e.target.value; });
  root.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && e.target.dataset && e.target.dataset.draft) { e.preventDefault(); e.target.dataset.draft === 'sms' ? sendSms() : sendConvo(); }
    if (s.lb !== null) {
      if (e.key === 'ArrowRight') lbStep(1);
      else if (e.key === 'ArrowLeft') lbStep(-1);
      else if (e.key === 'Escape') { s.lb = null; render(); }
    }
  });
  window.addEventListener('themechange', function () { if (s.section === 'settings') render(); });

  render();
})();
