; Fifteen independent instructions fill the 15-entry reorder buffer once, so
; the sixteenth instruction is presented while the tail has wrapped around to
; entry 0 and the head has moved on. It reads r0, which no instruction writes,
; so the ROB lookup must report no producer for it. Before KI-12 was fixed,
; the lookup matched a released entry, whose rd field reads as r0.

ADD  r11, r1, r2       ; 3
OR   r12, r3, r4       ; 7
ADD  r13, r5, r6       ; 11
AND  r14, r7, r9       ; 1
SUB  r15, r10, r8      ; 2
OR   r16, r1, r8       ; 9
ADD  r17, r2, r9       ; 11
AND  r18, r10, r6      ; 2
SLL  r19, r7           ; 14
NOT  r21, r2           ; 0xFFFFFFFD
ADD  r22, r3, r3       ; 6
OR   r23, r9, r6       ; 15
SUB  r24, r8, r1       ; 7
AND  r25, r5, r7       ; 5
ADD  r26, r4, r4       ; 8
OR   r20, r0, r5       ; 5, presented while the tail is 0
HALT
