# -*- coding: utf-8 -*-
"""Dashboard in tema chiaro e foglio del sistema di progetto."""
import sys, re; sys.path.insert(0, '.')
from _build_common import artboard, chip, icon

# --- La dashboard chiara riusa lo stesso corpo: cambia solo il tema di partenza.
source = open('Main.dc.html', encoding='utf-8').read()
body = source[source.index('<div class="root {{temaClasse}}">'):source.index('</x-dc>')]
body = body.replace('<div class="root {{temaClasse}}">\n', '').rsplit('</div>', 1)[0]
light_props = ('{"tema":{"editor":"enum","options":["scuro","chiaro"],"default":"chiaro"},'
               '"$preview":{"width":390,"height":844}}')
open('DashboardChiaro.dc.html', 'w', encoding='utf-8').write(artboard(body, props=light_props))
print('scritto DashboardChiaro.dc.html')

# ------------------------------------------------------------------ SISTEMA
SHEET_CSS = """
    .root { width: 860px; height: 760px; overflow: hidden; }
    .col { display: flex; flex-direction: column; gap: 26px; }
    .swatch { display: flex; align-items: center; gap: 10px; }
    .swatch .dot { width: 34px; height: 34px; border-radius: 3px; border: 1px solid var(--line); }
"""

def swatch(name, value, token):
    return ('''<div class="swatch">
      <div class="dot" style="background: %s"></div>
      <div>
        <div class="mono" style="font-size: 11px; font-weight: 500">%s</div>
        <div class="mono" style="font-size: 9.5px; color: var(--fg3)">%s · %s</div>
      </div>
    </div>''' % (value, name, token, value))

def typerow(sample, spec, style):
    return ('''<div style="display: flex; align-items: baseline; gap: 16px; padding: 7px 0; border-bottom: 1px solid var(--hair)">
      <div style="width: 250px; %s">%s</div>
      <div class="mono" style="font-size: 9.5px; color: var(--fg3)">%s</div>
    </div>''' % (style, sample, spec))

sheet = '''
<div style="flex: 0 0 auto; padding: 26px 30px 18px; border-bottom: 1px solid var(--line)">
  <div class="mono" style="font-size: 15px; font-weight: 500; letter-spacing: 0.16em; text-transform: uppercase">Sistema di progetto</div>
  <div class="note" style="margin-top: 4px; max-width: 560px">Terminale dati, su caratteri di sistema: SF Mono per i dati, SF Pro per il testo. Superfici piatte e filetti al posto delle card, numeri in monospaziato tabellare, un solo accento di segnale per stato. Il colore porta informazione: non decora.</div>
</div>

<div style="flex: 1 1 auto; display: flex; gap: 30px; padding: 26px 30px; overflow: hidden">

  <div class="col" style="flex: 1">
    <div>
      <div class="lbl" style="margin-bottom: 12px">Palette · scuro</div>
      <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px">
        ''' + swatch('Fondo', '#0E1116', '--bg') + swatch('Pannello', '#12171E', '--panel') \
            + swatch('Filetto', '#232A34', '--line') + swatch('Reticolo', '#1B222B', '--grid') \
            + swatch('Testo', '#E6EDF3', '--fg') + swatch('Secondario', '#8B949E', '--fg2') + '''
      </div>
    </div>

    <div>
      <div class="lbl" style="margin-bottom: 12px">Segnale · l'indice è un colore</div>
      <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px">
        ''' + swatch('Alto 80–100', '#3FB950', '--ok') + swatch('Medio 50–79', '#D8A02A', '--warn') \
            + swatch('Basso 0–49', '#F85149', '--bad') + swatch('Azione', '#58A6FF', '--key') + '''
      </div>
    </div>

    <div>
      <div class="lbl" style="margin-bottom: 10px">Tipografia</div>
      ''' + typerow('86', 'SF Mono 500 · 46/41 · −0.02em', "font-family: var(--mono); font-size: 46px; font-weight: 500; line-height: 0.9; letter-spacing: -0.02em") \
          + typerow('6.897', 'SF Mono 500 · 26/29', "font-family: var(--mono); font-size: 26px; font-weight: 500") \
          + typerow('ARCHIVIO LOCALE', 'SF Mono 500 · 10 · 0.14em', "font-family: var(--mono); font-size: 10px; font-weight: 500; letter-spacing: 0.14em; color: var(--fg3)") \
          + typerow('Frequenze e ritardi', 'SF Pro Text 500 · 13/19', "font-size: 13px; font-weight: 500") \
          + typerow('Descrive il passato, non il futuro.', 'SF Pro Text 400 · 11/16.5 · fg2', "font-size: 11px; color: var(--fg2)") + '''
    </div>
  </div>

  <div class="col" style="flex: 1">
    <div>
      <div class="lbl" style="margin-bottom: 12px">Numeri · quadrati, non palline</div>
      <div style="display: flex; gap: 8px; align-items: center">
        ''' + chip(17, 91) + chip(43, 64) + chip(12, 31) + chip(28) + '''
      </div>
      <div class="note" style="margin-top: 8px">Il bordo e il colore dicono la fascia dell'indice. La forma quadrata allontana deliberatamente l'app dall'immaginario della tombola.</div>
    </div>

    <div>
      <div class="lbl" style="margin-bottom: 12px">Riga dati</div>
      <div style="border-top: 1px solid var(--hair)">
        <div class="rowline">
          <span class="mono" style="font-size: 10px; color: var(--fg3); width: 18px">01</span>
          <span style="display: flex; opacity: 0.75">''' + icon('link', 'var(--fg2)') + '''</span>
          <span class="grow" style="font-weight: 500">Ambi</span>
          <span class="mono" style="font-size: 10.5px; color: var(--fg2)">4.005 coppie</span>
          <span style="display: flex; opacity: 0.5">''' + icon('arrow', 'var(--fg3)') + '''</span>
        </div>
        <div class="rowline">
          <span class="grow" style="color: var(--fg2); font-size: 12px">ROI teorico</span>
          <span class="mono" style="font-size: 12.5px; font-weight: 500; color: var(--ok)">+113,7 %</span>
        </div>
      </div>
      <div class="note" style="margin-top: 8px">Un filetto separa, nessuna card racchiude. L'altezza minima toccabile resta 44px.</div>
    </div>

    <div>
      <div class="lbl" style="margin-bottom: 12px">Controlli</div>
      <div style="display: flex; gap: 10px">
        <div class="btn key" style="flex: 1">Genera</div>
        <div class="btn" style="flex: 1">Esporta</div>
      </div>
      <div style="height: 10px"></div>
      <div style="display: flex; border: 1px solid var(--line); border-radius: 3px; overflow: hidden">
        <div class="mono" style="flex: 1; text-align: center; padding: 9px 0; font-size: 11px; letter-spacing: 0.1em; background: var(--panel); border-right: 1px solid var(--line)">LOTTO</div>
        <div class="mono" style="flex: 1; text-align: center; padding: 9px 0; font-size: 11px; letter-spacing: 0.1em; color: var(--fg3)">SUPERENALOTTO</div>
      </div>
    </div>

    <div>
      <div class="lbl" style="margin-bottom: 10px">Grafici</div>
      <svg width="100%" height="52" viewBox="0 0 360 52" preserveAspectRatio="none">
        ''' + ''.join('<rect x="%.2f" y="%.2f" width="2.4" height="%.2f" fill="%s"/>'
                      % (i * 4.0, 52 - (10 + (i * 37 % 31)), (10 + (i * 37 % 31)),
                         '#3FB950' if (i * 37 % 31) > 26 else ('#F85149' if (i * 37 % 31) < 4 else '#59626D'))
                      for i in range(90)) + '''
        <line x1="0" x2="360" y1="24" y2="24" stroke="#59626D" stroke-width="1" stroke-dasharray="3 3"/>
      </svg>
      <div class="note" style="margin-top: 8px">Barre a piena larghezza, tratteggio per il valore atteso dal caso: il confronto con la casualità è sempre visibile, non nascosto in una nota.</div>
    </div>

    <div>
      <div class="lbl" style="margin-bottom: 8px">Avvertenza</div>
      <div class="warnbox">Le estrazioni sono casuali. Le analisi statistiche degli estratti passati non modificano la probabilità matematica di vincita.</div>
      <div class="note" style="margin-top: 8px">Filetto a sinistra e testo secondario: presente su ogni schermata, mai un riquadro d'allarme colorato.</div>
    </div>
  </div>
</div>
'''

open('Sistema.dc.html', 'w', encoding='utf-8').write(
    artboard(sheet,
             props='{"tema":{"editor":"enum","options":["scuro","chiaro"],"default":"scuro"},"$preview":{"width":860,"height":760}}',
             extra_css=SHEET_CSS))
print('scritto Sistema.dc.html')
