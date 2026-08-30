/* Piccoli aiuti per costruire il DOM e formattare i numeri in italiano. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  /** Crea un elemento: el('div.card', {}, [figli…]) */
  function el(spec, attributes, children) {
    const parts = String(spec).split('.');
    const tag = parts.shift() || 'div';
    const node = document.createElement(tag);
    if (parts.length) node.className = parts.join(' ');

    if (attributes) {
      Object.keys(attributes).forEach((key) => {
        const value = attributes[key];
        if (value === null || value === undefined || value === false) return;
        if (key === 'text') node.textContent = value;
        else if (key === 'html') node.innerHTML = value;
        else if (key === 'style') Object.assign(node.style, value);
        else if (key.indexOf('on') === 0 && typeof value === 'function') {
          node.addEventListener(key.slice(2).toLowerCase(), value);
        } else node.setAttribute(key, value);
      });
    }

    if (children) {
      (Array.isArray(children) ? children : [children]).forEach((child) => {
        if (child === null || child === undefined || child === false) return;
        node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
      });
    }
    return node;
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
    return node;
  }

  function pad(number) { return number < 10 ? '0' + number : String(number); }

  function decimal(value, digits) {
    const places = digits === undefined ? 1 : digits;
    if (!isFinite(value)) return '—';
    return Number(value).toFixed(places).replace('.', ',');
  }

  function percent(value, digits) { return decimal(value, digits) + '%'; }

  function integer(value) {
    return new Intl.NumberFormat('it-IT').format(Math.round(value));
  }

  function currency(value) {
    if (!isFinite(value)) return '—';
    return new Intl.NumberFormat('it-IT', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2 })
      .format(value);
  }

  function shortDate(timestamp) {
    if (!timestamp) return '—';
    return new Date(timestamp).toLocaleDateString('it-IT', { day: '2-digit', month: '2-digit', year: '2-digit' });
  }

  function longDate(timestamp) {
    if (!timestamp) return '—';
    return new Date(timestamp).toLocaleDateString('it-IT', { day: 'numeric', month: 'long', year: 'numeric' });
  }

  function isoDate(timestamp) {
    return new Date(timestamp).toISOString().slice(0, 10);
  }

  /** Colore associato a un indice statistico. */
  function scoreColor(score) {
    if (score >= 80) return 'var(--high)';
    if (score >= 50) return 'var(--medium)';
    return 'var(--low)';
  }

  // ------------------------------------------------------------ Componenti

  function card(title, icon, children, subtitle) {
    const node = el('div.card');
    if (title) {
      node.appendChild(el('h2', {}, [icon ? el('span', { text: icon }) : null, el('span', { text: title })]));
    }
    if (subtitle) node.appendChild(el('p.subtitle', { text: subtitle }));
    (Array.isArray(children) ? children : [children]).forEach((child) => {
      if (child) node.appendChild(child);
    });
    return node;
  }

  function ball(number, score, size) {
    const color = score === undefined || score === null ? 'var(--accent)' : scoreColor(score);
    return el('span.ball' + (size ? '.' + size : ''), {
      text: pad(number),
      style: {
        color: color,
        background: 'color-mix(in srgb, ' + color + ' 14%, transparent)',
        borderColor: 'color-mix(in srgb, ' + color + ' 38%, transparent)'
      }
    });
  }

  function combinationRow(numbers, scoreMap, size) {
    return el('div.combination', {}, numbers.map((number) =>
      ball(number, scoreMap ? scoreMap[number] : undefined, size)));
  }

  function scoreBadge(score) {
    const color = scoreColor(score);
    return el('span.badge', {
      style: { background: 'color-mix(in srgb, ' + color + ' 14%, transparent)', color: color }
    }, [
      el('span.dot', { style: { background: color } }),
      el('span', { text: String(Math.round(score)) }),
      el('span', { text: '/100', style: { opacity: 0.65, fontWeight: '400' } })
    ]);
  }

  function metric(label, value, caption, color) {
    return el('div.metric', {}, [
      el('div.label', { text: label }),
      el('div.value', { text: value, style: color ? { color: color } : null }),
      caption ? el('div.caption', { text: caption }) : null
    ]);
  }

  function metrics(items) {
    return el('div.metrics', {}, items.filter(Boolean));
  }

  function barRow(label, value) {
    return el('div.bar-row', {}, [
      el('div.head', {}, [el('span', { text: label }), el('span', { text: String(Math.round(value)) })]),
      el('div.bar', {}, [el('span', {
        style: { width: Math.max(Math.min(value, 100), 2) + '%', background: scoreColor(value) }
      })])
    ]);
  }

  function disclaimer(text, icon) {
    return el('div.disclaimer', {}, [
      el('span', { text: icon || 'ℹ️' }),
      el('span', { text: text || Lotto.DISCLAIMER.primary })
    ]);
  }

  function empty(icon, title, message, actionLabel, action) {
    return el('div.empty', {}, [
      el('span.icon', { text: icon }),
      el('div', { text: title, style: { fontWeight: '600', color: 'var(--text)' } }),
      el('p', { text: message }),
      actionLabel ? el('button.btn', { text: actionLabel, onclick: action }) : null
    ]);
  }

  function progress(label, value) {
    const track = el('div.track', {}, [el('span', { style: { width: ((value || 0) * 100) + '%' } })]);
    return el('div.progress', {}, [
      el('div', { text: label }),
      track,
      value === undefined ? null : el('div', { text: Math.round((value || 0) * 100) + '%' })
    ]);
  }

  function segmented(options, selected, onChange) {
    const node = el('div.segmented');
    options.forEach((option) => {
      node.appendChild(el('button', {
        text: option.name,
        'aria-selected': option.id === selected ? 'true' : 'false',
        onclick: () => onChange(option.id)
      }));
    });
    return node;
  }

  function chips(options, selected, onChange) {
    const node = el('div.chips');
    options.forEach((option) => {
      node.appendChild(el('button.chip', {
        text: option.name,
        'aria-pressed': option.id === selected ? 'true' : 'false',
        onclick: () => onChange(option.id)
      }));
    });
    return node;
  }

  function select(label, options, value, onChange) {
    const node = el('select');
    options.forEach((option) => {
      node.appendChild(el('option', { value: option.id, text: option.name, selected: option.id === value }));
    });
    node.addEventListener('change', () => onChange(node.value));
    return el('div.field', {}, [el('label', { text: label }), node]);
  }

  function reasonsList(reasons) {
    return el('ul.reasons', {}, reasons.map((reason) => el('li', { text: reason })));
  }

  Lotto.ui = Object.assign(Lotto.ui || {}, {
    el: el, clear: clear, pad: pad, decimal: decimal, percent: percent, integer: integer,
    currency: currency, shortDate: shortDate, longDate: longDate, isoDate: isoDate,
    scoreColor: scoreColor, card: card, ball: ball, combinationRow: combinationRow,
    scoreBadge: scoreBadge, metric: metric, metrics: metrics, barRow: barRow,
    disclaimer: disclaimer, empty: empty, progress: progress, segmented: segmented,
    chips: chips, select: select, reasonsList: reasonsList
  });
})(typeof self !== 'undefined' ? self : this);
