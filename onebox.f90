!#########################################
!           Matthew Copper
! One box model of io plasma torus
! Based on IDL program by Andrew Steffl 
! Started on 2/25/2013
!#########################################

PROGRAM Onebox

  USE DEBUG
  USE FUNCTIONS
  USE TIMESTEP 
  USE ReadEmis
  USE INPUTS
  USE FTMIX
  USE PARALLELVARIABLES
  USE OUTPUTS
  USE MPI

  IMPLICIT NONE
  character(len=8)    ::x1

  call MPI_INIT(ierr)
  call MPI_COMM_RANK(MPI_COMM_WORLD, mype, ierr)
  call MPI_COMM_SIZE(MPI_COMM_WORLD, npes, ierr)
  
  lnggrid=mod(mype,LNG_GRID)+1
  radgrid=(mype/LNG_GRID)+1

  write (x1, '(I3.3)') mype !write the integer 'mygrid' to non-existent file
 
  num_char=trim(x1)  !trim non-existent file and store as num_char
  !num_char can be used to name output files by grid space using "output"//num_char//".dat" 

  if ( npes .ne. LNG_GRID*RAD_GRID ) then
    print *, "The current version only supports ", LNG_GRID*RAD_GRID, " processors."   
  else 
   call model()
  endif

call MPI_FINALIZE(ierr)

CONTAINS 

subroutine model()
  integer             ::nit
  real                ::lontemp, day, source_tot, trans_tot
  real                ::tm, tm0, source_mult
  type(density)       ::n, ni, np
  real                ::const
  type(temp)          ::T, Ti, Tp
  real                ::Te0, Ti0, Teh0
  type(height)        ::h, hi
  type(r_ind)         ::ind
  type(nT)            ::nrg, nTi, nTp
  integer             ::i, j, k
  real                ::var, n_height
  type(nu)            ::v, vi
  type(r_dep)         ::dep, depi
  type(lat_dist)      ::lat, lati
  type(ft_int)        ::ft
  type(energy)        ::nrgy
  type(ft_mix)        ::plot
  real                ::output_it
  character(len=8)    ::x1
  character(len=4)    ::day_char
  integer             ::file_num
  real                ::longitude, elecHot_multiplier, intensity, n_ave, T_ave, test_multiplier, volume

!  call initNu(v)
  longitude = (mype * 360.0 / LNG_GRID)

  do i=1, LAT_SIZE
    lat%z(i)= (i-1) * Rj / 5.0  !Initializing lat%z
  end do

  call readInputs()  !call to input.f90 module to read initial variables from 'input.dat'
!print *, source
  call read_rec_tables()

!set trans_ variables (user prompt or formatted file migh be used in the future)
  trans_exp=1.0
  trans_type=.false.

!set dt (2000)
  dt=1000.0
!  source = source *2000.0/dt

!set run time
  runt=run_days*8.64e4 !one day = 86400 seconds

  nit=(runt/dt)+1 ! number of iterations to reach run_days

!set radial distance
!  rdist= 6   !in Rj
  dr=(3.0/(RAD_GRID-1))*Rj
  rdist= 6.0+dr*(radgrid-1)/Rj   !in Rj
  volume=PI*((((rdist*Rj + dr)*1e5))**2 - (rdist*Rj*1e5)**2)
!  print *, volume*(ROOTPI*Rj*.5*1e5)
!  source=source/volume
!  source = source * (rdist/6.0)**source_exp
!  source = source*((6.0**source_exp)*(source_exp+1.0))/((9.0**(source_exp+1.0))-(6.0**(source_exp+1.0)))
  net_source= (source/((6.0**source_exp)*(source_exp+1.0)*(dr/Rj)))*((rdist+(dr/Rj))**(source_exp+1.0) - (rdist**(source_exp+1.0)))
  call MPI_ALLREDUCE(net_source, source_tot, 1, MPI_REAL, MPI_SUM, MPI_COMM_WORLD, ierr)
  var=net_source
  net_source=net_source*(source/source_tot)
  if (mype .eq. 0) then
    print*, "TOTAL SOURCE", var, net_source, source_tot
  endif
  call MPI_ALLREDUCE(net_source, source_tot, 1, MPI_REAL, MPI_SUM, MPI_COMM_WORLD, ierr)
  if (mype .eq. 0) then
    print*, "TOTAL SOURCE",  source_tot
  endif
  net_source=net_source/volume
  print *, mype, "is at the radial distance", rdist, "Rj, with volumetric source ",  net_source/(ROOTPI*Rj*1e5*.5), " /cm3s"
!  print *, source/(ROOTPI*Rj*1e5*.5)
  


  torus_circumference = Rj * rdist * 2 * PI
  dx = torus_circumference / LNG_GRID
  numerical_c_neutral = v_neutral*dt/dx
  numerical_c_ion = v_ion*dt/dx

!set sys3 longitude of box
  lon3=110

!set zoff
  zoff= abs(6.4* cos((lon3-longitude) * dTOr) * dTOr * rdist * Rj) !in km

  n_height = Rj/2.0

  tm0=0.01

!set density values
  const=1800.0

  test_multiplier=1.0
  if( test_pattern ) then
    test_multiplier= 1.0+0.5*cos(2*longitude*dTOr)
  endif

  n%sp = 0.060 * const * test_multiplier * (rdist/6.0)**source_exp
  n%s2p= 0.212 * const * test_multiplier* (rdist/6.0)**source_exp
  n%s3p= 0.034 * const * test_multiplier* (rdist/6.0)**source_exp
  n%op = 0.242 * const * test_multiplier* (rdist/6.0)**source_exp
  n%o2p= 0.123 * n%op

  n%s=25.0 * test_multiplier* (rdist/6.0)**source_exp
  n%o=50.0 * test_multiplier* (rdist/6.0)**source_exp


  Te0 = 5.0
  Ti0 = 70.0
  Teh0= tehot*(rdist/6.0)**5.5
  fehot_const= fehot_const*(rdist/6.0)**fehot_exp
!  trans = 4.62963e-7
!  trans = 1.0/((v_r0/dr)*86400.0) 
!  net_source = source*(6.0/rdist)**20 ! ~6.3e6 fix FIX
!  if (radgrid .eq. 1 ) net_source = source

!  do i=1, RAD_GRID
!    source_mult=source_mult+1.0/(10.0**i)
!  end do 

!  net_source=(source/((10.0**radgrid)*source_mult))

  n%elec = (n%sp + n%op + 2 * (n%s2p + n%o2p) + 3 * n%s3p) * (1.0 - n%protons)
  n%elecHot = n%fh * n%elec / (1.0-n%fh)
  n%fc = 1.0 - n%fh

!set temp values
  T%sp      = Ti0
  T%s2p     = Ti0
  T%s3p     = Ti0
  T%op      = Ti0
  T%o2p     = Ti0
  T%elec    = Te0
  T%elecHot = Teh0
  

!get scale heights 
  call get_scale_heights(h, T, n)

  if (protons > 0.0) then
    n%protons = protons
  endif

  ind%o_to_s= o_to_s
  ind%o2s_spike=2.0

!  v_r0=v_r0*(rdist/6.0)**expv_r0
  v_r0= (v_r0/((6.0**expv_r0)*(expv_r0+1.0)*(dr/Rj)))*((rdist+(dr/Rj))**(expv_r0+1.0) - (rdist**(expv_r0+1.0)))
  call MPI_ALLREDUCE(dr/v_r0, trans_tot, 1, MPI_REAL, MPI_SUM, MPI_COMM_WORLD, ierr)
  if(mype .eq. 0) then
    print *, "TOTAL RANSPORT TIME:::", trans_tot
  endif 
!  net_source= (source/((6.0**source_exp)*(source_exp+1.0)*dr))*((rdist+dr)**(source_exp+1.0) - (rdist**(source_exp+1.0)))
  numerical_c_r=v_r0*dt/dr
 
    write(*,*) rdist, net_source/(ROOTPI*Rj*1e5*.5)  
    write(*,*) rdist, dr/v_r0 
if( mype .eq. 0 ) then 
  open(unit=320, file='AllSource.dat', status='replace', position='append')
    write(320,*) rdist, net_source/(ROOTPI*Rj*1e5*.5)  
  close(320)
  open(unit=330, file='AllTrans.dat', status='replace', position='append')
    write(330,*) rdist, dr/v_r0  
  close(330)
endif
call MPI_BARRIER(MPI_COMM_WORLD, ierr)
do i=1, npes-1
  if(mype .eq. i) then
    open(unit=320, file='AllSource.dat', status='old', position='append')
      write(320,*) rdist, net_source/(ROOTPI*Rj*1e5*.5)  
    close(320)
    open(unit=330, file='AllTrans.dat', status='old', position='append')
      write(330,*) rdist, dr/v_r0  
    close(330)
  endif
  call MPI_BARRIER(MPI_COMM_WORLD, ierr)
enddo

!  transport = (v_r0/dr)*86400.0 
  transport = transport * (6.0/rdist)**5.6

  tau0=transport !1.0/(trans*8.64e4)
  net_source0=net_source 
  !fh0 = fehot_const

  h%s=n_height
  h%o=n_height

  call InitIndependentRates(ind)

  T%pu_s = Tpu(32.0, rdist*1.0)
  T%pu_o = Tpu(16.0, rdist*1.0)

  T%elecHot=Teh0

  call independent_rates(ind, T, h)

  n%fc= 1.0 - n%fh   

  n%elec = ((n%sp + n%op) + 2.0*(n%s2p + n%o2p) + 3.0 * n%s3p)/(1.0-n%protons)
  n%elecHot = n%elec * n%fh/n%fc
  nrg%elec = n%elec * T%elec
  nrg%elecHot = n%elecHot * T%elecHot
  nrg%sp = n%sp * T%sp
  nrg%s2p = n%s2p * T%s2p
  nrg%s3p = n%s3p * T%s3p
  nrg%op = n%op * T%op
  nrg%o2p = n%o2p * T%o2p

  ni=n
  np=n

  Ti=T
  Tp=T

  hi=h
 
  nTi=nrg
  nTp=nrg

  vi=v

  lati=lat

  call get_scale_heights(h, T, n)

  output_it = 0 !This variable determine when data is output. 
  Io_loc=0      !Io's location in the torus
  sys4_loc=0    !The location of the sys4 hot electron population
  file_num=0    !Output files are numbered so they can be assembled as a animated visualization (refer to scripts)

  do i=1, nit
!    if( mype .eq. 0 ) then
!      print *, "((((((((((((((((((( i = ", i, " )))))))))))))))))))"
!    endif
    tm = tm0 + (i-1) * dt / 86400

    var =exp(-((tm-neutral_t0)/neutral_width)**2)

  !  net_source = net_source0*(1.0 + neutral_amp*var) !Ubiquitous source
    if( moving_Io ) then
      if( mype .eq. int(Io_loc*LNG_GRID/torus_circumference) )then
        net_source = LNG_GRID*net_source0*(1.0+neutral_amp*var)
      else
        if( i .eq. 1 ) then
          net_source = net_source0*(1.0+neutral_amp*var)
        else
          net_source=0
        endif
      endif
    endif

    if( .not. moving_Io ) then
      net_source = (net_source0*(1.0 + neutral_amp*var))!/LNG_GRID !ubiquitous
    endif

    ind%o_to_s = o_to_s
!    ind%o_to_s = (otos + o2s_spike * neutral_amp * var) & !o2s_spike
!               / (1.0 + neutral_amp * var)
    n%fh  = fehot_const * (1.0 + hote_amp * var)

    elecHot_multiplier=1.0

    if( sys3hot ) then
      elecHot_multiplier=elecHot_multiplier+sys3_amp*(sin((lon3-longitude)*dTOr))
    endif

    if( sys4hot ) then
      elecHot_multiplier=elecHot_multiplier&
             +sys4_amp*cos(((mype/(LNG_GRID-1.0))-(sys4_loc/torus_circumference))*2.0*PI)
    endif

    n%fh  = fehot_const * (1.0 + hote_amp * var)*elecHot_multiplier

    ni%fh = n%fh
    np%fh = n%fh

    n%fc  = 1.0 - n%fh
    ni%fc = n%fc
    np%fc = n%fc

    n%elecHot = n%elec * n%fh/n%fc
    nrg%elecHot = n%elecHot * T%elecHot

    do j=1, LAT_SIZE
      lat%elecHot(j) = n%elecHot
      lati%elecHot(j) = n%elecHot
    end do

    if ( DEBUG_GEN ) then !this variable set in debug.f90
      call DebugOutput(i, n, h, T, v, nrg)
    endif

    call cm3_latavg_model(n, T, nrg, h, v, ni, Ti, nTi, hi &
                         ,vi, np, Tp, nTp, ind, dep, depi, lat, lati, ft, zoff) 

    call update_temp(n, nrg, T)

    call get_scale_heights(h, T, n)

    call energyBudget(n, h, T, dep, ind, ft, lat, v, nrgy)

    if (nint(output_it)+1 .eq. i .and. (OUTPUT_MIXR .or. OUTPUT_DENS .or. OUTPUT_TEMP .or. OUTPUT_INTS)) then !Output at set intervals when OUTPUT_MIX is true (from debug.f90)
        day = (i-1.0)*dt/86400
        write (x1, '(I4.4)') file_num
        day_char=trim(x1)  !trim non-existent file and store as day_char
        !if( mype .eq. 0 ) then
        !endif
        call dens_ave(n_ave, n) 
        call temp_ave(T_ave, T) 
        do k=0, RAD_GRID-1
          do j=0, LNG_GRID
            if( mype .eq. mod(j,LNG_GRID)+(k*LNG_GRID)) then
              if(OUTPUT_DENS) call IonElecOutput(n%sp, n%s2p, n%s3p, n%op, n%o2p, n%elec,&
                longitude+((j+1)/(LNG_GRID+1))*360.0, day_char, 'DENS')
              if(OUTPUT_MIXR) then  
                plot = ftint_mix(n, h) !calculate values to be plotted
                call IonOutput(plot%sp, plot%s2p, plot%s3p, plot%op, plot%o2p, &
                  longitude+((j+1)/(LNG_GRID+1))*360.0, day_char, 'MIXR')
              endif
              if(OUTPUT_TEMP) call IonElecOutput(T%sp, T%s2p, T%s3p, T%op, T%o2p, T%elec, & !longitude, day_char, 'TEMP')
                longitude+((j+1)/(LNG_GRID+1))*360.0, day_char, 'TEMP')
              if(OUTPUT_INTS) then !Intensity
                call IonOutput(n%sp*T%sp, n%s2p*T%s2p, n%s3p*T%s3p, n%op*T%op, n%o2p*T%o2p,&
                  longitude+((j+1)/(LNG_GRID+1))*360.0, day_char, 'INTS')
                intensity= n%sp*T_ave/(n_ave*T%sp)
                open(unit=120, file='intensity'//day_char//'.dat', status='unknown', position='append')
                  write(120,*) longitude, intensity 
                close(120)
              end if
!              open(unit=200, file='feh'//day_char//'.dat', status='unknown', position='append')
!              open(unit=210, file='vr'//day_char//'.dat', status='unknown', position='append')
!              open(unit=220, file='source'//day_char//'.dat', status='unknown', position='append')
!                 write(200,*) longitude, n%fh
!                 write(210,*) longitude, v_r0, numerical_c_r
!                 write(220,*) longitude, net_source
!              close(200)
!              close(210)
!              close(220)
            endif
            call MPI_BARRIER(MPI_COMM_WORLD, ierr)
          end do
        end do
        output_it=output_it + (86400.0/(dt*per_day)) !Determines when data is output. Set for once each run day (86400/dt).
        file_num = file_num + 1
    endif        

    call Grid_transport(n, nrg, dep)

    Io_loc = mod(Io_loc+(dt*v_Io), torus_circumference)  
    sys4_loc = mod(sys4_loc+(dt*v_sys4), torus_circumference)  

  end do

call FinalOutput(nrgy)

end subroutine model

subroutine dens_ave(n_ave, n)!, i)
  real                ::n_tot, n_ave, space_ave
  type(density)       ::n
!  integer             ::i

  n_tot=n%sp !+n%s2p+n%s3p+n%op+n%o2p
  call MPI_REDUCE(n_tot, n_ave, 1, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  n_ave=n_ave/LNG_GRID
  call MPI_BCAST(n_ave, 1, MPI_REAL, 0, MPI_COMM_WORLD, ierr)

!  n_tot=n%sp+n%s2p+n%s3p+n%op+n%o2p
!  call MPI_REDUCE(n_tot, space_ave, 1, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
!  space_ave=space_ave/LNG_GRID
!  n_ave=(n_ave*(i-1.0)+space_ave)/(i*1.0)
!  call MPI_BCAST(n_ave, 1, MPI_REAL, 0, MPI_COMM_WORLD, ierr)

end subroutine dens_ave

subroutine temp_ave(T_ave, T)!, i)
  real                ::T_tot, T_ave, space_ave
  type(temp)          ::T
!  integer             ::i

  T_tot=T%sp !+T%s2p+T%s3p+T%op+T%o2p
  call MPI_REDUCE(T_tot, T_ave, 1, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  T_ave=T_ave/LNG_GRID
  call MPI_BCAST(T_ave, 1, MPI_REAL, 0, MPI_COMM_WORLD, ierr)

!  T_tot=T%sp+T%s2p+T%s3p+T%op+T%o2p
!  call MPI_REDUCE(T_tot, space_ave, 1, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
!  space_ave=space_ave/LNG_GRID
!  T_ave=(T_ave*(i-1.0)+space_ave)/(i*1.0)
!  call MPI_BCAST(T_ave, 1, MPI_REAL, 0, MPI_COMM_WORLD, ierr)

end subroutine temp_ave

subroutine FinalOutput(nrgy)
  type(energy)        ::nrgy, avg
  integer             ::j

  call MPI_REDUCE(nrgy%s_ion, avg%s_ion, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%s_ion=avg%s_ion/LNG_GRID

  call MPI_REDUCE(nrgy%s_cx, avg%s_cx, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%s_cx=avg%s_cx/LNG_GRID

  call MPI_REDUCE(nrgy%o_ion, avg%o_ion, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%o_ion=avg%o_ion/LNG_GRID

  call MPI_REDUCE(nrgy%o_cx, avg%o_cx, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%o_cx=avg%o_cx/LNG_GRID

  call MPI_REDUCE(nrgy%elecHot_eq, avg%elecHot_eq, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%elecHot_eq=avg%elecHot_eq/LNG_GRID

  call MPI_REDUCE(nrgy%tot_eq, avg%tot_eq, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%tot_eq=avg%tot_eq/LNG_GRID

  call MPI_REDUCE(nrgy%P_in, avg%P_in, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%P_in=avg%P_in/LNG_GRID

  call MPI_REDUCE(nrgy%Puv, avg%Puv, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%Puv=avg%Puv/LNG_GRID

  call MPI_REDUCE(nrgy%Pfast, avg%Pfast, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%Pfast=avg%Pfast/LNG_GRID

  call MPI_REDUCE(nrgy%Ptrans, avg%Ptrans, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%Ptrans=avg%Ptrans/LNG_GRID

  call MPI_REDUCE(nrgy%Ptrans_elecHot, avg%Ptrans_elecHot, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%Ptrans_elecHot=avg%Ptrans_elecHot/LNG_GRID

  call MPI_REDUCE(nrgy%P_out, avg%P_out, LNG_GRID, MPI_REAL, MPI_SUM, 0, MPI_COMM_WORLD, ierr)
  avg%P_out=avg%P_out/LNG_GRID

  if( mype .eq. 0 ) then
    print *, "AVERAGE VALUES"
    call FinalTable(avg)
    print *, ""
  endif

!  do j=1, LNG_GRID
!    if( mygrid .eq. j ) then
!      print *, "mygrid = ", mygrid
!      call FinalTable(nrgy)
!      print *, ""
!    endif
!    call MPI_BARRIER(MPI_COMM_WORLD, ierr)
!  enddo

end subroutine FinalOutput

subroutine FinalTable(nrgy)
  type(energy)        ::nrgy

  print *, '$$--------------------------------'
  print *, '$$ INPUT PARAMETERS'
  print *, '$$--------------------------------'
  print *, '$$ Source Rate..........', source 
  print *, '$$ Hot Elec Fraction....', fehot_const 
  print *, '$$ Transport............', transport 
  print *, '$$ Hot Elec Temp........', tehot  
  print *, '$$ Subcorotation........', v_ion
  print *, '$$ Sys 3 Hot Elec Frac..', sys3_amp 
  print *, '$$ Sys 4 Hot Elec Amp...', sys4_amp
  print *, '$$ Sys 4 Speed..........', v_sys4

  print *, ''
  print *, '$$ GAUSSIAN SOURCE CHANGE VARIABLES'  
  print *, '$$ Neutral Variation....', neutral_amp 
  print *, '$$ Neutral Temp.........', neutral_t0 
  print *, '$$ Variation Duration...', neutral_width
  print *, '$$ Hot Elec Variation...', hote_amp  
  print *, '$$ Hot Elec Temp........', hote_t0
  print *, '$$ Variation Duration...', hote_width
 
  print *, ''
  print *, '$$ Run Length(days)....',  run_days
  print *, '$$ Outputs per day.....',  per_day

  print *, ''
  print *, '$$--------------------------------'
  print *, '$$ IN-CODE ENERGY BUDGET'
  print *, '$$--------------------------------'
  print *, '$$ ionized S............', nrgy%s_ion
  print *, '$$ ionized O............', nrgy%o_ion
  print *, '$$ charge exchange S....', nrgy%s_cx
  print *, '$$ charge exchange O....', nrgy%o_cx
  print *, '$$ equil with ehot......', nrgy%elecHot_eq + nrgy%tot_eq
  print *, '$$ total in.............', nrgy%P_in + nrgy%tot_eq
  print *, '$$ puv..................', nrgy%Puv
  print *, '$$ fast/ena.............', nrgy%pfast - nrgy%tot_eq
  print *, '$$ transport............', nrgy%ptrans + nrgy%ptrans_elecHot
  print *, '$$ total out............', nrgy%P_out - nrgy%tot_eq
  print *, '$$ in/out...............', (nrgy%P_in + nrgy%tot_eq )/(nrgy%P_out - nrgy%tot_eq )
!  print *, ""
!  print *, '++++++++++++++++++++++++++++++++++++'
!  print *, 'Final Variable Values'
!  print *, '++++++++++++++++++++++++++++++++++++'
!  print *, 'O/S.........................', o_to_s
!  print *, 'Fraction of Hot Electrons...', fehot_const
!  print *, 'Transport...................', transport
!  print *, 'Hot Electron Temp...........', tehot
!  print *, 'Lag Constant................', lag_const
!  print *, 'Neutral Amplitude...........', neutral_amp
!  print *, 'Inital Neutral Temperature..', neutral_t0
!  print *, 'Neutral Width...............', neutral_width
!  print *, 'Hot Electron Amplitude......', hote_amp
!  print *, 'Hot Electron Initial Temp...', hote_t0
!  print *, 'Hot Electron Width..........', hote_width

end subroutine FinalTable

subroutine DebugOutput(i, n, h, T, v, nrg)
  integer             ::i
  type(density)       ::n
  type(height)        ::h
  type(temp)          ::T
  type(nu)            ::v
  type(nT)            ::nrg

  print *,  "||||||||||||||||||||||||||||||||||||||||||||||"
  print *,  "lnggrid = ", lnggrid
  print *,  "radgrid = ", radgrid
  print *,  "i = ", i-1
  print *,  "||||||||||||||||||||||||||||||||||||||||||||||"
  print *, "~~~~~~~~~~~~~DENSITY~~~~~~~~~~~~~"
  call output(n)
  print *, "~~~~~~~~~~~~~HEIGHT~~~~~~~~~~~~~~"
  call output(h)
  print *, "~~~~~~~~~~~TEMPERATURE~~~~~~~~~~~"
  call output(T)
  print *, "~~~~~~~~~~~~~~~NU~~~~~~~~~~~~~~~~"
  call output(v)
  print *, "~~~~~~~~~~~~~ENERGY~~~~~~~~~~~~~~"
  call output(nrg)
 

end subroutine DebugOutput

subroutine Grid_transport(n, nrg, dep)
  type(density)       ::n, dens_source
  type(nT)            ::nrg, nrg_source
  type(r_dep)         ::dep

  call az_transport(n, nrg)
!  print *, "CHECKPOINT 1 reached by processor ", mype+1
!  call MPI_BARRIER(MPI_COMM_WORLD, ierr)
  call rad_transport(n, nrg, dep)
!  print *, "CHECKPOINT 2 reached by processor ", mype+1
!  call MPI_BARRIER(MPI_COMM_WORLD, ierr)

end subroutine Grid_transport

subroutine Communicate(dens_source, nrg_source)
  type(density)       ::dens_source
  type(nT)            ::nrg_source

  call MPI_SEND(dens_loss%s, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(dens_source%s, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(dens_loss%sp, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(dens_source%sp, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(dens_loss%s2p, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(dens_source%s2p, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(dens_loss%s3p, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(dens_source%s3p, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(dens_loss%o, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(dens_source%o, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(dens_loss%op, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(dens_source%op, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(dens_loss%o2p, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(dens_source%o2p, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(nrg_loss%sp, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(nrg_source%sp, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(nrg_loss%s2p, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(nrg_source%s2p, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(nrg_loss%s3p, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(nrg_source%s3p, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(nrg_loss%op, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(nrg_source%op, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  call MPI_SEND(nrg_loss%o2p, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(nrg_source%o2p, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

end subroutine Communicate

subroutine az_transport(n, nrg)
  type(density)     ::n
  type(nT)          ::nrg
    
  if( Upwind ) then
    call GetAzNeighbors(n, nrg)
    if(mype .eq. 0) then
      print *, "AZ Transport:::", n%sp-UpwindTransport(nleft%sp , n%sp ,numerical_c_ion)
    endif 
    n%s   =UpwindTransport(nleft%s  , n%s  ,numerical_c_neutral)
    n%sp  =UpwindTransport(nleft%sp , n%sp ,numerical_c_ion)
    n%s2p =UpwindTransport(nleft%s2p, n%s2p,numerical_c_ion)
    n%s3p =UpwindTransport(nleft%s3p, n%s3p,numerical_c_ion)
    n%o   =UpwindTransport(nleft%o  , n%o  ,numerical_c_neutral)
    n%op  =UpwindTransport(nleft%op , n%op ,numerical_c_ion)
    n%o2p =UpwindTransport(nleft%o2p, n%o2p,numerical_c_ion)
  
    nrg%sp  =UpwindTransport(nTleft%sp , nrg%sp ,numerical_c_ion)
    nrg%s2p =UpwindTransport(nTleft%s2p, nrg%s2p,numerical_c_ion)
    nrg%s3p =UpwindTransport(nTleft%s3p, nrg%s3p,numerical_c_ion)
    nrg%op  =UpwindTransport(nTleft%op , nrg%op ,numerical_c_ion)
    nrg%o2p =UpwindTransport(nTleft%o2p, nrg%o2p,numerical_c_ion)
  endif

  if( Euler ) then
    n%s   = EulerTransport(n%s  , v_neutral)
    n%sp  = EulerTransport(n%sp , v_ion)
    n%s2p = EulerTransport(n%s2p, v_ion)
    n%s3p = EulerTransport(n%s3p, v_ion)
    n%o   = EulerTransport(n%o  , v_neutral)
    n%op  = EulerTransport(n%op , v_ion)
    n%o2p = EulerTransport(n%o2p, v_ion)

    nrg%sp  = EulerTransport(nrg%sp , v_ion)
    nrg%s2p = EulerTransport(nrg%s2p, v_ion)
    nrg%s3p = EulerTransport(nrg%s3p, v_ion)
    nrg%op  = EulerTransport(nrg%op , v_ion)
    nrg%o2p = EulerTransport(nrg%o2p, v_ion)
  endif

end subroutine az_transport

subroutine rad_transport(n, nrg, dep)
  type(density)     ::n, nempty, ni,ninold
  type(nT)          ::nrg, nTempty, nrgi,nTinold
  type(r_dep)       ::dep
  double precision  ::loss
  
  call GetRadNeighbors(n, nrg)

  if (mype .lt. LNG_GRID) then
!    print *, "The following output should be zeroes!"
    nin%sp=n%sp*numerical_c_r
    nin%s2p=n%s2p*numerical_c_r
    nin%s3p=n%s3p*numerical_c_r
    nin%op=n%op*numerical_c_r
    nin%o2p=n%o2p*numerical_c_r
    nin%elec=n%elec*numerical_c_r
!    call output(nin) 
!    call output(n) 
    nTin%sp=nrg%sp*numerical_c_r
    nTin%s2p=nrg%s2p*numerical_c_r
    nTin%s3p=nrg%s3p*numerical_c_r
    nTin%op=nrg%op*numerical_c_r
    nTin%o2p=nrg%o2p*numerical_c_r
    nTin%elec=nrg%elec*numerical_c_r
  endif
!    if (mype .eq. 0) then
      !print*, n%sp-UpwindTransport(nin%sp ,  n%sp , numerical_c_r)
!    endif
  if (mype .eq. 0) then
    print *, "NCR DEBUG", numerical_c_r, v_r0, dr, dt
  endif 
    if( mype .eq. 0) then
      print *, "Transport loss::" , n%sp-UpwindRadTransport(nin%sp ,  n%sp , numerical_c_r)

    endif
    n%sp  =UpwindRadTransport(nin%sp ,  n%sp , numerical_c_r)
    n%s2p =UpwindRadTransport(nin%s2p,  n%s2p, numerical_c_r)
    n%s3p =UpwindRadTransport(nin%s3p,  n%s3p, numerical_c_r)
    n%op  =UpwindRadTransport(nin%op ,  n%op , numerical_c_r)
    n%o2p =UpwindRadTransport(nin%o2p,  n%o2p, numerical_c_r)
    n%elec=UpwindRadTransport(nin%elec, n%elec,numerical_c_r)
!    n%elecHot =UpwindTransport(nin%elecHot, n%elecHot,numerical_c_r)
  
    nrg%sp  =UpwindRadTransport(nTin%sp ,  nrg%sp , numerical_c_r)
    nrg%s2p =UpwindRadTransport(nTin%s2p,  nrg%s2p, numerical_c_r)
    nrg%s3p =UpwindRadTransport(nTin%s3p,  nrg%s3p, numerical_c_r)
    nrg%op  =UpwindRadTransport(nTin%op ,  nrg%op , numerical_c_r)
    nrg%o2p =UpwindRadTransport(nTin%o2p,  nrg%o2p, numerical_c_r)
    nrg%elec=UpwindRadTransport(nTin%elec, nrg%elec,numerical_c_r)
!    nrg%elecHot =UpwindTransport(nTin%elecHot, nrg%elecHot,numerical_c_r)


!Improved Euler method
!  ni%sp   = n%sp  + (nin%sp  - n%sp )*numerical_c_r
!  ni%s2p  = n%s2p + (nin%s2p - n%s2p)*numerical_c_r 
!  ni%s3p  = n%s3p + (nin%s3p - n%s3p)*numerical_c_r 
!  ni%op   = n%op  + (nin%op  - n%op )*numerical_c_r 
!  ni%o2p  = n%o2p + (nin%o2p - n%o2p)*numerical_c_r 
!
!  nrgi%sp   = nrg%sp   + (nTin%sp   - nrg%sp )*numerical_c_r 
!  nrgi%s2p  = nrg%s2p  + (nTin%s2p  - nrg%s2p)*numerical_c_r 
!  nrgi%s3p  = nrg%s3p  + (nTin%s3p  - nrg%s3p)*numerical_c_r 
!  nrgi%op   = nrg%op   + (nTin%op   - nrg%op )*numerical_c_r 
!!  nrgi%o2p  = nrg%o2p  + (nTin%o2p  - nrg%o2p)*numerical_c_r 

!  ninold=nin
!  nTinold=nTin
!
!  call GetRadNeighbors(ni, nrgi)
!
!  n%sp   = n%sp  + .5 * (nin%sp  + ninold%sp - ni%sp - n%sp )*numerical_c_r
!  n%s2p  = n%s2p + .5 * (nin%s2p + ninold%s2p- ni%s2p- n%s2p)*numerical_c_r
!  n%s3p  = n%s3p + .5 * (nin%s3p + ninold%s3p- ni%s3p- n%s3p)*numerical_c_r
!  n%op   = n%op  + .5 * (nin%op  + ninold%op - ni%op - n%op )*numerical_c_r
!  n%o2p  = n%o2p + .5 * (nin%o2p + ninold%o2p- ni%o2p- n%o2p)*numerical_c_r
!
!  nrg%sp   = nrg%sp  + .5 * (nTin%sp  + nTinold%sp  - nrgi%sp - nrg%sp )*numerical_c_r 
!  nrg%s2p  = nrg%s2p + .5 * (nTin%s2p + nTinold%s2p - nrgi%s2p- nrg%s2p)*numerical_c_r 
!!  nrg%s3p  = nrg%s3p + .5 * (nTin%s3p + nTinold%s3p - nrgi%s3p- nrg%s3p)*numerical_c_r 
!  nrg%op   = nrg%op  + .5 * (nTin%op  + nTinold%op  - nrgi%op - nrg%op )*numerical_c_r 
!  nrg%o2p  = nrg%o2p + .5 * (nTin%o2p + nTinold%o2p - nrgi%o2p- nrg%o2p)*numerical_c_r 
    !handles all radial transport 
    !must remove radial loss from F_* and EF_* functions in functions.f90

end subroutine rad_transport


double precision function UpwindTransport(left, center, c)
  double precision    ::left, center
  real                ::c

!  UpwindTransport = (numerical_s + c)*left + (1 - 2*numerical_s - c)*center + numerical_s*right
  UpwindTransport =  c*left + (1.0 - c)*center

end function UpwindTransport

double precision function UpwindRadTransport(left, center, c)
  double precision    ::left, center
  real                ::c

!  UpwindTransport = (numerical_s + c)*left + (1 - 2*numerical_s - c)*center + numerical_s*right
  UpwindRadTransport =  left + (1.0 - c)*center

end function UpwindRadTransport

double precision function EulerTransport(old, v) !improved euler method applied to azimuthal transport
  double precision    ::old, intermediate, loss
  real                ::v

  loss = getLoss(v, old)

  intermediate = old - loss

  EulerTransport = old - .5 * (loss + getLoss(v, intermediate))

end function EulerTransport

double precision function getLoss(v, val)
  real                ::v
  double precision    ::val, source

  getLoss = val * dt * v * LNG_GRID / torus_circumference
  
  call MPI_SEND(getLoss, 1, MPI_DOUBLE_PRECISION, mod(mype+1, npes), 22, MPI_COMM_WORLD, ierr)
  call MPI_RECV(source, 1, MPI_DOUBLE_PRECISION, mod(mype-1, npes), 22, MPI_COMM_WORLD, stat, ierr)

  getLoss = getLoss - source

end function getLoss

subroutine GetAzNeighbors(n, nrg)
  type(density)       ::n
  type(nT)            ::nrg
  integer             ::left, right, i

! ALGORITHM
! Send to right
! Receive from left
! Send to left X           upwind only needs left
! Receive from right X
!!!!!!!!!!!!!!!!!!!!DENSITY!!!!!!!!!!!!!!!!!!!!!
  do i=0, RAD_GRID-1
    if(mype .ge. i*LNG_GRID .and. mype < (i+1)*LNG_GRID) then
      left = mype - 1 
      right= mype + 1

      if( left < (i*LNG_GRID) )           left = left+LNG_GRID
      if( right .ge. ((i+1)*LNG_GRID) ) right=right-LNG_GRID

      call MPI_SEND(n%s, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nleft%s, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(n%sp, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nleft%sp, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(n%s2p, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nleft%s2p, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(n%s3p, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nleft%s3p, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(n%o, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nleft%o, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(n%op, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nleft%op, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(n%o2p, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nleft%o2p, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(n%elec, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nleft%elec, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

!      call MPI_SEND(n%elecHot, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
!      call MPI_RECV(nleft%elecHot, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

!!!!!!!!!!!!!!!!!!!!ENERGY!!!!!!!!!!!!!!!!!!!!!!
      call MPI_SEND(nrg%sp, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nTleft%sp, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(nrg%s2p, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nTleft%s2p, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(nrg%s3p, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nTleft%s3p, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(nrg%op, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nTleft%op, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(nrg%o2p, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nTleft%o2p, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

      call MPI_SEND(nrg%elec, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
      call MPI_RECV(nTleft%elec, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

!      call MPI_SEND(nrg%elecHot, 1, MPI_DOUBLE_PRECISION, right, 22, MPI_COMM_WORLD, ierr)
!      call MPI_RECV(nTleft%elecHot, 1, MPI_DOUBLE_PRECISION, left, 22, MPI_COMM_WORLD, stat, ierr)

    endif
  end do
  call MPI_BARRIER(MPI_COMM_WORLD, ierr)
end subroutine GetAzNeighbors

subroutine GetRadNeighbors(n, nrg)
  type(density)       ::n
  type(nT)            ::nrg
  real                ::rado
  integer             ::inside, outside, i

! ALGORITHM
! Send to outside
! Receive from inside
! Send to inside X           upwind only needs inside
! Receive from outside X
!!!!!!!!!!!!!!!!!!!!DENSITY!!!!!!!!!!!!!!!!!!!!!
 
  outside = mype+LNG_GRID
  inside  = mype-LNG_GRID

  if(inside.ge.0) call MPI_SEND(rdist, 1, MPI_REAL, inside, 22, MPI_COMM_WORLD, ierr)
  if(outside<npes) call MPI_RECV(rado, 1, MPI_REAL, outside, 22, MPI_COMM_WORLD, stat, ierr)
!rado=rdist
!  if(outside<npes) call MPI_SEND(n%s*rdist/rado, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
!  if(inside.ge.0) call MPI_RECV(nin%s, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

  if(outside<npes) call MPI_SEND(n%sp*numerical_c_r*rdist/rado, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nin%sp, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

  if(outside<npes) call MPI_SEND(n%s2p*numerical_c_r*rdist/rado, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nin%s2p, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

  if(outside<npes) call MPI_SEND(n%s3p*numerical_c_r*rdist/rado, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nin%s3p, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

!  if(outside<npes) call MPI_SEND(n%o*rdist/rado, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
!  if(inside.ge.0) call MPI_RECV(nin%o, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

  if(outside<npes) call MPI_SEND(n%op*numerical_c_r*rdist/rado, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nin%op, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

  if(outside<npes) call MPI_SEND(n%o2p*numerical_c_r*rdist/rado, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nin%o2p, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

!!!!!!!!!!!!!!!!!!!!ENERGY!!!!!!!!!!!!!!!!!!!!!!
  if(outside<npes) call MPI_SEND(nrg%sp*numerical_c_r, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nTin%sp, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

  if(outside<npes) call MPI_SEND(nrg%s2p*numerical_c_r, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nTin%s2p, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

  if(outside<npes) call MPI_SEND(nrg%s3p*numerical_c_r, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nTin%s3p, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

  if(outside<npes) call MPI_SEND(nrg%op*numerical_c_r, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nTin%op, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)

  if(outside<npes) call MPI_SEND(nrg%o2p*numerical_c_r, 1, MPI_DOUBLE_PRECISION, outside, 22, MPI_COMM_WORLD, ierr)
  if(inside.ge.0) call MPI_RECV(nTin%o2p, 1, MPI_DOUBLE_PRECISION, inside, 22, MPI_COMM_WORLD, stat, ierr)
  call MPI_BARRIER(MPI_COMM_WORLD, ierr)
end subroutine GetRadNeighbors


END PROGRAM Onebox

