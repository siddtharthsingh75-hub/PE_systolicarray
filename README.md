# PE_systolicarray
# Processing Element (PE) — RTL + Verification

Weight-stationary processing element for a 1D systolic array (part of the systolic
TPU / EV battery management system project). This PE performs a single
multiply-accumulate per cycle with saturating accumulation.

## Interface

| Signal         | Dir | Width | Description                                   |
|----------------|-----|-------|------------------------------------------------|
| `clk`          | in  | 1     | Clock                                          |
| `rst`          | in  | 1     | Synchronous reset                              |
| `weight_in`    | in  | 8     | Weight value (signed)                          |
| `weight_load`  | in  | 1     | Load `weight_in` into the internal weight reg  |
| `act_in`       | in  | 8     | Activation input (signed)                      |
| `acc_in`       | in  | 20    | Accumulator input (for chaining/feedback)       |
| `acc_out`      | out | 20    | Accumulator output (signed, saturating)         |
| `act_out`      | out | 8     | Pipelined activation passthrough                |
| `overflow_pos` | out | 1     | Set when result saturates at `ACC_MAX`          |
| `overflow_neg` | out | 1     | Set when result saturates at `ACC_MIN`          |

**Parameters:** `WIDTH = 8`, `ACC_WIDTH = 20` → `ACC_MAX = 524287`, `ACC_MIN = -524288`.

## Datapath

`mult_result = weight_reg * act_in` → sign-extended to `mult_ext` → summed with
`acc_in` into `sum_ext` (21-bit, extra headroom for overflow detection) →
saturation logic clamps to `[ACC_MIN, ACC_MAX]` → registered into `acc_out`
on the next clock edge, alongside a pipelined `act_out`.

`weight_load` gates loading `weight_in` into `weight_reg`; the weight otherwise
holds its value across cycles, which is what makes this weight-stationary
(the weight sits still while activations stream through).

## Testbench

Directed testbench in plain Verilog (Icarus), using two reusable tasks:
- `drive(w, a, ac, wl)` — applies weight/activation/accumulator-in/load for one cycle
- `check_acc(expected, tag)` — samples `acc_out` after the pipeline delay and
  compares against `expected`, logging to an `errors` counter and tagging the
  case by name for waveform readability

No functional coverage or constrained-random stimulus — every case below is
explicitly directed. `errors` stayed at 0 for the full run.

### Cases covered

| Tag | Weight | Act_in | Acc_in | Expected | Purpose |
|---|---|---|---|---|---|
| T1 — single MAC | 5 | 3 | 0 | 15 | Basic multiply-accumulate from a clean state |
| T2a — accumulate | 5 | 2 | 15 (fed back from T1's `acc_out`) | 25 | Accumulator correctly carries forward across cycles |
| T2b — accumulate w/ negative act_in | 5 | −4 | 25 | 5 | Signed multiply with a negative operand, still accumulating |
| Weight reload mid-stream | −10 (reloaded via `weight_load`) | 2 | 0 | −20 | Confirms `weight_load` correctly overwrites `weight_reg` and the new weight is used immediately |
| Positive saturation | 127 | −128 | (large negative pre-accumulated value) | clamps to `ACC_MAX` = 524287 | `overflow_pos` and saturation clamp exercised at the boundary |
| Negative saturation | −128 | 127 | (large positive pre-accumulated value) | clamps to `ACC_MIN` = −524288 | `overflow_neg` and saturation clamp exercised at the boundary |

### What this does and doesn't demonstrate

Covered: basic MAC correctness, multi-cycle accumulation, signed arithmetic
(negative weight and negative activation independently), dynamic weight
reload, and saturation at both rails.

Not covered here: constrained-random/coverage-driven verification, back-to-back
weight reloads, simultaneous overflow-both-directions edge cases, or reset
behavior mid-computation. A cocotb-based environment with a Python golden
model (used elsewhere in this project) supersedes this directed suite for
broader coverage.

## Bugs found during bring-up

- Accumulator bit-growth: an early version didn't give `sum_ext` enough
  headroom above `ACC_WIDTH`, which masked overflow before saturation logic
  could catch it.
- A posedge/negedge race between the weight-load path and the MAC datapath
  caused an intermittent one-cycle mismatch, caught via the cocotb suite and
  fixed in the RTL's clocking discipline.
