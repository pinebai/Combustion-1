subroutine smc()

  use advance_module
  use checkpoint_module
  use chemistry_module
  use derivative_stencil_module
  use eglib_module
  use initialize_module
  use layout_module
  use make_plotfile_module
  use multifab_module
  use omp_module
  use probin_module
  use runtime_init_module
  use time_module
  use variables_module

  use cputime_module, only: start_cputime_clock

  implicit none

  integer :: dm, i !, numcell
  integer :: init_step, istep

  real(dp_t) :: dt, courno
  real(dp_t)  , pointer     :: dx(:)

  real(dp_t) :: wt0, wt1, wt2, wt_init, wt_advance

  integer :: last_plt_written,last_chk_written
  character(len=5)               :: plot_index, check_index
  character(len=6)               :: plot_index6, check_index6
  character(len=256)             :: plot_file_name, check_file_name
  character(len=20), allocatable :: plot_names(:)

  logical :: dump_plotfile, dump_checkpoint, abort_smc
  real(dp_t) :: write_pf_time
  
  type(layout)   :: la
  type(multifab) :: U

  type(bl_prof_timer), save :: bpt_advance

  wt0 = parallel_wtime()

  ! keep track of cputime
  call start_cputime_clock()

  last_plt_written = -1
  last_chk_written = -1

  call runtime_init()

  call stencil_init()

  call chemistry_init()
  if (verbose .ge. 1) then
     if (parallel_IOProcessor()) then
        print *, ''
        write(*,'(A,1X,I0,1X,A)', advance='no') "Chemistry model has", nspecies, "species:"
        do i=1,nspecies
           write(*, '(3X,A)', advance='no') trim(spec_names(i))
        end do
        print *, ''
     end if
  end if

  call init_variables()
  call init_plot_variables()

  allocate(plot_names(n_plot_comps))
  call get_plot_names(plot_names)

  if (restart >= 0) then

     if (restart <= 99999) then
        write(unit=check_index,fmt='(i5.5)') restart
        check_file_name = trim(check_base_name) // check_index
     else
        write(unit=check_index6,fmt='(i6.6)') restart
        check_file_name = trim(check_base_name) // check_index6
     endif
     
     if (parallel_IOProcessor() .and. verbose.ge.1) then
        print*,""
        print*,"Restarting from", check_file_name
     end if

     call initialize_from_restart(check_file_name, la,dt,courno,dx,U)

  else 

     if (parallel_IOProcessor() .and. verbose.ge.1) then
        print*,""
        print*,"Starting from scratch"
     end if

     call initialize_from_scratch(la,dt,courno,dx,U)

  end if


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! error checking
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  dm = dm_in
  if (dm .ne. 3) then 
     call bl_error('SMC can only do 3D')
  end if

  ! check to make sure dimensionality is consistent in the inputs file
  if (dm .ne. get_dim(la)) then 
     call bl_error('dm_in not properly set in inputs file')
  end if

  if (.not. all(pmask)) then
     call bl_error('SMC minimalist version only supports triple periodic bpundaries')
  end if

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! print processor and grid info
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  if (parallel_IOProcessor()) then
     print *, ' '     
     print *, 'number of MPI processes = ', parallel_nprocs()
     print *, 'number of threads       = ', omp_get_max_threads()
     print *, ' '
     print *, 'number of dimensions    = ', dm
     print *, 'number of boxes         = ', nboxes(la)
     print *, ' '
  end if
  
!   if (verbose .ge. 1) then
!      numcell = multifab_volume(U,.false.)
!      if (parallel_IOProcessor()) then
!         print*,"Number of valid cells:              ",numcell
!      end if
!      numcell = multifab_volume(U,.true.)
!      if (parallel_IOProcessor()) then
!         print*,"Number of valid cells + ghost cells:",numcell
!         print*,""
!      end if
!   end if

  wt1 = parallel_wtime()

  if (restart < 0) then

     istep = 0

     if (chk_int > 0) then
        write(unit=check_index,fmt='(i5.5)') istep
        check_file_name = trim(check_base_name) // check_index

        call checkpoint_write(check_file_name, U, dt, courno)
        
        last_chk_written = istep
     end if

     if (plot_int > 0 .or. plot_deltat > ZERO) then
        write(unit=plot_index,fmt='(i5.5)') istep
        plot_file_name = trim(plot_base_name) // plot_index
        
        call make_plotfile(plot_file_name,la,U,plot_names,time,dx,write_pf_time)

        call write_job_info(plot_file_name, la, write_pf_time)
        
        last_plt_written = istep
     end if
  end if

  if (restart < 0) then
     init_step = 1 
  else
     init_step = restart + 1
  end if

  if ( parallel_IOProcessor()) then
     print*,""
     print*,"BEGIN MAIN EVOLUTION LOOP"
     print*,""
  end if

  if ( (max_step >= init_step) .and. (time < stop_time .or. stop_time < 0.d0) ) then

     do istep = init_step, max_step

        if ( verbose .ge. 1 ) then
           if ( parallel_IOProcessor() ) then
              print*, ' '
              print *, 'MEMORY STATS AT START OF TIMESTEP ', istep
              print*, ' '
           end if
           call print(multifab_mem_stats(),    "    multifab")
           call print(fab_mem_stats(),         "         fab")
           call print(boxarray_mem_stats(),    "    boxarray")
           call print(layout_mem_stats(),      "      layout")
           call print(boxassoc_mem_stats(),    "    boxassoc")
!           call print(fgassoc_mem_stats(),     "     fgassoc")
!           call print(syncassoc_mem_stats(),   "   syncassoc")
           call print(copyassoc_mem_stats(),   "   copyassoc")
!           call print(fluxassoc_mem_stats(),   "   fluxassoc")
           if ( parallel_IOProcessor() ) print*, ''
        end if

        if (parallel_IOProcessor()) then
           print*,'Advancing time step',istep,'time = ',time
           print*, ""
        end if

        call build(bpt_advance, "advance")     !! vvvvvvvvvvvvvvvvvvvvvvv timer
        call advance(U,dt,courno,dx,istep)
        call destroy(bpt_advance)              !! ^^^^^^^^^^^^^^^^^^^^^^^ timer

        time = time + dt

        if ( parallel_IOProcessor() ) then
           print *, 'End of step', istep,'time = ', time
        end if

        ! if the file .dump_checkpoint exists in our output directory, then
        ! automatically dump a plotfile
        inquire(file="dump_checkpoint", exist=dump_checkpoint)

        if (chk_int > 0 .or. dump_checkpoint) then
           if (mod(istep,chk_int) .eq. 0 .or. dump_checkpoint) then
              
              if (istep <= 99999) then
                 write(unit=check_index,fmt='(i5.5)') istep
                 check_file_name = trim(check_base_name) // check_index
              else
                 write(unit=check_index6,fmt='(i6.6)') istep
                 check_file_name = trim(check_base_name) // check_index6
              endif
              
              call checkpoint_write(check_file_name, U, dt, courno)
              
              last_chk_written = istep
              
           end if

           if (dump_checkpoint .and. parallel_IOProcessor()) then
              open(2,file='dump_checkpoint',status='old')
              close(2,status='delete')
           end if
        end if

        ! if the file dump_plotfile exists in our output directory, then
        ! automatically dump a plotfile
        inquire(file="dump_plotfile", exist=dump_plotfile)

        if (plot_int > 0 .or. plot_deltat > ZERO .or. dump_plotfile) then
           if ( (plot_int > 0 .and. mod(istep,plot_int) .eq. 0) .or. &
                (plot_deltat > ZERO .and. &
                mod(time - dt,plot_deltat) > mod(time,plot_deltat)) .or. &
                dump_plotfile) then

              if (istep <= 99999) then
                 write(unit=plot_index,fmt='(i5.5)') istep
                 plot_file_name = trim(plot_base_name) // plot_index
              else
                 write(unit=plot_index6,fmt='(i6.6)') istep
                 plot_file_name = trim(plot_base_name) // plot_index6
              endif

              call make_plotfile(plot_file_name,la,U,plot_names,time,dx,write_pf_time)

              call write_job_info(plot_file_name, la, write_pf_time)

              last_plt_written = istep

           end if

           if (dump_plotfile .and. parallel_IOProcessor()) then
              open(2,file='dump_plotfile',status='old')
              close(2,status='delete')
           end if
        end if

        if (parallel_IOProcessor() .and. verbose .ge. 2) then
           call flush(6)
        end if

        ! if the file abort_smc exists in our output directory, then
        ! automatically end the run.  This has the effect of also dumping
        ! a final checkpoint file.
        inquire(file="abort_smc", exist=abort_smc)
        if (abort_smc) exit

        ! have we reached the stop time?
        if (stop_time >= 0.d0) then
           if (time >= stop_time) then
              goto 999
           end if
        end if

     end do

999  continue
     if (istep > max_step) istep = max_step

     if ( chk_int > 0 .and. last_chk_written .ne. istep ) then

        if (istep <= 99999) then
           write(unit=check_index,fmt='(i5.5)') istep
           check_file_name = trim(check_base_name) // check_index
        else
           write(unit=check_index6,fmt='(i6.6)') istep
           check_file_name = trim(check_base_name) // check_index6
        endif
        
        call checkpoint_write(check_file_name, U, dt, courno)
              
     end if

     if ( plot_int > 0 .and. last_plt_written .ne. istep ) then

        if (istep <= 99999) then
           write(unit=plot_index,fmt='(i5.5)') istep
           plot_file_name = trim(plot_base_name) // plot_index
        else
           write(unit=plot_index6,fmt='(i6.6)') istep
           plot_file_name = trim(plot_base_name) // plot_index6
        endif

        call make_plotfile(plot_file_name,la,U,plot_names,time,dx,write_pf_time)

        call write_job_info(plot_file_name, la, write_pf_time)
     end if

     if (abort_smc .and. parallel_IOProcessor()) then
        open(2,file='abort_smc',status='old')
        close(2,status='delete')
     end if
  end if

  wt2 = parallel_wtime()

  call destroy(U)

  call destroy(la)

  call chemistry_close()
  call eglib_close()

  call runtime_close()

  deallocate(plot_names)
  deallocate(dx)

  call parallel_reduce(wt_init, wt1-wt0, MPI_MAX, proc = parallel_IOProcessorNode())
  call parallel_reduce(wt_advance, wt2-wt1, MPI_MAX, proc = parallel_IOProcessorNode())

  if (parallel_IOProcessor()) then
     print*, ' '
     print*, 'SMC Initialization Time = ', wt_init
     print*, 'SMC Advance + I/O  Time = ', wt_advance
     print*, ' '
  end if

end subroutine smc
