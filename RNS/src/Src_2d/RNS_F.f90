
subroutine rns_dudt_ad (lo, hi, domlo, domhi, &
     U, U_l1, U_l2, U_h1, U_h2, &
     dUdt, Ut_l1, Ut_l2, Ut_h1, Ut_h2, &
     xflx, xf_l1, xf_l2, xf_h1, xf_h2, &
     yflx, yf_l1, yf_l2, yf_h1, yf_h2, &
     dx)
  use meth_params_module, only : NVAR, gravity, URHO, UMY, UEDEN, do_weno, &
       xblksize, yblksize, nthreads
  use hypterm_module, only : hypterm
  use difterm_module, only : difterm
  use threadbox_module, only : build_threadbox_2d, get_lo_hi
  implicit none

  integer, intent(in) :: lo(2), hi(2), domlo(2), domhi(2)
  integer, intent(in) ::  U_l1,  U_h1,  U_l2,  U_h2
  integer, intent(in) :: Ut_l1, Ut_h1, Ut_l2, Ut_h2
  integer, intent(in) :: xf_l1, xf_h1, xf_l2, xf_h2
  integer, intent(in) :: yf_l1, yf_h1, yf_l2, yf_h2
  double precision, intent(in)  ::    U( U_l1: U_h1, U_l2: U_h2,NVAR)
  double precision, intent(out) :: dUdt(Ut_l1:Ut_h1,Ut_l2:Ut_h2,NVAR)
  double precision, intent(out) :: xflx(xf_l1:xf_h1,xf_l2:xf_h2,NVAR)
  double precision, intent(out) :: yflx(yf_l1:yf_h1,yf_l2:yf_h2,NVAR)
  double precision, intent(in)  :: dx(2)

  integer :: Ulo(2), Uhi(2), fxlo(2), fxhi(2), fylo(2), fyhi(2), tlo(2), thi(2)
  integer :: iblock, nblocks, i, j, n, ib, jb, nb(2), boxsize(2)
  double precision :: dxinv(2)
  double precision, allocatable :: bxflx(:,:,:), byflx(:,:,:)
  integer, allocatable :: bxlo(:), bxhi(:), bylo(:), byhi(:)

  integer, parameter :: blocksize_min = 4

  dxinv(1) = 1.d0/dx(1)
  dxinv(2) = 1.d0/dx(2)
  
  Ulo(1) = U_l1
  Ulo(2) = U_l2
  Uhi(1) = U_h1
  Uhi(2) = U_h2

  boxsize = hi-lo+1

  if (nthreads > 1) then
     call build_threadbox_2d(nthreads, boxsize, blocksize_min, nb)
     if (nb(1).eq.0) then
        nb = boxsize/blocksize_min
     end if
  else
     nb(1) = max(boxsize(1)/xblksize, 1)
     nb(2) = max(boxsize(2)/yblksize, 1)
  end if

  allocate(bxlo(0:nb(1)-1))
  allocate(bxhi(0:nb(1)-1))
  allocate(bylo(0:nb(2)-1))
  allocate(byhi(0:nb(2)-1))

  call get_lo_hi(boxsize(1), nb(1), bxlo, bxhi)
  call get_lo_hi(boxsize(2), nb(2), bylo, byhi)

  nblocks = nb(1)*nb(2)

  !$omp parallel private(fxlo,fxhi,fylo,fyhi,tlo,thi,i,j,n,ib,jb,bxflx,byflx,iblock)
  
  !$omp do
  do iblock = 0, nblocks-1
     
     jb = iblock / nb(1)
     ib = iblock - jb*nb(1)

     tlo(1) = lo(1) + bxlo(ib)
     thi(1) = lo(1) + bxhi(ib)
     
     tlo(2) = lo(2) + bylo(jb)
     thi(2) = lo(2) + byhi(jb)
     
     fxlo(1) = tlo(1)
     fxlo(2) = tlo(2)
     fxhi(1) = thi(1)+1
     fxhi(2) = thi(2)
     
     fylo(1) = tlo(1)
     fylo(2) = tlo(2)
     fyhi(1) = thi(1)
     fyhi(2) = thi(2)+1
     
     allocate(bxflx(fxlo(1):fxhi(1),fxlo(2):fxhi(2),NVAR))
     allocate(byflx(fylo(1):fyhi(1),fylo(2):fyhi(2),NVAR))
     
     bxflx = 0.d0
     byflx = 0.d0
     
     if (do_weno) then
        call hypterm(tlo,thi,domlo,domhi,U,Ulo,Uhi,bxflx,fxlo,fxhi,byflx,fylo,fyhi,dx)
     end if
     call difterm(tlo,thi,domlo,domhi,U,Ulo,Uhi,bxflx,fxlo,fxhi,byflx,fylo,fyhi,dx)
     
     ! Note that fluxes are on faces.  So don't double count!
     if (thi(1) .ne. hi(1)) fxhi(1) = fxhi(1) - 1
     if (thi(2) .ne. hi(2)) fyhi(2) = fyhi(2) - 1
     
     do n=1,NVAR
        do j=fxlo(2),fxhi(2)
           do i=fxlo(1),fxhi(1)
              xflx(i,j,n) = bxflx(i,j,n)
           end do
        end do
        
        do j=fylo(2),fyhi(2)
           do i=fylo(1),fyhi(1)
              yflx(i,j,n) = byflx(i,j,n)
           end do
        end do
     end do
     
     deallocate(bxflx,byflx)
     
  end do
  !$omp end do

  !$omp do
  do n=1, NVAR
     do j=lo(2),hi(2)
        do i=lo(1),hi(1)
           dUdt(i,j,n) = dxinv(1)*(xflx(i,j,n)-xflx(i+1,j,n)) &
                +        dxinv(2)*(yflx(i,j,n)-yflx(i,j+1,n))
        end do
     end do
  end do
  !$omp end do

  if (gravity .ne. 0.d0) then
     !$omp do
     do j=lo(2),hi(2)
        do i=lo(1),hi(1)
           dUdt(i,j,UMY  ) = dUdt(i,j,UMY  ) + U(i,j,URHO)*gravity
           dUdt(i,j,UEDEN) = dUdt(i,j,UEDEN) + U(i,j,UMY )*gravity
        end do
     end do
     !$omp end do
  end if
  
  !$omp end parallel

  deallocate(bxlo,bxhi,bylo,byhi)

end subroutine rns_dudt_ad

! :::
! ::: ------------------------------------------------------------------
! :::

subroutine rns_advchem(lo,hi,U,U_l1,U_l2,U_h1,U_h2, &
     st,st_l1,st_l2,st_h1,st_h2, dt)
  use meth_params_module, only : NVAR
  use chemterm_module, only : chemterm
  implicit none
  integer, intent(in) :: lo(2), hi(2)
  integer, intent(in) ::  U_l1, U_l2, U_h1, U_h2, st_l1,st_l2,st_h1,st_h2
  double precision, intent(inout) :: U(U_l1:U_h1,U_l2:U_h2,NVAR)
  double precision, intent(inout) :: st(st_l1:st_h1,st_l2:st_h2)
  double precision, intent(in) :: dt

  integer :: Ulo(2), Uhi(2), stlo(2), sthi(2)

  Ulo(1) = U_l1
  Ulo(2) = U_l2
  Uhi(1) = U_h1
  Uhi(2) = U_h2
  stlo(1) = st_l1
  stlo(2) = st_l2
  sthi(1) = st_h1
  sthi(2) = st_h2
  call chemterm(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt)
end subroutine rns_advchem

subroutine rns_advchem2(lo,hi,U,U_l1,U_l2,U_h1,U_h2, &
     st,st_l1,st_l2,st_h1,st_h2, &
     Up,Up_l1,Up_l2,Up_h1,Up_h2,dt)
  use meth_params_module, only : NVAR
  use chemterm_module, only : chemterm
  implicit none
  integer, intent(in) :: lo(2), hi(2)
  integer, intent(in) ::  U_l1, U_l2, U_h1, U_h2, st_l1,st_l2,st_h1,st_h2
  integer, intent(in) ::  Up_l1, Up_l2, Up_h1, Up_h2
  double precision, intent(inout) :: U(U_l1:U_h1,U_l2:U_h2,NVAR)
  double precision, intent(inout) :: st(st_l1:st_h1,st_l2:st_h2)
  double precision, intent(in) :: Up(Up_l1:Up_h1,Up_l2:Up_h2,NVAR)
  double precision, intent(in) :: dt

  integer :: Ulo(2), Uhi(2), stlo(2), sthi(2)

  Ulo(1) = U_l1
  Ulo(2) = U_l2
  Uhi(1) = U_h1
  Uhi(2) = U_h2
  stlo(1) = st_l1
  stlo(2) = st_l2
  sthi(1) = st_h1
  sthi(2) = st_h2
  call chemterm(lo, hi, U, Ulo, Uhi, st, stlo, sthi, dt, Up)
end subroutine rns_advchem2

! :::
! ::: ------------------------------------------------------------------
! :::

subroutine rns_dUdt_chem(lo,hi,U,U_l1,U_l2,U_h1,U_h2,Ut,Ut_l1,Ut_l2,Ut_h1,Ut_h2, &
          st,st_l1,st_l2,st_h1,st_h2)
  use meth_params_module, only : NVAR
  use chemterm_module, only : dUdt_chem
  implicit none
  integer, intent(in) :: lo(2), hi(2)
  integer, intent(in) ::  U_l1, U_h1, Ut_l1, Ut_h1, U_l2, U_h2, Ut_l2, Ut_h2, &
       st_l1,st_l2,st_h1,st_h2
  double precision, intent(in ) ::  U( U_l1: U_h1, U_l2: U_h2,NVAR)
  double precision, intent(out) :: Ut(Ut_l1:Ut_h1,Ut_l2:Ut_h2,NVAR)
  double precision, intent(inout) :: st(st_l1:st_h1,st_l2:st_h2)

  integer :: Ulo(2), Uhi(2), Utlo(2), Uthi(2), stlo(2), sthi(2)

  Ulo(1) = U_l1
  Ulo(2) = U_l2
  Uhi(1) = U_h1
  Uhi(2) = U_h2
  Utlo(1) = Ut_l1
  Utlo(2) = Ut_l2
  Uthi(1) = Ut_h1
  Uthi(2) = Ut_h2
  stlo(1) = st_l1
  stlo(2) = st_l2
  sthi(1) = st_h1
  sthi(2) = st_h2
  call dUdt_chem(lo, hi, U, Ulo, Uhi, Ut, Utlo, Uthi, st, stlo, sthi)
end subroutine rns_dUdt_chem

! :::
! ::: ------------------------------------------------------------------
! :::

subroutine rns_compute_temp(lo,hi,U,U_l1,U_l2,U_h1,U_h2)
  use meth_params_module, only : NVAR, URHO, UMX, UMY, UEDEN, UTEMP, UFS, NSPEC
  use eos_module, only : eos_get_T
  implicit none
  
  integer, intent(in) :: lo(2), hi(2)
  integer, intent(in) :: U_l1, U_l2, U_h1, U_h2
  double precision, intent(inout) :: U(U_l1:U_h1,U_l2:U_h2,NVAR)

  integer :: i, j, pt_index(2), ierr
  double precision :: rhoInv, e, vx, vy, Y(NSPEC)

  !$omp parallel do private(i,j,rhoInv,e,vx,vy,Y,pt_index,ierr)
  do j=lo(2),hi(2)
  do i=lo(1),hi(1)
     pt_index(1) = i
     pt_index(2) = j

     rhoInv = 1.0d0/U(i,j,URHO)

     vx = U(i,j,UMX)*rhoInv     
     vy = U(i,j,UMY)*rhoInv     
     e  = U(i,j,UEDEN)*rhoInv - 0.5d0*(vx**2+vy**2)

     Y = U(i,j,UFS:UFS+NSPEC-1)*rhoInv

     call eos_get_T(U(i,j,UTEMP), e, Y, pt_index, ierr)

     if (ierr .ne. 0) then
        print *, 'rns_compute_temp failed at ', i,j,U(i,j,:)
        call bl_error("rns_compute_temp failed")
     end if
  end do
  end do
  !$omp end parallel do
end subroutine rns_compute_temp

! :::
! ::: ------------------------------------------------------------------
! :::

subroutine rns_enforce_consistent_Y(lo,hi,U,U_l1,U_l2,U_h1,U_h2)
  use meth_params_module, only : NVAR, URHO, UFS, NSPEC
  implicit none
  
  integer, intent(in) :: lo(2), hi(2)
  integer, intent(in) :: U_l1, U_l2, U_h1, U_h2
  double precision, intent(inout) :: U(U_l1:U_h1,U_l2:U_h2,NVAR)

  ! Local variables
  integer          :: i,j,n
  integer          :: int_dom_spec
  logical          :: any_negative
  double precision :: dom_spec,x,rhoInv, sumrY, fac

  double precision, parameter :: eps = -1.d-16

  !$omp parallel do private(i,j,n,int_dom_spec,any_negative,dom_spec) &
  !$omp private(x,rhoInv,sumrY,fac)
  do j = lo(2),hi(2)
  do i = lo(1),hi(1)

     any_negative = .false.

     rhoInv = 1.d0/U(i,j,URHO)

     sumrY = 0.d0

     ! First deal with tiny undershoots by just setting them to zero
     do n = UFS, UFS+nspec-1
        if (U(i,j,n) .lt. 0.d0) then
           x = U(i,j,n) * rhoInv
           if (x .gt. eps) then
              U(i,j,n) = 0.d0
           else
              any_negative = .true.
           end if
        end if

        sumrY = sumrY + U(i,j,n)
     end do

     fac = U(i,j,URHO)/sumrY
     do n = UFS, UFS+nspec-1
        U(i,j,n) = U(i,j,n)*fac
     end do

     ! We know there are one or more undershoots needing correction 
     if (any_negative) then

        ! Find the dominant species
        dom_spec = 0.d0
        int_dom_spec = 0
        do n = UFS,UFS+nspec-1
           if (U(i,j,n) .gt. dom_spec) then
              dom_spec = U(i,j,n)
              int_dom_spec = n
           end if
        end do

        ! Now take care of undershoots greater in magnitude than 1e-16.
        do n = UFS, UFS+nspec-1
           
           if (U(i,j,n) .lt. 0.d0) then
              
              x = U(i,j,n)*rhoInv
              
              ! ! Here we only print the bigger negative values
              ! if (x .lt. -1.d-2) then
              !    print *,'Correcting negative species   ',n-UFS+1
              !    print *,'   at cell (i,j)              ',i,j
              !    print *,'Negative (rho*Y) is           ',U(i,j,n)
              !    print *,'Negative      Y  is           ',x
              !    print *,'Filling from dominant species ',int_dom_spec-UFS+1
              !    print *,'  which had Y =               ',&
              !         U(i,j,int_dom_spec) / U(i,j,URHO)
              ! end if

              ! Take enough from the dominant species to fill the negative one.
              U(i,j,int_dom_spec) = U(i,j,int_dom_spec) + U(i,j,n)
   
              ! Test that we didn't make the dominant species negative
              if (U(i,j,int_dom_spec) .lt. 0.d0) then 
                 print *,' Just made dominant species negative ',int_dom_spec-UFS+1,' at ',i,j
                 print *,'We were fixing species ',n-UFS+1,' which had value ',x
                 print *,'Dominant species became ',U(i,j,int_dom_spec)*rhoinv
                 call bl_error("rns_enforce_consistent_Y")
              end if

              ! Now set the negative species to zero
              U(i,j,n) = 0.d0

           end if

        end do

     end if
     
  end do
  end do
  !$omp end parallel do

end subroutine rns_enforce_consistent_Y


subroutine rns_sum_cons ( &
     U  ,U_l1,U_l2,U_h1,U_h2, &
     msk,m_l1,m_l2,m_h1,m_h2, &
     vol,v_l1,v_l2,v_h1,v_h2, &
     s)
  use meth_params_module, only : NVAR
  implicit none
  
  integer, intent(in) :: U_l1,U_l2,U_h1,U_h2
  integer, intent(in) :: m_l1,m_l2,m_h1,m_h2
  integer, intent(in) :: v_l1,v_l2,v_h1,v_h2
  double precision, intent(in) :: U  (U_l1:U_h1,U_l2:U_h2,NVAR)
  double precision, intent(in) :: msk(m_l1:m_h1,m_l2:m_h2)
  double precision, intent(in) :: vol(v_l1:v_h1,v_l2:v_h2)
  double precision, intent(inout) :: s(4)

  integer :: i, j, n

  !$omp parallel do private(i,j,n)
  do n=1,4
     do j=m_l2,m_h2
        do i=m_l1,m_h1
           s(n) = s(n) + msk(i,j)*vol(i,j)*U(i,j,n)
        end do
     end do
  end do
  !$omp end parallel do

end subroutine rns_sum_cons

! :::
! ::: ------------------------------------------------------------------
! :::

      subroutine rns_estdt(u,u_l1,u_l2,u_h1,u_h2,lo,hi,dx,dt)
        use eos_module, only : eos_get_c
        use meth_params_module, only : NVAR, URHO, UMX, UMY, UEDEN, UTEMP, UFS, NSPEC
        implicit none

        integer u_l1,u_l2,u_h1,u_h2
        integer lo(2), hi(2)
        double precision u(u_l1:u_h1,u_l2:u_h2,NVAR)
        double precision dx(2), dt

        integer :: i, j
        double precision :: rhoInv, vx, vy, T, e, c, Y(NSPEC)

        !$omp parallel do private(i,j,rhoInv,vx,vy,T,e,c,Y) reduction(min:dt)
        do j = lo(2), hi(2)
        do i = lo(1), hi(1)
           rhoInv = 1.d0/u(i,j,URHO)

           vx = u(i,j,UMX)*rhoInv
           vy = u(i,j,UMY)*rhoInv
           T  = u(i,j,UTEMP)
           
           e = u(i,j,UEDEN)*rhoInv - 0.5d0*(vx**2+vy**2)
           
           Y = u(i,j,UFS:UFS+NSPEC-1)*rhoInv
           
           call eos_get_c(c,u(i,j,URHO),T,Y)

           dt = min(dt, dx(1)/(abs(vx)+c+1.d-50), dx(2)/(abs(vy)+c+1.d-50))
        end do
        end do
        !$omp end parallel do

      end subroutine rns_estdt
