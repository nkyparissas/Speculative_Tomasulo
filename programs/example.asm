; The program shipped with the original Speculative Tomasulo project, where it
; was hand-encoded in binary. It mixes both execution units and contains RAW
; dependencies through r11 and r13 as well as a WAW hazard on r13. The default
; testbench raises an exception at ROB tag 3 (the SUB) while it runs.
;
; Initial registers: r0..r10 = 0..10.

OR   r11, r0, r1       ; r11 = 0 | 1 = 1
ADD  r12, r11, r2      ; r12 = 1 + 2 = 3
AND  r13, r11, r12     ; r13 = 1 & 3 = 1
SUB  r13, r11, r1      ; r13 = 1 - 1 = 0
NOT  r14, r13, r1      ; r14 = ~0 = 0xFFFFFFFF (rt = r1 kept from the original encoding)
OR   r16, r13, r11     ; r16 = 0 | 1 = 1
HALT
