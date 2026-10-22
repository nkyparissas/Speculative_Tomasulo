# Known issues

This document lists the deviations from the intended behaviour of the processor. All of them are inherited from the original Speculative Tomasulo project, on which this version is based, and they were identified while its design was reworked. They are preserved on purpose for the time being: the RTL was verified against cycle-exact traces of the original design (`tests/golden/`), so each issue below still behaves exactly as in the original code. The RTL comments refer to the issues by their identifiers.

Fixing an issue changes the golden traces. Hence, a fix should be followed by a review of the trace differences that `tests/run_tests.py` reports, by `tests/run_tests.py --bless` once the new behaviour is confirmed, and by the removal of the corresponding `@xfail` directive, if any. Issues marked "code reading" have not been reproduced by a test.

**KI-1: The reorder buffer ignores all other activity in the exception cycle.** While `exception_flag` is high, the ROB only discards entries. It neither stores a result broadcast on the CDB, nor commits, nor allocates an entry for an instruction that issues in the same cycle. A lost result leaves its entry incomplete, so the processor stops committing: in `example_exception_c7` (the original testbench), the exception coincides with the broadcast of tag 0, and no instruction ever commits. Similarly, in `example_exception_c6`, the NOT issues into a reservation station in the exception cycle but never receives a ROB entry; it survives the flush and later broadcasts tag 4 for an entry that does not belong to it.

**KI-2: The reservation stations ignore all other activity in the flush cycle.** In the cycle after an exception, the stations only release flushed entries. They ignore the CDB, so a station that waits for the broadcast result is never woken up, which deadlocks `example_exception_c6` with the ROB head at entry 1. They also skip the operand fill, the dispatch and the credit return. Since `fu_tag` keeps its previous value instead of returning to `TAG_NONE`, an operation dispatched in the preceding cycle may enter the functional unit a second time (code reading).

**KI-4: The ROB lookup lets the CDB take precedence over the second operand.** When the CDB broadcasts a result for one source register of the presented instruction, the lookup returns that value and does not search the ROB for the other source register, which then falls back to a possibly outdated register file value. Moreover, the broadcast value is used even if a younger in-flight instruction writes the same register (code reading).

**KI-5: The reorder buffer has no full detection.** Issue does not check whether a ROB entry is free, and a full buffer (head equal to tail) cannot be distinguished from an empty one. Overflowing the 15 entries requires many completed but uncommitted instructions, which none of the test programs produces (code reading).

**KI-6: Functional units are not flushed.** Operations of discarded instructions remain in the functional unit pipelines and are still broadcast. Since the ROB reallocates the discarded entries, such a stale result can complete a newly allocated entry or wake up a station that waits for the new instruction (code reading).

**KI-7: The in-flight counter can undercount.** When a reservation station dispatches an operation in the same cycle in which the CDB grants the bus to its unit, the decrement overrides the increment, so the counter ends one lower than the number of operations in the pipeline. The functional unit silently drops an operation that arrives while every stage is occupied, which the counter is meant to prevent (code reading).

**KI-8: Flush ranges are computed inconsistently.** The ROB discards the entries from the faulting one up to `tail - 1`, computed modulo 16, so a tail of 0 discards every entry. The reservation stations compute the same range with ordinary integers, and they treat a faulting tag equal to the tail as "every tag", whereas the ROB treats it as "no entry". These cases require an exception for an entry that is not in flight or a tail of 0, which the tests do not produce (code reading). Note also that `exception_tag` must lie between 0 and 14, since 15 causes an index error in simulation.

**KI-9: The tail is restored from the input port.** In the cycle after an exception, the ROB moves its tail back to `exception_tag` as it appears on the port in that cycle, rather than to the tag latched in the exception cycle. The result is correct only if the source holds `exception_tag` stable for two cycles, as the testbench does (code reading).

**KI-10: Instruction fetch is not redirected after an exception.** The processor reports the program counter of the faulting instruction on `exception_pc` but continues fetching after the last issued instruction. The discarded instructions are therefore never executed: in `example_exception_c8`, the SUB and the NOT of the example program are lost, while the final OR executes with a reallocated tag.

**KI-11: Redundant register file writes.** The ROB keeps `commit_we` high during the exception cycle, so the last committed value is written a second time (visible in `example_exception_c8`), and the register file's write-first bypass compares addresses without checking `commit_we`. Neither affects the register contents, since the commit port always presents the last committed value.

**KI-12: The ROB lookup searches every entry when the tail is 0.** When the occupied entries wrap around and the tail equals 0, `tail - 1` evaluates to 15, so the second search loop covers all entries, including released ones. Released entries hold `rd = r0`; hence, an instruction that reads r0 at that moment may be told to wait for an entry that never produces a result (code reading).

## Fixed issues

**KI-3: A wakeup in the cycle after issue was lost.** The operand fill now takes a result that the CDB broadcasts in the fill cycle directly from the bus instead of storing the stale tag from the lookup, so `missed_wakeup` completes.
