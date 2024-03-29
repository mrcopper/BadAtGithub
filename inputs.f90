MODULE INPUTS

  USE GLOBAL
  USE ParallelVariables
  USE VARTYPES
!a module to read and store inputs from input.dat
!should only be used in onebox.f90
!variables will be global to eliminate the need for passing variables

real                  ::source, source_exp, o_to_s, transport, tehot
real                  ::neutral_amp, neutral_t0, neutral_width
real                  ::hote_amp, hote_t0, hote_width, run_days
real                  ::per_day, expv_r0, fehot_exp

CONTAINS

subroutine readInputs()
  open(unit=100, file='inputs.dat', status='old')

  read(100,*) source
  read(100,*) source_exp
  read(100,*) o_to_s
  read(100,*) fehot_const  !declared in global module
  read(100,*) fehot_exp  !declared in global module
  read(100,*) transport
  read(100,*) tehot
  read(100,*) lag_const  !declared in global module
  read(100,*) neutral_amp
  read(100,*) neutral_t0
  read(100,*) neutral_width
  read(100,*) hote_amp
  read(100,*) hote_t0
  read(100,*) hote_width
  read(100,*) run_days
  read(100,*) per_day
  read(100,*) numerical_s
  read(100,*) v_r0
  read(100,*) expv_r0

  close(100)
end subroutine readInputs

END MODULE
