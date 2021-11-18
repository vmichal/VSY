; Vojtech Michal (michavo3), developed for VSY 2021, homework "Tester B".
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
; stores the timestamp of last state machine transition (used for precise state machine timings)
fsm_lastTransition space 4
; stores the index of current state. Shall only contain values of STATE_* listed below
fsm_state space 4
is_paused space 4 ; stores true when the application is paused
pause_start_timestamp space 4 ;how long has the application been paused for
test_length space 4 ; chosen length of current test
series_start_timestamp space 4 ; timestamp when the test series started
pause_length_sum space 4 ; sum of lengths of pauses during test series

;stores 1 if given LED shall be on. Zero otherwise
led_on_mask space 4
; stores constant identifying which side will light up when the test delay elapses
tested_side space 4 
	
num2str_result space 12
	
;;;;;;;; configurable parameters
;runtime bounds for randomly generated length of test
test_length_min space 4
test_length_max space 4
idle_blink_period space 4
press_timeout space 4
rgb_brightness space 4
;;;;;;;;

; test data
;three 4 byte values to be indexed by side index (index zero is padding)
TestDataBegin
hit_counter space 3*4 ; the number of times the user successfully hit given button
test_counter space 3*4; the total number of tests aimed at given side
reaction_time_sum space 3 * 4 ; sum of time (in ms) taken by the user to react on given side
reaction_time_best space 3 * 4 ; best time achieved on either side
TestDataEnd

config_state space 4 ;state of configuration mechanism
ConfigDataBegin
config_name space 40 ; stores the name of attribute to be written
config_value space 40 ;stores the new value of said attribute
ConfigDataEnd
	area STM32F3xx, code, readonly
	get stm32f303xe.s
		

CONFIG_IDLE EQU 0
CONFIG_NAME EQU 1 
CONFIG_VALUE EQU 2

;enumeration of possible state machine states

STATE_BEFORE_TEST EQU 0
STATE_TEST_DELAY EQU 1
STATE_TEST_WAIT_FOR_USER EQU 2
STATE_MISSED EQU 3

strNoSeriesToEnd
	DCB "There is no active test to end!\r\n", 0
	
strSeriesAlreadyStarted
	DCB "The test is already in progress. To start again, quit the current test first, please.\r\n", 0

strCommandReceived
	DCB "Received command '", 0

strNotRecognized
	DCB "Command not recognized.\r\n", 0
	
strLineBreak
	DCB "\r\n", 0
	
strNA
	DCB "N/A", 0

strNoTestInProgress
	DCB "There is currently no test in progress, for which results could be displayed.\r\n", 0

welcomeMessage
	DCB "\r\n\r\nWelcome to Vomi's reaction tester v2!\r\nSee the documentation for instructions.\r\n", 0

pausedMessage
	DCB "Application paused.\r\n", 0

resumedMessage1
	DCB "Application resumed after ", 0

resumedMessage2
	DCB " seconds.\r\n", 0

endMessage
	DCB "Test ended!\r\n", 0
	
startMessage
	DCB "Test started!\r\n", 0

statsMessage1
	DCB "Test statistics: Duration ", 0
statsMessage2
	DCB " minutes and ", 0
statsMessage3
	DCB " seconds (paused ", 0
statsMessage4
	DCB " % of time).\r\n", 0

statsMessageSide1
	DCB " side hit ", 0
statsMessageSide2
	DCB " out of ", 0
statsMessageSide3
	DCB ", accuracy ", 0
statsMessageSide4	
	DCB " %. Reaction time: ", 0
statsMessageSide5
	DCB " ms average, ", 0
statsMessageSide6	
	DCB " ms best.\r\n", 0

strWaiting
	DCB "Waiting for user to press ", 0

strLeft
	DCB "Left", 0
	
strRight
	DCB "Right", 0
	
strMiddle
	DCB "Middle", 0
	
strFailure
	DCB "Wata hail you doing, failure? ", 0
	
strTooLate
	DCB "My grandma has faster reactions", 0
strTooSoon1
	DCB "You pressed ", 0
strTooSoon2
	DCB " too soon", 0
	
strBadButton1
	DCB "Incorrect button - expected ", 0
strBadButton2
	DCB " and got ", 0
	
strSuccess
	DCB "Excellent (that means stoooooopid)! Reaction took ", 0
	
strMilliseconds
	DCB " ms", 0
	
strNewBestTime
	DCB "New best time (improvement by ",0
	
strIncorrectButton
	DCB " side missed.\r\n", 0

strTestEnded
	DCB "Test ended!\r\n", 0
	
strNewTest1
	DCB "New test generated: Duration ",0
	
strNewTest2
	DCB " ms, tested side ",0
	
strCannotConfig
	DCB "To start configuration mode, you must first pause the application!\r\n", 0
	
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
	
;the length of interval during which the user must react to deactivated LED
press_timeout_default EQU 400
;default bounds for randomly generated length of test
test_length_min_default EQU 300
test_length_max_default EQU 800
	
idle_blink_period_default EQU 500
rgb_brightness_default EQU 128
rgb_brightness_max EQU 256
mistake_on_time EQU 400
	
; make systick generate an interrupt every 1 ms
systick_freq EQU 1000
USART_baudrate EQU 115200
	
FAILURE_TOO_LATE   EQU 0
FAILURE_TOO_SOON   EQU 1
FAILURE_BAD_BUTTON EQU 2

SIDE_MIDDLE EQU 0 ;there is no led for this side
SIDE_RIGHT EQU 1
SIDE_LEFT EQU 2
SIDE_BOTH EQU (SIDE_RIGHT :OR: SIDE_LEFT)

	export __main
;	export SystemInit
	export __use_two_region_memory
	export time_elapsed_fun
	export GetTick
	export print_string
	export print_header
	export print_char
	export get_side_name
	EXPORT  USART2_IRQHandler
		
	import GPIO_INIT
	import buttonSample
	import buttonStable
	import buttonPressedFiltered
	import consumeButtonPress
	import led_write
__use_two_region_memory


	ALIGN
__main
	ENTRY
MAIN
	; zero out variables in the data section
	zero_address systemTicks
	zero_address is_paused
	
	mov r0, #CONFIG_IDLE
	store_address config_state, r0
	
	;initialize parameter modifiable at runtime
	ldr r0, =test_length_min_default
	store_address test_length_min, r0
	ldr r0, =test_length_max_default
	store_address test_length_max, r0
	ldr r0, =idle_blink_period_default
	store_address idle_blink_period, r0
	ldr r0, =rgb_brightness_default
	store_address rgb_brightness, r0
	
	ldr r0, =press_timeout_default
	store_address press_timeout, r0
	
	; Initialize the peripherals
	BL GPIO_INIT
	bl initUSART
	bl initSPI
	bl initDMA
	
	;update the Neopixel RGB LED
	ldr r0, =RGB_BLUE
	bl rgbDisplay

	;print the welcome message
	ldr r0, =welcomeMessage
	bl print_string

	call1 SYSTICK_INIT, systick_freq
		
	bl get_random_led ; turn one random led on
	store_address led_on_mask, r0
	
	call1 fsm_transition, STATE_BEFORE_TEST
	
ENDLESS_LOOP
	bl fsm_tick
	b ENDLESS_LOOP

update_leds proc
	push {r0-r1, lr}
	load_address led_on_mask, r2 ; bitmask of all leds to be enabled
	
	mov r0, #SIDE_RIGHT
	and r1, r2, #SIDE_RIGHT
	bl led_write

	mov r0, #SIDE_LEFT
	and r1, r2, #SIDE_LEFT
	bl led_write
	
	pop {r0-r1, pc}	
	endp	
	
generate_next_test proc
	push {r0-r2, lr}
	;deactivate LEDs
	zero_address led_on_mask
	; generate random test delay
	load_address test_length_min, r0
	load_address test_length_max, r1
	bl random
	store_address test_length, r0
	;transition to new state
	call1 fsm_transition, STATE_TEST_DELAY
	
	;Choose one side (random number in range [1, 2]), activate said LED and store the index for later processing
	bl get_random_led
	store_address tested_side, r0 ;store for the future

	; do not increment the test counter. Do it only when the test ends
	bl print_header
	ldr r0, =strNewTest1
	bl print_string
	load_address test_length, r0
	mov r1, #0
	bl num2str
	bl print_string
	
	ldr r0, =strNewTest2
	bl print_string
	
	load_address tested_side, r0
	bl get_side_name
	bl print_string
	mov r0, #'.'
	bl print_char
	ldr r0, =strLineBreak
	bl print_string
	
	pop {r0-r2, pc}
	endp

get_random_led proc
	push {r1, lr}
	mov r0, #SIDE_RIGHT
	mov r1, #SIDE_LEFT
	bl random
	pop {r1, pc}
	endp
		
	ALIGN
	LTORG

; one tick of the state machine logic.
; reads inputs, transitions between states etc
fsm_tick proc
	push {r0-r3, lr}
	bl buttonSample
	bl handle_buttons
	
	; if the application is paused, do not continue with the logic.
	load_address is_paused, r0
	if_true r0, RETURN_FROM_TICK
	
	bl update_leds
	load_address fsm_state, r0
	ldr r1, =FSM_CASE_TABLE
	tbh [r1, r0, lsl #1]
FSM_HANDLE_BEFORE_TEST	
	load_address idle_blink_period, r1
	load_address fsm_lastTransition, r0
	bl time_elapsed_fun
	if_false r0, RETURN_FROM_TICK
	
	toggle_bits led_on_mask, #SIDE_BOTH
	
	;enter the same state to reset the timer (needed for led toggling)
	call1 fsm_transition, STATE_BEFORE_TEST
	B RETURN_FROM_TICK
	
FSM_HANDLE_TEST_DELAY
	load_address test_length, r1
	load_address fsm_lastTransition, r0
	bl time_elapsed_fun
	; if the random time has not elapsed yet, return
	if_false r0, RETURN_FROM_TICK
	
	; the test time has elapsed, activate the LED.
	load_address tested_side, r0
	store_address led_on_mask, r0
	call1 fsm_transition, STATE_TEST_WAIT_FOR_USER
	
	bl print_header
	ldr r0, =strWaiting
	bl print_string
	load_address tested_side, r0
	bl get_side_name
	bl print_string
	ldr r0, =strLineBreak
	bl print_string
	
	
	b RETURN_FROM_TICK	

FSM_HANDLE_TEST_WAIT_FOR_USER
	load_address press_timeout, r1
	load_address fsm_lastTransition, r0
	bl time_elapsed_fun
	if_false r0, RETURN_FROM_TICK
	;the user did not manage to react
	mov r0, #SIDE_MIDDLE
	mov r1, #FAILURE_TOO_LATE
	bl handle_failure
	B RETURN_FROM_TICK
	
FSM_HANDLE_MISSED
	time_elapsed fsm_lastTransition, mistake_on_time
	if_false r0, RETURN_FROM_TICK
	; the on time has elapsed. Deactivate both leds and start a new test
	zero_address led_on_mask
	bl generate_next_test
	b RETURN_FROM_TICK
		
RETURN_FROM_TICK
	pop {r0-r3, pc}	


	endp
		
	ALIGN
		
		
FSM_CASE_TABLE
	DCW (FSM_HANDLE_BEFORE_TEST - FSM_HANDLE_BEFORE_TEST)/2
	DCW (FSM_HANDLE_TEST_DELAY - FSM_HANDLE_BEFORE_TEST)/2
	DCW (FSM_HANDLE_TEST_WAIT_FOR_USER - FSM_HANDLE_BEFORE_TEST)/2
	DCW (FSM_HANDLE_MISSED - FSM_HANDLE_BEFORE_TEST)/2
	
	ALIGN
	
; returns in r0 - bool whether all buttons are stable
all_buttons_stable proc
	push {lr}
	call1 buttonStable, SIDE_MIDDLE
	if_false r0, RETURN_FALSE
	call1 buttonStable, SIDE_LEFT
	if_false r0, RETURN_FALSE
	call1 buttonStable, SIDE_RIGHT
	if_false r0, RETURN_FALSE
	mov r0, #1
	pop {pc}
RETURN_FALSE
	mov r0, #0
	pop {pc}
	endp
	
handle_buttons proc
	push {r0-r7, lr}
	; do not proceed unless all three buttons are stable (so that we don't need to check the state of "other" button all the time)
	bl all_buttons_stable
	if_false r0, RETURN_FROM_BUTTONS	
	
	;check the state of middle button (pausing/resuming)
	call1 consumeButtonPress, SIDE_MIDDLE
	if_false r0, MIDDLE_DONE ; middle button is not pressed, so skip handling it
	
	; the middle button is pressed -> toggle the paused state
	bl toggle_pause_state

MIDDLE_DONE
	; we are inside of a test. If no button is pressed, nothing is happening.
	call1 buttonPressedFiltered, SIDE_LEFT
	mov r1, r0
	call1 buttonPressedFiltered, SIDE_RIGHT
	orr r2, r0, r1
	if_false r2, RETURN_FROM_BUTTONS ; none of the buttons is pressed -> return

	tst r0, r1
	beq SINGLE_BUTTON_PRESSED
	
	call1 consumeButtonPress, SIDE_LEFT
	if_false r0, RETURN_FROM_BUTTONS
	call1 consumeButtonPress, SIDE_RIGHT
	if_false r0, RETURN_FROM_BUTTONS

	
	;both buttons are pressed -> end the series or start a new one
	bl series_in_progress
	if_false r0, DO_START
	; series already in progress -> end it.
	bl end_series
	b RETURN_FROM_BUTTONS
	
DO_START
	bl start_series
	b RETURN_FROM_BUTTONS
	
SINGLE_BUTTON_PRESSED
	;check the state of left/right buttons...
	load_address fsm_state, r0
	; only inspect button presses during the initial test delay or when waiting for user input
	value_in_range r0, r0, #STATE_TEST_DELAY, #STATE_TEST_WAIT_FOR_USER
	if_false r0, RETURN_FROM_BUTTONS

	load_address is_paused, r0
	if_true r0, RETURN_FROM_BUTTONS; do not count hits when the system is paused	

	call1 consumeButtonPress, SIDE_LEFT
	lsl r1, r0, #1
	call1 consumeButtonPress, SIDE_RIGHT
	orr r0, r1
	
	ldr r1, =BUTTON_STATE_TABLE
	tbh [r1, r0, lsl #1]
BOTH_PRESSED
NEITHER_PRESSED
	b RETURN_FROM_BUTTONS
LEFT_ONLY
	mov r0, #SIDE_LEFT
	b BUTTONS_CHOSEN
RIGHT_ONLY
	mov r0, #SIDE_RIGHT
	b BUTTONS_CHOSEN

	
BUTTON_STATE_TABLE
	DCW (NEITHER_PRESSED - BOTH_PRESSED)/2
	DCW (RIGHT_ONLY - BOTH_PRESSED)/2
	DCW (LEFT_ONLY - BOTH_PRESSED)/2
	DCW (BOTH_PRESSED - BOTH_PRESSED)/2	
	
BUTTONS_CHOSEN
	bl process_reaction
RETURN_FROM_BUTTONS
	pop {r0-r7, pc}
	endp
		
; takes one arg in r0 - constant identifying the side user responded on
process_reaction proc
	push {r0-r2, lr}
	mov r2, r0
	load_address fsm_state, r0
	cmp r0, #STATE_TEST_DELAY
	beq TOO_SOON_FAILURE ;the user pressed the button too early
	
	load_address tested_side, r0
	cmp r0, r2
	bne BAD_BUTTON_FAILURE ; if the user pressed the button on incorrect side, count it as failure
	
	;the user pressed the button correctly. Increment score
	bl handle_hit	
	b RETURN_FROM_PROCESS
BAD_BUTTON_FAILURE
	mov r1, #FAILURE_BAD_BUTTON
	b FAILURE
TOO_SOON_FAILURE
	mov r1, #FAILURE_TOO_SOON
FAILURE
	mov r0, r2
	bl handle_failure
RETURN_FROM_PROCESS
	pop {r0-r2, pc}	
	endp
		
; returns bool in r0 indicating, whether some test is in progress
series_in_progress proc
	load_address fsm_state, r0
	value_in_range r0, r0, #STATE_TEST_DELAY, #STATE_MISSED
	bx lr
	endp
	
start_series proc
	push {r0-r7, lr}
	bl series_in_progress
	if_true r0, SERIES_ALREADY_IN_PROGRESS
	
	copy systemTicks, series_start_timestamp	
	copy systemTicks, pause_start_timestamp
	zero_address pause_length_sum
	
	bl print_header
	ldr r0, =startMessage
	bl print_string
	
	;zero-out all counters of test data
	ldr r1, =TestDataBegin
	ldr r2, =TestDataEnd
	mov r0, #0
	
TEST_DATA_CLEAR_LOOP
	str r0, [r1], #4
	cmp r1, r2
	bne TEST_DATA_CLEAR_LOOP
	
	load_address press_timeout, r0
	lsl r0, #1 ;initialize best time variables to big values
	ldr r1, =reaction_time_best
	str r0, [r1]
	str r0, [r1, #4]
	str r0, [r1, #8]	
	
	bl generate_next_test
	
	b RETURN_FROM_START_SERIES
	
SERIES_ALREADY_IN_PROGRESS
	ldr r0, =strSeriesAlreadyStarted
	bl print_string	
RETURN_FROM_START_SERIES
	pop {r0-r7, pc}
	endp

	ALIGN
	LTORG
	
; takes r0 = constant identifying one side. Returns average time in r0
calculate_avg_reaction_time proc
	push {r1, r2, lr}
	ldr r1, =hit_counter
	ldr r1, [r1, r0, LSL #2]
	load_address press_timeout, r2
	cmp r1, #0
	itt eq
	lsleq r0, r2, #1
	beq RETURN_FROM_AVG
	
	ldr r2, =reaction_time_sum
	ldr r2, [r2, r0, LSL #2]
	udiv r0, r2, r1	
RETURN_FROM_AVG
	pop {r1, r2, pc}
	endp
	
; takes r0 = constant identifying left or right side
print_stats_of_side proc
	push {r0-r7, lr}
	mov r3, r0
	bl get_side_name
	mov r1, #5 ;min 5 charatcer to fit both "left" and "right"
	mov r2, #' '
	bl print_padded_string
	
	ldr r0, =statsMessageSide1
	bl print_string
	
	mov r1, #0
	ldr r0, =hit_counter
	ldr r4, [r0, r3, LSL #2]
	mov r0, r4
	bl num2str
	mov r1, #3
	mov r2, #' '
	bl print_padded_string
	
	ldr r0, =statsMessageSide2
	bl print_string
	
	ldr r0, =test_counter
	ldr r5, [r0, r3, LSL #2]
	mov r0, r5
	mov r1, #0
	bl num2str
	mov r1, #3
	mov r2, #' '
	bl print_padded_string
	
	ldr r0, =statsMessageSide3
	bl print_string
	
	cmp r5, #0
	beq HAD_NO_TESTS

HAD_SOME_TESTS	
	mov r0, #100 * 100
	mul r0, r4
	udiv r0, r5
	mov r1, #2
	bl num2str
	mov r1, #5
	mov r2, #' '
	bl print_padded_string
	b PRECISION_DONE
	
HAD_NO_TESTS
	ldr r0, =strNA
	mov r1, #5
	mov r2, #' '
	bl print_padded_string
	
PRECISION_DONE
	
	; precision
	ldr r0, =statsMessageSide4
	bl print_string
	
	cmp r4, #0
	bne HAD_SOME_HITS
	; not a single hit -> reaction time is just N/A
	ldr r0, =strNA
	bl print_string
	ldr r0, =strLineBreak
	bl print_string
	b RETURN_FROM_SIDE_STATS
	
HAD_SOME_HITS
	mov r0, r3
	bl calculate_avg_reaction_time
	mov r1, #0
	bl num2str
	mov r1, #4
	mov r2, #' '
	bl print_padded_string
	
	; average reaction time
	ldr r0, =statsMessageSide5
	bl print_string
	
	ldr r0, =reaction_time_best
	ldr r0, [r0, r3, LSL #2]
	mov r1, #0
	bl num2str
	mov r1, #4
	mov r2, #' '
	bl print_padded_string
	
	;best reaction time
	ldr r0, =statsMessageSide6
	bl print_string
RETURN_FROM_SIDE_STATS
	pop {r0-r7, pc}	
	endp
	
print_stats proc
	push {r0-r7, lr}
	; if no test is in progress, quit
	bl series_in_progress
	if_false r0, NO_TEST_IN_PROGRESS

	
	;test is in progress -> print stats
	
	ldr r0, =statsMessage1
	bl print_string
	
	load_address series_start_timestamp, r0
	bl get_time_elapsed
	mov r3, r0 ; r3 = length of test in ms
	
	ldr r4, =60*1000
	udiv r0, r3, r4
	mov r1, #0
	bl num2str
	bl print_string	
	
	ldr r0, =statsMessage2
	bl print_string
	
	modulo r0, r3, r4
	mov r1, #3
	bl num2str
	bl print_string
	
	ldr r0, =statsMessage3
	bl print_string
	
	load_address pause_length_sum, r0
	tst r0, r0
	beq HAD_NO_PAUSES
	
	ldr r4, =100*100
	mul r0, r4
	udiv r0, r3
HAD_NO_PAUSES
	mov r1, #2
	bl num2str
	bl print_string
	
	ldr r0, =statsMessage4
	bl print_string
	
	mov r0, #SIDE_LEFT
	bl print_stats_of_side
	mov r0, #SIDE_RIGHT
	bl print_stats_of_side
	b RETURN_FROM_PRINT_STATS
NO_TEST_IN_PROGRESS
	ldr r0, =strNoTestInProgress
	bl print_string
	
RETURN_FROM_PRINT_STATS
	pop {r0-r7, pc}
	endp

; takes no arguments. Ends the test, prints stats to stdout
end_series proc
	push {r0-r7, lr}
	bl series_in_progress
	if_false r0, NOTHING_TO_END
	
	load_address is_paused, r0
	if_false r0, NOT_PAUSED
	;handle case when the test is ended when paused. Make sure the time spent in pause is accounted for
	load_address pause_start_timestamp, r0
	bl get_time_elapsed
	increment_memory pause_length_sum, r0
	
NOT_PAUSED

	;update the Neopixel RGB LED
	ldr r0, =RGB_BLUE
	bl rgbDisplay
	copy rgb_color, rgb_color_before_pause
	
	bl print_header
	ldr r0, =strTestEnded
	bl print_string
	
	bl print_stats
	
	call1 fsm_transition, STATE_BEFORE_TEST	
	
	bl get_random_led ; turn one random led on
	store_address led_on_mask, r0
	
	b RETURN_FROM_END_SERIES
	
NOTHING_TO_END
	ldr r0, =strNoSeriesToEnd
	bl print_string
RETURN_FROM_END_SERIES
	pop {r0-r7, pc}
	endp
	
; takes constant identifying side in r0, returns correspoding string in r0
get_side_name proc
	cmp r0, #SIDE_LEFT
	beq ITS_LEFT
	cmp r0, #SIDE_RIGHT
	beq ITS_RIGHT
	b DUNNO
ITS_LEFT
	ldr r0, =strLeft
	bx lr
ITS_RIGHT
	ldr r0, =strRight
	bx lr
DUNNO
	ldr r0, =strMiddle
	bx lr
	endp
	
; takes two args in r0 - constant identifying the tested side
; and r1 - the cause of failure
; registers test failure, activates leds and enters STATE_MISSED
handle_failure proc
	push {r0-r4, lr}
	
	mov r4, r1
	mov r3, r0
	
	;update the Neopixel RGB LED
	ldr r0, =RGB_RED
	bl rgbDisplay
	
	bl print_header
	ldr r0, =strFailure
	bl print_string
		
	cmp r4, #FAILURE_TOO_LATE
	beq TOO_LATE
	cmp r4, #FAILURE_TOO_SOON
	beq TOO_SOON
	b BAD_BUTTON
	
TOO_SOON
	ldr r0, =strTooSoon1
	bl print_string
	mov r0, r3
	bl get_side_name
	bl print_string
	ldr r0, =strTooSoon2
	bl print_string
	b TAUNT_FINISHED
	
TOO_LATE
	ldr r0, =strTooLate
	bl print_string
	b TAUNT_FINISHED

BAD_BUTTON
	ldr r0, =strBadButton1
	bl print_string
	
	load_address tested_side, r0
	bl get_side_name
	bl print_string
	
	ldr r0, =strBadButton2
	bl print_string
	
	mov r0, r3
	bl get_side_name
	bl print_string
		
TAUNT_FINISHED	
	mov r0, #'.'
	bl print_char
	ldr r0, =strLineBreak
	bl print_string
	mov r0, #SIDE_BOTH
	store_address led_on_mask, r0
	call1 fsm_transition, STATE_MISSED
	
	; increment the test counter
	load_address tested_side, r3
	ldr r1, =test_counter
	ldr r2, [r1, r3, LSL #2]
	add r2, #1
	str r2, [r1, r3, LSL #2]
	
	pop {r0-r4, pc}
	endp
		
	ALIGN
	LTORG
	ALIGN
		
; takes one arg in r0 - constant identifying the tested side
handle_hit proc
	push {r1-r7, lr}
	mov r5, r0
	
	;update the Neopixel RGB LED
	ldr r0, =RGB_GREEN
	bl rgbDisplay
	
	bl print_header
	ldr r0, =strSuccess
	bl print_string
	
	;add the duration of this test to the sum
	load_address fsm_lastTransition, r0
	bl get_time_elapsed
	mov r4, r0
	mov r1, #0
	bl num2str
	bl print_string
	
	ldr r0, =strMilliseconds
	bl print_string
	mov r0, #'.'
	bl print_char
	mov r0, #' '
	bl print_char
	
	ldr r1, =reaction_time_best
	ldr r2, [r1, r5, LSL #2]
	cmp r2, r4
	
	ble NOT_THE_BEST_RESULT
	
	str r4, [r1, r5, LSL #2]
	
	ldr r0, =strNewBestTime
	bl print_string
	sub r0, r2, r4
	mov r1, #0
	bl num2str
	bl print_string
	ldr r0, =strMilliseconds
	bl print_string
	mov r0, #')'
	bl print_char
	mov r0, #'.'
	bl print_char
	
NOT_THE_BEST_RESULT	

	ldr r0, =strLineBreak
	bl print_string

	ldr r1, =reaction_time_sum
	ldr r2, [r1, r5, LSL #2]
	add r2, r4 
	str r2, [r1, r5, LSL #2]	
	
	; increment the hit counter
	ldr r1, =hit_counter
	ldr r2, [r1, r5, LSL #2]
	add r2, #1
	str r2, [r1, r5, LSL #2]
	
	; increment the test counter
	ldr r1, =test_counter
	ldr r2, [r1, r5, LSL #2]
	add r2, #1
	str r2, [r1, r5, LSL #2]
	
	bl generate_next_test	
	pop {r1-r7, pc}
	endp
		
toggle_pause_state proc
	push {r0-r1, lr}
	
	bl print_header
	
	load_address is_paused, r0
	eor r1, r0, #1 ; toggle the bottom bit
	store_address is_paused, r1
	
	; print whether we have paused or resumed the test
	tst r1, r1
	beq RESUMED
PAUSED
	ldr r0, =pausedMessage
	bl print_string
	copy systemTicks, pause_start_timestamp ; store the current timestamp for later compuation
	
	copy rgb_color, rgb_color_before_pause ;store the previous color for later restoration
	;update the Neopixel RGB LED
	ldr r0, =RGB_WHITE
	bl rgbDisplay
	
	b RETURN_FROM_PAUSE
RESUMED

	; restore previous state of neopixel RGB
	load_address rgb_color_before_pause, r0
	bl rgbDisplay
	
	ldr r0, =resumedMessage1
	bl print_string
	
	load_address pause_start_timestamp, r0
	bl get_time_elapsed ; r0 = number of ms elapsed during pause. Use it to adjust fsm timing
	increment_memory fsm_lastTransition, r0
	increment_memory pause_length_sum, r0
	
	mov r1, #3
	bl num2str
	bl print_string
	ldr r0, =resumedMessage2
	bl print_string	
RETURN_FROM_PAUSE
	pop {r0-r1, pc}
	endp		
	
; returns a random integer in range [r0, r1]
random proc
	push {r1-r3}
	;does not work, because the loop appears to be somehow synchronized with systick period...
	;load_address STK_VAL, r0 ; take the current value of systick counter 
	sub r2, r1, r0 
	add r2, #1; the number of permissible values
	
	load_address systemTicks, r3
	modulo r1, r3, r2 ; r1 = r3 % r2
	add r0, r1		; add the min value
	pop {r1-r3}
	bx lr
	
	endp
	
	
; takes a single argument in r0 - enumerator representing the nest state
; transitions the state machine to the next state, keeping record of the transition time
fsm_transition proc
	store_address fsm_state, r0
	copy systemTicks, fsm_lastTransition
	bx lr
	endp

systick_hook proc
	; not needed, empty
	bx lr	
	endp

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
	push {lr}
	increment_memory systemTicks, #1
	bl systick_hook
	
	pop {pc}
	ENDP
	

GetTick proc; returns the current time in ms in r0
    load_address systemTicks, r0
    bx lr
	endp
		
		
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
	
; Prints surrent time to stdout
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
RETURN_FROM_TO_UPPER
	pop {r1-r3, pc}
	endp

apostrophSpaceParen
	DCB "' ('", 0
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
	
	mov r0, #'\r'
	bl print_char
	
	mov r0, #' '
	mov r1, #112
	bl print_repeated_char
	
	mov r0, #'\r'
	bl print_char
	
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
	cmp r0, #'T'
	beq CMD_START
	cmp r0, #'S'
	beq CMD_START
	cmp r0, #'Q'
	beq CMD_QUIT
	cmp r0, #'R'
	beq CMD_RESULTS
	cmp r0, #'P'
	beq CMD_PAUSE
	cmp r0, #'5'
	beq CMD_PAUSE
	cmp r0, #'4'
	beq CMD_REACTION
	cmp r0, #'6'
	beq CMD_REACTION
	cmp r0, #'C'
	beq CMD_CONFIG
	ldr r0, =strNotRecognized
	bl print_string
	b RETURN_FROM_CMD

CMD_CONFIG
	bl config_start
	b RETURN_FROM_CMD
CMD_REACTION
	cmp r0, #'6'
	moveq r0, #SIDE_RIGHT
	movne r0, #SIDE_LEFT
	bl process_reaction
	b RETURN_FROM_CMD	
CMD_START
	bl start_series
	b RETURN_FROM_CMD
CMD_QUIT
	bl end_series
	b RETURN_FROM_CMD
CMD_PAUSE
	bl toggle_pause_state
	b RETURN_FROM_CMD
CMD_RESULTS
	bl print_stats	
RETURN_FROM_CMD
	pop {r0-r7, pc}
	endp
		
config_start proc
	push {r0-r2, lr}
	;start configuration if possible
	bl print_header
	load_address is_paused, r0
	if_false r0, CANNOT_CONFIGURE
	
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
test_length_min_name
	DCB "TEST_LENGTH_MIN", 0
	
test_length_max_name
	DCB "TEST_LENGTH_MAX", 0
	
idle_blink_period_name
	DCB "IDLE_BLINK_PERIOD", 0
	
press_timeout_name
	DCB "PRESS_TIMEOUT", 0
	
rgb_brightness_name
	DCB "RGB_BRIGHTNESS", 0
	
	ALIGN
		
config_end proc
	push {r0-r7, lr}
	ldr r0, =config_value
	mov r1, #10
	bl str2num
	push {r0} ;store the value for later use
	
	;parse the parameter name
TRY_TEST_LENGTH_MIN
	ldr r0, =config_name
	ldr r1, =test_length_min_name
	bl strcmp
	tst r0, r0
	bne TRY_IDLE_BLINK_PERIOD
	ldr r1, =test_length_min
	b PARAMETER_FOUND
	
TRY_IDLE_BLINK_PERIOD
	ldr r0, =config_name
	ldr r1, =idle_blink_period_name
	bl strcmp
	tst r0, r0
	bne TRY_PRESS_TIMEOUT
	ldr r1, =idle_blink_period
	b PARAMETER_FOUND
	
TRY_PRESS_TIMEOUT
	ldr r0, =config_name
	ldr r1, =press_timeout_name
	bl strcmp
	tst r0, r0
	bne TRY_RGB_BRIGHTNESS
	ldr r1, =press_timeout
	b PARAMETER_FOUND
	
TRY_RGB_BRIGHTNESS
	ldr r0, =config_name
	ldr r1, =rgb_brightness_name
	bl strcmp
	tst r0, r0
	bne TRY_TEST_LENGTH_MAX
	ldr r1, =rgb_brightness
	b PARAMETER_FOUND

TRY_TEST_LENGTH_MAX
	ldr r0, =config_name
	ldr r1, =test_length_max_name
	bl strcmp
	tst r0, r0
	bne NO_PARAM_FOUND
	ldr r1, =test_length_max
	b PARAMETER_FOUND
	
PARAMETER_FOUND
	;write the new value to corresponding memory location
	pop {r5}
	str r5, [r1]
	
	ldr r2, =rgb_brightness
	cmp r1, r2 ;RGB LED needs to be refreshed with new brightness...
	bne NO_REFRESH_NEEDED
	load_address rgb_color, r0
	bl rgbDisplay
	
NO_REFRESH_NEEDED
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

	ALIGN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	SPI driver
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	area SPI_data, data, noinit, readwrite
RGB_DATA_LENGTH EQU 24
RGB_LOG_ZERO EQU 2_10000
RGB_LOG_ONE EQU  2_11110
	
RGB_RED EQU 0xff0000
RGB_GREEN EQU 0x00ff00
RGB_BLUE EQU 0x0000ff
RGB_WHITE EQU 0xffffff
	
rgb_data space RGB_DATA_LENGTH
rgb_color_before_pause space 4
rgb_color space 4	
	
	ALIGN
		
	area SPI_driver, code, readonly
		
;takes one value in r0 - hex code of 24 bit color to display 0xrr'gg'bb
rgbDisplay proc
	push {r0-r6, lr}
	
	store_address rgb_color, r0
	
	;accoutn for decreased brightness
	load_address rgb_brightness, r1
	mov r2, #3
	b BRIGHTNESS_ADJUSTMENT_COND
BRIGHTNESS_ADJUSTMENT_LOOP
	sub r2, #1
	mov r4, #8
	mul r4, r2 ; bit shift for this byte
	lsr r3, r0, r4 ;shift given word to bottom byte
	and r3, #0xff
	;r3 = r3 *brightness / max_brightness
	mul r3, r1
	mov r5, #rgb_brightness_max
	udiv r3, r5	
	lsl r3, r4
	; bitwise or the modified byte back to the original word
	mov r6, #0xff
	lsl r6, r4
	bic r0, r6
	orr r0, r3
	
BRIGHTNESS_ADJUSTMENT_COND
	tst r2, r2
	bne BRIGHTNESS_ADJUSTMENT_LOOP
	
	
	load_address DMA1_Channel3_CCR, r1
	bic r1, #DMA_CCR_EN ; disable the channel
	store_address DMA1_Channel3_CCR, r1
	
	mov r1, #1 :SHL: (RGB_DATA_LENGTH-1)
	ldr r2, =rgb_data
BIT_EXTRACTION_LOOP
	tst r0, r1
	movne r3, #RGB_LOG_ONE
	moveq r3, #RGB_LOG_ZERO
	strb r3, [r2], #1
	lsr r1, #1
	tst r1, r1 ; more bits to go
	bne BIT_EXTRACTION_LOOP

	;start the DMA transmission
	; number of data
	mov r0, #RGB_DATA_LENGTH
	store_address DMA1_Channel3_CNDTR, r0
	load_address DMA1_Channel3_CCR, r0
	orr r0, #DMA_CCR_EN ; set the enable bit
	store_address DMA1_Channel3_CCR, r0
	
	pop {r0-r6, pc}
	endp

; DMA1 channel 3 is connected to SPI1_TX
initDMA proc
	push {r0-r1, lr}
	load_address RCC_AHBENR, r0
	orr r0, #RCC_AHBENR_DMA1EN
	store_address RCC_AHBENR, r0
	
	; peripheral address
	ldr r0, =SPI1_DR
	store_address DMA1_Channel3_CPAR, r0
	
	; memory address
	ldr r0, =rgb_data
	store_address DMA1_Channel3_CMAR, r0

	load_address DMA1_Channel3_CCR, r0
	;not memory 2 memory, priority is ok low, memory and periph size 8 bits by default
	;increment memory; read from memory and write to periph
	ldr r1, =DMA_CCR_MINC :OR: DMA_CCR_DIR
	orr r0, r1
	store_address DMA1_Channel3_CCR, r0
	
	pop {r0-r1, pc}
	endp


; initializes SPI1 for communication with Neopixel RGB LED
initSPI proc
	push {r0-r1, lr}
	;enable clock for the spi peripheral
	load_address RCC_APB2ENR, r0
	orr r0, #RCC_APB2ENR_SPI1EN
	store_address RCC_APB2ENR, r0
	
	load_address SPI1_CR2, r0
	ldr r1, =SPI_CR2_DS_2 :OR: SPI_CR2_TXDMAEN ;5 bits of data, enable DMA transmission
	orr r0, r1	
	store_address SPI1_CR2, r0
	
	load_address SPI1_CR1, r0
	;software slave management (none) and pull internal slave select high; enable SPI
	; keep BR == 0, that means frequency 4 MHz -> 5 bits per Neopixel period
	; ignore clock configuration
	ldr r1, =SPI_CR1_SSM :OR: SPI_CR1_SSI :OR: SPI_CR1_SPE :OR: SPI_CR1_MSTR
	orr r0, r1
	store_address SPI1_CR1, r0
	
	zero_address rgb_color
	zero_address rgb_color_before_pause
	pop {r0-r1, pc}	
	endp

	ALIGN
	
	END