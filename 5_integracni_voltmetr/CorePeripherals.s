;********************************************************************************
;* JMÉNO SOUBORU	: CorePeripherals.S
;* AUTOR			: Vojtech Michal
;* DATUM			: 6.10.2020
;* POPIS			: File containing definitions for core peripherals
;********************************************************************************


	AREA    STM32F10x_INI, CODE, READONLY    



 
;********************************************************************************
;*   				SysTick				 	  	*
;********************************************************************************
;SysTick Registers 
;-------------------------------------------------------------------------------- 
STK_BASE            EQU     0xE000E010

STK_CTRL			EQU		STK_BASE + 0
STK_LOAD	 		EQU		STK_BASE + 0x4
STK_VAL	 		    EQU		STK_BASE + 0x8
STK_CALIB	 		EQU		STK_BASE + 0xc 
    
; bit flags

STK_CTRL_COUNTFLAG  EQU     1:SHL:16
STK_CTRL_CLKSOURCE  EQU     1:SHL:2
STK_CTRL_TICKINT    EQU     1:SHL:1
STK_CTRL_ENABLE     EQU     1:SHL:0
    
    
    END