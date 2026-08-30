/* Grafici in SVG puro: nessuna libreria esterna, quindi l'app resta
   completamente offline e leggera. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const NS = 'http://www.w3.org/2000/svg';

  function svgEl(tag, attributes) {
    const node = document.createElementNS(NS, tag);
    Object.keys(attributes || {}).forEach((key) => {
      node.setAttribute(key, attributes[key]);
    });
    return node;
  }

  function wrap(svg, width) {
    const box = document.createElement('div');
    box.className = 'chart';
    if (width) svg.style.minWidth = width + 'px';
    box.appendChild(svg);
    return box;
  }

  /**
   * Istogramma verticale.
   * `items`: [{ label, value, color }]. `reference` disegna una linea tratteggiata.
   */
  function barChart(items, options) {
    const settings = Object.assign({ height: 170, minWidth: 0, showLabels: true, reference: null }, options || {});
    const width = Math.max(settings.minWidth, items.length * 4 + 40);
    const height = settings.height;
    const padding = { top: 12, right: 8, bottom: settings.showLabels ? 22 : 8, left: 34 };
    const plotWidth = width - padding.left - padding.right;
    const plotHeight = height - padding.top - padding.bottom;

    let maximum = 0;
    items.forEach((item) => { if (item.value > maximum) maximum = item.value; });
    if (settings.reference !== null && settings.reference > maximum) maximum = settings.reference;
    if (maximum <= 0) maximum = 1;

    const svg = svgEl('svg', { viewBox: '0 0 ' + width + ' ' + height, width: '100%', height: height });
    const barWidth = plotWidth / items.length;

    // Assi orizzontali di riferimento.
    [0, 0.5, 1].forEach((fraction) => {
      const y = padding.top + plotHeight * (1 - fraction);
      svg.appendChild(svgEl('line', {
        x1: padding.left, x2: width - padding.right, y1: y, y2: y,
        stroke: 'var(--separator)', 'stroke-width': 1
      }));
      svg.appendChild(svgEl('text', {
        x: padding.left - 5, y: y + 3.5, 'text-anchor': 'end',
        'font-size': 9, fill: 'var(--text-secondary)'
      })).textContent = Lotto.ui.decimal(maximum * fraction, maximum > 20 ? 0 : 1);
    });

    items.forEach((item, index) => {
      const barHeight = Math.max((item.value / maximum) * plotHeight, item.value > 0 ? 1 : 0);
      svg.appendChild(svgEl('rect', {
        x: padding.left + index * barWidth + barWidth * 0.12,
        y: padding.top + plotHeight - barHeight,
        width: Math.max(barWidth * 0.76, 1),
        height: barHeight,
        rx: Math.min(barWidth * 0.3, 2),
        fill: item.color || 'var(--accent)'
      }));
      if (settings.showLabels && (items.length <= 20 || index % Math.ceil(items.length / 12) === 0)) {
        const text = svgEl('text', {
          x: padding.left + index * barWidth + barWidth / 2,
          y: height - 7, 'text-anchor': 'middle', 'font-size': 9, fill: 'var(--text-secondary)'
        });
        text.textContent = item.label;
        svg.appendChild(text);
      }
    });

    if (settings.reference !== null) {
      const y = padding.top + plotHeight * (1 - settings.reference / maximum);
      svg.appendChild(svgEl('line', {
        x1: padding.left, x2: width - padding.right, y1: y, y2: y,
        stroke: 'var(--text-secondary)', 'stroke-width': 1, 'stroke-dasharray': '4 3'
      }));
    }
    return wrap(svg, settings.minWidth);
  }

  /** Istogramma orizzontale, per classifiche con etichette lunghe. */
  function horizontalBars(items, options) {
    const settings = Object.assign({ rowHeight: 22, max: null }, options || {});
    const height = items.length * settings.rowHeight + 8;
    const width = 320;
    const labelWidth = 42;
    let maximum = settings.max;
    if (maximum === null) {
      maximum = 0;
      items.forEach((item) => { if (item.value > maximum) maximum = item.value; });
    }
    if (maximum <= 0) maximum = 1;

    const svg = svgEl('svg', { viewBox: '0 0 ' + width + ' ' + height, width: '100%', height: height });
    items.forEach((item, index) => {
      const y = index * settings.rowHeight + 4;
      const text = svgEl('text', {
        x: 0, y: y + settings.rowHeight * 0.66, 'font-size': 11, fill: 'var(--text-secondary)'
      });
      text.textContent = item.label;
      svg.appendChild(text);
      svg.appendChild(svgEl('rect', {
        x: labelWidth, y: y + 3, rx: 4,
        width: Math.max((item.value / maximum) * (width - labelWidth - 44), 2),
        height: settings.rowHeight - 9,
        fill: item.color || 'var(--accent)'
      }));
      const value = svgEl('text', {
        x: width, y: y + settings.rowHeight * 0.66, 'text-anchor': 'end',
        'font-size': 10, fill: 'var(--text-secondary)'
      });
      value.textContent = item.caption !== undefined ? item.caption : Lotto.ui.decimal(item.value, 0);
      svg.appendChild(value);
    });
    return wrap(svg);
  }

  /** Due serie affiancate, per i confronti storico/simulato o strategia/baseline. */
  function groupedBars(items, options) {
    const settings = Object.assign({ height: 170, labels: ['A', 'B'], colors: ['var(--accent)', 'var(--text-secondary)'] }, options || {});
    const width = Math.max(300, items.length * 46);
    const height = settings.height;
    const padding = { top: 22, right: 8, bottom: 24, left: 34 };
    const plotWidth = width - padding.left - padding.right;
    const plotHeight = height - padding.top - padding.bottom;

    let maximum = 0;
    items.forEach((item) => {
      maximum = Math.max(maximum, item.a || 0, item.b || 0);
    });
    if (maximum <= 0) maximum = 1;

    const svg = svgEl('svg', { viewBox: '0 0 ' + width + ' ' + height, width: '100%', height: height });
    [0, 0.5, 1].forEach((fraction) => {
      const y = padding.top + plotHeight * (1 - fraction);
      svg.appendChild(svgEl('line', {
        x1: padding.left, x2: width - padding.right, y1: y, y2: y,
        stroke: 'var(--separator)', 'stroke-width': 1
      }));
      const label = svgEl('text', {
        x: padding.left - 5, y: y + 3.5, 'text-anchor': 'end', 'font-size': 9, fill: 'var(--text-secondary)'
      });
      label.textContent = Lotto.ui.decimal(maximum * fraction, maximum > 20 ? 0 : 1);
      svg.appendChild(label);
    });

    const slot = plotWidth / items.length;
    items.forEach((item, index) => {
      const base = padding.left + index * slot;
      [['a', 0], ['b', 1]].forEach((pair) => {
        const value = item[pair[0]] || 0;
        const barHeight = Math.max((value / maximum) * plotHeight, value > 0 ? 1 : 0);
        svg.appendChild(svgEl('rect', {
          x: base + slot * (0.15 + pair[1] * 0.38),
          y: padding.top + plotHeight - barHeight,
          width: slot * 0.32,
          height: barHeight,
          rx: 2,
          fill: settings.colors[pair[1]]
        }));
      });
      const label = svgEl('text', {
        x: base + slot / 2, y: height - 8, 'text-anchor': 'middle',
        'font-size': 9, fill: 'var(--text-secondary)'
      });
      label.textContent = item.label;
      svg.appendChild(label);
    });

    // Legenda.
    settings.labels.forEach((text, index) => {
      svg.appendChild(svgEl('rect', {
        x: padding.left + index * 92, y: 4, width: 9, height: 9, rx: 2, fill: settings.colors[index]
      }));
      const node = svgEl('text', {
        x: padding.left + index * 92 + 13, y: 12, 'font-size': 10, fill: 'var(--text-secondary)'
      });
      node.textContent = text;
      svg.appendChild(node);
    });
    return wrap(svg, 300);
  }

  /** Spezzata, usata per il saldo cumulato del backtest. */
  function lineChart(points, options) {
    const settings = Object.assign({ height: 160 }, options || {});
    if (!points.length) return document.createElement('div');
    const width = Math.max(300, points.length * 3 + 40);
    const height = settings.height;
    const padding = { top: 12, right: 8, bottom: 20, left: 46 };
    const plotWidth = width - padding.left - padding.right;
    const plotHeight = height - padding.top - padding.bottom;

    let minimum = Infinity;
    let maximum = -Infinity;
    points.forEach((point) => {
      if (point.value < minimum) minimum = point.value;
      if (point.value > maximum) maximum = point.value;
    });
    if (minimum === maximum) { minimum -= 1; maximum += 1; }

    const x = (index) => padding.left + (index / Math.max(points.length - 1, 1)) * plotWidth;
    const y = (value) => padding.top + plotHeight * (1 - (value - minimum) / (maximum - minimum));

    const svg = svgEl('svg', { viewBox: '0 0 ' + width + ' ' + height, width: '100%', height: height });
    if (minimum < 0 && maximum > 0) {
      svg.appendChild(svgEl('line', {
        x1: padding.left, x2: width - padding.right, y1: y(0), y2: y(0),
        stroke: 'var(--separator)', 'stroke-width': 1, 'stroke-dasharray': '3 3'
      }));
    }
    const path = points.map((point, index) => (index === 0 ? 'M' : 'L') + x(index) + ' ' + y(point.value)).join(' ');
    svg.appendChild(svgEl('path', {
      d: path, fill: 'none', 'stroke-width': 1.8,
      stroke: points[points.length - 1].value >= 0 ? 'var(--high)' : 'var(--low)'
    }));

    [maximum, minimum].forEach((value) => {
      const node = svgEl('text', {
        x: padding.left - 5, y: y(value) + 3.5, 'text-anchor': 'end',
        'font-size': 9, fill: 'var(--text-secondary)'
      });
      node.textContent = Lotto.ui.decimal(value, 0);
      svg.appendChild(node);
    });
    return wrap(svg, 300);
  }

  /** Heatmap ruote × numeri o anni × numeri. */
  function heatmap(rows, columns, valueFor) {
    const cell = 9;
    const labelWidth = 30;
    const width = labelWidth + columns.length * cell + 6;
    const height = rows.length * cell + 16;
    const svg = svgEl('svg', { viewBox: '0 0 ' + width + ' ' + height, width: '100%', height: height });

    rows.forEach((row, rowIndex) => {
      const label = svgEl('text', {
        x: 0, y: 12 + rowIndex * cell + cell * 0.75, 'font-size': 8, fill: 'var(--text-secondary)'
      });
      label.textContent = row.label;
      svg.appendChild(label);
      columns.forEach((column, columnIndex) => {
        const value = valueFor(row, column);
        svg.appendChild(svgEl('rect', {
          x: labelWidth + columnIndex * cell,
          y: 12 + rowIndex * cell,
          width: cell - 1,
          height: cell - 1,
          fill: 'var(--accent)',
          'fill-opacity': (0.08 + value * 0.85).toFixed(3)
        }));
      });
    });
    [1, 15, 30, 45, 60, 75, 90].forEach((number) => {
      if (number > columns.length) return;
      const node = svgEl('text', {
        x: labelWidth + (number - 1) * cell, y: 8, 'font-size': 8, fill: 'var(--text-secondary)'
      });
      node.textContent = String(number);
      svg.appendChild(node);
    });
    return wrap(svg, width);
  }

  Lotto.charts = { barChart: barChart, horizontalBars: horizontalBars, groupedBars: groupedBars,
    lineChart: lineChart, heatmap: heatmap };
})(typeof self !== 'undefined' ? self : this);
