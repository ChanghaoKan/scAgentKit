"""Maintainable source for the current development workflow SVG (stdlib only)."""
from html import escape
from pathlib import Path

WIDTH=1100
MAIN_X=64
MAIN_W=620
TOP=154
NODE_H=86
GAP=28
NODES=[
 ('input','原始 Counts（10x MEX / RDS）','样本 metadata 与研究背景'),
 ('local','导入检查与事实确认','分别声明样本、capture、条件及批次'),
 ('local','本地 QC 与可选证据','样本分布、细胞指标；可选 doublet / 周期诊断'),
 ('author','① 作者确认分析方案','QC、PC 规则与可选方法'),
 ('local','执行已确认的 QC 与细胞选择','按方案保留细胞或处理质量异常 / 预测 doublet'),
 ('local','Normalize → HVG','默认全局；可选样本汇总 / 周期回归'),
 ('local','Scale / PCA → PC 选择','top50 80/85% 与肘部候选；执行已确认的规则'),
 ('local','可选 Harmony → 邻居图','明确技术设计后选择整合；UMAP 可选'),
 ('local','多分辨率扫描与候选 marker','簇关系树；可选 k±5 与重采样比较'),
 ('author','② 作者确认最终分群','审查实际扫描结果，选择分辨率'),
 ('local','注释证据与候选标签','marker、面板表达、参考；可选 LLM 建议'),
 ('author','③ 作者确认注释','确认标签或保留 Unknown'),
 ('output','输出可复核结果','Seurat · markers · metadata · report'),
]
COLORS={
 'input':('#eff4fb','#7c98b8'),
 'local':('#eef5fd','#94b5d7'),
 'author':('#fff3dc','#d59a3d'),
 'output':('#e9f5ee','#7caa90'),
}
HEIGHT=TOP+len(NODES)*(NODE_H+GAP)+126
parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-labelledby="title desc">',
 '<title id="title">scAgentKit 项目分析流程</title>',
 '<desc id="desc">从原始 counts 启动的当前开发分支流程，三次作者确认，可选本地科学诊断及独立 ambient 校正支路。</desc>',
 '<defs><marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#8095aa"/></marker></defs>',
 '<style>text{font-family:"PingFang SC","Noto Sans CJK SC","Microsoft YaHei",Arial,sans-serif;fill:#24384c}.title{font-size:31px;font-weight:650}.subtitle{font-size:17px;fill:#62768b}.node-title{font-size:23px;font-weight:600}.node-detail{font-size:17px;fill:#50677d}.small{font-size:16px;fill:#526b7c}.optional-title{font-size:22px;font-weight:600;fill:#2e6d6b}.optional-detail{font-size:17px;fill:#486f70}</style>',
 f'<rect width="{WIDTH}" height="{HEIGHT}" rx="20" fill="#fbfcfe"/>',
 '<text x="64" y="58" class="title">scAgentKit 项目分析流程</text>',
 '<text x="64" y="91" class="subtitle">当前开发分支 · 可选方法需显式开启，并按输入与研究设计使用</text>']

def text(x,y,value,css,anchor='middle'):
 parts.append(f'<text x="{x}" y="{y}" class="{css}" text-anchor="{anchor}">{escape(value)}</text>')
def line(x1,y1,x2,y2,dashed=False):
 dash=' stroke-dasharray="6 5"' if dashed else ''
 parts.append(f'<path d="M{x1} {y1} L{x2} {y2}" fill="none" stroke="#8095aa" stroke-width="2"{dash} marker-end="url(#arrow)"/>')
for i,(kind,title,detail) in enumerate(NODES):
 y=TOP+i*(NODE_H+GAP);fill,stroke=COLORS[kind]
 parts.append(f'<rect x="{MAIN_X}" y="{y}" width="{MAIN_W}" height="{NODE_H}" rx="13" fill="{fill}" stroke="{stroke}" stroke-width="1.6"/>')
 text(MAIN_X+MAIN_W/2,y+35,title,'node-title')
 text(MAIN_X+MAIN_W/2,y+64,detail,'node-detail')
 if i<len(NODES)-1:line(MAIN_X+MAIN_W/2,y+NODE_H+3,MAIN_X+MAIN_W/2,y+NODE_H+GAP-5)
# Straight side branches, no looping arrows or hidden automatic replacement.
y=TOP+3*(NODE_H+GAP)-3
parts.append(f'<rect x="756" y="{y}" width="294" height="144" rx="13" fill="#edf8f6" stroke="#71a6a2" stroke-width="1.6" stroke-dasharray="6 4"/>')
line(MAIN_X+MAIN_W+4,y+46,748,y+46,True)
for offset,value,css in [(32,'可选 ambient 校正','optional-title'),(62,'SoupX / decontX 单独运行','optional-detail'),(91,'另存校正 counts 与前后对照','optional-detail'),(120,'以新输入另建项目','optional-detail')]:text(903,y+offset,value,css)
text(902,y+170,'不替换原始 counts 或项目','small')
y=TOP+10*(NODE_H+GAP)-8
parts.append(f'<rect x="756" y="{y}" width="294" height="110" rx="13" fill="#eff4fb" stroke="#94b5d7" stroke-width="1.6"/>')
text(903,y+35,'已处理 RDS：显式复用','optional-title')
text(903,y+66,'保留现有分析基础','optional-detail')
text(903,y+93,'从当前注释证据进入','optional-detail')
line(748,y+53,MAIN_X+MAIN_W+8,y+53,True)
base=TOP+len(NODES)*(NODE_H+GAP)+6
for x,fill,label in [(64,'#eef5fd','本地处理 / 证据'),(344,'#fff3dc','作者确认'),(574,'#edf8f6','可选支路')]:
 parts.append(f'<rect x="{x}" y="{base}" width="20" height="20" rx="4" fill="{fill}" stroke="#9bafc1"/>')
 text(x+30,base+17,label,'small','start')
text(64,base+61,'保存项目后可重开审查；方案、分群与注释的确认分别记录。','small','start')
text(64,base+87,'本图展示开发分支能力；不表示所有可选方法已验证有效或默认启用。','small','start')
parts.append('</svg>')
Path(__file__).with_name('project-analysis-flow.svg').write_text('\n'.join(parts)+'\n',encoding='utf-8')
