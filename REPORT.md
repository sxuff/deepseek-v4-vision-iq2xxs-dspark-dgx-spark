# Measured result

- No-spec aggregate whole-request rate: **20.05 tok/s**
- Native DSpark aggregate whole-request rate: **37.47 tok/s**
- Whole-request speedup: **1.87x**
- Server decode: **21.50 -> 43.01 tok/s**, **2.00x**
- Exact outputs: **4/4**
- Matched payloads: **4/4**
- Acceptance: **2234/2283**, **97.85%**
- Minimum `MemAvailable`: **30.52 GiB no-spec**, **20.81 GiB DSpark**
- Service swap: **0 bytes both arms**

## Per case

| Fixture | No spec tok/s | DSpark tok/s | Wall speedup | Acceptance | Exact |
|---|---:|---:|---:|---:|---:|
| copy_python | 20.38 | 38.99 | 1.91x | 99.88% | yes |
| copy_json | 20.33 | 39.13 | 1.92x | 99.90% | yes |
| structured_transform | 18.47 | 32.43 | 1.76x | 99.69% | yes |
| novel_code | 20.32 | 30.86 | 1.52x | 68.06% | yes |

Whole-request tok/s includes prefill and first-token latency. One fixed-order paired sweep, four text fixtures, one repetition.
