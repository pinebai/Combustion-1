module chemterm_module

  use meth_params_module
  use burner_module, only : burn, compute_rhodYdt, splitburn, beburn
  use eos_module, only : eos_get_T
  use renorm_module, only : floor_species
  use passinfo_module, only : level

  implicit none

  private

  public :: chemterm, dUdt_chem

contains

  subroutine chemterm(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt, Up)
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3), stlo(3), sthi(3)
    double precision, intent(inout) :: U(Ulo(1):Uhi(1),Ulo(2):Uhi(2),Ulo(3):Uhi(3),NVAR)
    double precision, intent(inout) :: st(stlo(1):sthi(1),stlo(2):sthi(2),stlo(3):sthi(3))
    double precision, intent(in) :: dt
    double precision, intent(in), optional :: Up(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),NVAR)

    select case (chem_solver)
       case (cc_burning)
          call chemterm_cellcenter(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt)
       case (Gauss_burning)
          call chemterm_gauss(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt)
       case (split_burning)
          call chemterm_split(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt)
       case (BEcc_burning)
          call chemterm_becc(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt, Up)
       case (BEGp_burning)
          call chemterm_begp(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt, Up)
       case default
          call bl_error("unknown chem_solver")
       end select

  end subroutine chemterm


  subroutine dUdt_chem(lo, hi, U, Ulo, Uhi, Ut, Utlo, Uthi, st, stlo, sthi)
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3), Utlo(3), Uthi(3), stlo(3), sthi(3)
    double precision, intent(in ) ::  U( Ulo(1): Uhi(1), Ulo(2): Uhi(2), Ulo(3): Uhi(3),NVAR)
    double precision, intent(out) :: Ut(Utlo(1):Uthi(1),Utlo(2):Uthi(2),Utlo(3):Uthi(3),NVAR)
    double precision, intent(inout) :: st(stlo(1):sthi(1),stlo(2):sthi(2),stlo(3):sthi(3))
    if (chem_solver .eq. cc_burning .or. chem_solver .eq. BEcc_burning) then
       call dUdt_chem_cellcenter(lo, hi, U, Ulo, Uhi, Ut, Utlo, Uthi, st, stlo, sthi)
    else
       call dUdt_chem_gauss(lo, hi, U, Ulo, Uhi, Ut, Utlo, Uthi, st, stlo, sthi)
    end if
  end subroutine dUdt_chem


  subroutine chemterm_cellcenter(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt)
    use convert_module, only : cellavg2cc_3d, cc2cellavg_3d
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3), stlo(3), sthi(3)
    double precision, intent(inout) :: U(Ulo(1):Uhi(1),Ulo(2):Uhi(2),Ulo(3):Uhi(3),NVAR)
    double precision, intent(inout) :: st(stlo(1):sthi(1),stlo(2):sthi(2),stlo(3):sthi(3))
    double precision, intent(in) :: dt

    integer :: i, j, k, n, ierr
    logical :: force_new_J
    double precision :: rhot(1), Yt(nspec+1)
    double precision, allocatable :: Ucc(:,:,:,:)

    allocate(Ucc(lo(1)-1:hi(1)+1,lo(2)-1:hi(2)+1,lo(3)-1:hi(3)+1,NVAR))

    !$omp parallel private(i,j,k,n,ierr,rhot,Yt,force_new_J)

    !$omp do
    do n=1,NVAR
       call cellavg2cc_3d(lo-1,hi+1, U(:,:,:,n), Ulo,Uhi, Ucc(:,:,:,n), lo-1,hi+1)
    end do
    !$omp end do

    force_new_J = .true.  ! always recompute Jacobian when a new FAB starts

    !$omp do schedule(dynamic) collapse(2)
    do k=lo(3)-1,hi(3)+1
       do j=lo(2)-1,hi(2)+1
          do i=lo(1)-1,hi(1)+1

             if (st(i,j,k) .eq. 0.d0) then
                call get_rhoYT(Ucc(i,j,k,:), rhot(1), YT(1:nspec), YT(nspec+1), ierr)

                if (ierr .ne. 0) then
                   st(i,j,k) = -1.d0
                   force_new_J = .true.
                else
                   call burn(1, rhot, Yt, dt, force_new_J, ierr)
                   if (ierr .ne. 0) then
                      st(i,j,k) = -1.d0
                      force_new_J = .true.
                   else
                      force_new_J = new_J_cell                      
                   end if
                end if
             end if

             if (st(i,j,k) .ne. 0.d0) then  ! burn cell average instead
                call get_rhoYT(U(i,j,k,:), rhot(1), YT(1:nspec), YT(nspec+1), ierr)
                if (ierr .ne. 0) then
                   print *, 'chemterm_cellcenter: eos_get_T failed for U at ', &
                        level,i,j,k,U(i,j,k,:)
                   call bl_error("chemterm_cellcenter failed at eos_get_T")
                end if

                force_new_J = .true.
                call burn(1, rhot, Yt, dt, force_new_J, ierr)
                force_new_J = new_J_cell
                if (ierr .ne. 0) then
                   print *, 'chemterm_cellcenter: bdf burn failed for U at ', &
                        level,i,j,k,U(i,j,k,:)
                   call bl_error("chemterm_cellcenter failed at bdf burn for U")
                end if
             end if

             do n=1,nspec
                Ucc(i,j,k,UFS+n-1) = rhot(1)*Yt(n)
             end do

          end do
       end do
    end do
    !$omp end do

    !$omp do
    do n=UFS,UFS+nspec-1
       call cc2cellavg_3d(lo,hi, Ucc(:,:,:,n), lo-1,hi+1, U(:,:,:,n), Ulo,Uhi)
    end do
    !$omp end do

    !$omp end parallel

    deallocate(Ucc)

  end subroutine chemterm_cellcenter


  subroutine chemterm_gauss(lo, hi, U, Ulo, Uhi, st, stlo, sthi,dt)
    use weno_module, only : cellavg2gausspt_3d
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3), stlo(3), sthi(3)
    double precision, intent(inout) :: U(Ulo(1):Uhi(1),Ulo(2):Uhi(2),Ulo(3):Uhi(3),NVAR)
    double precision, intent(inout) :: st(stlo(1):sthi(1),stlo(2):sthi(2),stlo(3):sthi(3))
    double precision, intent(in) :: dt

    integer :: i, j, k, n, g, ierr
    logical :: force_new_J
    double precision :: rhot(8), Yt(nspec+1,8)
    double precision, allocatable :: UG(:,:,:,:,:)

    allocate(UG(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),8,NVAR))

    if (chem_do_weno) then
       call chem_weno(lo, hi, U, Ulo, Uhi, UG)
    else
       !$omp parallel do private(n)
       do n=1,NVAR
          call cellavg2gausspt_3d(lo,hi, U(:,:,:,n), Ulo,Uhi, UG(:,:,:,:,n), lo,hi)
       end do
       !$omp end parallel do
    end if

    !$omp parallel private(i,j,k,n,g,ierr,rhot,Yt,force_new_J)

    force_new_J = .true.  ! always recompute Jacobian when a new FAB starts

    !$omp do schedule(dynamic) collapse(2)
    do k=lo(3),hi(3)
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)

             if (st(i,j,k) .eq. 0.d0) then
                do g=1,8
                   call get_rhoYT(UG(i,j,k,g,:), rhot(g), YT(1:nspec,g), YT(nspec+1,g), ierr)
                   if (ierr .ne. 0) then
                      st(i,j,k) = -1.d0
                      force_new_J = .true.
                      exit
                   end if
                end do
             end if

             if (st(i,j,k) .eq. 0.d0) then
                call burn(8, rhot, Yt, dt, force_new_J, ierr)
                if (ierr .ne. 0) then
                   st(i,j,k) = -1.d0
                   force_new_J = .true.
                else
                   force_new_J = new_J_cell
                end if
             end if
                
             if (st(i,j,k) .eq. 0.d0) then

                U(i,j,k,UFS:UFS+nspec-1) = 0.d0 
                do g=1,8
                   do n=1,nspec
                      U(i,j,k,UFS+n-1) = U(i,j,k,UFS+n-1) + 0.125d0*rhot(g)*Yt(n,g)
                   end do
                end do

             else ! burn cell average instead

                call get_rhoYT(U(i,j,k,:), rhot(1), YT(1:nspec,1), YT(nspec+1,1), ierr)
                if (ierr .ne. 0) then
                   print *, 'chemterm_gauss: eos_get_T failed for U at ', &
                        level, i,j,k,U(i,j,k,:)
                   call bl_error("chemterm_gauss failed at eos_get_T")
                end if

                force_new_J = .true.
                call burn(1, rhot(1:1), YT(:,1), dt, force_new_J, ierr)
                force_new_J = new_J_cell
                if (ierr .ne. 0) then
                   print *, 'chemterm_gauss: bdf burn failed for U at ', &
                        level, i,j,k,U(i,j,k,:)
                   call bl_error("chemterm_gauss failed at bdf burn for U")
                end if

                do n=1,nspec
                   U(i,j,k,UFS+n-1) = rhot(1)*YT(n,1)
                end do

             end if

          end do
       end do
    end do
    !$omp end do
    !$omp end parallel

    deallocate(UG)

  end subroutine chemterm_gauss


  subroutine chemterm_split(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt)
    use weno_module, only : cellavg2gausspt_3d
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3), stlo(3), sthi(3)
    double precision, intent(inout) :: U(Ulo(1):Uhi(1),Ulo(2):Uhi(2),Ulo(3):Uhi(3),NVAR)
    double precision, intent(inout) :: st(stlo(1):sthi(1),stlo(2):sthi(2),stlo(3):sthi(3))
    double precision, intent(in) :: dt

    integer :: i, j, k, n, g, ierr
    logical :: force_new_J
    double precision :: rhot(8), rho0(1)
    double precision :: Yt(nspec+1,8), YT0(nspec+1)
    double precision, allocatable :: UG(:,:,:,:,:)

    allocate(UG(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),8,NVAR))

    if (chem_do_weno) then
       call chem_weno(lo,hi,U,Ulo,Uhi,UG)
    else
       !$omp parallel do private(n)
       do n=1,NVAR
          call cellavg2gausspt_3d(lo,hi, U(:,:,:,n), Ulo,Uhi, UG(:,:,:,:,n), lo,hi)
       end do
       !$omp end parallel do
    end if

    !$omp parallel private(i,j,k,n,g,ierr,rhot,Yt,force_new_J,rho0,YT0)

    force_new_J = .true.  ! always recompute Jacobina when a new FAB starts

    !$omp do schedule(dynamic) collapse(2)
    do k=lo(3),hi(3)
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)

             if (st(i,j,k) .eq. 0.d0) then
                rho0 = 0.d0
                YT0 = 0.d0
                do g=1,8
                   call get_rhoYT(UG(i,j,k,g,:), rhot(g), YT(1:nspec,g), YT(nspec+1,g), ierr)
                   if (ierr .ne. 0) then
                      st(i,j,k) = -1.d0
                      force_new_J = .true.
                      exit
                   end if
                   YT0 = YT0 + 0.125d0*Yt(:,g)
                   rho0(1) = rho0(1) + 0.125d0*rhot(g)
                end do
             end if

             if (st(i,j,k) .eq. 0.d0) then
                call burn(1, rho0, YT0, dt, force_new_J, ierr)
                if (ierr .ne. 0) then
                   st(i,j,k) = -1.d0
                   force_new_J = .true.
                else
                   force_new_J = new_J_cell
                end if
             end if

             if (st(i,j,k) .eq. 0.d0) then

                call splitburn(8, rho0(1), YT0, rhot, Yt, dt)
                ! Now Yt is \Delta Y and T
                
                U(i,j,k,UFS:UFS+nspec-1) = 0.d0 
                do g=1,8
                   do n=1,nspec
                      U(i,j,k,UFS+n-1) = U(i,j,k,UFS+n-1) + &
                           0.125d0*(UG(i,j,k,g,UFS+n-1) + rhot(g)*Yt(n,g))
                   end do
                end do

             else  ! burn cell average instead

                call get_rhoYT(U(i,j,k,:), rhot(1), YT(1:nspec,1), YT(nspec+1,1), ierr)
                if (ierr .ne. 0) then
                   print *, 'chemterm_split: eos_get_T failed for U at ', &
                        level, i,j,k,U(i,j,k,:)
                   call bl_error("chemterm_split failed at eos_get_T")
                end if

                call burn(1, rhot(1:1), YT(:,1), dt, force_new_J, ierr)
                force_new_J = new_J_cell
                if (ierr .ne. 0) then
                   print *, 'chemterm_split: bdf burn failed for U at ', &
                        level, i,j,k,U(i,j,k,:)
                   call bl_error("chemterm_split failed at bdf burn for U")
                end if

                do n=1,nspec
                   U(i,j,k,UFS+n-1) = rhot(1)*YT(n,1)
                end do

             end if

          end do
       end do
    end do
    !$omp end do
    !$omp end parallel

    deallocate(UG)

  end subroutine chemterm_split


  subroutine chemterm_becc(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt, Up)
    use convert_module, only : cellavg2cc_3d, cc2cellavg_3d
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3), stlo(3), sthi(3)
    double precision, intent(inout) :: U(Ulo(1):Uhi(1),Ulo(2):Uhi(2),Ulo(3):Uhi(3),NVAR)
    double precision, intent(inout) :: st(stlo(1):sthi(1),stlo(2):sthi(2),stlo(3):sthi(3))
    double precision, intent(in) :: dt
    double precision, intent(in), optional :: Up(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),NVAR)

    integer :: i, j, k, n, ierr
    logical :: force_new_J
    double precision :: rho0(1), rhot(1), YT0(nspec+1), YT(nspec+1)
    double precision, allocatable :: Ucc(:,:,:,:)

    allocate(Ucc(lo(1)-1:hi(1)+1,lo(2)-1:hi(2)+1,lo(3)-1:hi(3)+1,NVAR))

    !$omp parallel private(i,j,k,n,ierr,rho0,rhot,YT0,YT,force_new_J)

    !$omp do
    do n=1,NVAR
       call cellavg2cc_3d(lo-1,hi+1, U(:,:,:,n), Ulo,Uhi, Ucc(:,:,:,n), lo-1,hi+1)
    end do
    !$omp end do

    force_new_J = .true.  ! always recompute Jacobian when a new FAB starts

    !$omp do schedule(dynamic) collapse(2)
    do k=lo(3)-1,hi(3)+1
       do j=lo(2)-1,hi(2)+1
          do i=lo(1)-1,hi(1)+1

             if (st(i,j,k) .eq. 0.d0) then

                call get_rhoYT(Ucc(i,j,k,:), rhot(1), YT(1:nspec), YT(nspec+1), ierr)

                if (ierr .ne. 0) then
                   st(i,j,k) = -1.d0
                   force_new_J = .true.
                else

                   if (present(Up) .and. i.ge.lo(1) .and. i.le.hi(1) &
                        .and.            j.ge.lo(2) .and. j.le.hi(2) &
                        .and.            k.ge.lo(3) .and. k.le.hi(3)) then

                      rho0(1) = Up(i,j,k,URHO)
                      YT0(1:nspec) = Up(i,j,k,UFS:UFS+nspec-1)/rho0(1)
                      YT0(nspec+1) = Up(i,j,k,UTEMP)

                   else

                      rho0(1) = rhot(1)
                      YT0 = YT

                      call burn(1, rho0, YT0, dt, force_new_J, ierr)
                      if (ierr .ne. 0) then
                         st(i,j,k) = -1.d0
                         force_new_J = .true.
                      else
                         force_new_J = new_J_cell
                      end if

                   end if

                end if

             end if

             if (st(i,j,k) .ne. 0.d0) then  ! burn cell average

                call get_rhoYT(U(i,j,k,:), rhot(1), YT(1:nspec), YT(nspec+1), ierr)
                if (ierr .ne. 0) then
                   print *, 'chemterm_becc: eos_get_T failed for U at ', &
                        level,i,j,k,U(i,j,k,:)
                   call bl_error("chemterm_becc failed at eos_get_T")
                end if

                if (present(Up) .and. i.ge.lo(1) .and. i.le.hi(1) &
                     .and.            j.ge.lo(2) .and. j.le.hi(2) &
                     .and.            k.ge.lo(3) .and. k.le.hi(3)) then

                   rho0(1) = Up(i,j,k,URHO)
                   YT0(1:nspec) = Up(i,j,k,UFS:UFS+nspec-1)/rho0(1)
                   YT0(nspec+1) = Up(i,j,k,UTEMP)
                   
                else
                   
                   rho0(1) = rhot(1)
                   YT0 = YT

                   force_new_J = .true.
                   call burn(1, rho0, YT0, dt, force_new_J, ierr)
                   force_new_J = new_J_cell
                   if (ierr .ne. 0) then
                      print *, 'chemterm_becc: bdf burn failed for U at ', &
                           level,i,j,k,U(i,j,k,:)
                      call bl_error("chemterm_becc failed at bdf burn for U")
                   end if

                end if
                
             end if

             call floor_species(nspec, YT0(1:nspec))

             call beburn(rho0(1), YT0, rhot(1), YT, dt, 1, ierr)
             if (ierr .ne. 0) then ! beburn failed
                print *, 'chemterm_becc: beburn failed at ',level,i,j,k,U(i,j,k,:)
                call bl_error("chemterm_becc: beburn failed")
             end if
             
             do n=1,nspec
                Ucc(i,j,k,UFS+n-1) = rhot(1)*YT(n)
             end do

          end do
       end do
    end do
    !$omp end do

    !$omp do
    do n=UFS,UFS+nspec-1
       call cc2cellavg_3d(lo,hi, Ucc(:,:,:,n), lo-1,hi+1, U(:,:,:,n), Ulo,Uhi)
    end do
    !$omp end do

    !$omp end parallel

    deallocate(Ucc)

  end subroutine chemterm_becc


  subroutine chemterm_begp(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt, Up)
    use weno_module, only : cellavg2gausspt_3d
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3), stlo(3), sthi(3)
    double precision, intent(inout) :: U(Ulo(1):Uhi(1),Ulo(2):Uhi(2),Ulo(3):Uhi(3),NVAR)
    double precision, intent(inout) :: st(stlo(1):sthi(1),stlo(2):sthi(2),stlo(3):sthi(3))
    double precision, intent(in) :: dt
    double precision, intent(in), optional :: Up(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),NVAR)

    integer :: i, j, k, n, g, ierr
    logical :: force_new_J
    double precision :: rhot(8), rho0(1)
    double precision :: Yt(nspec+1,8), YT0(nspec+1), rhoY(nspec)
    double precision, allocatable :: UG(:,:,:,:,:)

    allocate(UG(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),8,NVAR))

    if (chem_do_weno) then
       call chem_weno(lo, hi, U, Ulo, Uhi, UG)
    else
       !$omp parallel do private(n)
       do n=1,NVAR
          call cellavg2gausspt_3d(lo,hi, U(:,:,:,n), Ulo,Uhi, UG(:,:,:,:,n), lo,hi)
       end do
       !$omp end parallel do
    end if

    !$omp parallel private(i,j,k,n,g,ierr,rhot,Yt,force_new_J,rho0,YT0,rhoY)

    force_new_J = .true.  ! always recompute Jacobina when a new FAB starts

    !$omp do schedule(dynamic) collapse(2)
     do k=lo(3),hi(3)
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)

             if (st(i,j,k).eq.0.d0) then
                do g=1,8
                   call get_rhoYT(UG(i,j,k,g,:), rhot(g), YT(1:nspec,g), YT(nspec+1,g), ierr)
                   if (ierr .ne. 0) then
                      force_new_J = .true.
                      st(i,j,k) = -1.d0
                      exit
                   end if
                end do
             endif

             if (st(i,j,k) .eq. 0.d0) then

                if (present(Up)) then
                   rho0(1) = Up(i,j,k,URHO)
                   YT0(1:nspec) = Up(i,j,k,UFS:UFS+nspec-1)/rho0(1)
                   YT0(nspec+1) = Up(i,j,k,UTEMP)
                else
                   call get_rhoYT(U(i,j,k,:), rho0(1), YT0(1:nspec), YT0(nspec+1), ierr)
                   if (ierr .ne. 0) then
                      print *, 'chemterm_begp: eos_get_T failed for U at ', &
                           level,i,j,k,U(i,j,k,:)
                      call bl_error("chemterm_begp failed at eos_get_T for U")
                   end if
                
                   call burn(1, rho0, YT0, dt, force_new_J, ierr)
                   force_new_J = new_J_cell
                   if (ierr .ne. 0) then
                      print *, 'chemterm_begp: bdf burn failed at ', level,i,j,k,U(i,j,k,:)
                      print *, '   rho0, YT0 =', rho0(1), YT0
                      call bl_error("chemterm_begp failed at bdf burn")
                   end if
                end if
                
                call floor_species(nspec, YT0(1:nspec))

                rhoY = 0.d0
                do g=1,8
                   call beburn(rho0(1), YT0, rhot(g), Yt(:,g), dt, g, ierr)
                   if (ierr .ne. 0) then ! beburn failed
                      st(i,j,k) = -1.d0
                      force_new_J = .true.
                      exit
                   end if
                   do n=1,nspec
                      rhoY(n) = rhoY(n) + 0.125d0*rhot(g)*Yt(n,g)
                   end do
                end do
                
             end if

             if (st(i,j,k) .eq. 0.d0) then

                U(i,j,k,UFS:UFS+nspec-1) = rhoY

             else

                call get_rhoYT(U(i,j,k,:), rhot(1), YT(1:nspec,1), YT(nspec+1,1), ierr)
                if (ierr .ne. 0) then
                   print *, 'chemterm_begp: eos_get_T failed for U at ', &
                        level,i,j,k,U(i,j,k,:)
                   call bl_error("chemterm_begp failed at eos_get_T")
                end if

                if (present(Up)) then

                   rho0(1) = Up(i,j,k,URHO)
                   YT0(1:nspec) = Up(i,j,k,UFS:UFS+nspec-1)/rho0(1)
                   YT0(nspec+1) = Up(i,j,k,UTEMP)
                   
                else
                   
                   rho0(1) = rhot(1)
                   YT0 = YT(:,1)

                   force_new_J = .true.
                   call burn(1, rho0, YT0, dt, force_new_J, ierr)
                   force_new_J = new_J_cell
                   if (ierr .ne. 0) then
                      print *, 'chemterm_begp: bdf burn failed for U at ', &
                           level,i,j,k,U(i,j,k,:)
                      call bl_error("chemterm_begp failed at bdf burn for U")
                   end if

                end if

                call floor_species(nspec, YT0(1:nspec))

                call beburn(rho0(1), YT0, rhot(1), YT(:,1), dt, 1, ierr)
                if (ierr .ne. 0) then ! beburn failed
                   print *, 'chemterm_begp: beburn failed for U at ',level,i,j,k,U(i,j,k,:)
                   call bl_error("chemterm_begp: beburn failed")
                end if
             
                do n=1,nspec
                   U(i,j,k,UFS+n-1) = rhot(1)*YT(n,1)
                end do

             end if

          end do
       end do
    end do
    !$omp end do
    !$omp end parallel

    deallocate(UG)

  end subroutine chemterm_begp


  subroutine dUdt_chem_gauss(lo, hi, U, Ulo, Uhi, Ut, Utlo, Uthi, st, stlo, sthi)
    use weno_module, only : cellavg2gausspt_3d
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3), Utlo(3), Uthi(3), stlo(3), sthi(3)
    double precision, intent(in ) ::  U( Ulo(1): Uhi(1), Ulo(2): Uhi(2), Ulo(3): Uhi(3),NVAR)
    double precision, intent(out) :: Ut(Utlo(1):Uthi(1),Utlo(2):Uthi(2),Utlo(3):Uthi(3),NVAR)
    double precision, intent(inout) :: st(stlo(1):sthi(1),stlo(2):sthi(2),stlo(3):sthi(3))

    integer :: i, j, k, n, g, np, ierr
    double precision :: rho(lo(1):hi(1)), T(lo(1):hi(1))
    double precision :: Y(lo(1):hi(1),nspec), rdYdt(lo(1):hi(1),nspec)
    double precision, allocatable :: UG(:,:,:,:,:)

    np = hi(1)-lo(1)+1

    allocate(UG(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),8,NVAR))

    if (chem_do_weno) then
       call chem_weno(lo, hi, U, Ulo, Uhi, UG)
    else
       !$omp parallel do private(n)
       do n=1,NVAR
          call cellavg2gausspt_3d(lo,hi, U(:,:,:,n), Ulo,Uhi, UG(:,:,:,:,n), lo,hi)
       end do
       !$omp end parallel do
    end if

    !$omp parallel private(i,j,k,n,g,ierr,rho,T,Y,rdYdt)

    !$omp do
    do n=1,NVAR
       do k=lo(3),hi(3)
       do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          Ut(i,j,k,n) = 0.d0
       end do
       end do
       end do
    end do
    !$omp end do

    !$omp do collapse(2)
    do k=lo(3),hi(3)
       do j=lo(2),hi(2)

          do g=1,8

             do i=lo(1),hi(1)
                call get_rhoYT(UG(i,j,k,g,:), rho(i), Y(i,:), T(i), ierr)
                if (ierr .ne. 0) then
                   st(i,j,k) = -1.d0
                end if
             end do
             
             call compute_rhodYdt(np,rho,T,Y,rdYdt)
             
             do n=1,nspec
                do i=lo(1),hi(1)
                   Ut(i,j,k,UFS+n-1) = Ut(i,j,k,UFS+n-1) + 0.125d0*rdYdt(i,n)
                end do
             end do
             
          end do

          do i=lo(1),hi(1)
             if (st(i,j,k) .ne. 0.d0) then
                call get_rhoYT(U(i,j,k,:), rho(i), Y(i,:), T(i), ierr)
                if (ierr .ne. 0) then
                   print *, 'dUdt_chem_gauss: eos_get_T failed for U at ', &
                        level,i,j,k,U(i,j,k,:)
                   call bl_error("dUdt_chem_gauss failed at eos_get_T for U")
                end if
                call compute_rhodYdt(1,rho(i:i),T(i:i),Y(i:i,:),Ut(i:i,j,k,UFS:UFS+nspec-1))
             end if
          end do

       end do
    end do
    !$omp end do 

    !$omp end parallel

    deallocate(UG)

  end subroutine dUdt_chem_gauss


  subroutine dUdt_chem_cellcenter(lo, hi, U, Ulo, Uhi, Ut, Utlo, Uthi, st, stlo, sthi)
    use convert_module, only : cellavg2cc_3d, cc2cellavg_3d
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3), Utlo(3), Uthi(3), stlo(3), sthi(3)
    double precision, intent(in ) ::  U( Ulo(1): Uhi(1), Ulo(2): Uhi(2), Ulo(3): Uhi(3),NVAR)
    double precision, intent(out) :: Ut(Utlo(1):Uthi(1),Utlo(2):Uthi(2),Utlo(3):Uthi(3),NVAR)
    double precision, intent(inout) :: st(stlo(1):sthi(1),stlo(2):sthi(2),stlo(3):sthi(3))

    integer :: i, j, k, n, np, ierr
    double precision :: rho(lo(1)-1:hi(1)+1), Y(lo(1)-1:hi(1)+1,nspec), &
         T(lo(1)-1:hi(1)+1)
    double precision, allocatable :: Ucc(:,:,:,:), Utcc(:,:,:,:)

    np = hi(1)-lo(1)+3

    allocate( Ucc(lo(1)-1:hi(1)+1,lo(2)-1:hi(2)+1,lo(3)-1:hi(3)+1,NVAR))
    allocate(Utcc(lo(1)-1:hi(1)+1,lo(2)-1:hi(2)+1,lo(3)-1:hi(3)+1,nspec))

    !$omp parallel private(i,j,k,n,ierr,rho,Y,T)

    !$omp do
    do n=1,NVAR
       call cellavg2cc_3d(lo-1,hi+1, U(:,:,:,n), Ulo,Uhi, Ucc(:,:,:,n), lo-1,hi+1)
    end do
    !$omp end do

    !$omp do collapse(2)
    do k    = lo(3)-1, hi(3)+1
       do j = lo(2)-1, hi(2)+1
       
          do i = lo(1)-1, hi(1)+1
             if (st(i,j,k) .eq. 0.d0) then
                call get_rhoYT(Ucc(i,j,k,:), rho(i), Y(i,:), T(i), ierr)
                if (ierr .ne. 0) then
                   st(i,j,k) = -1.d0
                end if
             end if
             if (st(i,j,k) .ne. 0.d0) then
                call get_rhoYT(U(i,j,k,:), rho(i), Y(i,:), T(i), ierr)
                if (ierr .ne. 0) then
                   print *, 'dUdt_chem_cellcenter: eos_get_T failed for U at ', &
                        level,i,j,k,Ucc(i,j,k,:)
                   call bl_error("dUdt_chem_cellcenter failed at eos_get_T for U")
                end if
             end if
          end do

          call compute_rhodYdt(np,rho,T,Y,Utcc(:,j,k,:))

       end do
    end do
    !$omp end do

    !$omp do collapse(2)
    do n=1,UFS-1
       do k=lo(3),hi(3)
       do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          Ut(i,j,k,n) = 0.d0
       end do
       end do
       end do
    end do
    !$omp end do

    !$omp do
    do n=1,nspec
       call cc2cellavg_3d(lo,hi, Utcc(:,:,:,n), lo-1,hi+1, Ut(:,:,:,UFS+n-1), Utlo,Uthi)
    end do
    !$omp end do

    !$omp end parallel

    deallocate(Ucc,Utcc)

  end subroutine dUdt_chem_cellcenter


  subroutine get_rhoYT(U, rho, Y, T, ierr)
    double precision, intent(in) :: U(NVAR)
    double precision, intent(out) :: rho, Y(nspec), T
    integer, intent(out) :: ierr

    integer :: n
    double precision :: rhoinv, ei
    
    rho = 0.d0
    do n=1,NSPEC
       Y(n) = U(UFS+n-1)
       rho = rho + Y(n)
    end do
    rhoinv = 1.d0/rho
    
    Y = Y * rhoinv
    T = U(UTEMP)
    
    ei = rhoinv*( U(UEDEN) - 0.5d0*rhoinv*(U(UMX)**2 &
         + U(UMY)**2 + U(UMZ)**2) )
    
    call floor_species(nspec, Y)

    call eos_get_T(T, ei, Y, ierr=ierr)
  end subroutine get_rhoYT


  subroutine chem_weno(lo, hi, U, Ulo, Uhi, UG)
    use reconstruct_module, only : reconstruct_comp
    integer, intent(in) :: lo(3), hi(3), Ulo(3), Uhi(3)
    double precision, intent(in) :: U(Ulo(1):Uhi(1),Ulo(2):Uhi(2),Ulo(3):Uhi(3),NVAR)
    double precision, intent(out):: UG(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),8,NVAR)

    integer :: i,j,k,lo1,lo2,lo3,hi1,hi2,hi3
    double precision, allocatable :: UG1z(:,:,:,:), UG2z(:,:,:,:)
    double precision, allocatable :: UG1y(:,:,:,:), UG2y(:,:,:,:)

    lo1 = lo(1)
    lo2 = lo(2)
    lo3 = lo(3)
    hi1 = hi(1)
    hi2 = hi(2)
    hi3 = hi(3)

    allocate(UG1z(lo(1)-2:hi(1)+2,lo(2)-2:hi(2)+2,lo(3):hi(3),NVAR))
    allocate(UG2z(lo(1)-2:hi(1)+2,lo(2)-2:hi(2)+2,lo(3):hi(3),NVAR))
    allocate(UG1y(lo(1)-2:hi(1)+2,lo(2)  :hi(2)  ,lo(3):hi(3),NVAR))
    allocate(UG2y(lo(1)-2:hi(1)+2,lo(2)  :hi(2)  ,lo(3):hi(3),NVAR))

    !$omp parallel private(i,j,k)

    !$omp do collapse(2)
    do j   =lo2-2,hi2+2
       do i=lo1-2,hi1+2
          call reconstruct_comp(lo3,hi3, &
               Ulo(3),Uhi(3), &  ! for U
               0, 0,          &  ! for UL & UR, not present
               lo3,    hi3,   &  ! for UG1 & UG2
               U(i,j,:,:), &
               UG1=UG1z(i,j,:,:), UG2=UG2z(i,j,:,:) )
       end do
    end do
    !$omp end do

    !$omp do collapse(2)
    do k   =lo3  ,hi3
       do i=lo1-2,hi1+2
          call reconstruct_comp(lo2,hi2, &
               lo2-2,hi2+2,   &  ! for U
               0, 0,          &  ! for UL & UR, not present
               lo2  ,hi2,     &  ! for UG1 & UG2
               UG1Z(i,:,k,:), &
               UG1=UG1y(i,:,k,:), UG2=UG2y(i,:,k,:) )
       end do
    end do
    !$omp end do
    
    !$omp do collapse(2)
    do k   =lo3, hi3
       do j=lo2, hi2
          call reconstruct_comp(lo1,hi1, &
               lo1-2,hi1+2,   &  ! for U
               0, 0,          &  ! for UL & UR, not present
               lo1  ,hi1,     &  ! for UG1 & UG2
               UG1y(:,j,k,:), &
               UG1=UG(:,j,k,1,:), UG2=UG(:,j,k,2,:) )
          call reconstruct_comp(lo1,hi1, &
               lo1-2,hi1+2,   &  ! for U
               0, 0,          &  ! for UL & UR, not present
               lo1  ,hi1,     &  ! for UG1 & UG2
               UG2y(:,j,k,:), &
               UG1=UG(:,j,k,3,:), UG2=UG(:,j,k,4,:) )
       end do
    end do
    !$omp end do 
    
    !$omp do collapse(2)
    do k   =lo3  ,hi3
       do i=lo1-2,hi1+2
          call reconstruct_comp(lo2,hi2, &
               lo2-2,hi2+2,   &  ! for U
               0, 0,          &  ! for UL & UR, not present
               lo2  ,hi2,     &  ! for UG1 & UG2
               UG2Z(i,:,k,:), &
               UG1=UG1y(i,:,k,:), UG2=UG2y(i,:,k,:) )
       end do
    end do
    !$omp end do
    
    !$omp do collapse(2)
    do k   =lo3, hi3
       do j=lo2, hi2
          call reconstruct_comp(lo1,hi1, &
               lo1-2,hi1+2,   &  ! for U
               0, 0,          &  ! for UL & UR, not present
               lo1  ,hi1,     &  ! for UG1 & UG2
               UG1y(:,j,k,:), &
               UG1=UG(:,j,k,5,:), UG2=UG(:,j,k,6,:) )
          call reconstruct_comp(lo1,hi1, &
               lo1-2,hi1+2,   &  ! for U
               0, 0,          &  ! for UL & UR, not present
               lo1  ,hi1,     &  ! for UG1 & UG2
               UG2y(:,j,k,:), &
               UG1=UG(:,j,k,7,:), UG2=UG(:,j,k,8,:) )
       end do
    end do
    !$omp end do 

    !$omp end parallel

    deallocate(UG1z,UG2z,UG1y,UG2y)

  end subroutine chem_weno

end module chemterm_module
