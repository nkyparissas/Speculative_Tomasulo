# Known issues

This document lists the deviations from the intended behaviour of the processor. All of them are inherited from the original Speculative Tomasulo project, on which this version is based, and they were identified while its design was reworked. They are preserved on purpose for the time being: the RTL was verified against cycle-exact traces of the original design (`tests/golden/`), so each issue below still behaves exactly as in the original code. The RTL comments refer to the issues by their identifiers.

Fixing an issue changes the golden traces. Hence, a fix should be followed by a review of the trace differences that `tests/run_tests.py` reports, by `tests/run_tests.py --bless` once the new behaviour is confirmed, and by the removal of the corresponding `@xfail` directive, if any. Issues marked "code reading" have not been reproduced by a test.

**KI-8: Flush ranges are computed inconsistently.** The ROB discards the entries from the faulting one up to `tail - 1`, computed modulo 16, so a tail of 0 discards every entry. The reservation stations compute the same range with ordinary integers, and they treat a faulting tag equal to the tail as "every tag", whereas the ROB treats it as "no entry". These cases require an exception for an entry that is not in flight or a tail of 0, which the tests do not produce (code reading). Note also that `exception_tag` must lie between 0 and 14, since 15 causes an index error in simulation.

**KI-10: Instruction fetch is not redirected after an exception.** The processor reports the program counter of the faulting instruction on `exception_pc` but continues fetching after the last issued instruction. The discarded instructions are therefore never executed: in `example_exception_c8`, the SUB and the NOT of the example program are lost, while the final OR executes with a reallocated tag.

**KI-11: Redundant register file writes.** The ROB keeps `commit_we` high during the exception cycle, so the last committed value is written a second time (visible in `example_exception_c8`), and the register file's write-first bypass compares addresses without checking `commit_we`. Neither affects the register contents, since the commit port always presents the last committed value.

## Fixed issues

**KI-3: A wakeup in the cycle after issue was lost.** The operand fill now takes a result that the CDB broadcasts in the fill cycle directly from the bus instead of storing the stale tag from the lookup, so `missed_wakeup` completes.

**KI-4: The ROB lookup let the CDB take precedence over the second operand.** The lookup now searches the ROB for the youngest in-flight producer of both source registers and takes a value from the CDB only when that producer is the entry being broadcast; `cdb_lookup_second_operand` and `cdb_lookup_younger_producer` cover both cases.

**KI-12: The ROB lookup searched every entry when the tail was 0.** The bound of the search is now compared as an integer, so a tail of 0 no longer wraps to 15 and released entries are no longer matched as producers of r0; `r0_read_at_tail_wrap` covers the case.

**KI-7: The in-flight counter could undercount.** A dispatch and a grant to the same unit in one cycle now leave the counter unchanged, so it stays exact and never admits an operation into a full pipeline; `inflight_counter_undercount` covers the case.

**KI-5: The reorder buffer had no full detection.** The reorder buffer now keeps a full flag, and the reservation stations accept no instruction while it is set, so an issued instruction can no longer overwrite an occupied entry; `rob_full` covers the case, which random testing found when an old instruction waited at the head behind younger ones.

**KI-1: The reorder buffer ignored all other activity in the exception cycle.** In the exception cycle, the reorder buffer now records a result broadcast on the CDB, and an instruction that issues in that cycle advances the tail so that it is discarded together with the faulting instruction; the exception scenarios are now checked functionally, and `example_exception_c7`, the original testbench, completes correctly.

**KI-2: The reservation stations ignored all other activity in the flush cycle.** The flush is now an additional step: the stations of discarded instructions are released and their pending operand fill is cancelled, while all other stations perform their wakeup, operand fill, dispatch and credit return as usual, and `fu_tag` no longer holds an operation for a second cycle; `example_exception_c6` now completes correctly.

**KI-6: Functional units were not flushed.** Operations of discarded instructions are now marked during the flush and drain as usual, so that the in-flight counter stays exact, but their results reach the CDB without a tag; in the cycle after an exception, the reorder buffer also ignores a discarded result that is still on the CDB. The new exception scenarios `example_exception_c9`, `example_exception_tag0_c4` and `example_exception_tag0_c6` cover both paths.

**KI-9: The tail was restored from the input port.** In the cycle after an exception, the reorder buffer now restores its tail from the tag latched in the exception cycle, so the result no longer depends on how long the source holds `exception_tag`; the testbench generic `EXCEPTION_TAG_HELD` and the scenario `example_exception_c7_tag_released` cover the case.
