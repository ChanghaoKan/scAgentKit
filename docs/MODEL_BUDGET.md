# Model budget and measured costs

For a new DeepSeek `deepseek-flash` project with non-thinking mode, at most
4096 output tokens and a request reservation no greater than USD0.05,
`sc_start()` and `sc_analyze()` select a **USD0.20 project cap** when `budget`
is omitted. An explicit cap, including `budget=0`, takes precedence. Manual
mode remains free of model requests. Explicit in-memory callbacks and other models/settings need an explicit
cap; they have not been assigned this measured default. Existing projects keep
their saved provider, rates, cap and consent.

This default configures a limit; it does not authorize transmission. New
projects start with external transfer disabled unless explicitly enabled. Review
the data categories, provider/model and cap before confirming project consent,
or approve each exact aggregate preview in strict mode. Creation-time project
consent requires an explicitly stated cap (for example `budget=.20`); an omitted
budget cannot silently confirm the default cap. No usable key means no
provider request. Scientific approvals remain separate from transmission.

## Calibration and conservative allowance

On 2026-10-19, one repaired workflow using public SeuratObject `pbmc_small`
(80 cells) made three separate official DeepSeek requests, with valid QC/strategy,
measured-strategy and annotation responses. It retained the explicitly supplied
analysis choices, used three independent software-control approvals, and did not
force the model labels to Unknown. This is transport/schema/workflow evidence,
not proof of biological annotation accuracy or a cost benchmark for every dataset.

| Gate | Input tokens | Cache-hit input | Output tokens | Peak-rate USD estimate |
| --- | ---: | ---: | ---: | ---: |
| Initial strategy | 3039 | 0 | 921 | 0.002016900 |
| Measured strategy | 5164 | 768 | 1172 | 0.002729808 |
| Independent annotation | 2835 | 2688 | 137 | 0.000224628 |
| Total | 11038 | 3456 | 2230 | 0.004971336 |

The preceding recovery calibration cost an additional estimated USD0.005623440,
so both runs conservatively total USD0.010594776 under the shared USD2 authorization.
No failed or uncertain request was retried. The earlier recovery run included a
manual discard and forced Unknown and is not counted as an all-valid model run.

[Official prices](https://api-docs.deepseek.com/quick_start/pricing/) checked
2026-10-19 list peak rates per million tokens: USD0.30 input cache miss,
USD0.006 input cache hit, USD1.20 output. Off-peak prices are half these rates;
the repaired run occurred outside peak hours, implying USD0.002485668 from tokens.
These are usage-derived estimates; no provider cash invoice was verified.
The API reported `deepseek-flash`; the documentation maps it to
DeepSeek-V4.1-Flash-1017. All three prompts used aggregate-review.v2.

The USD0.20 default is approximately40times the measured peak-rate total.
Independently of that tiny fixture, the100000-byte aggregate request limit and
4096-token output cap give a conservative uncached token bound of
USD0.0349152 per call at the published peak rates, before small message framing.
Each request reserves USD0.05. Four full reservations fit USD0.20, allowing the
three gates and at most one guided annotation comparison. Unknown delivery keeps
its reservation; it is never treated as free or automatically retried. A larger
output cap, another model, another price schedule or higher reservation requires
an explicit budget choice.

The workbench visibly separates estimated used cost, held reservations and
remaining allowance. Held amounts reduce the remainder. The ledger retains
provider-original allowlisted numeric usage, nested token details, safe response
IDs and integrity hashes; keys and arbitrary HTTP headers/strings are excluded.
