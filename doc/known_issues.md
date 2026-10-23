# Known issues

This document lists the deviations from the intended behaviour that the original Speculative Tomasulo project, on which this version is based, exhibited. They were identified while its design was reworked, preserved at first so that the rework could be verified against cycle-exact traces of the original design, and then fixed one at a time, as summarised below. No known issue remains open. A newly found issue belongs above the section "Fixed issues", with an identifier that the RTL comments can refer to.

Fixing an issue changes the golden traces. Hence, a fix should be followed by a review of the trace differences that `tests/run_tests.py` reports, by `tests/run_tests.py --bless` once the new behaviour is confirmed, and by the removal of the corresponding `@xfail` directive, if any. Issues marked "code reading" have not been reproduced by a test.

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

**KI-8: Flush ranges were computed inconsistently.** The reorder buffer now discards the range that the reservation stations and the functional units compute with `in_flush_range`, so a tail of 0 no longer discards older entries and an exception on the head of a full buffer discards every entry. Furthermore, the reorder buffer accepts an exception only if its tag names an occupied entry, and it ignores any other request, including one for tag 15 or for an entry that has already committed or been discarded. The scenarios `rob_wraparound_exception_c36`, `rob_full_exception_c25`, `example_exception_tag0_c8`, `example_exception_tag5_c7`, `example_exception_tag15_c7` and `example_exception_c7_flag_held` (with the new testbench generic `EXCEPTION_LENGTH`) cover these cases.

**KI-10: Instruction fetch was not redirected after an exception.** In the cycle after an exception, the reorder buffer's flush notification now also loads the program counter with the address of the exception handler, which the new generic `HANDLER_ADDR` of `top_level` sets, so the discarded instructions are no longer replaced by the instructions that follow the last issued one. By default, the handler address is the last ROM word, which holds `HALT`, so the processor stops after the older instructions have committed. The exception oracle now runs the instructions older than the faulting one followed by the handler, and `exception_handler_c7` covers a handler that reads results of older instructions still in flight.

**KI-11: Redundant register file writes.** The reorder buffer now drives `commit_we` low in the exception cycle, so the last committed value is no longer written a second time, and the register file's write-first bypass forwards the commit value only when the port writes. The exception scenarios now also require the register-file writes to equal the reference commit sequence, which `example_exception_c8` failed before.
