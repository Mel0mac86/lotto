# -*- coding: utf-8 -*-
"""Cinquina AI, pagina risultato, backtest e AI Analyst."""
import sys; sys.path.insert(0, '.')
from _build_common import artboard, nav, topbar, backbar, ctx, chip, icon, band

def w(name, body):
    open(name, 'w', encoding='utf-8').write(artboard(body))
    print('scritto', name)

def meter(value, label, width=None):
    """Barra di componente: il valore è anche testo, non solo lunghezza."""
    return ('''<div style="margin-bottom: 9px">
      <div style="display: flex; align-items: baseline">
        <span class="lbl grow" style="color: var(--fg2)">%s</span>
        <span class="mono" style="font-size: 11px; color: %s">%d</span>
      </div>
      <div style="height: 3px; background: var(--grid); margin-top: 4px">
        <div style="height: 3px; width: %d%%; background: %s"></div>
      </div>
    </div>''' % (label, band(value), value, max(value, 2), band(value)))

# ------------------------------------------------------------- CINQUINA AI
def mode(name, sub, on):
    marker = ('<span class="mono" style="color: var(--key); font-size: 13px">[×]</span>' if on
              else '<span class="mono" style="color: var(--fg3); font-size: 13px">[ ]</span>')
    return ('''<div class="rowline" style="padding: 11px 0">
      %s
      <span class="grow">
        <div style="font-weight: 500; color: %s">%s</div>
        <div class="note" style="font-size: 10.5px">%s</div>
      </span>
    </div>''' % (marker, 'var(--fg)' if on else 'var(--fg2)', name, sub))

def combo(index, numbers, score, pari, bassi, somma):
    chips = ''.join(chip(n, score, True) for n in numbers)
    return ('''<div style="border-bottom: 1px solid var(--hair); padding: 13px 0">
      <div style="display: flex; align-items: center">
        <span class="lbl grow">Combinazione %d</span>
        <span class="mono" style="font-size: 17px; font-weight: 500; color: %s">%d<span style="font-size: 10px; color: var(--fg3)">/100</span></span>
      </div>
      <div style="display: flex; gap: 6px; margin: 9px 0 8px">%s</div>
      <div class="mono" style="display: flex; gap: 14px; font-size: 10px; color: var(--fg2)">
        <span>PARI <b style="color: var(--fg); font-weight: 500">%d</b></span>
        <span>1–45 <b style="color: var(--fg); font-weight: 500">%d</b></span>
        <span>SOMMA <b style="color: var(--fg); font-weight: 500">%d</b></span>
      </div>
    </div>''' % (index, band(score), score, chips, pari, bassi, somma))

cinquina = backbar('Cinquina AI', ctx('BARI · 5A')) + '''
<div class="scroll">
  <div class="sec" style="padding-bottom: 8px">
    <div class="lbl">Modalità di generazione</div>
    ''' + mode('Conservativa', 'Numeri con indice statistico elevato', False) \
        + mode('Bilanciata', 'Mix di frequenti, ritardatari e medi', True) \
        + mode('Diversificata', 'Riduce la sovrapposizione con le precedenti', False) \
        + mode('Random statistica', 'Casuale entro vincoli storici', False) + '''
    <div style="height: 12px"></div>
    <div class="btn key">Genera 5 combinazioni</div>
    <div style="height: 14px"></div>
  </div>

  <div class="sec">
    ''' + combo(1, [17, 28, 43, 64, 81], 86, 2, 3, 233) \
        + combo(2, [7, 22, 38, 55, 79], 78, 2, 3, 201) \
        + combo(3, [12, 30, 59, 72, 87], 64, 3, 2, 260) + '''
  </div>
</div>
''' + nav('wand')

w('Cinquina.dc.html', cinquina)

# ------------------------------------------------------- PAGINA RISULTATO
def dist(label, value):
    return ('''<div style="flex: 1 1 33%%; padding: 9px 0">
      <div class="lbl" style="font-size: 8.5px">%s</div>
      <div class="mono" style="font-size: 16px; font-weight: 500; margin-top: 1px">%s</div>
    </div>''' % (label, value))

gauge_segments = ''.join(
    '<div style="flex: 1; height: 6px; background: %s"></div>'
    % ('var(--ok)' if i < 17 else 'var(--grid)') for i in range(20))

risultato = backbar('Combinazione', ctx('BILANCIATA')) + '''
<div class="scroll">
  <div class="sec" style="padding-bottom: 16px">
    <div class="lbl">Combinazione generata</div>
    <div style="display: flex; gap: 8px; margin: 12px 0 18px">
      ''' + ''.join(chip(n, 86) for n in [17, 28, 43, 64, 81]) + '''
    </div>
    <div style="display: flex; align-items: flex-end; gap: 10px">
      <span class="mono" style="font-size: 46px; font-weight: 500; line-height: 0.9; letter-spacing: -0.02em; color: var(--ok)">86</span>
      <span class="mono" style="font-size: 13px; color: var(--fg3); padding-bottom: 4px">/100</span>
      <span class="grow"></span>
      <span class="lbl" style="padding-bottom: 5px">Indice statistico</span>
    </div>
    <div style="display: flex; gap: 2px; margin-top: 10px">''' + gauge_segments + '''</div>
    <div class="mono" style="display: flex; justify-content: space-between; font-size: 9px; color: var(--fg3); margin-top: 5px">
      <span>0</span><span>50</span><span>80</span><span>100</span>
    </div>
  </div>

  <div class="sec">
    <div class="lbl" style="margin-bottom: 10px">Scomposizione</div>
    ''' + meter(88, 'Frequenza') + meter(54, 'Ritardo') + meter(71, 'Trend') \
        + meter(83, 'Co-occorrenza') + meter(79, 'Equilibrio') + '''
    <div style="height: 6px"></div>
  </div>

  <div class="sec">
    <div class="lbl">Distribuzione</div>
    <div style="display: flex; flex-wrap: wrap; border-bottom: 1px solid var(--hair)">
      ''' + dist('Pari', '2') + dist('Dispari', '3') + dist('Somma', '233') \
          + dist('1–45', '3') + dist('46–90', '2') + dist('Decine', '5') + '''
    </div>
  </div>

  <div class="sec">
    <div class="lbl" style="margin-bottom: 6px">In sintesi</div>
    <div class="note">Il 73 è il più frequente della combinazione: 48 uscite su 627 estrazioni, 7,66% contro un atteso del 5,56%. Il 64 manca da 87 estrazioni, con un massimo storico di 94.</div>
    <div style="height: 12px"></div>
    <div class="warnbox">Score statistico basato sui dati storici selezionati. Non rappresenta la probabilità reale che la combinazione venga estratta.</div>
    <div style="height: 14px"></div>
  </div>
</div>
''' + nav('wand')

w('Risultato.dc.html', risultato)

# ------------------------------------------------------------------ BACKTEST
def equity(points, width=358, height=72):
    """Curva del saldo: viewBox alla larghezza reale, così il tratto non si deforma."""
    top, low = max(points), min(points)
    span = (top - low) or 1
    step = width / (len(points) - 1)
    d = ' '.join(('M' if i == 0 else 'L') + '%.1f %.1f' % (i * step, height - (v - low) / span * height)
                 for i, v in enumerate(points))
    zero = height - (0 - low) / span * height
    colour = 'var(--ok)' if points[-1] >= 0 else 'var(--bad)'
    return ('<svg width="100%%" height="%d" viewBox="0 0 %d %d">'
            '<line x1="0" x2="%d" y1="%.1f" y2="%.1f" stroke="var(--grid)" stroke-width="1"/>'
            '<path d="%s" fill="none" stroke="%s" stroke-width="1.4"/></svg>'
            % (height, width, height, width, zero, zero, d, colour))

curve = [0]
HITS = {104}
for step in range(1, 157):
    curve.append(curve[-1] - 3 + (250 if step in HITS else 0))

def kv(label, value, colour='var(--fg)'):
    return ('''<div class="rowline" style="padding: 8px 0">
      <span class="grow" style="color: var(--fg2); font-size: 12px">%s</span>
      <span class="mono" style="font-size: 12.5px; font-weight: 500; color: %s">%s</span>
    </div>''' % (label, colour, value))

backtest = backbar('Backtest', ctx('TOP AMBI')) + '''
<div class="scroll">
  <div class="sec" style="padding-bottom: 12px">
    <div class="mono" style="display: flex; gap: 6px; font-size: 10px">
      <span style="border: 1px solid var(--line); border-radius: 3px; padding: 5px 8px">BARI</span>
      <span style="border: 1px solid var(--line); border-radius: 3px; padding: 5px 8px">5 ANNI</span>
      <span style="border: 1px solid var(--line); border-radius: 3px; padding: 5px 8px">3 GIOCATE</span>
      <span style="border: 1px solid var(--line); border-radius: 3px; padding: 5px 8px">08.25 → 08.26</span>
    </div>
  </div>

  <div class="sec">
    <div style="display: flex; align-items: center; gap: 8px">
      ''' + icon('lock', 'var(--fg3)') + '''
      <span class="lbl">Verdetto</span>
    </div>
    <div style="font-size: 14px; font-weight: 500; line-height: 1.4; margin: 8px 0 6px">Nessun vantaggio predittivo dimostrato.</div>
    <div class="note">Nel periodo testato la strategia non ha prodotto una differenza statisticamente significativa rispetto a giocate casuali (p = 0,42).</div>
    <div style="height: 14px"></div>
  </div>

  <div class="sec">
    <div class="lbl">Saldo teorico cumulato</div>
    <div style="margin: 10px 0 6px">''' + equity(curve) + '''</div>
    <div class="mono" style="display: flex; justify-content: space-between; font-size: 9px; color: var(--fg3); padding-bottom: 12px">
      <span>SET 25</span><span>GEN 26</span><span>MAG 26</span><span>AGO 26</span>
    </div>
  </div>

  <div class="sec">
    <div class="lbl" style="margin-bottom: 2px">Risultati teorici</div>
    ''' + kv('Estrazioni simulate', '156') + kv('Giocate', '468') \
        + kv('Ambi centrati', '1') + kv('Costo teorico', '468,00 €') \
        + kv('Vincite teoriche', '250,00 €') \
        + kv('Saldo', '−218,00 €', 'var(--bad)') \
        + kv('ROI teorico', '−46,6 %', 'var(--bad)') + '''
  </div>

  <div class="sec">
    <div class="lbl" style="margin-bottom: 2px">Baseline casuale</div>
    ''' + kv('Ambi centrati', '2') + kv('ROI', '+6,8 %', 'var(--fg2)') + '''
    <div style="height: 10px"></div>
    <div class="warnbox">Il backtest è walk-forward: a ogni passo l'algoritmo vede soltanto le estrazioni precedenti alla data simulata.</div>
    <div style="height: 14px"></div>
  </div>
</div>
''' + nav('flask')

w('Backtest.dc.html', backtest)

# ---------------------------------------------------------------- AI ANALYST
auc_ticks = ''.join(
    '<div style="flex: 1; height: %dpx; background: %s"></div>'
    % (14 if i in (0, 25, 50) else 8, 'var(--fg3)' if i in (0, 25, 50) else 'var(--grid)')
    for i in range(51))

ai = backbar('AI Analyst', ctx('SPERIMENTALE')) + '''
<div class="scroll">
  <div class="sec" style="padding-bottom: 12px">
    <div style="display: flex; gap: 8px; align-items: center">
      ''' + icon('brain', 'var(--fg2)') + '''
      <span class="grow" style="font-weight: 500">Gradient Boosting</span>
      <span class="mono" style="font-size: 10px; color: var(--fg3)">40 ALBERI</span>
    </div>
    <div class="note" style="margin-top: 6px">Alberi additivi della famiglia XGBoost/LightGBM: il modello più capace fra quelli inclusi, ed è proprio per questo che il suo risultato è il confronto più severo con la casualità.</div>
  </div>

  <div class="sec">
    <div class="lbl">Area sotto la curva ROC</div>
    <div style="display: flex; align-items: flex-end; gap: 10px; margin-top: 8px">
      <span class="mono" style="font-size: 44px; font-weight: 500; line-height: 0.9; letter-spacing: -0.02em">0,492</span>
      <span class="mono" style="font-size: 11px; color: var(--fg3); padding-bottom: 5px">0,500 = CASUALE</span>
    </div>
    <div style="display: flex; gap: 1px; align-items: flex-end; margin-top: 12px; height: 14px">''' + auc_ticks + '''</div>
    <div class="mono" style="display: flex; justify-content: space-between; font-size: 9px; color: var(--fg3); margin-top: 4px; padding-bottom: 12px">
      <span>0,00</span><span>0,50</span><span>1,00</span>
    </div>
  </div>

  <div class="sec">
    <div class="lbl" style="margin-bottom: 2px">Metriche sul test</div>
    ''' + kv('Campioni addestramento', '5.355') + kv('Campioni test', '2.295') \
        + kv('Accuratezza', '94,44 %') + kv('Baseline (classe maggioritaria)', '94,44 %') \
        + kv('Log loss', '0,2129') + kv('Log loss baseline', '0,2127') + '''
  </div>

  <div class="sec">
    <div class="lbl" style="margin-bottom: 6px">Verdetto</div>
    <div style="font-size: 14px; font-weight: 500; line-height: 1.4">Nessun vantaggio predittivo dimostrato.</div>
    <div class="note" style="margin-top: 6px">L'AUC è 0,492, praticamente indistinguibile dal valore 0,500 di un classificatore casuale. Lo split fra addestramento e test è temporale.</div>
    <div style="height: 12px"></div>
    <div class="warnbox">Il modulo di machine learning è sperimentale e serve a descrivere e classificare i pattern storici. Non è, e non può essere, uno strumento di previsione di un evento casuale.</div>
    <div style="height: 14px"></div>
  </div>
</div>
''' + nav('flask')

w('AIAnalyst.dc.html', ai)
