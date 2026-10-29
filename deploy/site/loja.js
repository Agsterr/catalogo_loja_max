// Loja web (Loja Max): /loja/<slug>, /loja/<slug>/p/<id>, /loja/<slug>/pedido/<id>
// Tudo é montado com textContent (nada de innerHTML com dado da loja). A API é a mesma dos apps.
(function () {
  'use strict';
  var m = location.pathname.match(/^\/loja\/([a-z0-9-]{3,60})(?:\/(p|pedido)\/(\d+))?\/?$/);
  var app = document.getElementById('app');
  if (!m) { app.textContent = 'Loja não encontrada.'; return; }
  var slug = m[1], route = { kind: m[2] || 'home', id: m[3] ? Number(m[3]) : null };
  var API = '/api/public/stores/' + slug, API_C = '/api/stores/' + slug;
  var LS = { cart: 'lm.cart.' + slug, token: 'lm.token', user: 'lm.user' };
  var DEPTS = [['', 'Tudo'], ['ROUPAS', 'Roupas'], ['CALCADOS', 'Calçados'], ['BIJUTERIAS', 'Bijuterias']];
  var PAY = { PIX: 'Pix', CARD: 'Cartão', CASH: 'Dinheiro' };
  var store = null, cart = load(LS.cart, []), session = { token: sget(LS.token), user: load(LS.user, null) };
  var list = { items: [], page: 0, hasMore: false, loading: false };
  var filt = { department: '', categoryId: '', q: '', onSale: false, sort: '' };
  var categories = [];

  // ---------- utilidades ----------
  function sget(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function sset(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { /* modo privado */ } }
  function load(k, d) { try { var v = JSON.parse(sget(k)); return v == null ? d : v; } catch (e) { return d; } }
  function save() { sset(LS.cart, JSON.stringify(cart)); }
  function money(v) { return Number(v || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }); }
  function h(tag, attrs) {
    var el = document.createElement(tag);
    for (var k in (attrs || {})) {
      var v = attrs[k];
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
      else if (k === 'text') el.textContent = v;
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (var i = 2; i < arguments.length; i++) add(el, arguments[i]);
    return el;
  }
  function add(el, c) {
    if (c == null || c === false) return;
    if (Array.isArray(c)) c.forEach(function (x) { add(el, x); });
    else el.appendChild(typeof c === 'object' ? c : document.createTextNode(String(c)));
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); }
  function safeUrl(u) { return typeof u === 'string' && /^(https:\/\/|\/)/.test(u) && u.slice(0, 2) !== '//' ? u : ''; }
  function img(u, alt) { var s = safeUrl(u); return s ? h('img', { src: s, alt: alt || '', loading: 'lazy', decoding: 'async' }) : null; }
  function toast(t) { var el = h('div', { class: 'toast', role: 'status', text: t }); document.body.appendChild(el); setTimeout(function () { el.remove(); }, 2600); }
  function parse() { var mm = location.pathname.match(/^\/loja\/[a-z0-9-]+(?:\/(p|pedido)\/(\d+))?\/?$/); route = { kind: mm && mm[1] || 'home', id: mm && mm[2] ? Number(mm[2]) : null }; }
  function nav(path) { history.pushState(null, '', path); parse(); start(); window.scrollTo(0, 0); }
  window.addEventListener('popstate', function () { parse(); start(); });

  function api(method, url, body, auth) {
    var headers = {};
    if (body) headers['Content-Type'] = 'application/json';
    if (auth && session.token) headers.Authorization = 'Bearer ' + session.token;
    return fetch(url, { method: method, headers: headers, body: body ? JSON.stringify(body) : undefined }).then(function (r) {
      return r.text().then(function (t) {
        var d = null; try { d = t ? JSON.parse(t) : null; } catch (e) { /* vazio */ }
        if (r.ok) return d;
        if (r.status === 401 && auth && !(d && d.code)) logout();
        var err = new Error((d && (d.detail || d.title)) || 'Não deu certo. Tente de novo.');
        err.status = r.status; err.code = d && d.code; throw err;
      });
    });
  }
  function logout() { session = { token: null, user: null }; sset(LS.token, null); sset(LS.user, null); }

  // ---------- sacola ----------
  function cartCount() { return cart.reduce(function (n, i) { return n + i.quantity; }, 0); }
  function addToCart(p, v, qty) {
    var f = cart.filter(function (i) { return i.variantId === v.id; })[0];
    if (f) f.quantity = Math.min(20, Math.min(v.stock, f.quantity + qty));
    else cart.push({ variantId: v.id, productId: p.id, name: p.name, size: v.size, color: v.color, thumb: (p.photos[0] || {}).thumbUrl || null, quantity: Math.min(qty, v.stock) });
    save(); renderBadge(); toast('Adicionado à sacola');
  }
  function renderBadge() { var n = document.querySelector('#bagbtn .n'); if (n) { n.textContent = cartCount(); n.style.display = cartCount() ? '' : 'none'; } }

  // ---------- início ----------
  function start() {
    closeAll();
    if (store) return draw();
    api('GET', API).then(function (s) { store = s; document.title = s.name + ' · Loja Max'; return api('GET', API + '/categories'); })
      .then(function (c) { categories = c || []; draw(); })
      .catch(function () { clear(app); app.appendChild(h('div', { class: 'empty' }, h('h2', { text: 'Loja não encontrada' }), h('p', { text: 'Confira o link com a loja.' }))); });
  }
  function draw() {
    clear(app);
    app.appendChild(header());
    app.appendChild(bar());
    if (route.kind === 'p') return product(route.id);
    if (route.kind === 'pedido') return orderPage(route.id);
    var main = h('main', { class: 'wrap', id: 'main' });
    app.appendChild(main);
    drawFilters(main);
    main.appendChild(h('div', { id: 'grid', class: 'grid' }));
    main.appendChild(h('div', { id: 'more' }));
    app.appendChild(footer());
    reload();
  }

  function header() {
    var s = store, cover = safeUrl(s.coverUrl), logo = safeUrl(s.logoUrl);
    var info = h('div', { style: 'flex:1;min-width:220px' },
      h('h1', { text: s.name }),
      s.description ? h('p', { text: s.description }) : null,
      h('div', { class: 'badges' },
        s.status ? h('span', { class: 'badge' + (s.status.open ? '' : ' closed') }, h('i'), s.status.label) : null,
        s.city ? h('span', { class: 'badge', text: s.city + (s.state ? '/' + s.state : '') }) : null,
        s.whatsapp ? h('a', { class: 'badge', href: 'https://wa.me/' + String(s.whatsapp).replace(/\D/g, ''), rel: 'noopener', target: '_blank', text: 'WhatsApp' }) : null,
        s.instagram ? h('a', { class: 'badge', href: 'https://instagram.com/' + String(s.instagram).replace(/[^\w.]/g, ''), rel: 'noopener', target: '_blank', text: 'Instagram' }) : null,
        s.pickupEnabled ? h('span', { class: 'badge', text: 'Retirada' }) : null,
        s.deliveryEnabled ? h('span', { class: 'badge', text: s.freeDeliveryFrom ? 'Frete grátis acima de ' + money(s.freeDeliveryFrom) : 'Entrega' }) : null));
    var el = h('div', { class: 'hero' },
      cover ? h('div', { class: 'cover', style: "background-image:url('" + cover.replace(/['")\\]/g, '') + "')" }) : null,
      h('div', { class: 'wrap' }, logo ? h('img', { class: 'logo', src: logo, alt: '' }) : h('div', { class: 'logo', text: s.name.charAt(0).toUpperCase() }), info));
    return el;
  }
  function footer() {
    return h('div', { class: 'wrap foot' }, h('div', { text: store.name }),
      h('div', { class: 'muted' }, 'Loja criada com ', h('a', { href: '/', text: 'Loja Max' }), ' · ', h('a', { href: '/privacidade', text: 'Privacidade' }), ' · ', h('a', { href: '/termos', text: 'Termos' })));
  }
  function bar() {
    var input = h('input', { type: 'search', placeholder: 'Buscar produtos', 'aria-label': 'Buscar', value: filt.q, maxlength: 80 });
    var t; input.addEventListener('input', function () { clearTimeout(t); t = setTimeout(function () { filt.q = input.value.trim(); if (route.kind === 'home') reload(); else nav('/loja/' + slug); }, 350); });
    var acc = h('button', { class: 'iconbtn', title: 'Minha conta', 'aria-label': 'Minha conta', text: session.token ? '👤' : '🔑', onclick: accountSheet });
    var bag = h('button', { class: 'iconbtn', id: 'bagbtn', 'aria-label': 'Sacola', onclick: bagSheet }, '🛍', h('span', { class: 'n' }));
    var el = h('div', { class: 'bar' }, h('div', { class: 'wrap' }, h('div', { class: 'search' }, '🔍', input), acc, bag));
    setTimeout(renderBadge, 0);
    return el;
  }
  function drawFilters(main) {
    var chips = h('div', { class: 'chips', role: 'tablist' }, DEPTS.map(function (d) {
      return h('button', { class: 'chip' + (filt.department === d[0] ? ' on' : ''), onclick: function () { filt.department = d[0]; filt.categoryId = ''; drawFilters2(); reload(); } , text: d[1] });
    }));
    var catSel = h('select', { 'aria-label': 'Categoria', onchange: function (e) { filt.categoryId = e.target.value; reload(); } },
      h('option', { value: '', text: 'Todas as categorias' }),
      categories.filter(function (c) { return !filt.department || c.department === filt.department; }).map(function (c) { return h('option', { value: c.id, text: c.name, selected: String(c.id) === String(filt.categoryId) }); }));
    var sort = h('select', { 'aria-label': 'Ordenar', onchange: function (e) { filt.sort = e.target.value; reload(); } },
      [['', 'Novidades'], ['price_asc', 'Menor preço'], ['price_desc', 'Maior preço'], ['name', 'Nome']].map(function (o) { return h('option', { value: o[0], text: o[1], selected: filt.sort === o[0] }); }));
    var promo = h('button', { class: 'chip' + (filt.onSale ? ' on' : ''), text: '🔥 Promoções', onclick: function () { filt.onSale = !filt.onSale; drawFilters2(); reload(); } });
    var wrap = h('div', { id: 'filters' }, chips, h('div', { class: 'tools' }, promo, catSel, sort));
    var old = document.getElementById('filters');
    if (old) old.replaceWith(wrap); else main.appendChild(wrap);
  }
  function drawFilters2() { drawFilters(document.getElementById('main')); }

  function reload() { list = { items: [], page: 0, hasMore: false, loading: false }; var g = document.getElementById('grid'); if (g) clear(g); more(); }
  function more() {
    if (list.loading) return; list.loading = true;
    var g = document.getElementById('grid'), mo = document.getElementById('more'); if (!g) return;
    var sk = []; if (!list.items.length) for (var i = 0; i < 8; i++) { var s = h('div', { class: 'skel' }); sk.push(s); g.appendChild(s); }
    var qs = ['page=' + list.page, 'size=24'];
    if (filt.department) qs.push('department=' + filt.department);
    if (filt.categoryId) qs.push('categoryId=' + encodeURIComponent(filt.categoryId));
    if (filt.q) qs.push('q=' + encodeURIComponent(filt.q));
    if (filt.onSale) qs.push('onSale=true');
    if (filt.sort) qs.push('sort=' + filt.sort);
    api('GET', API + '/products?' + qs.join('&')).then(function (r) {
      sk.forEach(function (x) { x.remove(); });
      r.items.forEach(function (p) { g.appendChild(card(p)); });
      list.items = list.items.concat(r.items); list.page++; list.hasMore = r.hasMore; list.loading = false;
      clear(mo);
      if (!list.items.length) mo.appendChild(h('div', { class: 'empty' }, h('h3', { text: 'Nada por aqui ainda' }), h('p', { text: 'Tente outra busca ou outro departamento.' })));
      else if (r.hasMore) mo.appendChild(h('button', { class: 'btn alt more', text: 'Ver mais produtos', onclick: more }));
    }).catch(function (e) { sk.forEach(function (x) { x.remove(); }); list.loading = false; clear(mo); mo.appendChild(h('div', { class: 'err', text: e.message })); });
  }
  function card(p) {
    var sale = p.discountPercent > 0;
    return h('button', { class: 'card', 'aria-label': p.name, onclick: function () { nav('/loja/' + slug + '/p/' + p.id); } },
      !p.inStock ? h('span', { class: 'tag out', text: 'Esgotado' }) : sale ? h('span', { class: 'tag', text: '-' + p.discountPercent + '%' }) : null,
      h('div', { class: 'ph' }, img(p.thumbUrl, p.name)),
      h('div', { class: 'info' }, p.brand ? h('div', { class: 'br', text: p.brand }) : null, h('div', { class: 'nm', text: p.name }),
        h('div', { class: 'price' }, h('b', { text: money(p.finalPrice) }), sale ? h('s', { text: money(p.price) }) : null)));
  }

  // ---------- produto ----------
  function product(id) {
    var box = h('main', { class: 'wrap' }, h('div', { class: 'boot' }, h('div', { class: 'spin' })));
    app.appendChild(box);
    api('GET', API + '/products/' + id).then(function (p) {
      document.title = p.name + ' · ' + store.name;
      var photos = p.photos || [], cur = 0, color = null, variant = null, qty = 1;
      var variants = (p.variants || []).filter(function (v) { return v.active; });
      var colors = uniq(variants.map(function (v) { return v.color; }));
      var sizes = uniq(variants.map(function (v) { return v.size; }));
      var big = h('div', { class: 'big', onclick: function () { var u = safeUrl((shown()[cur] || {}).url); if (u) zoomImg(u); } });
      var thumbs = h('div', { class: 'thumbs' });
      var opts = h('div'), msg = h('div'), buy = h('button', { class: 'btn block', text: 'Adicionar à sacola' });
      function shown() { var f = photos.filter(function (x) { return color && x.color === color; }); return f.length ? f : photos; }
      function paintGal() {
        clear(big); var s = shown(); if (cur >= s.length) cur = 0;
        add(big, img((s[cur] || {}).url || (s[cur] || {}).thumbUrl, p.name));
        clear(thumbs);
        if (s.length > 1) s.forEach(function (ph, i) { thumbs.appendChild(h('button', { class: i === cur ? 'on' : '', 'aria-label': 'Foto ' + (i + 1), onclick: function () { cur = i; paintGal(); } }, img(ph.thumbUrl || ph.url, ''))); });
      }
      function pick() { variant = variants.filter(function (v) { return (!colors.length || v.color === color) && v.size === sel.size; })[0] || null; }
      var sel = { size: sizes.length === 1 ? sizes[0] : null };
      if (colors.length === 1) color = colors[0];
      function paintOpts() {
        clear(opts);
        if (colors.length > 1) {
          opts.appendChild(h('div', { class: 'lbl', text: 'Cor' }));
          opts.appendChild(h('div', { class: 'opts' }, colors.map(function (c) { return h('button', { class: 'opt' + (c === color ? ' on' : ''), text: c, onclick: function () { color = c; cur = 0; paintGal(); paintOpts(); } }); })));
        }
        if (sizes.length && !(sizes.length === 1 && !sizes[0])) {
          opts.appendChild(h('div', { class: 'lbl', text: 'Tamanho' }));
          opts.appendChild(h('div', { class: 'opts' }, sizes.map(function (s) {
            var v = variants.filter(function (x) { return x.size === s && (!colors.length || !color || x.color === color); })[0];
            return h('button', { class: 'opt' + (s === sel.size ? ' on' : ''), text: s, disabled: !v || v.stock < 1, onclick: function () { sel.size = s; paintOpts(); } });
          })));
        }
        pick(); clear(msg);
        if (variant) msg.appendChild(h('div', { class: variant.stock <= 3 ? 'warn' : 'muted', text: variant.stock <= 3 ? 'Últimas ' + variant.stock + ' unidades!' : 'Em estoque' }));
        opts.appendChild(msg);
        buy.disabled = p.totalStock < 1;
        buy.textContent = p.totalStock < 1 ? 'Esgotado' : 'Adicionar à sacola';
      }
      buy.addEventListener('click', function () {
        if (colors.length > 1 && !color) return toast('Escolha a cor');
        pick(); if (!variant) return toast('Escolha o tamanho');
        if (variant.stock < 1) return toast('Esse item esgotou');
        addToCart(p, variant, qty);
      });
      var qv = h('span', { text: '1' });
      var qbox = h('div', { class: 'qty' }, h('button', { 'aria-label': 'Menos', text: '−', onclick: function () { qty = Math.max(1, qty - 1); qv.textContent = qty; } }), qv,
        h('button', { 'aria-label': 'Mais', text: '+', onclick: function () { qty = Math.min(10, qty + 1); qv.textContent = qty; } }));
      var share = h('button', { class: 'btn alt block', text: 'Compartilhar', style: 'margin-top:10px', onclick: function () {
        var u = location.href; if (navigator.share) navigator.share({ title: p.name, url: u }).catch(function () { });
        else if (navigator.clipboard) navigator.clipboard.writeText(u).then(function () { toast('Link copiado'); }); } });
      clear(box);
      box.appendChild(h('button', { class: 'crumb', text: '← Voltar à vitrine', onclick: function () { nav('/loja/' + slug); } }));
      box.appendChild(h('div', { class: 'prod' }, h('div', { class: 'gal' }, big, thumbs),
        h('div', null, p.brand ? h('div', { class: 'muted', text: p.brand }) : null, h('h1', { text: p.name }),
          h('div', { class: 'price big-price' }, h('b', { text: money(p.finalPrice) }), p.discountPercent > 0 ? h('s', { text: money(p.price) }) : null,
            p.discountPercent > 0 ? h('span', { class: 'tag', style: 'position:static', text: '-' + p.discountPercent + '%' }) : null),
          p.promotion ? h('div', { class: 'muted', text: '🔥 ' + p.promotion }) : null,
          opts, h('div', { class: 'lbl', text: 'Quantidade' }), h('div', { style: 'margin:8px 0 18px' }, qbox), buy, share,
          p.description ? h('div', null, h('div', { class: 'lbl', text: 'Descrição' }), h('p', { style: 'white-space:pre-wrap', text: p.description })) : null,
          p.sizeChart ? h('div', null, h('div', { class: 'lbl', text: 'Tabela de medidas' }), h('p', { class: 'muted', style: 'white-space:pre-wrap', text: p.sizeChart })) : null)));
      paintGal(); paintOpts();
      app.appendChild(footer());
    }).catch(function () { clear(box); box.appendChild(h('div', { class: 'empty' }, h('h2', { text: 'Produto não encontrado' }), h('button', { class: 'btn', text: 'Ver a vitrine', onclick: function () { nav('/loja/' + slug); } }))); });
  }
  function uniq(a) { var r = []; a.forEach(function (x) { if (x != null && x !== '' && r.indexOf(x) < 0) r.push(x); }); return r; }
  function zoomImg(u) { var z = h('div', { class: 'zoom', onclick: function () { z.remove(); } }, h('img', { src: u, alt: '' })); document.body.appendChild(z); }

  // ---------- painéis ----------
  function closeAll() { document.querySelectorAll('.veil,.sheet').forEach(function (e) { e.remove(); }); }
  function sheet(title, body, footer, kind) {
    closeAll();
    var veil = h('div', { class: 'veil', onclick: closeAll });
    var sh = h('div', { class: 'sheet ' + (kind || 'right'), role: 'dialog', 'aria-label': title },
      h('header', null, title, h('button', { class: 'x', 'aria-label': 'Fechar', text: '✕', onclick: closeAll })),
      h('div', { class: 'body' }, body), footer ? h('footer', null, footer) : null);
    document.body.appendChild(veil); document.body.appendChild(sh);
    return sh;
  }

  var quote = null;
  function bagSheet() {
    var body = h('div'), foot = h('div');
    sheet('Sua sacola', body, foot);
    paintBag(body, foot);
  }
  function paintBag(body, foot) {
    clear(body); clear(foot);
    if (!cart.length) { body.appendChild(h('div', { class: 'empty' }, h('div', { style: 'font-size:48px', text: '🛍' }), h('p', { text: 'Sua sacola está vazia.' }))); return; }
    body.appendChild(h('div', { class: 'boot' }, h('div', { class: 'spin' })));
    api('POST', API + '/cart/quote', { items: cart.map(function (i) { return { variantId: i.variantId, quantity: i.quantity }; }) }).then(function (q) {
      quote = q; clear(body);
      var changed = false;
      q.items.forEach(function (ql) {
        var it = cart.filter(function (c) { return c.variantId === ql.variantId; })[0]; if (!it) return;
        var bad = !ql.available || ql.quantity < it.quantity;
        if (bad && ql.available) { it.quantity = Math.max(1, ql.quantity); changed = true; }
        body.appendChild(h('div', { class: 'line' }, img(it.thumb, '') || h('div', { class: 'noimg' }),
          h('div', { class: 'grow' }, h('div', { class: 'nm', text: it.name }),
            h('div', { class: 'muted', text: [it.color, it.size].filter(Boolean).join(' · ') }),
            !ql.available ? h('div', { class: 'warn', text: 'Esgotado ou fora de venda' }) : bad ? h('div', { class: 'warn', text: 'Só restam ' + ql.stock }) : null,
            h('div', { class: 'price' }, h('b', { text: ql.available ? money(ql.unitPrice) : '—' }), ql.discountPercent > 0 ? h('s', { text: money(ql.price) }) : null),
            h('div', { style: 'display:flex;gap:10px;align-items:center;margin-top:6px' },
              h('div', { class: 'qty' },
                h('button', { text: '−', 'aria-label': 'Menos', onclick: function () { it.quantity = Math.max(1, it.quantity - 1); save(); renderBadge(); paintBag(body, foot); } }),
                h('span', { text: it.quantity }),
                h('button', { text: '+', 'aria-label': 'Mais', onclick: function () { it.quantity = Math.min(20, Math.min(ql.stock || 20, it.quantity + 1)); save(); renderBadge(); paintBag(body, foot); } })),
              h('button', { class: 'crumb', style: 'padding:0', text: 'Remover', onclick: function () { cart = cart.filter(function (c) { return c !== it; }); save(); renderBadge(); paintBag(body, foot); } })))));
      });
      if (changed) save();
      var ok = q.items.some(function (x) { return x.available; }) && !q.items.some(function (x) { return !x.available; });
      foot.appendChild(h('div', { class: 'sum tot' }, h('span', { text: 'Subtotal' }), h('span', { text: money(q.subtotal) })));
      if (!ok) foot.appendChild(h('div', { class: 'warn', text: 'Remova os itens indisponíveis para continuar.' }));
      foot.appendChild(h('button', { class: 'btn block', style: 'margin-top:10px', text: 'Finalizar pedido', disabled: !ok, onclick: function () { session.token ? checkout() : accountSheet(checkout); } }));
    }).catch(function (e) { clear(body); body.appendChild(h('div', { class: 'err', text: e.message })); });
  }

  // ---------- conta ----------
  function accountSheet(after) {
    if (session.token) {
      var u = session.user || {};
      var sh = sheet('Minha conta', h('div', null, h('p', null, h('b', { text: u.name || '' }), h('br'), h('span', { class: 'muted', text: u.email || '' })),
        h('button', { class: 'btn alt block', text: 'Meus pedidos nesta loja', onclick: myOrders }),
        h('button', { class: 'btn alt block', style: 'margin-top:10px', text: 'Sair', onclick: function () { logout(); closeAll(); draw(); } })));
      return sh;
    }
    var mode = 'login', body = h('div');
    function paint() {
      clear(body);
      var name = h('input', { autocomplete: 'name', maxlength: 120 }), email = h('input', { type: 'email', autocomplete: 'email', maxlength: 180 }),
        phone = h('input', { type: 'tel', autocomplete: 'tel', maxlength: 30 }), pass = h('input', { type: 'password', autocomplete: mode === 'login' ? 'current-password' : 'new-password', maxlength: 100 }),
        code = h('input', { inputmode: 'numeric', maxlength: 10, placeholder: 'Código do app autenticador' }), codeBox = h('div', { class: 'f', style: 'display:none' }, h('label', { text: 'Código de 2 etapas' }), code),
        err = h('div'), go = h('button', { class: 'btn block', text: mode === 'login' ? 'Entrar' : 'Criar conta' });
      go.addEventListener('click', function () {
        clear(err); go.disabled = true;
        var req = mode === 'login' ? api('POST', '/api/auth/login', { email: email.value.trim(), password: pass.value, code: code.value.trim() || null })
          : api('POST', '/api/auth/register', { name: name.value.trim(), email: email.value.trim(), phone: phone.value.trim() || null, password: pass.value });
        req.then(function (r) {
          session = { token: r.token, user: r.user }; sset(LS.token, r.token); sset(LS.user, JSON.stringify(r.user));
          closeAll(); if (typeof after === 'function') after(); else draw();
        }).catch(function (e) {
          go.disabled = false;
          if (e.code === 'TOTP_REQUIRED') { codeBox.style.display = ''; code.focus(); }
          err.appendChild(h('div', { class: 'err', text: e.message }));
        });
      });
      body.appendChild(h('div', { class: 'form f' },
        mode === 'login' ? null : h('div', { class: 'f' }, h('label', { text: 'Nome' }), name),
        h('div', { class: 'f' }, h('label', { text: 'E-mail' }), email),
        mode === 'login' ? null : h('div', { class: 'f' }, h('label', { text: 'Telefone (WhatsApp)' }), phone),
        h('div', { class: 'f' }, h('label', { text: 'Senha' }), pass),
        mode === 'login' ? null : h('div', { class: 'muted', text: 'Use de 8 a 100 caracteres, com letras e números.' }),
        codeBox, err, go,
        h('button', { class: 'crumb', text: mode === 'login' ? 'Ainda não tenho conta' : 'Já tenho conta', onclick: function () { mode = mode === 'login' ? 'register' : 'login'; paint(); } }),
        h('div', { class: 'muted', text: 'A mesma conta vale no app Loja Max e em todas as lojas.' })));
    }
    sheet('Entrar', body); paint();
  }

  // ---------- fechar pedido ----------
  function checkout() {
    var s = store, st = { delivery: s.pickupEnabled === false && s.deliveryEnabled ? 'DELIVERY' : 'PICKUP', pay: 'PIX', fee: 0, ok: true, msg: '' };
    var addr = h('textarea', { rows: 3, maxlength: 400, placeholder: 'Rua, número, bairro, complemento' }), notes = h('textarea', { rows: 2, maxlength: 500, placeholder: 'Observações (opcional)' });
    var feeBox = h('div'), sum = h('div'), err = h('div'), go = h('button', { class: 'btn block', text: 'Enviar pedido' }), pos = {};
    var body = h('div', { class: 'form f' });
    function refreshFee() {
      st.ok = true; st.msg = ''; st.fee = 0;
      if (st.delivery !== 'DELIVERY') return paintSum();
      var qs = 'subtotal=' + (quote ? quote.subtotal : 0) + (pos.lat != null ? '&lat=' + pos.lat + '&lng=' + pos.lng : '');
      api('GET', API + '/delivery-quote?' + qs).then(function (d) {
        clear(feeBox);
        if (d.needsLocation) { st.ok = false; st.msg = 'Use sua localização para calcular a entrega.'; feeBox.appendChild(h('button', { class: 'btn alt block', text: '📍 Calcular a entrega', onclick: locate })); }
        else if (!d.available) { st.ok = false; st.msg = d.message || 'Fora da área de entrega.'; }
        else st.fee = Number(d.fee || 0);
        if (d.message && d.available) feeBox.appendChild(h('div', { class: 'muted', text: d.message }));
        paintSum();
      }).catch(function () { paintSum(); });
    }
    function locate() {
      if (!navigator.geolocation) return toast('Seu navegador não informa a localização');
      navigator.geolocation.getCurrentPosition(function (p) { pos = { lat: p.coords.latitude, lng: p.coords.longitude }; refreshFee(); }, function () { toast('Não consegui sua localização'); });
    }
    function paintSum() {
      clear(sum); var sub = quote ? Number(quote.subtotal) : 0;
      sum.appendChild(h('div', { class: 'sum' }, h('span', { text: 'Produtos' }), h('span', { text: money(sub) })));
      if (st.delivery === 'DELIVERY') sum.appendChild(h('div', { class: 'sum' }, h('span', { text: 'Entrega' }), h('span', { text: st.fee ? money(st.fee) : st.ok ? 'Grátis' : '—' })));
      sum.appendChild(h('div', { class: 'sum tot' }, h('span', { text: 'Total' }), h('span', { text: money(sub + st.fee) })));
      if (st.msg) sum.appendChild(h('div', { class: 'warn', text: st.msg }));
      addrWrap.style.display = st.delivery === 'DELIVERY' ? '' : 'none';
    }
    function seg(name, opts, get, set) {
      return h('div', { class: 'seg' }, opts.map(function (o) {
        var i = h('input', { type: 'radio', name: name, value: o[0], checked: get() === o[0] }); i.addEventListener('change', function () { set(o[0]); });
        return h('label', null, i, h('span', { text: o[1] }));
      }));
    }
    var dopts = []; if (s.pickupEnabled !== false) dopts.push(['PICKUP', 'Retirar na loja']); if (s.deliveryEnabled) dopts.push(['DELIVERY', 'Receber em casa']);
    if (!dopts.length) dopts.push(['PICKUP', 'Retirar na loja']);
    st.delivery = dopts[0][0];
    var addrWrap = h('div', { class: 'f' }, h('label', { text: 'Endereço de entrega' }), addr, feeBox);
    body.appendChild(h('div', { class: 'f' }, h('label', { text: 'Como receber' }), seg('d', dopts, function () { return st.delivery; }, function (v) { st.delivery = v; refreshFee(); })));
    if (s.pickupEnabled !== false && s.pickupAddress) body.appendChild(h('div', { class: 'muted', text: 'Retirada em: ' + s.pickupAddress }));
    body.appendChild(addrWrap);
    body.appendChild(h('div', { class: 'f' }, h('label', { text: 'Pagamento (na retirada/entrega ou combinado pelo WhatsApp)' }), seg('p', Object.keys(PAY).map(function (k) { return [k, PAY[k]]; }), function () { return st.pay; }, function (v) { st.pay = v; })));
    body.appendChild(h('div', { class: 'f' }, h('label', { text: 'Observações' }), notes));
    body.appendChild(sum); body.appendChild(err);
    go.addEventListener('click', function () {
      clear(err);
      if (!st.ok) return err.appendChild(h('div', { class: 'err', text: st.msg }));
      if (st.delivery === 'DELIVERY' && addr.value.trim().length < 8) return err.appendChild(h('div', { class: 'err', text: 'Informe o endereço de entrega.' }));
      go.disabled = true;
      api('POST', API_C + '/orders', {
        items: cart.map(function (i) { return { variantId: i.variantId, quantity: i.quantity }; }), deliveryMethod: st.delivery, paymentMethod: st.pay,
        address: st.delivery === 'DELIVERY' ? addr.value.trim() : null, notes: notes.value.trim() || null,
        deliveryLat: pos.lat != null ? pos.lat : null, deliveryLng: pos.lng != null ? pos.lng : null
      }, true).then(function (o) {
        cart = []; save(); renderBadge(); closeAll(); done(o);
      }).catch(function (e) { go.disabled = false; err.appendChild(h('div', { class: 'err', text: e.message })); });
    });
    sheet('Finalizar pedido', body, go, 'right'); paintSum(); refreshFee();
  }
  function done(o) {
    var wa = store.whatsapp ? 'https://wa.me/' + String(store.whatsapp).replace(/\D/g, '') + '?text=' + encodeURIComponent('Olá! Fiz o pedido ' + o.code + ' (' + money(o.total) + ').') : null;
    sheet('Pedido enviado', h('div', { class: 'okbox' }, h('div', { style: 'font-size:48px', text: '🎉' }), h('h2', { text: 'Pedido ' + o.code }), h('p', { text: 'Total ' + money(o.total) + '. A loja já foi avisada.' }),
      h('button', { class: 'btn block', text: 'Acompanhar pedido', onclick: function () { nav('/loja/' + slug + '/pedido/' + o.id); } }),
      wa ? h('a', { class: 'btn alt block', style: 'margin-top:10px', href: wa, target: '_blank', rel: 'noopener', text: 'Falar com a loja no WhatsApp' }) : null));
  }

  // ---------- pedidos ----------
  function myOrders() {
    var body = h('div', null, h('div', { class: 'boot' }, h('div', { class: 'spin' })));
    sheet('Meus pedidos', body);
    api('GET', API_C + '/orders?size=30', null, true).then(function (r) {
      clear(body);
      if (!r.items.length) return body.appendChild(h('div', { class: 'empty', text: 'Você ainda não fez pedidos aqui.' }));
      r.items.forEach(function (o) {
        body.appendChild(h('button', { class: 'card', style: 'margin-bottom:10px;padding:14px', onclick: function () { nav('/loja/' + slug + '/pedido/' + o.id); } },
          h('b', { text: o.code + ' · ' + o.statusLabel }), h('div', { class: 'muted', text: money(o.total) + ' · ' + o.itemCount + ' item(ns)' })));
      });
    }).catch(function (e) { clear(body); body.appendChild(h('div', { class: 'err', text: e.message })); });
  }
  var FLOW = ['PENDING', 'CONFIRMED', 'READY', 'OUT_FOR_DELIVERY', 'DELIVERED'];
  function orderPage(id) {
    var box = h('main', { class: 'wrap' }, h('div', { class: 'boot' }, h('div', { class: 'spin' })));
    app.appendChild(box);
    if (!session.token) { clear(box); box.appendChild(h('div', { class: 'empty' }, h('p', { text: 'Entre para ver seu pedido.' }), h('button', { class: 'btn', text: 'Entrar', onclick: function () { accountSheet(draw); } }))); return; }
    function paint() {
      api('GET', API_C + '/orders/' + id, null, true).then(function (o) {
        clear(box);
        box.appendChild(h('button', { class: 'crumb', text: '← Voltar à vitrine', onclick: function () { nav('/loja/' + slug); } }));
        var idx = FLOW.indexOf(o.status);
        box.appendChild(h('h2', { class: 't', text: 'Pedido ' + o.code }));
        box.appendChild(h('div', { class: 'muted', text: o.statusLabel + (o.paid ? ' · pago' : '') }));
        if (o.events && o.events.length) box.appendChild(h('ul', { class: 'steps' }, o.events.map(function (e) { return h('li', { class: 'done', text: e.label + (e.note ? ' — ' + e.note : '') }); })));
        o.items.forEach(function (i) {
          box.appendChild(h('div', { class: 'line' }, img(i.thumbUrl, '') || h('div', { class: 'noimg' }), h('div', { class: 'grow' }, h('div', { class: 'nm', text: i.productName }),
            h('div', { class: 'muted', text: [i.color, i.size].filter(Boolean).join(' · ') + ' · ' + i.quantity + 'x' }), h('b', { text: money(i.total) }))));
        });
        box.appendChild(h('div', { class: 'sum' }, h('span', { text: 'Produtos' }), h('span', { text: money(o.subtotal) })));
        if (Number(o.discount)) box.appendChild(h('div', { class: 'sum' }, h('span', { text: 'Desconto' }), h('span', { text: '-' + money(o.discount) })));
        if (o.deliveryMethod === 'DELIVERY') box.appendChild(h('div', { class: 'sum' }, h('span', { text: 'Entrega' }), h('span', { text: money(o.deliveryFee) })));
        box.appendChild(h('div', { class: 'sum tot' }, h('span', { text: 'Total' }), h('span', { text: money(o.total) })));
        if (o.courier && o.courier.deliveryCode) box.appendChild(h('div', { class: 'okbox', style: 'margin-top:14px' }, h('div', { class: 'muted', text: 'Código para o entregador' }), h('h2', { text: o.courier.deliveryCode })));
        if (o.canCancel) box.appendChild(h('button', { class: 'btn alt', style: 'margin-top:16px', text: 'Cancelar pedido', onclick: function () {
          if (confirm('Cancelar este pedido?')) api('POST', API_C + '/orders/' + id + '/cancel', {}, true).then(paint).catch(function (e) { toast(e.message); }); } }));
        void idx;
      }).catch(function (e) { clear(box); box.appendChild(h('div', { class: 'err', text: e.message })); });
    }
    paint();
  }

  start();
})();
