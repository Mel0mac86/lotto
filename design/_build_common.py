# -*- coding: utf-8 -*-
"""Assembla gli artboard .dc.html condividendo un'unica base tipografica e cromatica."""

FONTS = ''

CSS = """
    * { box-sizing: border-box; }
    body { margin: 0; background: #0E1116; }
    a { color: #58A6FF; text-decoration: none; }
    a:hover { color: #79B8FF; }

    /* Terminale dati: scuro di default, chiaro come variante. */
    .root {
      --bg: #0E1116;      /* fondo */
      --panel: #12171E;   /* fascia/pannello */
      --line: #232A34;    /* filetto marcato */
      --hair: #1A2029;    /* filetto sottile */
      --fg: #E6EDF3;      /* testo primario */
      --fg2: #8B949E;     /* testo secondario */
      --fg3: #59626D;     /* testo terziario */
      --ok: #3FB950;      /* indice alto */
      --warn: #D8A02A;    /* indice medio */
      --bad: #F85149;     /* indice basso / negativo */
      --key: #58A6FF;     /* azione */
      --grid: #1B222B;    /* reticolo dei grafici */
      --mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
      --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, "Segoe UI", sans-serif;
      width: 390px; height: 844px; overflow: hidden;
      display: flex; flex-direction: column;
      background: var(--bg); color: var(--fg);
      font-family: var(--sans);
      font-size: 13px; line-height: 1.45;
      -webkit-font-smoothing: antialiased;
    }
    .root.t-chiaro {
      --bg: #FFFFFF; --panel: #F7F8FA; --line: #D5DBE2; --hair: #E6EAEF;
      --fg: #10151B; --fg2: #5B6672; --fg3: #8A939E;
      --ok: #197A3D; --warn: #8A6100; --bad: #C0342E; --key: #1B5FC1;
      --grid: #EDF0F4;
    }

    .mono { font-family: var(--mono); font-variant-numeric: tabular-nums; }

    /* Etichetta di sezione: la spaziatura è la firma del terminale. */
    .lbl {
      font-family: var(--mono); font-size: 10px; font-weight: 500;
      letter-spacing: 0.14em; text-transform: uppercase; color: var(--fg3);
    }

    .bar {
      height: 46px; flex: 0 0 46px; display: flex; align-items: center; gap: 10px;
      padding: 0 16px; border-bottom: 1px solid var(--line); background: var(--bg);
    }
    .scroll { flex: 1 1 auto; overflow: hidden; }
    .pad { padding: 0 16px; }

    .sec { border-top: 1px solid var(--hair); padding: 14px 16px 0; }
    .sec:first-child { border-top: none; }

    .rowline { display: flex; align-items: center; gap: 10px; padding: 9px 0; border-bottom: 1px solid var(--hair); }
    .rowline:last-child { border-bottom: none; }
    .grow { flex: 1 1 auto; min-width: 0; }

    /* Chip numerico: quadrato, non pallina — è uno strumento, non una tombola. */
    .chip {
      width: 52px; height: 52px; border-radius: 3px; border: 1px solid;
      display: flex; align-items: center; justify-content: center;
      font-family: var(--mono); font-size: 19px; font-weight: 500;
      font-variant-numeric: tabular-nums;
    }
    .chip.sm { width: 38px; height: 38px; font-size: 14px; }
    .chip-ok   { color: var(--ok);   border-color: rgba(63,185,80,0.45);  background: rgba(63,185,80,0.10); }
    .chip-warn { color: var(--warn); border-color: rgba(216,160,42,0.45); background: rgba(216,160,42,0.10); }
    .chip-bad  { color: var(--bad);  border-color: rgba(248,81,73,0.45);  background: rgba(248,81,73,0.10); }
    .chip-flat { color: var(--fg2);  border-color: var(--line);           background: transparent; }
    .t-chiaro .chip-ok   { border-color: rgba(25,122,61,0.40);  background: rgba(25,122,61,0.07); }
    .t-chiaro .chip-warn { border-color: rgba(138,97,0,0.40);   background: rgba(138,97,0,0.07); }
    .t-chiaro .chip-bad  { border-color: rgba(192,52,46,0.40);  background: rgba(192,52,46,0.07); }

    .nav {
      flex: 0 0 58px; display: flex; border-top: 1px solid var(--line);
      background: var(--panel);
    }
    .nav > div {
      flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px;
      font-family: var(--mono); font-size: 9px; letter-spacing: 0.08em;
      text-transform: uppercase; color: var(--fg3); border-right: 1px solid var(--hair);
    }
    .nav > div:last-child { border-right: none; }
    .nav > div.on { color: var(--fg); background: var(--bg); }

    .btn {
      height: 44px; display: flex; align-items: center; justify-content: center; gap: 8px;
      border: 1px solid var(--line); border-radius: 3px; background: transparent; color: var(--fg);
      font-family: var(--mono); font-size: 11px; font-weight: 500;
      letter-spacing: 0.1em; text-transform: uppercase;
    }
    .btn.key { border-color: var(--key); color: var(--key); }

    .note { font-size: 11px; line-height: 1.5; color: var(--fg2); }
    .warnbox {
      border-left: 2px solid var(--fg3); padding: 8px 0 8px 10px;
      font-size: 10.5px; line-height: 1.5; color: var(--fg2);
    }
"""

def icon(name, color='currentColor'):
    """Icone a tratto, 20px, un solo stile. Mai emoji."""
    paths = {
        'home':   '<path d="M3 9.5 10 4l7 5.5V16a1 1 0 0 1-1 1h-3v-5H7v5H4a1 1 0 0 1-1-1z"/>',
        'chart':  '<path d="M3 17h14M6 14V8M10 14V4M14 14v-6"/>',
        'wand':   '<path d="M10 3v3M10 14v3M3 10h3M14 10h3M5.6 5.6l2.1 2.1M12.3 12.3l2.1 2.1M14.4 5.6l-2.1 2.1M7.7 12.3l-2.1 2.1"/>',
        'flask':  '<path d="M8 3v5L4 16a1 1 0 0 0 .9 1.5h10.2A1 1 0 0 0 16 16l-4-8V3M7 3h6M6.5 12h7"/>',
        'db':     '<ellipse cx="10" cy="5.5" rx="6" ry="2.5"/><path d="M4 5.5v9c0 1.4 2.7 2.5 6 2.5s6-1.1 6-2.5v-9M4 10c0 1.4 2.7 2.5 6 2.5s6-1.1 6-2.5"/>',
        'arrow':  '<path d="M7 4l6 6-6 6"/>',
        'back':   '<path d="M12 4l-6 6 6 6"/>',
        'link':   '<path d="M8.5 11.5a3 3 0 0 0 4.2 0l2.3-2.3a3 3 0 0 0-4.2-4.2l-1 1M11.5 8.5a3 3 0 0 0-4.2 0L5 10.8a3 3 0 0 0 4.2 4.2l1-1"/>',
        'clock':  '<circle cx="10" cy="10" r="7"/><path d="M10 6v4l2.5 2"/>',
        'flame':  '<path d="M10 3s4 3.5 4 7a4 4 0 0 1-8 0c0-1.6 1-2.8 1-2.8S7 9 8.5 9C8.5 6 10 3 10 3z"/>',
        'snow':   '<path d="M10 3v14M4 6.5l12 7M16 6.5l-12 7"/>',
        'target': '<circle cx="10" cy="10" r="7"/><circle cx="10" cy="10" r="3"/>',
        'brain':  '<path d="M8 4a2.5 2.5 0 0 0-2.5 2.5A2.5 2.5 0 0 0 4 9c0 1 .6 1.9 1.5 2.3V13a2.5 2.5 0 0 0 5 0V4.8A1.8 1.8 0 0 0 8 4zM12 4a2.5 2.5 0 0 1 2.5 2.5A2.5 2.5 0 0 1 16 9c0 1-.6 1.9-1.5 2.3V13a2.5 2.5 0 0 1-5 0"/>',
        'search': '<circle cx="9" cy="9" r="5.5"/><path d="M13 13l4 4"/>',
        'dice':   '<rect x="3.5" y="3.5" width="13" height="13" rx="2"/><circle cx="7.5" cy="7.5" r="1"/><circle cx="12.5" cy="12.5" r="1"/><circle cx="10" cy="10" r="1"/>',
        'scale':  '<path d="M10 4v13M5 8h10M6.5 8l-2.5 4.5h5zM13.5 8L11 12.5h5z"/>',
        'lock':   '<rect x="4.5" y="9" width="11" height="7.5" rx="1.5"/><path d="M7 9V6.5a3 3 0 0 1 6 0V9"/>',
        'check':  '<path d="M4.5 10.5l3.5 3.5 7.5-8"/>',
        'grid':   '<rect x="3.5" y="3.5" width="5.5" height="5.5"/><rect x="11" y="3.5" width="5.5" height="5.5"/><rect x="3.5" y="11" width="5.5" height="5.5"/><rect x="11" y="11" width="5.5" height="5.5"/>',
    }
    return ('<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="%s" '
            'stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">%s</svg>'
            % (color, paths[name]))

def artboard(body, props=None, extra_css=''):
    props_json = props or '{"tema":{"editor":"enum","options":["scuro","chiaro"],"default":"scuro"},"$preview":{"width":390,"height":844}}'
    return """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>%s%s</style>
</helmet>
<div class="root {{temaClasse}}">
%s
</div>
</x-dc>
<script data-dc-script data-props='%s'>
class Component extends DCLogic {
  renderVals() {
    return { temaClasse: this.props.tema === 'chiaro' ? 't-chiaro' : 't-scuro' };
  }
}
</script>
</body>
</html>
""" % (CSS, extra_css, body, props_json)

def nav(active):
    items = [('home', 'Home'), ('chart', 'Analisi'), ('wand', 'Genera'), ('flask', 'Verifica'), ('db', 'Dati')]
    cells = []
    for key, label in items:
        on = (key == active)
        colour = 'var(--fg)' if on else 'var(--fg3)'
        cells.append('  <div%s>%s<span>%s</span></div>'
                     % (' class="on"' if on else '', icon(key, colour), label))
    return '<div class="nav">\n' + '\n'.join(cells) + '\n</div>'

def topbar(title, right=''):
    return ('<div class="bar">\n'
            '  <span class="lbl" style="color: var(--fg); font-size: 11px; letter-spacing: 0.16em">%s</span>\n'
            '  <span class="grow"></span>\n'
            '  %s\n'
            '</div>' % (title, right))

def backbar(title, right=''):
    return ('<div class="bar">\n'
            '  <span style="display: flex; align-items: center; color: var(--key)">%s</span>\n'
            '  <span class="lbl" style="color: var(--fg); font-size: 11px; letter-spacing: 0.16em">%s</span>\n'
            '  <span class="grow"></span>\n'
            '  %s\n'
            '</div>' % (icon('back', 'var(--key)'), title, right))

def ctx(text):
    return ('<span class="mono" style="font-size: 10px; letter-spacing: 0.08em; color: var(--fg2); '
            'border: 1px solid var(--line); border-radius: 3px; padding: 3px 7px">%s</span>' % text)

def band(score):
    return 'var(--ok)' if score >= 80 else ('var(--warn)' if score >= 50 else 'var(--bad)')

def chip(number, score=None, small=False):
    kind = 'flat'
    if score is not None:
        kind = 'ok' if score >= 80 else ('warn' if score >= 50 else 'bad')
    return ('<div class="chip%s chip-%s">%02d</div>' % (' sm' if small else '', kind, number))
