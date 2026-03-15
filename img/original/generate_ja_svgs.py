#!/usr/bin/env python3
"""Generate all Tera Term dialog SVGs with Japanese labels."""

import os

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

COMMON_STYLE = """    <style>
      .title-bar { fill: #0078d4; }
      .title-text { fill: white; font-size: 11px; font-weight: bold; }
      .dialog-bg { fill: #f0f0f0; stroke: #999; stroke-width: 1; }
      .group-box { fill: none; stroke: #999; stroke-width: 1; }
      .label { fill: #000; font-size: 11px; }
      .edit-box { fill: #fff; stroke: #7a7a7a; stroke-width: 1; }
      .combo-box { fill: #fff; stroke: #7a7a7a; stroke-width: 1; }
      .button { fill: #e1e1e1; stroke: #adadad; stroke-width: 1; }
      .button-default { fill: #0078d4; stroke: #005a9e; stroke-width: 1; }
      .button-text { fill: #000; font-size: 11px; text-anchor: middle; }
      .button-text-default { fill: #fff; font-size: 11px; text-anchor: middle; }
      .checkbox { fill: #fff; stroke: #7a7a7a; stroke-width: 1; }
      .radio { fill: #fff; stroke: #7a7a7a; stroke-width: 1; }
      .combo-arrow { fill: #606060; }
      .text-area { fill: #fff; stroke: #7a7a7a; stroke-width: 1; }
      .scrollbar { fill: #c0c0c0; stroke: #999; stroke-width: 1; }
      .sample-box { fill: #000; stroke: #333; stroke-width: 2; }
      .link { fill: #0066cc; font-size: 11px; text-decoration: underline; }
      .tab-active { fill: #f0f0f0; stroke: #999; stroke-width: 1; }
      .tab-inactive { fill: #d0d0d0; stroke: #999; stroke-width: 1; }
      .tab-text { fill: #000; font-size: 10px; text-anchor: middle; }
      .listbox { fill: #fff; stroke: #7a7a7a; stroke-width: 1; }
      .progress-bar { fill: #0078d4; }
      .progress-bg { fill: #e0e0e0; stroke: #999; stroke-width: 1; }
    </style>"""

def svg_header(w, h, font="MS UI Gothic, Meiryo, sans-serif"):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" font-family="{font}" font-size="11">'

def svg_defs():
    return f"  <defs>\n{COMMON_STYLE}\n  </defs>"

def title_bar(w, title):
    return f"""  <!-- Title bar -->
  <rect class="title-bar" x="0" y="0" width="{w}" height="22" rx="4"/>
  <text class="title-text" x="8" y="15">{title}</text>"""

def dialog_bg(w, h):
    return f'  <rect class="dialog-bg" x="0" y="22" width="{w}" height="{h-22}"/>'

def group_box(x, y, w, h, label):
    return f"""  <rect class="group-box" x="{x}" y="{y}" width="{w}" height="{h}"/>
  <text class="label" x="{x+8}" y="{y}" font-weight="bold">{label}</text>"""

def edit_box(x, y, w, h=20, text=""):
    s = f'  <rect class="edit-box" x="{x}" y="{y}" width="{w}" height="{h}"/>'
    if text:
        s += f'\n  <text class="label" x="{x+6}" y="{y+14}">{text}</text>'
    return s

def combo_box(x, y, w, h=20, text=""):
    ax = x + w - 20
    return f"""  <rect class="combo-box" x="{x}" y="{y}" width="{w}" height="{h}"/>
  <rect fill="#e1e1e1" x="{ax}" y="{y}" width="20" height="{h}" stroke="#7a7a7a" stroke-width="1"/>
  <polygon class="combo-arrow" points="{ax+5},{y+8} {ax+15},{y+8} {ax+10},{y+15}"/>""" + (f'\n  <text class="label" x="{x+6}" y="{y+14}">{text}</text>' if text else "")

def label(x, y, text, **kwargs):
    extra = ""
    for k, v in kwargs.items():
        extra += f' {k.replace("_","-")}="{v}"'
    return f'  <text class="label" x="{x}" y="{y}"{extra}>{text}</text>'

def checkbox(x, y, text, checked=False):
    s = f'  <rect class="checkbox" x="{x}" y="{y}" width="13" height="13"/>'
    if checked:
        s += f'\n  <polyline fill="none" stroke="#000" stroke-width="2" points="{x+2},{y+7} {x+5},{y+11} {x+11},{y+2}"/>'
    s += f'\n  <text class="label" x="{x+18}" y="{y+11}">{text}</text>'
    return s

def radio(cx, cy, text, selected=False):
    s = f'  <circle class="radio" cx="{cx}" cy="{cy}" r="6"/>'
    if selected:
        s += f'\n  <circle fill="#000" cx="{cx}" cy="{cy}" r="3"/>'
    s += f'\n  <text class="label" x="{cx+12}" y="{cy+4}">{text}</text>'
    return s

def button(x, y, w, h, text, default=False):
    cls = "button-default" if default else "button"
    tcls = "button-text-default" if default else "button-text"
    return f"""  <rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="3"/>
  <text class="{tcls}" x="{x+w//2}" y="{y+16}">{text}</text>"""

def ok_cancel_help(x, y, w=72):
    return "\n".join([
        button(x, y, 64, 24, "OK", True),
        button(x+76, y, 80, 24, "キャンセル"),
        button(x+168, y, 72, 24, "ヘルプ(&H)"),
    ])

def ok_cancel_help_vert(x, y):
    return "\n".join([
        button(x, y, 72, 24, "OK", True),
        button(x, y+30, 72, 24, "キャンセル"),
        button(x, y+60, 72, 24, "ヘルプ(&H)"),
    ])


def write_svg(name, content):
    path = os.path.join(OUTPUT_DIR, name)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  Written: {name}")


# =========================================================================
# IDD_TERMDLG - Terminal setup dialog
# =========================================================================
def gen_termdlg():
    return "\n".join([
        svg_header(520, 340),
        svg_defs(),
        title_bar(520, "Tera Term: 端末の設定"),
        dialog_bg(520, 340),
        group_box(16, 36, 194, 108, "端末サイズ"),
        edit_box(42, 52, 44, 20, "80"),
        label(96, 66, "X"),
        edit_box(130, 52, 44, 20, "24"),
        checkbox(26, 80, "端末サイズ = ウィンドウサイズ"),
        checkbox(26, 100, "自動的にウィンドウサイズを調整"),
        group_box(224, 36, 170, 88, "改行コード"),
        label(232, 60, "受信:"),
        combo_box(300, 48, 84, 20, "CR"),
        label(232, 84, "送信:"),
        combo_box(300, 72, 84, 20, "CR"),
        label(18, 150, "端末ID:"),
        combo_box(110, 138, 100, 20, "VT220"),
        checkbox(246, 140, "ローカルエコー"),
        label(18, 174, "応答:"),
        edit_box(110, 162, 122),
        checkbox(246, 164, "自動切り替え(VT&lt;-&gt;TEK)"),
        group_box(16, 190, 194, 68, "エンコーディング-受信"),
        combo_box(26, 210, 174, 20, "UTF-8"),
        checkbox(26, 236, "半角カナ"),
        group_box(224, 190, 170, 68, "エンコーディング-送信"),
        combo_box(234, 210, 150, 20, "UTF-8"),
        checkbox(234, 236, "半角カナ"),
        label(18, 276, "漢字イン:"),
        combo_box(110, 264, 100, 20, "@"),
        label(224, 276, "漢字アウト:"),
        combo_box(316, 264, 100, 20, "B"),
        ok_cancel_help(140, 298),
        "</svg>"
    ])


# =========================================================================
# IDD_WINDLG - Window setup dialog
# =========================================================================
def gen_windlg():
    return "\n".join([
        svg_header(490, 520),
        svg_defs(),
        title_bar(490, "Tera Term: ウィンドウの設定"),
        dialog_bg(490, 520),
        label(56, 46, "タイトル:", text_anchor="end"),
        edit_box(102, 34, 278, 20, "Tera Term"),
        group_box(20, 60, 152, 120, "カーソルの形"),
        radio(38, 88, "四角", True),
        radio(38, 108, "垂直線"),
        radio(38, 128, "下線"),
        checkbox(196, 64, "タイトルバーを隠す"),
        checkbox(196, 84, "ウインドウ枠を隠す"),
        checkbox(196, 104, "メニューバーを隠す"),
        checkbox(196, 124, "16色モード(PC形式)"),
        checkbox(196, 144, "16色モード(aixterm形式)"),
        checkbox(196, 164, "256色モード(xterm形式)"),
        group_box(20, 190, 450, 246, "カラー"),
        radio(38, 224, "文字", True),
        radio(38, 246, "背景"),
        button(158, 228, 100, 24, "色入れ替え"),
        label(36, 278, "赤:"),
        label(84, 278, "255"),
        f'  <rect class="scrollbar" x="118" y="270" width="200" height="16" rx="2"/>',
        f'  <rect fill="#0078d4" x="308" y="270" width="10" height="16" rx="2"/>',
        label(36, 302, "緑:"),
        label(84, 302, "255"),
        f'  <rect class="scrollbar" x="118" y="294" width="200" height="16" rx="2"/>',
        f'  <rect fill="#0078d4" x="308" y="294" width="10" height="16" rx="2"/>',
        label(36, 326, "青:"),
        label(84, 326, "255"),
        f'  <rect class="scrollbar" x="118" y="318" width="200" height="16" rx="2"/>',
        f'  <rect fill="#0078d4" x="308" y="318" width="10" height="16" rx="2"/>',
        f'  <rect class="sample-box" x="330" y="212" width="114" height="126"/>',
        f'  <text fill="#fff" x="360" y="280" font-size="12">サンプル</text>',
        label(36, 356, "属性:"),
        radio(100, 356, "標準", True),
        radio(160, 356, "太字"),
        radio(210, 356, "点滅"),
        radio(260, 356, "反転"),
        radio(310, 356, "URL"),
        radio(350, 356, "下線"),
        checkbox(36, 380, "常に標準の背景色を使う"),
        label(20, 410, "スクロールバッファ:"),
        edit_box(150, 398, 60, 20, "10000"),
        label(216, 410, "行"),
        ok_cancel_help(130, 476),
        "</svg>"
    ])


# =========================================================================
# IDD_HOSTDLG - New Connection dialog
# =========================================================================
def gen_hostdlg():
    return "\n".join([
        svg_header(490, 230),
        svg_defs(),
        title_bar(490, "Tera Term: 新しい接続"),
        dialog_bg(490, 230),
        f'  <rect class="group-box" x="8" y="30" width="466" height="100"/>',
        radio(20, 48, "TCP/IP", True),
        label(124, 48, "ホスト:", text_anchor="end"),
        combo_box(190, 36, 276, 20),
        label(180, 70, "TCPポート#:", text_anchor="end"),
        edit_box(190, 58, 60, 18, "23"),
        label(276, 70, "IPバージョン:", text_anchor="end"),
        combo_box(280, 58, 88, 18, "AUTO"),
        checkbox(190, 82, "Telnet"),
        f'  <rect class="group-box" x="8" y="134" width="466" height="48"/>',
        radio(20, 160, "シリアル"),
        label(180, 164, "ポート:", text_anchor="end"),
        combo_box(190, 152, 276, 20),
        ok_cancel_help(130, 194),
        "</svg>"
    ])


# =========================================================================
# IDD_KEYBDLG - Keyboard setup dialog
# =========================================================================
def gen_keybdlg():
    return "\n".join([
        svg_header(320, 270),
        svg_defs(),
        title_bar(320, "Tera Term: キーボードの設定"),
        dialog_bg(320, 270),
        group_box(20, 32, 180, 78, "DELを送信するキー:"),
        checkbox(40, 48, "Backspace キー"),
        checkbox(40, 70, "Delete キー"),
        label(24, 124, "キーボード:"),
        combo_box(124, 112, 88, 20),
        label(24, 148, "Meta キー:"),
        combo_box(124, 136, 88, 20, "off"),
        group_box(20, 164, 260, 58, "無効化するモード"),
        checkbox(40, 180, "アプリケーションキーパッド"),
        checkbox(40, 200, "アプリケーションカーソル"),
        ok_cancel_help_vert(224, 36),
        "</svg>"
    ])


# =========================================================================
# IDD_SERIALDLG - Serial port setup dialog
# =========================================================================
def gen_serialdlg():
    return "\n".join([
        svg_header(560, 560),
        svg_defs(),
        title_bar(560, "Tera Term: シリアルポートの設定と接続"),
        dialog_bg(560, 560),
        label(30, 42, "ポート:"),
        combo_box(150, 30, 124, 20),
        label(30, 66, "スピード:"),
        combo_box(150, 54, 124, 20, "9600"),
        label(30, 90, "データ:"),
        combo_box(150, 78, 124, 20, "8 bit"),
        label(30, 114, "パリティ:"),
        combo_box(150, 102, 124, 20, "none"),
        label(30, 138, "ストップビット:"),
        combo_box(150, 126, 124, 20, "1 bit"),
        label(30, 162, "フロー制御:"),
        combo_box(150, 150, 124, 20, "none"),
        checkbox(30, 180, "CTS"),
        checkbox(92, 180, "RTS"),
        combo_box(150, 178, 124, 20),
        checkbox(30, 202, "DSR"),
        checkbox(92, 202, "DTR"),
        combo_box(150, 200, 124, 20),
        checkbox(30, 224, "RING"),
        checkbox(92, 224, "RLSD"),
        group_box(24, 248, 304, 64, "送信遅延"),
        edit_box(44, 268, 40, 20, "0"),
        label(92, 282, "ミリ秒/字"),
        edit_box(186, 268, 40, 20, "0"),
        label(232, 282, "ミリ秒/行"),
        f'  <rect class="text-area" x="20" y="320" width="516" height="144"/>',
        ok_cancel_help_vert(310, 30),
        "</svg>"
    ])


# =========================================================================
# IDD_TCPIPDLG - TCP/IP setup dialog
# =========================================================================
def gen_tcpipdlg():
    return "\n".join([
        svg_header(520, 400),
        svg_defs(),
        title_bar(520, "Tera Term: TCP/IPの設定"),
        dialog_bg(520, 400),
        checkbox(24, 42, "新規接続時にホストリストに追加"),
        button(24, 64, 160, 24, "ホストリストの編集"),
        checkbox(24, 104, "Telnet"),
        label(24, 142, "ポート#:"),
        edit_box(46, 152, 60, 20, "23"),
        label(24, 194, "Telnet Keep-alive"),
        edit_box(46, 204, 50, 20, "300"),
        label(102, 218, "秒(0指定で無効)"),
        checkbox(24, 240, "自動的にウィンドウを閉じる"),
        label(24, 278, "端末タイプ:"),
        edit_box(46, 288, 110, 20, "xterm"),
        ok_cancel_help(130, 360),
        "</svg>"
    ])


# =========================================================================
# IDD_GENDLG - General setup dialog
# =========================================================================
def gen_gendlg():
    return "\n".join([
        svg_header(420, 290),
        svg_defs(),
        title_bar(420, "Tera Term: 全般設定"),
        dialog_bg(420, 290),
        label(16, 42, "新しい接続のデフォルト:"),
        radio(30, 58, "TCP/IP", True),
        radio(120, 58, "シリアル"),
        label(16, 84, "UI言語:"),
        combo_box(34, 92, 254, 20, "Japanese"),
        edit_box(36, 122, 362, 116),
        f'  <text class="label" fill="#888" x="44" y="140">言語情報</text>',
        ok_cancel_help(90, 254),
        "</svg>"
    ])


# =========================================================================
# IDD_ABOUTDLG - About dialog
# =========================================================================
def gen_aboutdlg():
    return "\n".join([
        svg_header(460, 340),
        svg_defs(),
        title_bar(460, "Tera Term について"),
        dialog_bg(460, 340),
        f'  <rect fill="#ddd" stroke="#999" x="12" y="38" width="40" height="40" rx="4"/>',
        f'  <text class="label" x="22" y="62" fill="#666">TT</text>',
        label(76, 42, "Tera Term", font_weight="bold", font_size="13"),
        label(76, 58, "Version 5.x"),
        label(86, 72, "(C) 2004-2026 TeraTerm Project"),
        label(76, 96, "含む:"),
        label(76, 112, "Tera Term Pro version 2.3"),
        label(86, 126, "Copyright (C) 1994-1998 T. Teranishi"),
        label(76, 146, "IPv6 extention version 0.81"),
        label(86, 160, "(C) 2000-2003 Jun-ya KATO"),
        label(76, 180, "Oniguruma: x.x.x"),
        label(76, 196, "SFMT: x.x"),
        label(14, 220, "ビルド情報:"),
        f'  <text class="label" fill="#666" x="14" y="236">コンパイラ / プラットフォーム 情報</text>',
        label(14, 296, "作者:"),
        f'  <text class="link" x="72" y="296">https://teratermproject.github.io/</text>',
        button(380, 32, 64, 24, "OK", True),
        "</svg>"
    ])


# =========================================================================
# IDD_DIRDLG - Change directory dialog
# =========================================================================
def gen_dirdlg():
    return "\n".join([
        svg_header(400, 120),
        svg_defs(),
        title_bar(400, "Tera Term: ディレクトリの変更"),
        dialog_bg(400, 120),
        label(16, 46, "新しいディレクトリを選択してください"),
        edit_box(16, 56, 280, 20),
        button(310, 54, 72, 24, "参照..."),
        button(100, 88, 64, 24, "OK", True),
        button(176, 88, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_WINLISTDLG - Window list dialog
# =========================================================================
def gen_winlistdlg():
    return "\n".join([
        svg_header(370, 280),
        svg_defs(),
        title_bar(370, "Tera Term: ウィンドウのリスト"),
        dialog_bg(370, 280),
        label(16, 42, "ウィンドウ:"),
        f'  <rect class="listbox" x="16" y="50" width="240" height="180"/>',
        f'  <text class="label" x="24" y="68">Tera Term - localhost</text>',
        button(270, 50, 82, 24, "開く"),
        button(270, 82, 82, 24, "閉じる"),
        button(270, 114, 82, 24, "ヘルプ(&H)"),
        button(270, 240, 82, 24, "閉じる"),
        "</svg>"
    ])


# =========================================================================
# IDD_BROADCAST_DIALOG - Broadcast dialog
# =========================================================================
def gen_broadcastdlg():
    return "\n".join([
        svg_header(520, 400),
        svg_defs(),
        title_bar(520, "Tera Term: コマンドのブロードキャスト"),
        dialog_bg(520, 400),
        f'  <rect class="edit-box" x="16" y="32" width="486" height="60"/>',
        checkbox(16, 100, "リアルタイム"),
        label(16, 130, "ヒストリ"),
        combo_box(80, 118, 254, 20),
        f'  <rect class="listbox" x="16" y="150" width="486" height="170"/>',
        checkbox(16, 330, "このプロセスのみに送信"),
        checkbox(200, 330, "Enterキー"),
        button(16, 358, 80, 24, "送信"),
        button(110, 358, 80, 24, "閉じる"),
        button(204, 358, 80, 24, "ヘルプ(&H)"),
        "</svg>"
    ])


# =========================================================================
# IDD_CLIPBOARD_DIALOG - Clipboard confirmation dialog
# =========================================================================
def gen_clipboarddlg():
    return "\n".join([
        svg_header(500, 300),
        svg_defs(),
        title_bar(500, "Tera Term: クリップボードの確認"),
        dialog_bg(500, 300),
        f'  <rect class="text-area" x="16" y="32" width="466" height="200"/>',
        f'  <text class="label" x="24" y="50">クリップボードの内容がここに表示されます</text>',
        button(110, 254, 80, 24, "OK", True),
        button(204, 254, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_CTRLWIN - Macro control window
# =========================================================================
def gen_ctrlwin():
    return "\n".join([
        svg_header(280, 120),
        svg_defs(),
        title_bar(280, "MACRO"),
        dialog_bg(280, 120),
        label(16, 42, "マクロ実行中..."),
        f'  <rect class="progress-bg" x="16" y="50" width="246" height="12"/>',
        f'  <rect class="progress-bar" x="16" y="50" width="120" height="12"/>',
        button(16, 74, 72, 24, "中断(&P)"),
        button(100, 74, 72, 24, "終了(&E)"),
        "</svg>"
    ])


# =========================================================================
# IDD_DAD_DIALOG - Drag and Drop dialog
# =========================================================================
def gen_daddlg():
    return "\n".join([
        svg_header(480, 360),
        svg_defs(),
        title_bar(480, "Tera Term: ファイル ドラッグ&amp;ドロップ"),
        dialog_bg(480, 360),
        label(16, 42, "ファイル転送を行いますか？"),
        radio(30, 62, "SCP", True),
        radio(30, 82, "ファイル送信（ファイルの内容を貼り付け）"),
        radio(30, 102, "ファイル名を貼り付け"),
        label(30, 130, "送信先:"),
        edit_box(100, 118, 300, 20),
        label(30, 150, "空のときはホームディレクトリに送信されます", font_size="9"),
        checkbox(30, 168, "バイナリ"),
        checkbox(30, 188, "エスケープ"),
        radio(50, 210, "スペースで区切る"),
        radio(50, 230, "改行で区切る"),
        checkbox(30, 256, "同じ処理を次のファイルに適用"),
        checkbox(30, 276, "次のドロップ時、同じ処理を行う"),
        checkbox(30, 296, "次のドロップ時、ダイアログを表示しない"),
        label(16, 322, "このダイアログは、CTRLを押しながらドロップすると必ず表示されます", font_size="9"),
        button(120, 336, 64, 24, "OK", True),
        button(196, 336, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_EDITHISTORYDLG - Edit history dialog
# =========================================================================
def gen_edithistorydlg():
    return "\n".join([
        svg_header(380, 300),
        svg_defs(),
        title_bar(380, "Tera Term: ホストリストの編集"),
        dialog_bg(380, 300),
        f'  <rect class="listbox" x="16" y="32" width="254" height="220"/>',
        button(280, 32, 82, 24, "追加"),
        button(280, 64, 82, 24, "上へ"),
        button(280, 96, 82, 24, "削除"),
        button(280, 128, 82, 24, "下へ"),
        button(100, 264, 64, 24, "OK", True),
        button(176, 264, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_ERRDLG - Macro error dialog
# =========================================================================
def gen_errdlg():
    return "\n".join([
        svg_header(340, 140),
        svg_defs(),
        title_bar(340, "MACRO: エラー"),
        dialog_bg(340, 140),
        f'  <rect class="edit-box" x="16" y="32" width="306" height="60"/>',
        f'  <text class="label" x="24" y="50">エラーメッセージ</text>',
        button(130, 104, 80, 24, "OK", True),
        "</svg>"
    ])


# =========================================================================
# IDD_FILETRANSDLG - File transfer dialog
# =========================================================================
def gen_filetransdlg():
    return "\n".join([
        svg_header(380, 200),
        svg_defs(),
        title_bar(380, "ファイル送信"),
        dialog_bg(380, 200),
        label(16, 42, "ファイル名:"),
        label(100, 42, "example.txt"),
        label(16, 62, "フルパス:"),
        label(100, 62, "C:\\Users\\..."),
        label(16, 82, "転送済容量:"),
        label(100, 82, "0 bytes"),
        label(16, 102, "経過時間:"),
        label(100, 102, "00:00:00"),
        f'  <rect class="progress-bg" x="16" y="112" width="346" height="16"/>',
        f'  <rect class="progress-bar" x="16" y="112" width="0" height="16"/>',
        button(60, 150, 80, 24, "一時停止(&S)"),
        button(160, 150, 80, 24, "閉じる"),
        button(260, 150, 80, 24, "ヘルプ(&H)"),
        "</svg>"
    ])


# =========================================================================
# IDD_GETFNDLG - Kermit Get filename dialog
# =========================================================================
def gen_getfndlg():
    return "\n".join([
        svg_header(340, 120),
        svg_defs(),
        title_bar(340, "Tera Term: Kermit 取得"),
        dialog_bg(340, 120),
        label(16, 46, "ファイル名:"),
        edit_box(90, 34, 230, 20),
        button(80, 72, 64, 24, "OK", True),
        button(156, 72, 80, 24, "キャンセル"),
        button(248, 72, 72, 24, "ヘルプ(&H)"),
        "</svg>"
    ])


# =========================================================================
# IDD_INPDLG - Macro input dialog
# =========================================================================
def gen_inpdlg():
    return "\n".join([
        svg_header(360, 140),
        svg_defs(),
        title_bar(360, "MACRO: 入力"),
        dialog_bg(360, 140),
        label(16, 42, "入力してください:"),
        edit_box(16, 52, 326, 20),
        button(90, 90, 64, 24, "OK", True),
        button(166, 90, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_LISTDLG - Macro list dialog
# =========================================================================
def gen_listdlg():
    return "\n".join([
        svg_header(300, 260),
        svg_defs(),
        title_bar(300, "MACRO: リスト選択"),
        dialog_bg(300, 260),
        label(16, 42, "選択してください:"),
        f'  <rect class="listbox" x="16" y="50" width="266" height="150"/>',
        button(60, 216, 64, 24, "OK", True),
        button(136, 216, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_LOGDLG - Log dialog
# =========================================================================
def gen_logdlg():
    return "\n".join([
        svg_header(520, 340),
        svg_defs(),
        title_bar(520, "Tera Term: ログ"),
        dialog_bg(520, 340),
        label(16, 42, "ログファイル名(dialogにファイルをドロップ):"),
        edit_box(16, 52, 380, 20),
        button(404, 50, 72, 24, "参照..."),
        group_box(16, 84, 200, 52, "書き込みモード"),
        radio(30, 102, "新規/上書き", True),
        radio(120, 102, "追記"),
        group_box(230, 84, 200, 52, "テキスト/バイナリモード"),
        radio(244, 102, "テキスト", True),
        radio(330, 102, "バイナリ"),
        checkbox(16, 148, "BOM"),
        checkbox(16, 168, "プレーンテキスト"),
        checkbox(120, 168, "タイムスタンプ"),
        checkbox(16, 188, "ダイアログを非表示"),
        checkbox(16, 208, "現在バッファを含む"),
        group_box(16, 230, 480, 52, "タイムスタンプ形式"),
        radio(30, 248, "ローカルタイム", True),
        radio(140, 248, "UTC"),
        radio(200, 248, "経過時間(Logging)"),
        radio(350, 248, "経過時間(Connection)"),
        button(120, 298, 64, 24, "OK", True),
        button(196, 298, 80, 24, "キャンセル"),
        button(288, 298, 72, 24, "ヘルプ(&H)"),
        "</svg>"
    ])


# =========================================================================
# IDD_MSGDLG - Macro message dialog
# =========================================================================
def gen_msgdlg():
    return "\n".join([
        svg_header(340, 120),
        svg_defs(),
        title_bar(340, "MACRO: メッセージ"),
        dialog_bg(340, 120),
        f'  <rect class="edit-box" x="16" y="32" width="306" height="46"/>',
        f'  <text class="label" x="24" y="50">メッセージ内容</text>',
        button(130, 90, 80, 24, "OK", True),
        "</svg>"
    ])


# =========================================================================
# IDD_PRNABORTDLG - Print abort dialog
# =========================================================================
def gen_prnabortdlg():
    return "\n".join([
        svg_header(240, 100),
        svg_defs(),
        title_bar(240, "Tera Term"),
        dialog_bg(240, 100),
        label(80, 52, "印刷中"),
        button(80, 66, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_PROTDLG - Protocol transfer dialog
# =========================================================================
def gen_protdlg():
    return "\n".join([
        svg_header(360, 200),
        svg_defs(),
        title_bar(360, "Tera Term: ファイル転送"),
        dialog_bg(360, 200),
        label(16, 42, "ファイル名:"),
        label(100, 42, ""),
        label(16, 62, "プロトコル:"),
        label(100, 62, ""),
        label(16, 82, "パケット#:"),
        label(100, 82, "0"),
        label(16, 102, "転送済容量:"),
        label(100, 102, "0"),
        label(16, 122, "経過時間:"),
        label(100, 122, "00:00:00"),
        f'  <rect class="progress-bg" x="16" y="136" width="326" height="16"/>',
        button(140, 164, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_RECVFILEDLG - Receive file dialog
# =========================================================================
def gen_recvfiledlg():
    return "\n".join([
        svg_header(440, 160),
        svg_defs(),
        title_bar(440, "Tera Term: ファイル受信"),
        dialog_bg(440, 160),
        label(16, 42, "受信ファイル名(dialogにファイルをドロップ):"),
        edit_box(16, 52, 320, 20),
        button(344, 50, 72, 24, "参照..."),
        checkbox(16, 82, "バイナリ"),
        label(16, 106, "ファイル受信自動停止待ち時間(秒):"),
        edit_box(260, 94, 50, 20, "0"),
        button(100, 126, 64, 24, "OK", True),
        button(176, 126, 80, 24, "キャンセル"),
        button(268, 126, 72, 24, "ヘルプ(&H)"),
        "</svg>"
    ])


# =========================================================================
# IDD_SENDFILEDLG - Send file dialog
# =========================================================================
def gen_sendfiledlg():
    return "\n".join([
        svg_header(480, 200),
        svg_defs(),
        title_bar(480, "Tera Term: ファイル送信"),
        dialog_bg(480, 200),
        label(16, 42, "送信するファイルを選択:"),
        edit_box(16, 52, 360, 20),
        button(384, 50, 72, 24, "参照..."),
        group_box(16, 82, 200, 52, "ファイルの読み込み方法"),
        radio(30, 100, "バルク(一括)読み込み", True),
        radio(30, 118, "シーケンシャル(逐次)読み込み"),
        checkbox(230, 90, "バイナリ"),
        button(120, 158, 64, 24, "OK", True),
        button(196, 158, 80, 24, "キャンセル"),
        button(288, 158, 72, 24, "ヘルプ(&H)"),
        "</svg>"
    ])


# =========================================================================
# IDD_STATDLG - Macro status dialog
# =========================================================================
def gen_statdlg():
    return "\n".join([
        svg_header(300, 80),
        svg_defs(),
        title_bar(300, "MACRO"),
        dialog_bg(300, 80),
        label(16, 46, "マクロ処理中..."),
        f'  <rect class="progress-bg" x="16" y="54" width="266" height="12"/>',
        f'  <rect class="progress-bar" x="16" y="54" width="80" height="12"/>',
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_GENERAL - Additional Settings: General tab
# =========================================================================
def gen_tabsheet_general():
    return "\n".join([
        svg_header(500, 440),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - 全般"),
        dialog_bg(500, 440),
        checkbox(16, 36, "クリッカブルURLを有効にする"),
        checkbox(16, 56, "ブレーク送信のアクセラレータキーを無効にする"),
        checkbox(16, 76, "ブロードキャストを受け入れる"),
        label(16, 100, "ホイールのスクロール行数:"),
        edit_box(200, 88, 40, 20, "3"),
        checkbox(16, 116, "最下行でだけ自動スクロールする"),
        checkbox(16, 136, "ウィンドウサイズ変更時に表示内容をクリアする"),
        checkbox(16, 156, "IMEの状態によってカーソル形状を変更する"),
        checkbox(16, 176, "OSで非表示のフォントもフォントダイアログの一覧に表示する"),
        group_box(16, 196, 466, 110, "タイトル形式"),
        checkbox(30, 214, "ホスト/ポート名を表示する"),
        checkbox(30, 234, "セッション番号を表示する"),
        checkbox(30, 254, "VT/TEK を表示する"),
        checkbox(250, 214, "タイトルとホスト名の場所を入れ換える"),
        checkbox(250, 234, "TCP ポート番号を表示する"),
        checkbox(250, 254, "シリアルポートのスピードを表示する"),
        group_box(16, 316, 466, 70, "通知"),
        label(30, 336, "通知音:"),
        combo_box(100, 324, 120, 20),
        button(240, 324, 100, 24, "Notify テスト"),
        button(350, 324, 100, 24, "Tray テスト"),
        button(130, 402, 64, 24, "OK", True),
        button(206, 402, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_SEQUENCE - Additional Settings: Sequence tab
# =========================================================================
def gen_tabsheet_sequence():
    return "\n".join([
        svg_header(500, 420),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - 制御シーケンス"),
        dialog_bg(500, 420),
        checkbox(16, 36, "マウスイベント通知要求を受け入れる"),
        checkbox(16, 56, "Controlキーを押している間はマウスイベントを通知しない"),
        label(16, 80, "ウィンドウタイトルの変更要求を受け入れる:"),
        combo_box(300, 68, 120, 20, "上書き"),
        label(16, 106, "カーソル形状/点滅変更制御シーケンス:"),
        combo_box(300, 94, 120, 20),
        label(16, 130, "ウィンドウ操作制御シーケンス:"),
        combo_box(300, 118, 120, 20),
        label(16, 154, "ウィンドウ情報報告シーケンス:"),
        combo_box(300, 142, 120, 20),
        label(16, 180, "ウィンドウタイトルの報告要求:"),
        radio(300, 172, "無視"),
        radio(360, 172, "応答"),
        radio(420, 172, "空白"),
        label(16, 204, "リモートからのクリップボードアクセス:"),
        combo_box(300, 192, 120, 20, "無効"),
        checkbox(16, 220, "リモートからのクリップボードアクセスを通知する"),
        checkbox(16, 240, "リモートからのスクロールバッファの消去を受け入れる"),
        checkbox(16, 260, "印字開始シーケンスを無効化"),
        label(16, 284, "ベル:"),
        radio(60, 278, "無視"),
        radio(130, 278, "サウンド"),
        radio(210, 278, "ビジュアルベル"),
        button(130, 380, 64, 24, "OK", True),
        button(206, 380, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_COPYPASTE - Additional Settings: Copy and Paste tab
# =========================================================================
def gen_tabsheet_copypaste():
    return "\n".join([
        svg_header(500, 380),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - コピーと貼り付け"),
        dialog_bg(500, 380),
        checkbox(16, 36, "継続行コピーを有効にする"),
        checkbox(16, 56, "右クリックでの貼り付けを無効にする"),
        checkbox(16, 76, "右クリックでの貼り付けを確認する"),
        checkbox(16, 96, "中クリックでの貼り付けを無効にする"),
        checkbox(16, 116, "左クリックでのみ選択を開始する"),
        checkbox(16, 136, "貼り付け時に末尾の改行を削除する"),
        checkbox(16, 156, "危険なクリップボードの貼り付けを確認する"),
        label(16, 182, "キーワードファイル:"),
        edit_box(140, 170, 260, 20),
        button(408, 168, 72, 24, "参照..."),
        label(16, 206, "区切り文字:"),
        edit_box(100, 194, 380, 20),
        label(16, 230, "貼り付けの行間遅延:"),
        edit_box(160, 218, 50, 20, "0"),
        label(216, 230, "ミリ秒"),
        checkbox(16, 250, "マウスでウィンドウ選択時の文字選択を有効にする"),
        checkbox(16, 270, "マウスで文字選択時、自動でクリップボードへのコピーを行う"),
        button(130, 340, 64, 24, "OK", True),
        button(206, 340, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_VISUAL - Additional Settings: Visual tab
# =========================================================================
def gen_tabsheet_visual():
    return "\n".join([
        svg_header(500, 440),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - 表示"),
        dialog_bg(500, 440),
        group_box(16, 36, 220, 60, "ウィンドウの不透明度"),
        label(30, 56, "アクティブ時:"),
        edit_box(120, 44, 40, 20, "255"),
        label(30, 78, "非アクティブ時:"),
        edit_box(120, 66, 40, 20, "255"),
        label(260, 46, "マウスカーソル:"),
        combo_box(360, 34, 120, 20),
        label(260, 72, "フォントの品質:"),
        combo_box(360, 60, 120, 20, "デフォルト"),
        group_box(16, 106, 466, 60, "ANSIカラー"),
        label(30, 128, "赤:"),
        edit_box(52, 116, 36, 20),
        label(100, 128, "緑:"),
        edit_box(122, 116, 36, 20),
        label(170, 128, "青:"),
        edit_box(192, 116, 36, 20),
        checkbox(16, 176, "ウィンドウの角を丸くしない"),
        checkbox(16, 196, "太字属性色を有効にする"),
        checkbox(250, 196, "太字属性フォントを有効にする"),
        checkbox(16, 216, "点滅属性色を有効にする"),
        checkbox(16, 236, "反転属性色を有効にする"),
        checkbox(16, 256, "下線属性色を有効にする"),
        checkbox(250, 256, "下線属性に下線を付加する"),
        checkbox(16, 276, "URL属性色を有効にする"),
        checkbox(250, 276, "URL文字列に下線を付加する"),
        checkbox(16, 296, "ANSIカラーを有効にする"),
        checkbox(16, 316, "ウィンドウ移動/リサイズ時テーマを一時的にdisableする"),
        group_box(16, 340, 466, 50, "起動時のテーマ"),
        radio(30, 358, "使用しない", True),
        radio(130, 358, "固定テーマ(テーマファイル指定)"),
        radio(340, 358, "ランダムテーマ"),
        button(130, 402, 64, 24, "OK", True),
        button(206, 402, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_LOG - Additional Settings: Log tab
# =========================================================================
def gen_tabsheet_log():
    return "\n".join([
        svg_header(500, 360),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - ログ"),
        dialog_bg(500, 360),
        group_box(16, 36, 466, 64, "ログ表示用エディタ"),
        label(30, 56, "実行ファイル:"),
        edit_box(120, 44, 270, 20),
        button(396, 42, 72, 24, "参照..."),
        label(30, 78, "引き数:"),
        edit_box(120, 66, 270, 20),
        label(16, 116, "標準ログファイル名(strftimeフォーマット可):"),
        edit_box(16, 126, 370, 20),
        label(16, 158, "標準のログ保存先フォルダ:"),
        edit_box(16, 168, 370, 20),
        button(394, 166, 72, 24, "参照..."),
        checkbox(16, 200, "自動的にログ採取を開始する"),
        group_box(16, 224, 466, 64, "ログのローテート"),
        label(30, 248, "サイズ:"),
        edit_box(80, 236, 80, 20),
        label(176, 248, "世代:"),
        edit_box(210, 236, 50, 20),
        button(130, 310, 64, 24, "OK", True),
        button(206, 310, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_CODING - Additional Settings: Encoding tab
# =========================================================================
def gen_tabsheet_coding():
    return "\n".join([
        svg_header(500, 320),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - エンコーディング"),
        dialog_bg(500, 320),
        group_box(16, 36, 466, 80, "UnicodeをDEC Special Graphicsへマッピングする"),
        checkbox(30, 54, "罫線素片(U+2500-U+257F)"),
        checkbox(30, 74, "中点(U+00B7,U+2024,U+2219)"),
        group_box(16, 126, 466, 50, "DEC Special GraphicsをUnicodeへマッピングする"),
        radio(30, 146, "マッピングする", True),
        radio(230, 146, "マッピングしない"),
        checkbox(16, 190, "文字ごとの文字幅オーバーライド設定を使う"),
        button(130, 280, 64, 24, "OK", True),
        button(206, 280, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_FONT - Additional Settings: Font tab
# =========================================================================
def gen_tabsheet_font():
    return "\n".join([
        svg_header(500, 420),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - フォント"),
        dialog_bg(500, 420),
        group_box(16, 36, 466, 60, "VTウィンドウフォント"),
        label(30, 56, "フォント名: MS Gothic 14pt"),
        button(350, 44, 80, 24, "選択..."),
        label(30, 78, "文字描画で使用するAPI:"),
        combo_box(200, 66, 200, 20),
        group_box(16, 102, 466, 50, "ダイアログフォント"),
        label(30, 126, "フォント名: MS UI Gothic 9pt"),
        button(350, 114, 80, 24, "選択..."),
        button(350, 160, 80, 24, "デフォルト"),
        label(16, 174, "表示用文字変換コードページ(0の時自動):"),
        edit_box(300, 162, 60, 20, "0"),
        checkbox(16, 196, "プロポーショナルフォントをフォントダイアログの一覧に表示する(VT)"),
        checkbox(16, 216, "プロポーショナルフォントをフォントダイアログの一覧に表示する(DLG)"),
        label(16, 244, "文字間スペース:"),
        edit_box(120, 232, 50, 20, "0"),
        checkbox(16, 264, "描画幅に合わせてリサイズしたフォントを描画"),
        label(16, 290, "フォント設定/フォントフォルダを開く"),
        button(130, 380, 64, 24, "OK", True),
        button(206, 380, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_CYGWIN - Additional Settings: Cygwin tab
# =========================================================================
def gen_tabsheet_cygwin():
    return "\n".join([
        svg_header(500, 180),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - Cygwin"),
        dialog_bg(500, 180),
        label(16, 46, "Cygwinインストール先のパス:"),
        edit_box(16, 56, 370, 20),
        button(394, 54, 72, 24, "参照..."),
        button(130, 140, 64, 24, "OK", True),
        button(206, 140, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_MOUSE - Additional Settings: Mouse tab
# =========================================================================
def gen_tabsheet_mouse():
    return "\n".join([
        svg_header(500, 200),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - マウス"),
        dialog_bg(500, 200),
        label(16, 46, "マウス設定"),
        checkbox(16, 64, "マウスイベント通知要求を受け入れる"),
        checkbox(16, 84, "Controlキーを押している間はマウスイベントを通知しない"),
        button(130, 160, 64, 24, "OK", True),
        button(206, 160, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_PLUGIN - Additional Settings: Plugin tab
# =========================================================================
def gen_tabsheet_plugin():
    return "\n".join([
        svg_header(500, 240),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - プラグイン"),
        dialog_bg(500, 240),
        f'  <rect class="listbox" x="16" y="36" width="466" height="150"/>',
        f'  <text class="label" x="24" y="54">プラグイン一覧</text>',
        button(130, 200, 64, 24, "OK", True),
        button(206, 200, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_DEBUG - Additional Settings: Debug tab
# =========================================================================
def gen_tabsheet_debug():
    return "\n".join([
        svg_header(500, 240),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - デバッグ"),
        dialog_bg(500, 240),
        label(16, 42, "デバッグモード設定"),
        checkbox(16, 60, "デバッグモードを有効にする"),
        checkbox(16, 80, "通信ログを有効にする"),
        button(130, 200, 64, 24, "OK", True),
        button(206, 200, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_UI - Additional Settings: UI tab
# =========================================================================
def gen_tabsheet_ui():
    return "\n".join([
        svg_header(500, 240),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - UI"),
        dialog_bg(500, 240),
        label(16, 42, "UI設定"),
        checkbox(16, 60, "言語ファイルを使用する"),
        label(16, 84, "言語ファイル:"),
        edit_box(100, 72, 300, 20),
        button(408, 70, 72, 24, "参照..."),
        button(130, 200, 64, 24, "OK", True),
        button(206, 200, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_TEKFONT - Additional Settings: TEK Font tab
# =========================================================================
def gen_tabsheet_tekfont():
    return "\n".join([
        svg_header(500, 260),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - フォント(TEK)"),
        dialog_bg(500, 260),
        group_box(16, 36, 466, 160, "TEKフォント"),
        label(30, 56, "フォント4: (デフォルト)"),
        button(350, 44, 80, 24, "選択..."),
        label(30, 86, "フォント3:"),
        button(350, 74, 80, 24, "選択..."),
        label(30, 116, "フォント2:"),
        button(350, 104, 80, 24, "選択..."),
        label(30, 146, "フォント1:"),
        button(350, 134, 80, 24, "選択..."),
        label(30, 176, "フォント0: (最小)"),
        button(350, 164, 80, 24, "選択..."),
        button(130, 220, 64, 24, "OK", True),
        button(206, 220, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_TABSHEET_THEME - Additional Settings: Theme tab
# =========================================================================
def gen_tabsheet_theme():
    return "\n".join([
        svg_header(500, 320),
        svg_defs(),
        title_bar(500, "Tera Term: その他の設定 - テーマ"),
        dialog_bg(500, 320),
        group_box(16, 36, 466, 60, "プレビュー/ファイル"),
        button(30, 52, 80, 24, "読み込み"),
        button(120, 52, 80, 24, "保存"),
        group_box(16, 106, 466, 60, "背景"),
        label(30, 130, "背景画像:"),
        edit_box(100, 118, 300, 20),
        button(408, 116, 60, 24, "参照..."),
        group_box(16, 176, 466, 80, "文字色"),
        label(30, 200, "テーマカラー設定"),
        button(130, 280, 64, 24, "OK", True),
        button(206, 280, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_THEME_BG_EDITOR - Theme Background Editor
# =========================================================================
def gen_theme_bg_editor():
    return "\n".join([
        svg_header(500, 340),
        svg_defs(),
        title_bar(500, "Tera Term: テーマ背景エディタ"),
        dialog_bg(500, 340),
        label(16, 42, "背景画像:"),
        edit_box(100, 30, 300, 20),
        button(408, 28, 72, 24, "参照..."),
        group_box(16, 62, 466, 120, "背景画像透過"),
        label(30, 86, "通常文字背景色の透過(右が不透明):"),
        f'  <rect class="scrollbar" x="30" y="94" width="340" height="16" rx="2"/>',
        label(30, 124, "反転文字背景色の透過:"),
        f'  <rect class="scrollbar" x="30" y="132" width="340" height="16" rx="2"/>',
        label(30, 162, "その他の文字背景色の透過:"),
        f'  <rect class="scrollbar" x="30" y="170" width="340" height="16" rx="2"/>',
        button(130, 300, 64, 24, "OK", True),
        button(206, 300, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# IDD_THEME_COLOR_EDITOR - Theme Color Editor
# =========================================================================
def gen_theme_color_editor():
    return "\n".join([
        svg_header(500, 300),
        svg_defs(),
        title_bar(500, "Tera Term: テーマ文字色エディタ"),
        dialog_bg(500, 300),
        label(16, 42, "文字色テーマの設定"),
        f'  <rect class="listbox" x="16" y="52" width="466" height="190"/>',
        button(130, 260, 64, 24, "OK", True),
        button(206, 260, 80, 24, "キャンセル"),
        "</svg>"
    ])


# =========================================================================
# Main
# =========================================================================
DIALOGS = {
    "IDD_TERMDLG.svg": gen_termdlg,
    "IDD_WINDLG.svg": gen_windlg,
    "IDD_HOSTDLG.svg": gen_hostdlg,
    "IDD_KEYBDLG.svg": gen_keybdlg,
    "IDD_SERIALDLG.svg": gen_serialdlg,
    "IDD_TCPIPDLG.svg": gen_tcpipdlg,
    "IDD_GENDLG.svg": gen_gendlg,
    "IDD_ABOUTDLG.svg": gen_aboutdlg,
    "IDD_DIRDLG.svg": gen_dirdlg,
    "IDD_WINLISTDLG.svg": gen_winlistdlg,
    "IDD_BROADCAST_DIALOG.svg": gen_broadcastdlg,
    "IDD_CLIPBOARD_DIALOG.svg": gen_clipboarddlg,
    "IDD_CTRLWIN.svg": gen_ctrlwin,
    "IDD_DAD_DIALOG.svg": gen_daddlg,
    "IDD_EDITHISTORYDLG.svg": gen_edithistorydlg,
    "IDD_ERRDLG.svg": gen_errdlg,
    "IDD_FILETRANSDLG.svg": gen_filetransdlg,
    "IDD_GETFNDLG.svg": gen_getfndlg,
    "IDD_INPDLG.svg": gen_inpdlg,
    "IDD_LISTDLG.svg": gen_listdlg,
    "IDD_LOGDLG.svg": gen_logdlg,
    "IDD_MSGDLG.svg": gen_msgdlg,
    "IDD_PRNABORTDLG.svg": gen_prnabortdlg,
    "IDD_PROTDLG.svg": gen_protdlg,
    "IDD_RECVFILEDLG.svg": gen_recvfiledlg,
    "IDD_SENDFILEDLG.svg": gen_sendfiledlg,
    "IDD_STATDLG.svg": gen_statdlg,
    "IDD_TABSHEET_GENERAL.svg": gen_tabsheet_general,
    "IDD_TABSHEET_SEQUENCE.svg": gen_tabsheet_sequence,
    "IDD_TABSHEET_COPYPASTE.svg": gen_tabsheet_copypaste,
    "IDD_TABSHEET_VISUAL.svg": gen_tabsheet_visual,
    "IDD_TABSHEET_LOG.svg": gen_tabsheet_log,
    "IDD_TABSHEET_CODING.svg": gen_tabsheet_coding,
    "IDD_TABSHEET_FONT.svg": gen_tabsheet_font,
    "IDD_TABSHEET_CYGWIN.svg": gen_tabsheet_cygwin,
    "IDD_TABSHEET_MOUSE.svg": gen_tabsheet_mouse,
    "IDD_TABSHEET_PLUGIN.svg": gen_tabsheet_plugin,
    "IDD_TABSHEET_DEBUG.svg": gen_tabsheet_debug,
    "IDD_TABSHEET_UI.svg": gen_tabsheet_ui,
    "IDD_TABSHEET_TEKFONT.svg": gen_tabsheet_tekfont,
    "IDD_TABSHEET_THEME.svg": gen_tabsheet_theme,
    "IDD_THEME_BG_EDITOR.svg": gen_theme_bg_editor,
    "IDD_THEME_COLOR_EDITOR.svg": gen_theme_color_editor,
}

if __name__ == "__main__":
    print(f"Generating {len(DIALOGS)} SVG files with Japanese labels...")
    for name, gen_func in DIALOGS.items():
        content = gen_func()
        write_svg(name, content)
    print(f"Done! Generated {len(DIALOGS)} files in {OUTPUT_DIR}")
