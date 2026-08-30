# -*- coding: utf-8 -*-
"""Dashboard, Analisi e Ambi."""
import sys; sys.path.insert(0, '.')
from _build_common import artboard, nav, topbar, backbar, ctx, chip, icon, band

def w(name, body, extra_css=''):
    open(name, 'w', encoding='utf-8').write(artboard(body, extra_css=extra_css))
    print('scritto', name)

# ----------------------------------------------------------------- DASHBOARD
def stat(label, value, sub):
    return ('''<div style="flex: 1">
      <div class="lbl">%s</div>
      <div class="mono" style="font-size: 26px; font-weight: 500; letter-spacing: -0.01em; margin-top: 2px">%s</div>
      <div class="mono" style="font-size: 10px; color: var(--fg3); letter-spacing: 0.04em">%s</div>
    </div>''' % (label, value, sub))

def signal(kind, number, caption, colour):
    return ('''<div style="flex: 1; display: flex; align-items: center; gap: 8px; padding: 10px 0">
      <span style="display: flex">%s</span>
      <div>
        <div class="mono" style="font-size: 17px; font-weight: 500; color: %s; line-height: 1.1">%s</div>
        <div class="mono" style="font-size: 9px; color: var(--fg3); letter-spacing: 0.06em">%s</div>
      </div>
    </div>''' % (icon(kind, colour), colour, number, caption))

def dest(index, name, meta, ikon):
    return ('''<div class="rowline">
      <span class="mono" style="font-size: 10px; color: var(--fg3); width: 18px">%s</span>
      <span style="display: flex; opacity: 0.75">%s</span>
      <span class="grow" style="font-weight: 500; letter-spacing: -0.005em">%s</span>
      <span class="mono" style="font-size: 10.5px; color: var(--fg2)">%s</span>
      <span style="display: flex; opacity: 0.5">%s</span>
    </div>''' % (index, icon(ikon, 'var(--fg2)'), name, meta, icon('arrow', 'var(--fg3)')))

dashboard = topbar('Lotto AI Analyzer', ctx('BARI · 5A')) + '''
<div class="scroll">
  <div class="sec">
    <div class="lbl">Archivio locale</div>
    <div style="display: flex; gap: 16px; margin-top: 8px">
      ''' + stat('Lotto', '6.897', 'al 29.08.26') + stat('SuperEnalotto', '627', 'al 29.08.26') + '''
    </div>
    <div style="height: 14px"></div>
  </div>

  <div class="sec">
    <div class="lbl">Segnali del periodo</div>
    <div style="display: flex; gap: 12px; border-bottom: 1px solid var(--hair)">
      ''' + signal('flame', '73', 'trend +38%', 'var(--ok)') + \
            signal('snow', '12', 'trend −29%', 'var(--key)') + \
            signal('clock', '64', 'ritardo 87', 'var(--warn)') + '''
    </div>
  </div>

  <div class="sec" style="border-top: none; padding-top: 12px">
    <div style="display: flex; gap: 0; border: 1px solid var(--line); border-radius: 3px; overflow: hidden">
      <div class="mono on" style="flex: 1; text-align: center; padding: 9px 0; font-size: 11px; letter-spacing: 0.1em; background: var(--panel); color: var(--fg); border-right: 1px solid var(--line)">LOTTO</div>
      <div class="mono" style="flex: 1; text-align: center; padding: 9px 0; font-size: 11px; letter-spacing: 0.1em; color: var(--fg3)">SUPERENALOTTO</div>
    </div>
    <div style="height: 10px"></div>
  </div>

  <div class="sec">
    <div class="lbl" style="margin-bottom: 2px">Analisi</div>
    ''' + dest('01', 'Frequenze e ritardi', '90 numeri', 'chart') \
        + dest('02', 'Ritardatari', 'max 87', 'clock') \
        + dest('03', 'Caldi e freddi', '7 filtri', 'flame') + '''
  </div>

  <div class="sec">
    <div class="lbl" style="margin-bottom: 2px">Combinazioni</div>
    ''' + dest('04', 'Ambi', '4.005 coppie', 'link') \
        + dest('05', 'Terni', '117.480 terne', 'grid') \
        + dest('06', 'Cinquina AI', '4 modalità', 'target') \
        + dest('07', 'Multi-ruota', '11 ruote', 'dice') + '''
  </div>

  <div class="sec">
    <div class="lbl" style="margin-bottom: 2px">Verifica</div>
    ''' + dest('08', 'Backtest', 'walk-forward', 'flask') \
        + dest('09', 'AI Analyst', 'AUC 0,492', 'brain') + '''
  </div>
</div>
''' + nav('home')

w('Main.dc.html', dashboard)

# ------------------------------------------------------------------ ANALISI
def deviation_bars(values, expected, height=72, width=358, extreme=8):
    """Scostamento dall'atteso: barre sopra e sotto una linea centrale.
       Con frequenze tutte vicine alla media un istogramma classico diventa un
       blocco pieno; qui si legge subito chi sta sopra e chi sotto, che è il punto."""
    deltas = [v - expected for v in values]
    span = max(abs(d) for d in deltas) or 1
    mid = height / 2
    pitch = width / len(values)
    bar = pitch * 0.58
    order = sorted(range(len(values)), key=lambda i: deltas[i])
    low, high = set(order[:extreme]), set(order[-extreme:])
    rects = []
    for i, delta in enumerate(deltas):
        h = max(abs(delta) / span * (mid - 3), 0.8)
        y = mid - h if delta >= 0 else mid
        colour = 'var(--ok)' if i in high else ('var(--bad)' if i in low else 'var(--fg3)')
        rects.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>'
                     % (i * pitch, y, bar, h, colour))
    return ('<svg width="100%%" height="%d" viewBox="0 0 %d %d">%s'
            '<line x1="0" x2="%d" y1="%.1f" y2="%.1f" stroke="var(--fg3)" stroke-width="0.8" '
            'stroke-dasharray="3 3"/></svg>'
            % (height, width, height, ''.join(rects), width, mid, mid))


def bars(values, colours, height=64, width=358):
    """Istogramma sottile. Il colore compare solo dove porta informazione."""
    top = max(values) or 1
    pitch = width / len(values)
    bar = pitch * 0.58
    rects = ''.join(
        '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>'
        % (i * pitch, height - max(v / top * height, 0.8), bar, max(v / top * height, 0.8), colours[i])
        for i, v in enumerate(values))
    return '<svg width="100%%" height="%d" viewBox="0 0 %d %d">%s</svg>' % (height, width, height, rects)

import math

def pseudo(seed, count):
    """Sequenza deterministica con aspetto casuale (LCG): le frequenze reali
       oscillano attorno all'atteso, non disegnano onde."""
    values = []
    state = seed
    for _ in range(count):
        state = (state * 1103515245 + 12345) % 2147483648
        values.append(state / 2147483648)
    return values

noise = pseudo(7, 90)
freq = [round(34.8 + (u - 0.5) * 17) for u in noise]
order = sorted(range(90), key=lambda i: freq[i])
low8, high8 = set(order[:8]), set(order[-8:])
freq_colours = ['var(--bad)' if i in low8 else ('var(--ok)' if i in high8 else 'var(--fg3)')
                for i in range(90)]

delay_noise = pseudo(31, 90)
delays = [int(u * u * 88) for u in delay_noise]
top_delays = set(sorted(range(90), key=lambda i: delays[i])[-10:])
delay_colours = ['var(--bad)' if i in top_delays else 'var(--fg3)' for i in range(90)]

def trow(n, occ, freq_pct, rit, idx):
    return ('''<div class="rowline" style="padding: 7px 0">
      <span class="mono" style="width: 26px; font-weight: 500">%02d</span>
      <span class="mono grow" style="font-size: 12px; color: var(--fg2)">%d</span>
      <span class="mono" style="width: 48px; text-align: right; font-size: 12px; color: var(--fg2)">%s</span>
      <span class="mono" style="width: 34px; text-align: right; font-size: 12px; color: var(--fg2)">%d</span>
      <span class="mono" style="width: 38px; text-align: right; font-size: 12px; font-weight: 500; color: %s">%d</span>
    </div>''' % (n, occ, freq_pct, rit, band(idx), idx))

analisi = backbar('Analisi', ctx('LOTTO · BARI')) + '''
<div class="scroll">
  <div class="sec" style="padding-bottom: 12px">
    <div style="display: flex; gap: 8px">
      <div class="mono" style="flex: 1; border: 1px solid var(--line); border-radius: 3px; padding: 8px 10px; font-size: 11px; display: flex; justify-content: space-between"><span style="color: var(--fg3)">RUOTA</span><span>BARI</span></div>
      <div class="mono" style="flex: 1; border: 1px solid var(--line); border-radius: 3px; padding: 8px 10px; font-size: 11px; display: flex; justify-content: space-between"><span style="color: var(--fg3)">PERIODO</span><span>5 ANNI</span></div>
    </div>
    <div class="mono" style="display: flex; gap: 18px; margin-top: 12px; font-size: 10.5px; color: var(--fg2)">
      <span>ESTRAZIONI <b style="color: var(--fg); font-weight: 500">627</b></span>
      <span>DAL <b style="color: var(--fg); font-weight: 500">01.09.22</b></span>
      <span>AL <b style="color: var(--fg); font-weight: 500">29.08.26</b></span>
    </div>
  </div>

  <div class="sec">
    <div style="display: flex; align-items: baseline"><span class="lbl grow">Scostamento dall'atteso</span><span class="mono" style="font-size: 9.5px; color: var(--fg3)">--- 34,8 ATTESE</span></div>
    <div style="margin: 10px 0 4px">''' + deviation_bars(freq, 34.8) + '''</div>
    <div class="mono" style="display: flex; justify-content: space-between; font-size: 9px; color: var(--fg3); padding-bottom: 12px">
      <span>01</span><span>23</span><span>45</span><span>68</span><span>90</span>
    </div>
    <div class="note" style="padding-bottom: 12px; font-size: 10px">Sopra la linea i numeri usciti più dell'atteso, sotto quelli usciti meno. In colore i dieci estremi.</div>
  </div>

  <div class="sec">
    <div class="lbl">Ritardo attuale</div>
    <div style="margin: 10px 0 4px">''' + bars(delays, delay_colours, 48) + '''</div>
    <div class="note" style="padding-bottom: 12px; font-size: 10px">In rosso i dieci ritardi più lunghi del periodo.</div>
  </div>

  <div class="sec">
    <div class="rowline lbl" style="padding-bottom: 7px">
      <span style="width: 26px">N.</span><span class="grow">USCITE</span>
      <span style="width: 48px; text-align: right">FREQ %</span>
      <span style="width: 34px; text-align: right">RIT</span>
      <span style="width: 38px; text-align: right">IDX</span>
    </div>
    ''' + trow(73, 48, '7,66', 2, 91) + trow(28, 46, '7,34', 5, 84) \
        + trow(64, 27, '4,31', 87, 76) + trow(17, 43, '6,86', 11, 68) \
        + trow(43, 40, '6,38', 19, 57) + trow(12, 25, '3,99', 41, 38) + '''
  </div>
</div>
''' + nav('chart')

w('Analisi.dc.html', analisi)

# --------------------------------------------------------------------- AMBI
def pair_row(rank, a, b, score, uscite, attese, lift, ritardo, expanded=False):
    reasons = ''
    if expanded:
        reasons = '''
      <div style="border-top: 1px solid var(--hair); margin-top: 10px; padding-top: 10px">
        <div class="lbl" style="margin-bottom: 6px">Perché</div>
        <div class="note">Uscite congiunte: 6 su 627 estrazioni, attese dal caso 1,6.</div>
        <div class="note">Ricorrenza superiore all'atteso del 282%.</div>
        <div class="note">Ritardo dell'ambo: 41 estrazioni dall'ultima uscita congiunta.</div>
        <div class="note" style="color: var(--fg3); margin-top: 6px">Questi dati descrivono il passato e non aumentano la probabilità matematica dell'estrazione futura.</div>
      </div>'''
    return ('''<div style="border-bottom: 1px solid var(--hair); padding: 12px 0">
      <div style="display: flex; align-items: center; gap: 10px">
        <span class="mono" style="font-size: 10px; color: var(--fg3); width: 16px">%02d</span>
        <div style="display: flex; gap: 6px">%s%s</div>
        <span class="grow"></span>
        <div style="text-align: right">
          <div class="mono" style="font-size: 20px; font-weight: 500; color: %s; line-height: 1">%d</div>
          <div class="lbl" style="font-size: 8.5px">INDICE</div>
        </div>
      </div>
      <div class="mono" style="display: flex; gap: 14px; margin: 9px 0 0 26px; font-size: 10px; color: var(--fg2)">
        <span>USC <b style="color: var(--fg); font-weight: 500">%d</b></span>
        <span>ATT <b style="color: var(--fg); font-weight: 500">%s</b></span>
        <span>×<b style="color: %s; font-weight: 500">%s</b></span>
        <span>RIT <b style="color: var(--fg); font-weight: 500">%d</b></span>
      </div>%s
    </div>''' % (rank, chip(a, score, True), chip(b, score, True), band(score), score,
                 uscite, attese, 'var(--ok)' if float(lift.replace(',', '.')) > 1.15 else 'var(--fg)', lift,
                 ritardo, reasons))

ambi = backbar('Ambi', ctx('4.005 COPPIE')) + '''
<div class="scroll">
  <div class="sec" style="padding-bottom: 10px">
    <div class="lbl">Top ambi statisticamente interessanti</div>
    <div class="note" style="margin-top: 4px">Valutate tutte le coppie fra 1 e 90 sul periodo selezionato.</div>
  </div>
  <div class="pad">
    ''' + pair_row(1, 17, 64, 87, 6, '1,6', '3,82', 41, expanded=True) \
        + pair_row(2, 23, 71, 84, 6, '1,6', '3,82', 9) \
        + pair_row(3, 11, 48, 82, 5, '1,6', '3,18', 74) \
        + pair_row(4, 28, 73, 79, 5, '1,6', '3,18', 22) + '''
  </div>
</div>
''' + nav('wand')

w('Ambi.dc.html', ambi)
