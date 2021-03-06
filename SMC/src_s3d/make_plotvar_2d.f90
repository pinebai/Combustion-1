module make_plotvar_2d_module

  implicit none

contains

  subroutine make_wbar_2d(lo, hi, w,  vlo, vhi, Q, qlo, qhi)
    use variables_module
    integer, intent(in) :: lo(2), hi(2), vlo(2), vhi(2), qlo(2), qhi(2)
    double precision, intent(inout) :: w(vlo(1):vhi(1),vlo(2):vhi(2))
    double precision, intent(in   ) :: Q(qlo(1):qhi(1),qlo(2):qhi(2),nprim)

    integer :: i,j,iwrk
    double precision :: rwrk, Yt(nspecies)

    do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          Yt = Q(i,j,qy1:qy1+nspecies-1)
          call ckmmwy(Yt, iwrk, rwrk, w(i,j))
       enddo
    enddo

  end subroutine make_wbar_2d


  subroutine make_h_2d(lo, hi, h,  vlo, vhi, Q, qlo, qhi)
    use variables_module
    integer, intent(in) :: lo(2), hi(2), vlo(2), vhi(2), qlo(2), qhi(2)
    double precision, intent(inout) :: h(vlo(1):vhi(1),vlo(2):vhi(2))
    double precision, intent(in   ) :: Q(qlo(1):qhi(1),qlo(2):qhi(2),nprim)

    integer :: i,j, n, qyn, qhn

    do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          h(i,j) = 0.d0
          do n=1, nspecies
             qhn = qh1+n-1
             qyn = qy1+n-1
             h(i,j) = h(i,j) + q(i,j,qyn)*q(i,j,qhn)
          end do
       enddo
    enddo

  end subroutine make_h_2d


  subroutine make_rhoh_2d(lo, hi, rh,  vlo, vhi, Q, qlo, qhi)
    use variables_module
    integer, intent(in) :: lo(2), hi(2), vlo(2), vhi(2), qlo(2), qhi(2)
    double precision, intent(inout) :: rh(vlo(1):vhi(1),vlo(2):vhi(2))
    double precision, intent(in   ) ::  Q(qlo(1):qhi(1),qlo(2):qhi(2),nprim)

    integer :: i,j, n, qyn, qhn

    do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          rh(i,j) = 0.d0
          do n=1, nspecies
             qhn = qh1+n-1
             qyn = qy1+n-1
             rh(i,j) = rh(i,j) + q(i,j,qyn)*q(i,j,qhn)
          end do
          rh(i,j) = rh(i,j) * q(i,j,qrho)
       enddo
    enddo

  end subroutine make_rhoh_2d


  subroutine make_cs_2d(lo, hi, cs, vlo, vhi, Q, qlo, qhi)
    use variables_module
    use chemistry_module, only : Ru
    integer, intent(in) :: lo(2), hi(2), vlo(2), vhi(2), qlo(2), qhi(2)
    double precision, intent(inout) :: cs(vlo(1):vhi(1),vlo(2):vhi(2))
    double precision, intent(in   ) ::  Q(qlo(1):qhi(1),qlo(2):qhi(2),nprim)

    integer :: i,j, iwrk
    double precision :: Tt, Yt(nspecies), cv, cp, Wbar, gamma, rwrk

    do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          Tt = q(i,j,qtemp)
          Yt = q(i,j,qy1:qy1+nspecies-1)
          
          call ckcvbs(Tt, Yt, iwrk, rwrk, cv)
          call ckmmwy(Yt, iwrk, rwrk, Wbar)
          
          cp = cv + Ru/Wbar
          gamma = cp / cv
          cs(i,j) = sqrt(gamma*q(i,j,qpres)/q(i,j,qrho))
       enddo
    enddo

  end subroutine make_cs_2d


  subroutine make_magvel_2d(lo, hi, v, vlo, vhi, Q, qlo, qhi)
    use variables_module
    integer, intent(in) :: lo(2), hi(2), vlo(2), vhi(2), qlo(2), qhi(2)
    double precision, intent(inout) ::  v(vlo(1):vhi(1),vlo(2):vhi(2))
    double precision, intent(in   ) ::  Q(qlo(1):qhi(1),qlo(2):qhi(2),nprim)

    integer :: i,j

    do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          v(i,j) = sqrt(q(i,j,qu)**2+q(i,j,qv)**2)
       enddo
    enddo

  end subroutine make_magvel_2d


  subroutine make_Mach_2d(lo, hi, Ma, vlo, vhi, Q, qlo, qhi)
    use variables_module
    use chemistry_module, only : Ru
    integer, intent(in) :: lo(2), hi(2), vlo(2), vhi(2), qlo(2), qhi(2)
    double precision, intent(inout) :: Ma(vlo(1):vhi(1),vlo(2):vhi(2))
    double precision, intent(in   ) ::  Q(qlo(1):qhi(1),qlo(2):qhi(2),nprim)

    integer :: i,j, iwrk
    double precision :: Tt, Yt(nspecies), cv, cp, Wbar, gamma, cs2, v2, rwrk

    do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          Tt = q(i,j,qtemp)
          Yt = q(i,j,qy1:qy1+nspecies-1)
          
          call ckcvbs(Tt, Yt, iwrk, rwrk, cv)
          call ckmmwy(Yt, iwrk, rwrk, Wbar)
          
          cp = cv + Ru/Wbar
          gamma = cp / cv
          cs2 = gamma*q(i,j,qpres)/q(i,j,qrho)

          v2 = q(i,j,qu)**2+q(i,j,qv)**2

          Ma(i,j) = sqrt(v2/cs2)
       enddo
    enddo

  end subroutine make_Mach_2d


  subroutine make_divu_2d(lo, hi, divu, vlo, vhi, Q, qlo, qhi, dx, dlo_g, dhi_g)
    use variables_module
    use derivative_stencil_module, only : stencil_ng, first_deriv_8, first_deriv_6, &
                first_deriv_4, first_deriv_l3, first_deriv_r3, first_deriv_rb, first_deriv_lb

    integer, intent(in) :: lo(2), hi(2), vlo(2), vhi(2), qlo(2), qhi(2), dlo_g(2), dhi_g(2)
    double precision, intent(inout) :: divu(vlo(1):vhi(1),vlo(2):vhi(2))
    double precision, intent(in   ) ::    Q(qlo(1):qhi(1),qlo(2):qhi(2),nprim)
    double precision, intent(in) :: dx(2)

    integer :: i,j
    double precision, allocatable :: ux(:,:), vy(:,:)
    double precision :: dxinv(2)
    integer :: slo(2), shi(2), dlo(2), dhi(2)

    ! Only the region bounded by [dlo,dhi] contains good data.
    ! [slo,shi] will be safe for 8th-order stencil
    do i=1,2
       dlo(i) = max(lo(i)-stencil_ng, dlo_g(i))
       dhi(i) = min(hi(i)+stencil_ng, dhi_g(i))
       slo(i) = dlo(i) + stencil_ng
       shi(i) = dhi(i) - stencil_ng
    end do

    do i=1,2
       dxinv(i) = 1.0d0 / dx(i)
    end do

    allocate(ux(lo(1):hi(1),lo(2):hi(2)))
    allocate(vy(lo(1):hi(1),lo(2):hi(2)))

    do j=lo(2),hi(2)

       do i=slo(1),shi(1)
          ux(i,j) = dxinv(1)*first_deriv_8(q(i-4:i+4,j,qu))
       enddo
          
       ! lo-x boundary
       if (dlo(1) .eq. lo(1)) then
          i = lo(1)
          ! use completely right-biased stencil
          ux(i,j) = dxinv(1)*first_deriv_rb(q(i:i+3,j,qu))
          
          i = lo(1)+1
          ! use 3rd-order slightly right-biased stencil
          ux(i,j) = dxinv(1)*first_deriv_r3(q(i-1:i+2,j,qu))
          
          i = lo(1)+2
          ! use 4th-order stencil
          ux(i,j) = dxinv(1)*first_deriv_4(q(i-2:i+2,j,qu))
          
          i = lo(1)+3
          ! use 6th-order stencil
          ux(i,j) = dxinv(1)*first_deriv_6(q(i-3:i+3,j,qu))
       end if
       
       ! hi-x boundary
       if (dhi(1) .eq. hi(1)) then
          i = hi(1)-3
          ! use 6th-order stencil
          ux(i,j) = dxinv(1)*first_deriv_6(q(i-3:i+3,j,qu))
          
          i = hi(1)-2
          ! use 4th-order stencil
          ux(i,j) = dxinv(1)*first_deriv_4(q(i-2:i+2,j,qu))
          
          i = hi(1)-1
          ! use 3rd-order slightly left-biased stencil
          ux(i,j) = dxinv(1)*first_deriv_l3(q(i-2:i+1,j,qu))
          
          i = hi(1)
          ! use completely left-biased stencil
          ux(i,j) = dxinv(1)*first_deriv_lb(q(i-3:i,j,qu))
       end if
       
    end do

    do j=slo(2),shi(2)
       do i=lo(1),hi(1)
          vy(i,j) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,qv))
       enddo
    end do

    ! lo-y boundary
    if (dlo(2) .eq. lo(2)) then
       j = lo(2)
       ! use completely right-biased stencil
       do i=lo(1),hi(1)
          vy(i,j) = dxinv(2)*first_deriv_rb(q(i,j:j+3,qv))
       enddo
       
       j = lo(2)+1
       ! use 3rd-order slightly right-biased stencil
       do i=lo(1),hi(1)
          vy(i,j) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,qv))
       enddo
       
       j = lo(2)+2
       ! use 4th-order stencil
       do i=lo(1),hi(1)
          vy(i,j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qv))
       enddo
       
       j = lo(2)+3
       ! use 6th-order stencil
       do i=lo(1),hi(1)
          vy(i,j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qv))
       enddo
    end if
    
    ! hi-y boundary
    if (dhi(2) .eq. hi(2)) then
       j = hi(2)-3
       ! use 6th-order stencil
       do i=lo(1),hi(1)
          vy(i,j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qv))
       enddo
       
       j = hi(2)-2
       ! use 4th-order stencil
       do i=lo(1),hi(1)
          vy(i,j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qv))
       enddo
       
       j = hi(2)-1
       ! use 3rd-order slightly left-biased stencil
       do i=lo(1),hi(1)
          vy(i,j) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,qv))
       enddo
       
       j = hi(2)
       ! use completely left-biased stencil
       do i=lo(1),hi(1)
          vy(i,j) = dxinv(2)*first_deriv_lb(q(i,j-3:j,qv))
       enddo
    end if

    do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          divu(i,j) = ux(i,j) + vy(i,j)
       end do
    enddo

    deallocate(ux,vy)

  end subroutine make_divu_2d


  subroutine make_magvort_2d(lo, hi, mvor, vlo, vhi, Q, qlo, qhi, dx, dlo_g, dhi_g)
    use variables_module
    use derivative_stencil_module, only : stencil_ng, first_deriv_8, first_deriv_6, &
                first_deriv_4, first_deriv_l3, first_deriv_r3, first_deriv_rb, first_deriv_lb

    integer, intent(in) :: lo(2), hi(2), vlo(2), vhi(2), qlo(2), qhi(2), dlo_g(2), dhi_g(2)
    double precision, intent(inout) :: mvor(vlo(1):vhi(1),vlo(2):vhi(2))
    double precision, intent(in   ) ::    Q(qlo(1):qhi(1),qlo(2):qhi(2),nprim)
    double precision, intent(in) :: dx(2)

    integer :: i,j
    double precision, dimension(:,:), allocatable :: uy,vx
    double precision :: dxinv(2)
    integer :: slo(2), shi(2), dlo(2), dhi(2)

    ! Only the region bounded by [dlo,dhi] contains good data.
    ! [slo,shi] will be safe for 8th-order stencil
    do i=1,2
       dlo(i) = max(lo(i)-stencil_ng, dlo_g(i))
       dhi(i) = min(hi(i)+stencil_ng, dhi_g(i))
       slo(i) = dlo(i) + stencil_ng
       shi(i) = dhi(i) - stencil_ng
    end do

    do i=1,2
       dxinv(i) = 1.0d0 / dx(i)
    end do

    allocate(uy(lo(1):hi(1),lo(2):hi(2)))
    allocate(vx(lo(1):hi(1),lo(2):hi(2)))

    do j=lo(2),hi(2)
       
       do i=slo(1),shi(1)
          vx(i,j) = dxinv(1)*first_deriv_8(q(i-4:i+4,j,qv))
       enddo
       
       ! lo-x boundary
       if (dlo(1) .eq. lo(1)) then
          i = lo(1)
          ! use completely right-biased stencil
          vx(i,j) = dxinv(1)*first_deriv_rb(q(i:i+3,j,qv))
          
          i = lo(1)+1
          ! use 3rd-order slightly right-biased stencil
          vx(i,j) = dxinv(1)*first_deriv_r3(q(i-1:i+2,j,qv))
          
          i = lo(1)+2
          ! use 4th-order stencil
          vx(i,j) = dxinv(1)*first_deriv_4(q(i-2:i+2,j,qv))
          
          i = lo(1)+3
          ! use 6th-order stencil
          vx(i,j) = dxinv(1)*first_deriv_6(q(i-3:i+3,j,qv))
       end if

       ! hi-x boundary
       if (dhi(1) .eq. hi(1)) then
          i = hi(1)-3
          ! use 6th-order stencil
          vx(i,j) = dxinv(1)*first_deriv_6(q(i-3:i+3,j,qv))

          i = hi(1)-2
          ! use 4th-order stencil
          vx(i,j) = dxinv(1)*first_deriv_4(q(i-2:i+2,j,qv))
          
          i = hi(1)-1
          ! use 3rd-order slightly left-biased stencil
          vx(i,j) = dxinv(1)*first_deriv_l3(q(i-2:i+1,j,qv))
          
          i = hi(1)
          ! use completely left-biased stencil
          vx(i,j) = dxinv(1)*first_deriv_lb(q(i-3:i,j,qv))
       end if

    end do

    do j=slo(2),shi(2)
       do i=lo(1),hi(1)
          uy(i,j) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,qu))
       enddo
    end do

    ! lo-y boundary
    if (dlo(2) .eq. lo(2)) then
       j = lo(2)
       ! use completely right-biased stencil
       do i=lo(1),hi(1)
          uy(i,j) = dxinv(2)*first_deriv_rb(q(i,j:j+3,qu))
       enddo
       
       j = lo(2)+1
       ! use 3rd-order slightly right-biased stencil
       do i=lo(1),hi(1)
          uy(i,j) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,qu))
       enddo

       j = lo(2)+2
       ! use 4th-order stencil
       do i=lo(1),hi(1)
          uy(i,j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qu))
       enddo
       
       j = lo(2)+3
       ! use 6th-order stencil
       do i=lo(1),hi(1)
          uy(i,j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qu))
       enddo
    end if

    ! hi-y boundary
    if (dhi(2) .eq. hi(2)) then
       j = hi(2)-3
       ! use 6th-order stencil
       do i=lo(1),hi(1)
          uy(i,j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qu))
       enddo

       j = hi(2)-2
       ! use 4th-order stencil
       do i=lo(1),hi(1)
          uy(i,j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qu))
       enddo
       
       j = hi(2)-1
       ! use 3rd-order slightly left-biased stencil
       do i=lo(1),hi(1)
          uy(i,j) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,qu))
       enddo
       
       j = hi(2)
       ! use completely left-biased stencil
       do i=lo(1),hi(1)
          uy(i,j) = dxinv(2)*first_deriv_lb(q(i,j-3:j,qu))
       enddo
    end if

    do j=lo(2),hi(2)
       do i=lo(1),hi(1)
!          mvor(i,j) = abs(vx(i,j)-uy(i,j))
          mvor(i,j) = vx(i,j)-uy(i,j)
       end do
    end do

    deallocate(uy,vx)

  end subroutine make_magvort_2d


  subroutine make_burn_2d(lo, hi, burn, vlo, vhi, Q, qlo, qhi)
    use plotvar_index_module
    use variables_module
    use chemistry_module, only : molecular_weight, h0 => std_heat_formation

    integer, intent(in) :: lo(2), hi(2), vlo(2), vhi(2), qlo(2), qhi(2)
    double precision, intent(inout) :: burn(vlo(1):vhi(1),vlo(2):vhi(2),nburn)
    double precision, intent(in   ) ::    Q(qlo(1):qhi(1),qlo(2):qhi(2),nprim)

    integer :: i,j,n,np,iwrk
    double precision :: Yt(lo(1):hi(1),nspecies), wdot(lo(1):hi(1),nspecies), rwrk

    np = hi(1) - lo(1) + 1

    do j=lo(2),hi(2)
       
       do n=1, nspecies
          do i=lo(1),hi(1)
             Yt(i,n) = q(i,j,qy1+n-1)
          end do
       end do
       
       call vckwyr(np, q(lo(1),j,qrho), q(lo(1),j,qtemp), Yt, iwrk, rwrk, wdot)
       
       if (ib_omegadot > 0) then
          do n=1, nspecies
             do i=lo(1),hi(1)
                burn(i,j,ib_omegadot+n-1) = wdot(i,n) * molecular_weight(n)
             end do
          end do
       end if

       if (ib_dYdt > 0) then
          do n=1, nspecies
             do i=lo(1),hi(1)
                burn(i,j,ib_dYdt+n-1) = wdot(i,n) * molecular_weight(n) / q(i,j,qrho)
             end do
          end do
       end if

       if (ib_heatRelease > 0) then
          do i=lo(1),hi(1)
             burn(i,j,ib_heatRelease) = 0.d0
          end do
          
          do n=1,nspecies
             do i=lo(1),hi(1)
                burn(i,j,ib_heatRelease) = burn(i,j,ib_heatRelease) &
                     - h0(n) * wdot(i,n) * molecular_weight(n)
             end do
          end do
       end if
       
       if (ib_fuelConsumption > 0) then
          do i=lo(1),hi(1)
             burn(i,j,ib_fuelConsumption) = -wdot(i,ifuel) * molecular_weight(ifuel)
          end do
       end if

    enddo

  end subroutine make_burn_2d


  subroutine make_burn2_2d(lo, hi, burn, vlo, vhi, u0, u0lo, u0hi, u, ulo, uhi, dt)
    use plotvar_index_module
    use variables_module
    use chemistry_module, only : h0 => std_heat_formation

    integer, intent(in) :: lo(2),hi(2),vlo(2),vhi(2),u0lo(2),u0hi(2),ulo(2),uhi(2)
    double precision, intent(inout) :: burn( vlo(1): vhi(1), vlo(2): vhi(2),nburn)
    double precision, intent(in   ) ::   u0(u0lo(1):u0hi(1),u0lo(2):u0hi(2),ncons)
    double precision, intent(in   ) ::   u ( ulo(1): uhi(1), ulo(2): uhi(2),ncons)
    double precision, intent(in) :: dt

    integer :: i, j, n, iryn, ibn
    double precision :: dtinv

    dtinv = 1.d0/dt

    if (ib_omegadot > 0) then
       do n=1,nspecies
          iryn = iry1+n-1
          ibn  = ib_omegadot+n-1
          do j=lo(2),hi(2)
             do i=lo(1),hi(1)
                burn(i,j,ibn) = (u(i,j,iryn)-u0(i,j,iryn))*dtinv
             end do
          end do
       end do
    end if

    if (ib_dYdt > 0) then
       do n=1,nspecies
          iryn = iry1+n-1
          ibn  = ib_dYdt+n-1
          do j=lo(2),hi(2)
             do i=lo(1),hi(1)
                burn(i,j,ibn) = ( u(i,j,iryn)/ u(i,j,irho)  &
                     -           u0(i,j,iryn)/u0(i,j,irho) )*dtinv
             end do
          end do
       end do       
    end if

    if (ib_heatRelease > 0) then
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)
             burn(i,j,ib_heatRelease) = 0.d0
          end do
       end do
       
       do n=1,nspecies
          iryn = iry1+n-1
          do j=lo(2),hi(2)
             do i=lo(1),hi(1)
                burn(i,j,ib_heatRelease) = burn(i,j,ib_heatRelease) &
                     - h0(n) * (u(i,j,iryn)-u0(i,j,iryn))*dtinv
             end do
          end do
       end do
    end if

    if (ib_fuelConsumption > 0) then
       iryn = iry1+ifuel-1
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)
             burn(i,j,ib_fuelConsumption) = -(u(i,j,iryn)-u0(i,j,iryn))*dtinv
          end do
       end do       
    end if

  end subroutine make_burn2_2d

end module make_plotvar_2d_module
