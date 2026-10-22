; The example program with the NOT reading r11 instead of r13. The NOT issues
; in the cycle in which r11's producer broadcasts its result, so its
; reservation station has to take that value from the common data bus while
; it fills its operands. Before KI-3 was fixed, this wakeup was lost and the
; program deadlocked.

OR   r11, r0, r1       ; r11 = 1
ADD  r12, r11, r2      ; r12 = 3
AND  r13, r11, r12     ; r13 = 1
SUB  r13, r11, r1      ; r13 = 0
NOT  r14, r11, r1      ; r14 = ~1 = 0xFFFFFFFE
OR   r16, r13, r11     ; r16 = 1
HALT
