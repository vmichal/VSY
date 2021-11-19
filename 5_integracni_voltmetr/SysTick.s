



    AREA MOJEDATA, DATA, NOINIT, READWRITE
    
SystemTicks SPACE 4
    
    
    
    AREA    SystickDriver, CODE, READONLY  
        
	get stm32f303xe.s
    
    EXPORT STK_CONFIG
    export GetTick
    export TimeElapsed
    EXPORT SysTick_Handler        
    EXPORT BlockingDelay
        
;**************************************************************************************************
;* Jmeno funkce		: STK_CONFIG
;* Popis			: Konfigurace Systicku na interrupt kazdou milisekundu
;* Vstup			: r0 .. reload value for SysTick
;* Vystup			: Zadny
;**************************************************************************************************
STK_CONFIG								; Navesti zacatku podprogramu
; System clock runs at 24MHz speed

    push {r1, r2, lr}

    LDR r1, =SystemTicks ;clear the memory location for SystemTicks
    mov r2, #0
    str r2, [r1]

    LDR r1, =STK_LOAD ;configure reload register to 24 000 ticks
    str r0, [r1]
    
    LDR r0, =STK_VAL ; clear the value register
    mov r1, #0
    str r1, [r0]
    
    LDR R0, =STK_CTRL
    mov r1, #STK_CTRL_TICKINT :OR: STK_CTRL_ENABLE :OR: STK_CTRL_CLKSOURCE ; enable interrupt and the counter
    STR r1,  [r0]   
    
    pop {r1,r2,pc}
    

;**************************************************************************************************
;* Jmeno funkce		: SysTick_Handler
;* Popis			: Interrupt service routine for systick
;* Vstup			: Zadny
;* Vystup			: Zadny
;**************************************************************************************************
SysTick_Handler								; Navesti zacatku podprogramu
; System clock runs at 24MHz speed
    push {lr}
    ldr r0, =SystemTicks
    ldr r1, [r0]
    add r1, #1    
    str r1, [r0]
    
    import buttonSample
    bl buttonSample
    import applicationTick
    bl applicationTick
    pop {pc}
    

    
TimeElapsed;(duration, start) returns one if the time given on r0 has elapsed since time given in r1
    push {r2, lr}
    
    mov r2, r0; move the duration to r2
    bl GetTick ; get the current time
    sub r0, r0, r1; r0 = now() - start
    cmp r0, r2
    
    ite hs
    movhs r0, #1 ; mov zero or one into the register r0
    movlo r0, #0
    
    pop {r2, pc}
    
;**************************************************************************************************
;* Jmeno funkce		: BlockingDelay
;* Popis			: Softwarove zpozdeni procesoru
;* Vstup			: R0 = pocet opakovani cyklu spozdeni
;* Vystup			: Zadny
;* Komentar			: Podprodram zpozdi prubech vykonavani programu	
;**************************************************************************************************
BlockingDelay 									; Navesti zacatku podprogramu
				PUSH	{R2,r1,lr}		; Ulozeni hodnoty R2 do zasobniku (R2 muze byt editovan)
										; a ulozeni navratove adresy do zasobniku
                
                mov r2, r0 ; store the number of ms to wait
                bl GetTick ; get the starting time
                mov r1, r0
                
loop            mov r0, r2 ; get r0 = duration and r1 = starting timestamp
                bl TimeElapsed
                tst r0, r0 ; one is returned as true
                beq loop ; loop if not enough time has passed
	
				POP		{R2,r1,PC}		; Navrat z podprogramu, obnoveni hodnoty R2 ze zasobniku
										; a navratove adresy do PC

;**************************************************************************************************


    END    