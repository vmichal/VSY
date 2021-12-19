; Vojtech Michal (michavo3), developed for VSY 2021, homework ADC with dual slope integrator.
; for pinout overview and general documentation, please see the folder "dokumentace"
; containing detailed overview of the application's usage

; The code relies heavily on macros implemented by ARM assembler.
; This way it is possible to focus on the problem at hand instead
; of losing track because of the assembler boilerplate.
; see https://developer.arm.com/documentation/dui0489/g/directives-reference/assembly-control-directives/macro-and-mend for macro documentation

; MACROS

; 1) macros for function call with literal arguments (not registers, only values defined by 'EQU')
	
	;invokes a zero argument function
	macro
	call0 $fun
	bl $fun
	mend
	
	;invokes a single argument function with literal argument supplied in r0
	macro
	call1 $fun, $arg_a
	ldr r0, =$arg_a
	bl $fun
	mend
	
	;invokes a two argument function with literal arguments supplied in r0 and r1
	macro
	call2 $fun, $arg_a, $arg_b
	ldr r0, =$arg_a
	ldr r1, =$arg_b
	bl $fun
	mend	
	
	;invokes a three argument function with literal argument supplied in r0, r1 and r2
	macro
	call3 $fun, $arg_a, $arg_b, $arg_c
	ldr r0, =$arg_a
	ldr r1, =$arg_b
	ldr r2, =$arg_c
	bl $fun
	mend	
		
;2) Memory manipulation macros
	
	; load from given address into given register (second arg)
	macro
	load_address $address, $reg
	ldr $reg, =$address
	ldr $reg, [$reg]	
	mend
	
	; store the content of register given by second argument into memory location 'address'
	macro
	store_address $address, $reg
	push {r7}
	ldr r7, =$address
	str $reg, [r7]	
	pop {r7}	
	mend
	
	; toggle bits specified by mask 'bits' in value stored at memory location 'address'
	macro
	toggle_bits $address, $bits
	push {r6, r7}
	ldr r6, =$address
	ldr r7, [r6]
	eor r7, $bits
	str r7, [r6]
	pop {r6, r7}
	mend
	
	; load from memory, add value (used as immediate in add instruction, so it must be small) and store value back
	macro
	increment_memory $address, $value
	push {r6, r7}
	ldr r6, =$address
	ldr r7, [r6]
	add r7, $value
	str r7, [r6]
	pop {r6, r7}
	mend
	
	; test 'reg', if it is not zero, jump to 'branch'
	macro
	if_true $reg, $branch
	tst $reg, $reg
	bne $branch
	mend
	
	; test 'reg', if it is zero, jump to 'branch'
	macro
	if_false $reg, $branch
	tst $reg, $reg
	beq $branch
	mend
	
	; loads given timestamp into memory and tests, whether given ammount of time has elapsed.
	; result is stored in r0 as usual
	macro
	time_elapsed $start, $time
	load_address $start, r0
	ldr r1, =$time
	bl time_elapsed_fun
	mend
	
	; executes comparison of second and last argument and evaluates, whether the conditional suffix is fulfilled.
	; Stores 0 in destination if the comparison failed, one otherwise.
	macro
	compare$cond $destination, $lhs, $rhs
	cmp $lhs, $rhs
	mov $destination, #0
	it $cond
	mov$cond $destination, #1	
	mend
	
	; Stores 0 in destination iff 'lhs' and 'rhs' share no set bits. Stores one otherwise.
	macro
	test_bits $destination, $lhs, $rhs
	tst $lhs, $rhs
	mov $destination, #0
	it ne
	movne $destination, #1		
	mend
	
	; simplifies testing, whether some specified ammount of time has elapsed since the last state machine transition
	macro
	time_elapsed_since_transition $time
	time_elapsed fsm_lastTransition, $time
	mend
	
	; stores zero into the specified address
	macro
	zero_address $destination
	push {r0}
	mov r0, #0
	store_address $destination, r0
	pop {r0}
	mend
	
	; copies value stored in memory at address 'source' to address 'destination'
	macro
	copy $source, $destination
	push {r0,r1}
	ldr r0, =$source
	ldr r0, [r0]
	ldr r1, =$destination
	str r0, [r1]
	pop {r0,r1}
	mend
	
; 3) arithmetic macros
	
	; calculates destination = divident % divisor
	macro
	modulo $destination, $divident, $divisor
	udiv $destination, $divident, $divisor
	mul $destination, $divisor
	sub $destination, $divident, $destination	
	mend
	
	macro
	swap_regs $a, $b
	eor $a, $b
	eor $b, $a
	eor $a, $b
	mend
	
	macro
	value_in_range $destination, $val, $min, $max
	push {r6, r7}
	comparege r6, $val, $min
	comparele r7, $val, $max
	
	compareeq $destination, r7, r6	
	pop {r6, r7}
	
	
	mend
	
	area mojedata, data, noinit, readwrite
	
; stores the number of systick interrupts since system start
systemTicks space 4
meas_state space 4

num2str_result space 12
	
t2_counts space 4
Uin_tenths_mV space 4
samples_taken space 4
	
;;;;;;;; configurable parameters
avg_len space 4
overwrite_results space 4
;;;;;;;;

config_state space 4 ;state of configuration mechanism
ConfigDataBegin
config_name space 40 ; stores the name of attribute to be written
config_value space 40 ;stores the new value of said attribute
ConfigDataEnd

	
	area STM32F3xx, code, readonly
	get stm32f303xe.s

;default values for dynamically adjustable parameters
avg_len_default EQU 128
overwrite_results_default EQU 1

MEAS_IDLE EQU 0
MEAS_SINGLE EQU 1
MEAS_CONTINUOUS EQU 2
MEAS_CONTINUOUS_ENDING EQU 3
	
CONFIG_IDLE EQU 0
CONFIG_NAME EQU 1 
CONFIG_VALUE EQU 2
	
; make systick generate an interrupt every 1 ms
systick_freq EQU 1000
USART_baudrate EQU 115200
SYSCLK_freq EQU 8000000
soft_start_length_us EQU 800
T1_ms EQU 40
T1_counts EQU T1_ms * 1000 * 8
voltage_reference_mV EQU 2500
	
FALSE EQU 0
TRUE EQU 1
	
strResetPending
	DCB "System reset pending...\r\n", 0
	
strMeasured1
	DCB "Measurement finished. T2 = ", 0
strMeasured2
	DCB " ms (", 0
strMeasured3
	DCB " Kcycles) -> U_in = -", 0
strMeasured4
	DCB " mV.", 0
	
strSampling1
	DCB "Sample ", 0	
strSampling2
	DCB "/", 0
	
welcomeMessage	
	DCB "\r\n\n\n\n\nVoMi's dual slope integration ADC initialized and ready.\r\nConsult the documentation for the list of available commands.\r\n", 0

strCommandReceived
	DCB "Received command '", 0
	
strNotRecognized
	DCB "Command not recognized.\r\n", 0
	
strLineBreak
	DCB "\r\n", 0

strCannotConfig
	DCB "To start configuration mode, you must first stop the ongoing measurement!\r\n", 0
	
strConfigStarted
	DCB "Configuration mode started, use syntax \"[name];[value]c\" to adjust application parameters.\r\nUse space (ascii 0x20) to erase characters.\r\n",0
	
strConfigParamNotRecognized1
	DCB "Parameter \"",0
	
strConfigParamNotRecognized2
	DCB "\" is not recognized. Exiting configuration.\r\n",0
	
strConfigValueSet1
	DCB "Parameter \"", 0
strConfigValueSet2
	DCB "\" was set to new value ", 0
strConfigValueSet3
	DCB ".\r\n", 0
	
strReceivedConfigString
	DCB "Received config string: ", 0
	
strAlreadyMeasuring
	DCB "Cannot start new measurement, one is currently in progress.\r\n", 0
strNothingToEnd
	DCB "There is no ongoing measurement, nothing to end.\r\n", 0
	
strAlreadyEnding
	DCB "The measurement is going to end regardless.\r\n", 0
strEndScheduled
	DCB "The emasurement will be stopped when the current burst ends.\r\n", 0
	
strHelp
	DCB "Help message for dual slope integration ADC.\r\n"
	DCB "Developed by Vojtech Michal at FEE CTU in Prague\r\n"
	DCB "for course Embedded systems during winter semester 2021/2022.\r\n"
	DCB "\r\n"
	DCB "\r\n"
	DCB "List of supported commands (case insensitive):\r\n"
	DCB "\tH - print this help message\r\n"
	DCB "\tS - stop ongoing measurement or start new one\r\n"
	DCB "\tC - enter configuration mode\r\n"
	DCB "\tQ - reset system\r\n"
	DCB 0

	export __main
;	export SystemInit
	export __use_two_region_memory
	export time_elapsed_fun
	export GetTick
	export print_string
	export print_header
	export print_char
	EXPORT USART2_IRQHandler
	export TIM7_IRQHandler
	export TIM2_IRQHandler
		
	import GPIO_INIT
__use_two_region_memory


	ALIGN
__main
	ENTRY
MAIN
	; zero out variables in the data section
	zero_address systemTicks
	
	mov r0, #MEAS_IDLE
	store_address meas_state, r0
	
	zero_address Uin_tenths_mV
	zero_address t2_counts
	zero_address samples_taken
	call1 SYSTICK_INIT, systick_freq
	
	mov r0, #CONFIG_IDLE
	store_address config_state, r0
	
	;initialize configurable parameters to default values.
	ldr r0, =overwrite_results_default
	store_address overwrite_results, r0
	ldr r0, =avg_len_default
	store_address avg_len, r0
	
	; Initialize the peripherals
	BL GPIO_INIT
	bl initUSART
	bl initTIM
	
	mov r0, #TRUE
	bl mux_connect_feedback
	
	;print the welcome message
	ldr r0, =welcomeMessage
	bl print_string

ENDLESS_LOOP
	; nothing to do, operation initiated from USART2_IRQ
	b ENDLESS_LOOP
		
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;				Application timing
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
;********************************************
;* Function:	WAIT
;* Brief:		This procedure waits 
;* Input:		None
;* Output:		None
;********************************************

blocking_wait_ms proc
	; takes one argument in r0 - the number of ms to wait
	push {r1,r2, r3, lr}
	ldr r1, =systemTicks
	ldr r3, [r1] ;time when we started waiting
WAITING_LOOP
	ldr r2, [r1]
	sub r2, r3
	cmp r2, r0
	; by comparing for <= instead of <, 1 ms of waiting is added.
	; this is necessary since the systick period could occur at any moment...
	ble WAITING_LOOP
	
	pop {r1, r2, r3, pc}
	
	endp
		
; takes one argument in r0, the starting timestamp
; returns number of ms since that timestamp in r0
get_time_elapsed proc
	push {r2}
	load_address systemTicks, r2
	sub r0, r2, r0
	pop {r2}
	bx lr
	endp

; takes two arguments in r0, the starting timestamp
; and r1, the number of ms that should have elapsed
; returns in r0: non-zero value if the time elapsed, zero otherwise
time_elapsed_fun proc
	push {r2, lr}
	bl get_time_elapsed
	comparege r0, r0, r1
	pop {r2, pc}
	endp
		
SYSTICK_INIT PROC
	; takes a single argument - interrupt period in us in r0
	push {r2, lr}
	; assume the AHB is running at 8 MHz (RC oscillator)
	lsl r0, #3 ; multiply the period by 8 to convert from us to cpu cycles
	sub r0, #1
	store_address STK_LOAD, r0
	load_address STK_CTRL, r2
	; enable the systick, clock it from AHB and enable interrupt
	orr r2, #(STK_CTRL_ENABLE :OR: STK_CTRL_TICKINT :OR: STK_CTRL_CLKSOURCE)
	store_address STK_CTRL, r2
	
	pop {r2, pc}
	
	ENDP
		
SysTick_Handler PROC
	export SysTick_Handler
	; increment value systemTicks stored in memory by one
	increment_memory systemTicks, #1	
	bx lr
	ENDP
	

GetTick proc; returns the current time in ms in r0
    load_address systemTicks, r0
    bx lr
	endp
		
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;				String handling
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
; Prints current time to stdout
print_header proc
	push {r0-r7, lr}

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

;converts numeric value of r0/(10**r1) into string stored in num2str_result and returns it in r0.
;i.e. r1 stores the number of decimal places
num2str proc
	push {r1-r7, lr}
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
	pop {r1-r7, pc}	
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
		
	ALIGN
	LTORG		
	ALIGN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; 			USART Driver
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;initialize the USART2 peripheral for communication with PC
initUSART
    push {r0-r3, lr}
	;enable peripheral clock for USART2
	ldr r0, =RCC_APB1ENR
	ldr r1, [r0]
	orr r1, #RCC_APB1ENR_USART2EN
	str r1, [r0]
	
    ldr r0, =USART2
    ;we don't need to adjust anything in status reg, nor data reg
    
    ldr r1, =8000000/USART_baudrate
    str r1, [r0, #0xc];BRR
    
    ldr r1, [r0, #0] ;CR1
    orr r1, #(USART_CR1_UE :OR: USART_CR1_TE :OR: USART_CR1_RE) ;enable transmiter and receiver
	orr r1, #USART_CR1_RXNEIE ;enable RXNE interrupt
    str r1, [r0, #0]; CR1
	
	mov r0, #38 ; IRQn for USART2
	bl nvic_enable_irq
        
    pop {r0-r3, pc}

	ALIGN
		
USART2_IRQHandler proc
	push {r0-r7, lr}
	
	load_address USART2_RDR, r3
	mov r0, r3
	bl to_upper
	mov r2, r0 ;the received character
	load_address config_state, r0
	cmp r0, #CONFIG_IDLE
	beq CONFIG_OFF
	
	;handle new data for configuration
	
	;where do we write?
	mov r0, r2
	bl handle_new_config_char
	b RETURN_FROM_CMD
	
CONFIG_OFF
	bl print_header
	ldr r0, =strCommandReceived
	bl print_string
	mov r0, r3 ; print the actual received char, not after capitalization
	bl print_char
	ldr r0, =apostrophSpaceParen
	bl print_string
	mov r0, r2
	mov r1, #0
	bl num2str
	bl print_string
	mov r0, #')'
	bl print_char
	ldr r0, =strLineBreak
	bl print_string	

	mov r0, r2
	; compare the received character agains all recognized commands
	cmp r0, #'C'
	beq CMD_CONFIG
	
	cmp r0, #'S'
	beq CMD_SINGLE
	
	cmp r0, #'Q'
	beq CMD_RESET
	
	cmp r0, #'H'
	beq CMD_HELP
	
	cmp r0, #'R'
	beq CMD_RUN
	
	cmp r0, #'E'
	beq CMD_END
	
	
	ldr r0, =strNotRecognized
	bl print_string
	b RETURN_FROM_CMD
	
CMD_RESET
	ldr r0, =strResetPending
	bl print_string
	ldr r0, = (0x5fa :SHL: 16) :OR: (1 :SHL: 2); request system reset
	store_address 0xE000ED00 + 0xC, r0 ;Address of SCB_AIRCR
HALT_AFTER_RESET
	b HALT_AFTER_RESET
	
CMD_HELP
	ldr r0, =strHelp
	bl print_string
	B RETURN_FROM_CMD

CMD_END
	load_address meas_state, r0
	cmp r0, #MEAS_IDLE
	beq NOTHING_TO_END
	
	cmp r0, #MEAS_CONTINUOUS
	beq CAN_END
	
	; otherwise either single shot or continuous but already ending
	ldr r0, =strAlreadyEnding
	bl print_string
	b RETURN_FROM_CMD
	
CAN_END
	mov r0, #MEAS_CONTINUOUS_ENDING
	store_address meas_state, r0
	ldr r0, =strEndScheduled
	bl print_string
	b RETURN_FROM_CMD
	
NOTHING_TO_END
	ldr r0, =strNothingToEnd
	bl print_string
	b RETURN_FROM_CMD

CMD_SINGLE
CMD_RUN
	load_address meas_state, r0
	cmp r0, #MEAS_IDLE
	bne ALREADY_MEASURING
	
	cmp r2, #'R'
	moveq r0, #MEAS_CONTINUOUS
	movne r0, #MEAS_SINGLE
	bl start_measurement
	b RETURN_FROM_CMD
	
ALREADY_MEASURING
	ldr r0, =strAlreadyMeasuring
	bl print_string
	b RETURN_FROM_CMD
	
CMD_CONFIG
	bl config_start
	b RETURN_FROM_CMD

RETURN_FROM_CMD
	pop {r0-r7, pc}
	endp
		
		
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; 			System configuration
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;		


apostrophSpaceParen
	DCB "' (", 0
	ALIGN
		
handle_new_config_char proc
	push {r1-r5, lr}
	cmp r0, #' ' ;space used as backspace
	beq ERASE_CHAR
	
	mov r2, r0
	load_address config_state, r1
	cmp r1, #CONFIG_NAME
	beq RECEIVING_NAME
	b RECEIVING_VALUE
RECEIVING_NAME
	cmp r2, #';'
	ldrne r1, =config_name
	bne APPEND
	
	mov r0, #CONFIG_VALUE
	store_address config_state, r0 ; start receiving value
	b PRINT_CONFIG
RECEIVING_VALUE
	cmp r2, #'C'
	ldrne r1, =config_value
	bne APPEND
	
	bl config_end
	b RETURN_FROM_CONFIG_HANDLING
APPEND
	; write new char to the end of said data
	mov r0, r1
	bl strlen
	
	strb r2, [r1, r0]
	b PRINT_CONFIG
ERASE_CHAR
	load_address config_state, r1
	cmp r1, #CONFIG_NAME
	ldreq r0, =config_name
	ldrne r0, =config_value
	mov r1, r0
	bl strlen
	tst r0, r0
	beq GO_TO_PREVIOUS_STRING
	sub r0, #1
	mov r2, #0
	str r2, [r1, r0] ;clear the last char in this string
	b PRINT_CONFIG
GO_TO_PREVIOUS_STRING
	load_address config_state, r1
	cmp r1, #CONFIG_VALUE
	moveq r1, #CONFIG_NAME
	store_address config_state, r1	
	b PRINT_CONFIG
PRINT_CONFIG
	
	bl erase_line
	
	ldr r0, =strReceivedConfigString
	bl print_string
	
	mov r0, #'\"'
	bl print_char
	ldr r0, =config_name
	bl print_string
	mov r0, #';'
	bl print_char
	ldr r0, =config_value
	bl print_string
	mov r0, #'\"'
	bl print_char
RETURN_FROM_CONFIG_HANDLING
	pop {r1-r5, pc}
	endp
		
erase_line proc
	push {r0-r1, lr}
	mov r0, #'\r'
	bl print_char
	
	mov r0, #' '
	mov r1, #130
	bl print_repeated_char
	
	mov r0, #'\r'
	bl print_char
	pop {r0-r1, pc}
	endp
		
config_start proc
	push {r0-r2, lr}
	;start configuration if possible
	bl print_header
	load_address meas_state, r0
	cmp r0, #MEAS_IDLE
	bne CANNOT_CONFIGURE
	
	mov r0, #CONFIG_NAME
	store_address config_state, r0
	ldr r0, =strConfigStarted
	bl print_string
	ldr r1, =ConfigDataBegin
	ldr r2, =ConfigDataEnd
	mov r0, #0
CONFIG_INIT_LOOP
	str r0, [r1], #4
	cmp r1, r2
	blt CONFIG_INIT_LOOP
	b RETURN_FROM_CONFIG_START
CANNOT_CONFIGURE
	ldr r0, =strCannotConfig
	bl print_string	
RETURN_FROM_CONFIG_START
	pop {r0-r2, pc}
	endp
		
;Parameter names
avg_len_name
	DCB "AVERAGING_LENGTH", 0
	
overwrite_name
	DCB "OVERWRITE", 0
	
	ALIGN
	LTORG
	
config_end proc
	push {r0-r7, lr}
	ldr r0, =config_value
	mov r1, #10
	bl str2num
	push {r0} ;store the value for later use
	
	;parse the parameter name
TRY_AVERAGING_LENGTH
	ldr r0, =config_name
	ldr r1, =avg_len_name
	bl strcmp
	tst r0, r0
	bne TRY_OVERWRITE
	ldr r1, =avg_len
	b PARAMETER_FOUND
	
TRY_OVERWRITE
	ldr r0, =config_name
	ldr r1, =overwrite_name
	bl strcmp
	tst r0, r0
	bne NO_PARAM_FOUND
	ldr r1, =overwrite_results
	b PARAMETER_FOUND
	
	
PARAMETER_FOUND
	;write the new value to corresponding memory location
	pop {r5}
	str r5, [r1]
	
	mov r0, #'\r'
	bl print_char
	ldr r0, =strConfigValueSet1
	bl print_string
	ldr r0, =config_name
	bl print_string
	ldr r0, =strConfigValueSet2
	bl print_string
	mov r0, r5
	mov r1, #0
	bl num2str
	bl print_string
	ldr r0, =strConfigValueSet3
	bl print_string
	b RETURN_FROM_CONFIG_END
NO_PARAM_FOUND
	pop {r0} ;discard the stored value of parameter
	mov r0, #'\r'
	bl print_char
	ldr r0, =strConfigParamNotRecognized1
	bl print_string
	
	ldr r0, =config_name
	bl print_string
	
	ldr r0, =strConfigParamNotRecognized2
	bl print_string	
RETURN_FROM_CONFIG_END
	mov r0, #CONFIG_IDLE
	store_address config_state, r0
	pop {r0-r7, pc}
	endp
		

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	MUX driver
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; takes boolean value in r0. If it's true, then activates feedback
; in hardware, thus keeping the integrator near zero. If zero, feedback is deactivated
; needs to set or clear S2 (PC1)
mux_connect_feedback proc
	push {r0-r1, lr}
	mov r1, #1 :SHL: 1 ;pin set bit
	tst r0, r0 
	lsleq r1, #16 ;pin reset bit
	store_address GPIOC_BSRR, r1
	pop {r0-r1, pc}
	endp

; takes boolean value in r0. If it's true, then GNd is connected to the
; input integrator (thus allowing offset measurement).
; If false, U_in is connected. Needs to set S0 (PC0)
mux_connect_gnd proc
	push {r0-r1, lr}
	mov r1, #1 :SHL: 0 ;pin set bit
	tst r0, r0 
	lsleq r1, #16 ;pin reset bit
	store_address GPIOC_BSRR, r1
	pop {r0-r1, pc}	
	endp
		
; takes boolean value in r0. If it's true, then U_ref is connected to the
; input integrator (thus going below ground with integrator output).
; If false, U_in/GND is connected. Needs to modify pin S1, hence through TIM2
mux_connect_reference proc
	push {r0-r2, lr}
	load_address TIM2_CCMR1, r1
	ldr r2, =TIM_CCMR1_OC2M
	bic r1, r2
	orr r1, #TIM_CCMR1_OC2M_2 ;start forcing low level
	tst r0, r0
	orrne r1, #TIM_CCMR1_OC2M_0 ;if r0 != 0, nstart forcing high output
	store_address TIM2_CCMR1, r1
	load_address TIM2_CCER, r0
	orr r0, #TIM_CCER_CC2E
	store_address TIM2_CCER, r0
	pop {r0-r2, pc}	
	endp
		
; configures the TIM2 to automatically switch between reference and U_in
mux_auto_reference proc
	push {r0-r2, lr}
	load_address TIM2_CCMR1, r1
	ldr r2, =TIM_CCMR1_OC2M
	bic r1, r2
	store_address TIM2_CCMR1, r1 ; go to frozen mode, so that transition to PWM mdoe forces an update
	orr r1, #TIM_CCMR1_OC2M_2 :OR: TIM_CCMR1_OC2M_1 :OR: TIM_CCMR1_OC2M_0 ;set channel 2 to PWM2 mode
	store_address TIM2_CCMR1, r1
	pop {r0-r2, pc}	
	endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;					uint64_t handling
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Takes two numbers
add_64bit proc
	
	endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;					Measurement handling
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; initiates the measurement process, specifically the soft start
; Mux is connected to Uref, integrator voltage goes below zero.
; this lasts for some time, after which U_in is connected and integration starts
; takes one arg in r0 - constant MEAS_xxxx identifying what measurement to run
start_measurement proc
	push {r0-r3, lr}
	store_address meas_state, r0
	mov r0, #TRUE ;connect reference voltage
	bl mux_connect_reference
	mov r0, #FALSE ;disable feedback (start integrating)
	bl mux_connect_feedback
	toggle_bits TIM7_CR1, #TIM_CR1_CEN ;start the TIM7 countdown
	pop {r0-r3, pc}	
	endp
		
measurement_finished_handler proc
	push {r0-r3, lr}
	;disable IC3 unit (so that we do not overwrite the timestamp)
	load_address TIM2_CCER, r0
	bic r0, #TIM_CCER_CC3E
	store_address TIM2_CCER, r0
	
	;make the integrator oscillate close to zero.
	mov r0, #TRUE
	bl mux_connect_feedback
	
	; calculate the time between the OC event (when the mux switched from Uin to Uref)
	; and the IC event (when U_int crossed zero).
	load_address TIM2_CCR3, r0
	load_address TIM2_CCR2, r1
	sub r0, r1
	store_address t2_counts, r0

	bl t2_to_voltage
	store_address Uin_tenths_mV, r0

	bl erase_line
	bl print_measurement
	
	;did we finish this series?
	load_address samples_taken, r0
	load_address avg_len, r1
	add r0, #1
	store_address samples_taken, r0
	cmp r0, r1 ; did we collect enough samples?
	blt START_NEXT ; series not yet finished, continue measuring
	
	; This series is concluded. Append newline if we have to
	ldr r0, =strLineBreak
	load_address overwrite_results, r1
	tst r1, r1
	bleq print_string ;write newline iff we don't want to overwrite previous results

	;Do we want to start again?
	zero_address samples_taken
	load_address meas_state, r0
	cmp r0, #MEAS_CONTINUOUS
	beq START_NEXT
	;otherwise single shot or ending -> end
	mov r0, #MEAS_IDLE
	store_address meas_state, r0
	b SKIP_NEW_START
	
START_NEXT
	load_address meas_state, r0
	bl start_measurement ; start measurement again without changing the mode, if we are asked to.
SKIP_NEW_START
	pop {r0-r3, pc}
	endp

; prints information about the measurement progress
print_measurement proc
	push {r0-r1, lr}
	bl print_header
	ldr r0, =strMeasured1
	bl print_string
	load_address t2_counts, r0
	bl counts_to_us
	mov r1, #3
	bl num2str
	bl print_string
	
	ldr r0, =strMeasured2
	bl print_string
	
	load_address t2_counts, r0
	mov r1, #3
	bl num2str
	bl print_string
	
	ldr r0, =strMeasured3
	bl print_string
	
	load_address Uin_tenths_mV, r0
	mov r1, #1
	bl num2str
	bl print_string
	
	ldr r0, =strMeasured4
	bl print_string
	
	mov r0, #' '
	bl print_char
	
	bl print_sampling_progress	

	pop {r0-r1, pc}
	endp
		
print_sampling_progress proc
	push {r0-r2, lr}
	
	ldr r0, =strSampling1
	bl print_string
	
	load_address samples_taken, r2
	mov r0, r2
	mov r1, #0
	bl num2str
	bl print_string
	
	ldr r0, =strSampling2
	bl print_string
	
	load_address avg_len, r0
	bl num2str
	bl print_string
	
	mov r1, #10
	modulo r0, r2, r1
	mov r2, r0
	mov r0, #'.'
	
PRINT_DOT_LOOP
	bl print_char	
	subs r2, #1
	bge PRINT_DOT_LOOP

	pop {r0-r2, pc}
	endp

; takes time T2 in counts in r0 and returns estimated voltage in r0 in tenths of mV 
t2_to_voltage proc
	push {r1, lr}
	ldr r1, =voltage_reference_mV
	mul r0, r1
	ldr r1, =T1_counts/10 ; divide by ten to avoid multiplying Uref by ten 
	udiv r0, r1	
	pop {r1, pc}
	endp
		
; takes value in timer counts in r0, returns the same time expressed in us
counts_to_us proc
	; since SYSCLK = 8 MHz, the formula is r0 := r0/8
	lsr r0, #3
	bx lr	
	endp
		
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	TIM driver
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; initiclizes TIM2 (OC) and TIM7 (basic delay)
initTIM proc
	push {r0-r2, lr}
	;enable peripheral clock for TIM2 and TIM7
	load_address RCC_APB1ENR, r0
	orr r0, #RCC_APB1ENR_TIM2EN :OR: RCC_APB1ENR_TIM7EN
	store_address RCC_APB1ENR, r0
	
	;assume all buses (AHB and both APBx) are running at 8 MHz
	
	; first initilaize the tim7
	; activate one pulse mode, generate update event only on counter overflow
	ldr r0, =TIM_CR1_OPM :OR: TIM_CR1_URS
	store_address TIM7_CR1, r0
	
	; scale the input clock down to count at 1 MHz
	ldr r0, =(SYSCLK_freq / 1000000) - 1
	store_address TIM7_PSC, r0
	
	; length of soft start
	ldr r0, =soft_start_length_us
	store_address TIM7_ARR, r0
	
	; activate interrupt
	ldr r0, =TIM_DIER_UIE
	store_address TIM7_DIER, r0
	
	; TIM7 done, let's initialize TIM2
	
	; no prescalers or inversions anywhere. Do not filter (yet), no Master/Slave mode
	ldr r1, =TIM_SMCR_TS_2 :OR: TIM_SMCR_TS_0 ;Select TI1FP1 as trigger. Do not invert it elsewhere!
	store_address TIM2_SMCR, r1
	ldr r0, =TIM_SMCR_SMS_2 :OR: TIM_SMCR_SMS_0 ; select gated mode
	orr r0, r1
	store_address TIM2_SMCR, r0
	
	; Activate ARR preload and enable the counter (it will however not count because of gated mode)
	load_address TIM2_CR1, r0
	orr r0, #TIM_CR1_ARPE :OR: TIM_CR1_CEN
	store_address TIM2_CR1, r0
	;noting in CR2, since we are not master to anyone
	
	; generate interrupt on channel 3 capture
	ldr r0, =TIM_DIER_CC3IE
	store_address TIM2_DIER, r0
	
	;configure capture(compare units 3 and 2)
	; IC3 is waiting for falling edge on TI3FP3 (end of de-integration)
	; OC2 is going to control the mux address S1
	
	; use CC3 as IC unit and connect it to TI3, no prescaler or filtering
	ldr r0, = TIM_CCMR2_CC3S_0
	store_address TIM2_CCMR2, r0
	; CC2 is output (default), preload, no fast anything.
	; by default, keep the output signal low
	ldr r0, = TIM_CCMR1_OC2M_2 :OR: TIM_CCMR1_OC2PE
	store_address TIM2_CCMR1, r0
	
	;enable the OC 2 unit
	load_address TIM2_CCER, r0
	orr r0, #TIM_CCER_CC2E
	
	;configure correct polarity for both CC units. OC2 is default (active high),
	;but IC3 is inverted (sensitive to falling edge)
	ldr r0, =TIM_CCER_CC3P
	store_address TIM2_CCER, r0
	
	; keep the prescaler 0, as we desire maximal resolution
	; we want no updates -> ARR maximum, which is the default
	
	; set the OC2 value to 40 ms, times 1000 us in 1 ms, times 8 since SYSCLK is 8MHz
	ldr r0, =T1_counts
	store_address TIM2_CCR2, r0
	
	mov r0, #28 ; IRQn for TIM2
	bl nvic_enable_irq
	
	mov r0, #55 ; IRQn for TIM7
	bl nvic_enable_irq
	
	pop {r0-r2, pc}	
	endp
		
; Handles end of soft start
TIM7_IRQHandler proc
	push {r0, lr}
	;clear update interrupt flag in TIM7 status reg
	load_address TIM7_SR, r0
	bic r0, #TIM_SR_UIF
	store_address TIM7_SR, r0
	
	; generate TIM2 update (it should not be running right now, since integrator is below zero
	; and the trigger input is therefore low). It may have been running before with unpredictable
	; results
	mov r0, #TIM_EGR_UG
	store_address TIM2_EGR, r0
	;and clear the update flag
	load_address TIM2_SR, r0
	bic r0, #TIM_SR_UIF
	store_address TIM2_SR, r0

	;enable IC1 as well (ready to capture falling edge on Uint and then generate irq
	load_address TIM2_CCER, r0
	orr r0, #TIM_CCER_CC3E
	store_address TIM2_CCER, r0
	
	;activate TIM2
	load_address TIM2_CR1, r0
	orr r0, #TIM_CR1_CEN
	store_address TIM2_CR1, r0
	
	; since TIM2 has just been updated, it has CNT = 0
	; therefore this drives S1 low (0 < whatever in CCR2), thus connecting to U_in
	bl mux_auto_reference 
	pop {r0, pc}
	endp
		
TIM2_IRQHandler proc
	push {r0, lr}
	;clear IC3 capture event flag in status reg
	load_address TIM2_SR, r0
	bic r0, #TIM_SR_CC3IF
	store_address TIM2_SR, r0

	;deactivate TIM2
	load_address TIM2_CR1, r0
	bic r0, #TIM_CR1_CEN
	store_address TIM2_CR1, r0
	
	
	bl measurement_finished_handler

	pop {r0, pc}
	endp
	
	ALIGN
	
	END