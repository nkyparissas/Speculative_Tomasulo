; Exception handler reached through the redirect of instruction fetch. The
; code after the first HALT runs only after an exception, with the testbench
; generic HANDLER_ADDR set to its address, 8: the scenario
; exception_handler_c7 of tests/run_tests.py raises an exception for the SUB,
; which occupies ROB entry 3. The handler reads r13, which an older
; instruction that is still in flight produces, and r14, which only the
; discarded SUB writes, so that its operands must come from the ROB entry of
; the older instruction and from the register file, respectively.

ADD  r11, r1, r2      ; 3
SLL  r12, r11         ; 6
ADD  r13, r12, r3     ; 9
SUB  r14, r13, r4     ; 5, faults in exception_handler_c7
NOT  r15, r14         ; ~5 = 0xFFFFFFFA
OR   r16, r15, r12    ; 0xFFFFFFFE
ADD  r17, r16, r1     ; 0xFFFFFFFF
HALT
ADD  r20, r13, r14    ; handler: 9 + 0 = 9
OR   r21, r20, r5     ; 9 | 5 = 13
HALT
