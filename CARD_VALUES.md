# Result-card values

## Recommended card

**Title**  
DeepSeek V4 Vision IQ2_XXS · DSpark speculative decoding on one DGX Spark

**Subtitle**  
GB10, 128 GB unified · llama.cpp · Prometheus IQ2_XXS target + official native DSpark draft · paired sweep, 4 matched text requests per arm

**Left metric**  
No speculation  
**20.1 tok/s**  
aggregate whole-request

**Right metric**  
Native DSpark on  
**37.5 tok/s**  
aggregate whole-request · **1.87x**

**Proof panel 1**  
Exact output parity  
**4 / 4**  
identical completion bytes across arms

**Proof panel 2**  
DSpark draft acceptance  
**97.9%**  
2,234 / 2,283 draft tokens accepted

**Target**  
`prometheusAIR/DeepSeek-V4-Flash-Vision-Exp-GGUF` · IQ2_XXS

**Draft**  
`deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` · extracted native DSpark

**Min host MemAvailable**  
30.5 GiB no-spec · 20.8 GiB DSpark

**Service swap, both arms**  
0 B

**Metric footnote**  
Tok/s = total completion tokens ÷ summed whole-request wall time, prefill and first token included.

**Scope footnote**  
One fixed-order paired sweep, 4 text fixtures, 1 repetition. Native-image smoke passed separately.

**Repository footer**  
`github.com/sxuff/deepseek-v4-vision-iq2xxs-dspark-dgx-spark · results/summary.json`

## Do not use on the main card

- Do not label 43.0 tok/s as whole-request throughput. It is weighted server decode throughput.
- Do not imply a matched vision speedup. Vision passed only as a DSpark compatibility smoke.
- Do not call the draft Q2_K. The exercised native draft is mixed MXFP4_MOE/BF16/F32/Q8_0.
- Do not generalize the 97.9% acceptance beyond this copy-heavy four-case sweep. The novel-code control measured 68.1%.
