
		AREA    Strings_library, CODE, READONLY  	; hlavicka souboru




    EXPORT print_string
	export print_char
	export print_repeated_char
	export to_upper
	export print_header
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;				String handling
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
; Prints surrent time to stdout
print_header proc
	push {r0-r7, lr}
	mov r0, #'\r';start with carriage return in case there was something on the line before
	bl print_char
	mov r0, #'['
	bl print_char
	load_address systemTicks, r0
	mov r1, #3
	bl num2str
	mov r1, #(3+1+4)
	mov r2, #' '
	bl print_padded_string
	mov r0, #']'
	bl print_char
	mov r0, #' '
	bl print_char	
	pop {r0-r7, pc}	
	endp
	
;r0 = character to print, r1 = how many times
print_repeated_char proc
	push {lr}
	b REPEATED_COND
REPEATED_LOOP
	bl print_char
	sub r1, #1
REPEATED_COND
	tst r1, r1
	bne REPEATED_LOOP	
	pop {pc}	
	endp
		
; Prints one character given in r0
print_char proc
	push {r0-r2, lr}
WAIT_FOR_TX_EMPTY
	load_address USART2_ISR, r2
	tst r2, #USART_ISR_TXE
	beq WAIT_FOR_TX_EMPTY
	
	store_address USART2_TDR, r0
	pop {r0-r2, pc}
	endp
		
;reads string given in r0 and transmits it via USART. Completely blocking!
; r1 stores the minimal length of string. If the string is shorter, character given in r2 is used as fill
print_padded_string proc
	push {r0-r3, lr}
	mov r3, r0
	bl strlen
	cmp r0, r1
	bge STRING_TRANSMIT_LOOP ; the string is long enough, no need to add padding
	sub r1, r0
	mov r0, r2
PADDING_TRANSMIT_LOOP
	bl print_char	
	sub r1, #1
	if_true r1, PADDING_TRANSMIT_LOOP
	; else we have run out of padding to -> continue with string transmission
STRING_TRANSMIT_LOOP
	ldrb r0, [r3], #1
	tst r0, r0
	beq TRANSMIT_FINISHED ; if null terminator was loaded	
	bl print_char		
	b STRING_TRANSMIT_LOOP
TRANSMIT_FINISHED
	pop {r0-r3, pc}
	endp
	
	ALIGN
	LTORG
	
print_string proc
	push {r0-r2, lr}
	mov r1, #0 ;make sure no padding is used
	bl print_padded_string
	pop {r0-r2, pc}	
	endp
		
; takes two strings in r0 and r1 and compares them lexicographically
; returns in r0 - zero if both strings are equal, negative if r0 < r1, positive if r0 > r1
strcmp proc
	push {r1-r3, lr}
STRCMP_LOOP
	ldrb r2, [r0]
	ldrb r3, [r1]
	
	tst r2, r2
	bne SOME_NOT_ZERO
	tst r3, r3
	bne SOME_NOT_ZERO
	mov r0, #0 ;they are equal
	b RETURN_FROM_STRCMP
	
SOME_NOT_ZERO
	subs r2, r3
	bne UNEQUAL
	add r0, #1
	add r1, #1
	b STRCMP_LOOP
UNEQUAL
	mov r0, r2	
RETURN_FROM_STRCMP
	pop {r1-r3, pc}
	endp
		
;takes string in r0 and char in r1 .Returns pointer to the first occurence or r1 in r0
strchr proc
	push {r1-r3, lr}
STRCHR_LOOP
	ldrb r2, [r0]
	cmp r2, r1
	beq STRCHR_RET
	cmp r2, #0
	beq STRCHR_NOT_FOUND
	add r0, #1
	b STRCHR_LOOP
STRCHR_NOT_FOUND
	mov r0, #0
STRCHR_RET
	pop {r1-r3, pc}
	endp
		
; takes a string in r0 and char in r1. Returns the index of char r1 in r0
index_in_string proc
	push {r1-r7, lr}
	mov r4, r0
	bl strchr
	tst r0, r0
	beq NULL_TERMINATOR_REACHED
	
	sub r0, r4
	b RETURN_FROM_FIND

NULL_TERMINATOR_REACHED
	mov r0, #-1
	b RETURN_FROM_FIND
	
RETURN_FROM_FIND
	pop {r1-r7, pc}

	
	endp

	ALIGN
digitArray
	DCB "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", 0
	ALIGN
; takes in a string in r0 and base in r1, returns an integer in r0
str2num proc
	push {r1-r7, lr}
	mov r3, r0
	mov r4, r1
	mov r2, #0 ;result
	
	b STR2NUM_COND
STR2NUM_LOOP
	ldrb r0, [r3], #1
	bl to_upper
	mov r1, r0
	ldr r0, =digitArray	
	bl index_in_string
	
	mul r2, r4
	add r2, r0
STR2NUM_COND
	ldrb r0, [r3]
	tst r0, r0
	bne STR2NUM_LOOP
	;null terminator has been hit -> return	
	mov r0, r2
	pop {r1-r7, pc}	
	endp

;converts numeric value of r0/(10**r1) into string stored in num2str_result and returns it.
;i.e. r1 stores the number of decimal places
num2str proc
	push {r2-r7, lr}
	mov r5, r1 ; the index of decimal point
	
	ldr r1, =num2str_result
	mov r2, #10
	b NUM2STR_COND
NUM2STR_LOOP
	;extract least significant digit
	modulo r3, r0, r2
	;shift the divident
	udiv r0, r0, r2
	; convert digit to ASCII code
	add r3, #'0'	
	;write it to the buffer and incement buffer pointer
	strb r3, [r1], #1
	sub r5, #1
	tst r5, r5
	bne NUM2STR_COND
	; the decimal point shall be written
	mov r3, #'.'
	strb r3, [r1], #1
NUM2STR_COND
	tst r0, r0
	bne NUM2STR_LOOP ; more numbers to go
	; what if the number was not big enough? Add zeros to the beginning until decimal point can be printed
	cmp r5, #0
	blt NULL_TERMINATOR ;sufficient number of digits written, skip any leading zeros.
	beq ADD_ZERO_BEFORE_DEC_POINT ;the decimal point has been written during the last iteration -> additional zero needed
	
	mov r0, #'0'
ADD_ZEROS_LOOP
	strb r0, [r1], #1
	sub r5, #1
	tst r5, r5
	bne ADD_ZEROS_LOOP
	
	mov r0, #'.'
	strb r0, [r1], #1
	
ADD_ZERO_BEFORE_DEC_POINT
	mov r0, #'0'
	strb r0, [r1], #1

NULL_TERMINATOR
	mov r0, #0
	strb r0, [r1] ;write null terminator
	;reverse the string
	ldr r0, =num2str_result
	bl reverse_string
	pop {r2-r7, pc}	
	endp
	
; reverses null-terminated string given in r0 and returns it.
reverse_string proc
	push {r0-r3, lr}
	mov r1, r0
	bl strlen ; length of string
	; r1 = string
	add r0, r1 ;r0 = string + length (aka the null terminator)
	sub r0, #1 ; r0 points to last element of string
	swap_regs r0, r1
	b REVERSE_STRING_COND	
REVERSE_STRING_LOOP
	ldrb r2, [r0]
	ldrb r3, [r1]
	
	strb r2, [r1], #-1
	strb r3, [r0], #1
REVERSE_STRING_COND
	cmp r0, r1
	blt REVERSE_STRING_LOOP	
	pop {r0-r3, pc}
	endp
		
; returns the length of string given in r0
strlen proc
	push {r1-r2, lr}
	mov r1, r0
STRLEN_LOOP
	ldrb r2, [r1], #1
	tst r2, r2
	bne STRLEN_LOOP
	;here we have loaded the null terminator. Return to it (sub 1) and calculate the distance
	sub r1, #1
	sub r0, r1, r0	
	pop {r1-r2, pc}
	endp

; returns uppercase variant of letter given in r0. Other character are left unchanged
to_upper proc
	push {r1-r3, lr}
	; care only about chars between 'a' and 'z'
	comparege r1, r0, #'a'
	comparele r2, r0, #'z'
	tst r1, r1
	subne r0, #'a' - 'A' 
	pop {r1-r3, pc}
	endp
				END	
