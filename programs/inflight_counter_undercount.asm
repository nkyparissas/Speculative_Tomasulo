; Pairs of independent arithmetic instructions alternate with logical ones,
; so the arithmetic unit dispatches while the bus is granted to it and then
; has to wait for the bus while the logical unit broadcasts. The in-flight
; counter of the arithmetic reservation stations must stay exact, otherwise
; an operation is dispatched into a full pipeline and lost, as happened
; before KI-7 was fixed.

ADD  r11, r1, r2       ; 3
ADD  r12, r3, r4       ; 7
OR   r13, r5, r6       ; 7
ADD  r14, r7, r8       ; 15
ADD  r15, r9, r10      ; 19
OR   r16, r1, r3       ; 3
ADD  r17, r2, r4       ; 6
ADD  r18, r5, r7       ; 12
OR   r19, r6, r8       ; 14
ADD  r20, r9, r1       ; 10
ADD  r21, r2, r3       ; 5
OR   r22, r4, r5       ; 5
HALT
