; Found by random testing and minimised. The SUB at the seventh position
; (ROB entry 6) has its operands from about cycle 14, but dispatch prefers the
; lowest-numbered reservation station, so younger arithmetic instructions go
; first and the SUB holds the head of the reorder buffer until cycle 27.
; Meanwhile issue continues, so all 15 entries fill up; issue must stall then,
; or the next instruction overwrites the entry of the waiting SUB, as it did
; before KI-5 was fixed.

ADD  r17, r2, r9
SUB  r18, r13, r10
ADD  r16, r19, r7
SUB  r13, r10, r5
SLL  r20, r5
OR   r12, r11, r16
SUB  r12, r12, r14
ADD  r12, r3, r11
SUB  r20, r10, r15
SLL  r15, r16
NOT  r19, r8
SLL  r20, r14
NOT  r18, r16
ADD  r20, r11, r7
AND  r11, r9, r4
SLL  r14, r12
NOT  r17, r2
AND  r14, r2, r19
SLL  r19, r20
OR   r12, r7, r20
SUB  r12, r13, r3
NOT  r12, r2
HALT
