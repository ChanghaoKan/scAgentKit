"""Generate English-primary and Simplified Chinese workflow SVGs (stdlib only).

Run from any directory: python3 docs/diagrams/generate_project_flow.py
The canonical project-analysis-flow.svg remains the English README asset.
Both languages share geometry, node IDs, gates and optional-path boundaries.
"""
from html import escape
from pathlib import Path

WIDTH, MAIN_X, MAIN_W, SIDE_X, SIDE_W = 1200, 48, 752, 848, 304
TOP, NODE_H, GAP = 176, 124, 24
KINDS = ['input', 'auto', 'author', 'auto', 'auto', 'author', 'auto', 'author', 'output']
IDS = ['input', 'qc-evidence', 'gate-strategy', 'foundation', 'ordinary-scan',
       'gate-clusters', 'annotation-evidence', 'gate-annotation', 'export']
COLORS = {'input': ('#f0f4fa', '#899eb6'), 'auto': ('#edf4fc', '#7699bd'),
          'author': ('#fff2d8', '#bb7d28'), 'output': ('#eaf5ee', '#719d83')}
LANGUAGES = {
    'en': dict(
        title='A saved workflow with three scientific decisions',
        subtitle='Development raw-count path · automatic local steps pause for your review',
        desc='Counts and declared facts enter automatic local analyses. Three separate scientific approvals cover the initial strategy, measured clustering and annotation. Optional methods need explicit selection; ambient correction is a separate R-only API.',
        legend=['Automatic local work', 'You inspect and confirm', 'Optional / explicit selection'],
        nodes=[
            ['Counts + study facts', '10x MEX / sample table / raw-count Seurat or RDS', 'Declare sample roles, species, tissue and research goal'],
            ['Validate import + measure QC', 'Check counts, feature identity and metadata alignment', 'Prepare QC plots and candidate retention impacts'],
            ['1 · Confirm the initial strategy', 'Inspect QC plots, retention and planned PC / method rules', 'Choose QC + analysis plan; save it, then approve'],
            ['Run the approved foundation', 'QC → normalize / global HVG → scale / PCA', 'Apply approved PCs → neighbors; UMAP when selected'],
            ['Scan resolutions + build the cluster tree', 'Same cells, PCs, neighbor graph and seed', 'Prepare marker contrasts and sample composition'],
            ['2 · Confirm measured clustering', 'Inspect PC evidence, tree, marker contrasts and samples', 'Select a scanned resolution; save edits, then approve'],
            ['Prepare annotation evidence', 'Markers + applicable panels / references / Fisher evidence', 'Candidate labels and confidence are provisional'],
            ['3 · Confirm the annotation proposal', 'Inspect markers, expression, reference support and limits', 'Choose labels or Unknown + reasons; save all, then approve'],
            ['Export + reopen the saved result', 'New Seurat, markers, metadata, figures and decisions', 'Reopening inspects saved work; it does not rerun analysis'],
        ],
        optional=['Optional · explicit opt-in', 'Requires suitable inputs/design',
                  'PC k±5 · 80% resampling', 'Extra resolution / sample-HVG',
                  'Experimental QC draft prefill', 'Harmony / cycle correction',
                  'Declared doublet methods', 'LLM request: separate consent',
                  'Ordinary scan/tree stays on', 'Missing inputs → unavailable'],
        ambient=['R-only ambient correction', 'SoupX / decontX: separate API',
                 'Separate corrected counts + receipt', 'Use them in a new project',
                 'Original counts/checkpoints kept', 'No browser correction action'],
        footer=['The three gates apply to this standard raw-count scan; processed reuse has its own entry.',
                'Optional model requests need separate exact transfer consent. Evidence is not a guarantee of accuracy.'],
    ),
    'zh-CN': dict(
        title='保存每一步，分三次确认科学决策',
        subtitle='当前开发分支的原始 counts 路径 · 自动本地计算在审阅处暂停',
        desc='从 counts 和明确声明的事实开始自动本地计算。分析方案、实测分群和注释分别需要三次独立科学审批。可选方法须明确选择；ambient 校正是单独的 R-only API。',
        legend=['自动本地计算', '用户审阅并确认', '可选 / 明确选择'],
        nodes=[
            ['Counts 与研究事实', '10x MEX / 样本表 / 含原始 counts 的 Seurat 或 RDS', '明确样本角色、物种、组织和研究目标'],
            ['导入检查与 QC 实测', '检查 counts、特征身份及 metadata 对齐', '准备 QC 分布图和候选筛选的保留影响'],
            ['1 · 确认初始分析方案', '看：QC 图、保留影响及拟用 PC / 方法规则', '选：QC 与分析方案；先保存，再独立审批'],
            ['执行已批准的分析基础', 'QC → normalize / 全局 HVG → scale / PCA', '应用已批准的 PC → 邻居图；选择后才运行 UMAP'],
            ['常规分辨率扫描与簇关系树', '使用同一细胞、PC、邻居图及 seed', '准备 marker 对照和样本组成'],
            ['2 · 确认实测分群', '看：PC 证据、簇关系树、marker 对照和样本组成', '选：实际扫描过的分辨率；改动先保存，再审批'],
            ['准备注释证据', 'Markers 与适用的面板 / 参考 / Fisher 证据', '候选标签和置信度仍是待判断的提案'],
            ['3 · 确认注释提案', '看：marker、表达、参考支持及证据限制', '选：标签或 Unknown 并给理由；保存全部后再审批'],
            ['导出并重开已保存的结果', '新 Seurat、markers、metadata、图及决策记录', '重开读取保存状态，不会重新运行分析'],
        ],
        optional=['可选 · 主动开启', '需要适用的输入和研究设计',
                  'PC k±5 / 80% 重采样', '额外分辨率 / 样本汇总 HVG',
                  '实验性 QC 草稿自动预选', 'Harmony / 周期校正',
                  '明确声明的 doublet 方法', 'LLM 请求另需传输同意',
                  '常规扫描 / 簇关系树保留', '输入缺失则标记不可用'],
        ambient=['R-only ambient 校正', 'SoupX / decontX 单独 API',
                 '另存校正 counts 与 receipt', '使用时另建新项目',
                 '保留原 counts / checkpoints', '没有网页校正操作'],
        footer=['三次确认对应本图的标准 raw-count 扫描；已处理对象的显式复用走单独入口。',
                '可选模型请求还需针对实际传输内容单独同意。证据展示不保证注释准确率。'],
    ),
}


def generate(language):
    data = LANGUAGES[language]
    height = TOP + len(IDS) * (NODE_H + GAP) + 120
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{height}" viewBox="0 0 {WIDTH} {height}" xml:lang="{language}" role="img" aria-labelledby="title desc">',
             f'<title id="title">{escape(data["title"])}</title>',
             f'<desc id="desc">{escape(data["desc"])}</desc>',
             '<defs><marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#7c93a9"/></marker></defs>',
             '<style>text{font-family:Arial,"PingFang SC","Noto Sans CJK SC","Microsoft YaHei",sans-serif;fill:#23384b}.title{font-size:32px;font-weight:700}.subtitle{font-size:20px;fill:#51697e}.node-title{font-size:26px;font-weight:650}.node-detail{font-size:20px;fill:#425f75}.small{font-size:18px;fill:#4c667b}.side-title{font-size:21px;font-weight:650;fill:#286c67}.side-detail{font-size:17px;fill:#3d6664}</style>',
             f'<rect width="{WIDTH}" height="{height}" rx="20" fill="#fbfcfe"/>']

    def text(x, y, value, css, anchor='middle'):
        parts.append(f'<text x="{x}" y="{y}" class="{css}" text-anchor="{anchor}">{escape(value)}</text>')

    def line(x1, y1, x2, y2, dashed=False):
        dash = ' stroke-dasharray="6 5"' if dashed else ''
        parts.append(f'<path d="M{x1} {y1} L{x2} {y2}" fill="none" stroke="#7c93a9" stroke-width="2"{dash} marker-end="url(#arrow)"/>')

    text(48, 54, data['title'], 'title', 'start')
    text(48, 89, data['subtitle'], 'subtitle', 'start')
    for x, color, label in zip([48, 398, 776], ['#edf4fc', '#fff2d8', '#edf8f5'], data['legend']):
        parts.append(f'<rect x="{x}" y="119" width="20" height="20" rx="4" fill="{color}" stroke="#8ea5b7"/>')
        text(x+30, 136, label, 'small', 'start')
    for index, (node_id, kind, labels) in enumerate(zip(IDS, KINDS, data['nodes'])):
        y = TOP + index * (NODE_H + GAP)
        fill, stroke = COLORS[kind]
        parts.append(f'<g id="{node_id}" data-box="{node_id}" data-kind="{kind}">')
        parts.append(f'<rect x="{MAIN_X}" y="{y}" width="{MAIN_W}" height="{NODE_H}" rx="13" fill="{fill}" stroke="{stroke}" stroke-width="1.8"/>')
        for offset, label, css in zip([34, 70, 101], labels, ['node-title', 'node-detail', 'node-detail']):
            text(MAIN_X+MAIN_W/2, y+offset, label, css)
        parts.append('</g>')
        if index < len(IDS)-1:
            line(MAIN_X+MAIN_W/2, y+NODE_H+2, MAIN_X+MAIN_W/2, y+NODE_H+GAP-5)
    for node_id, index, labels, box_height in [('optional', 3, data['optional'], 356), ('ambient', 6, data['ambient'], 226)]:
        y = TOP + index * (NODE_H+GAP)
        parts.append(f'<g id="{node_id}" data-box="{node_id}" data-kind="optional">')
        parts.append(f'<rect x="{SIDE_X}" y="{y}" width="{SIDE_W}" height="{box_height}" rx="13" fill="#edf8f5" stroke="#68a09a" stroke-width="1.6" stroke-dasharray="6 4"/>')
        for number, label in enumerate(labels):
            text(SIDE_X+SIDE_W/2, y+34+number*31, label, 'side-title' if number==0 else 'side-detail')
        parts.append('</g>')
        line(MAIN_X+MAIN_W+3, y+NODE_H/2, SIDE_X-7, y+NODE_H/2, True)
    base = TOP + len(IDS) * (NODE_H+GAP)
    for offset, value in zip([22, 57], data['footer']):
        text(48, base+offset, value, 'small', 'start')
    parts.append('</svg>')
    return '\n'.join(parts)+'\n'


if __name__ == '__main__':
    directory = Path(__file__).resolve().parent
    for language, name in [('en', 'project-analysis-flow.svg'), ('zh-CN', 'project-analysis-flow.zh-CN.svg')]:
        (directory/name).write_text(generate(language), encoding='utf-8')
