      subroutine calc_divu(scal,beta,I_R,divu,dx,time)
      implicit none
      include 'spec.h'

c     Quantities passed in
      real*8 scal(-1:nx,nscal)
      real*8 beta(-1:nx,nscal)
      real*8 divu(0:nx-1)
      real*8 I_R(0:nx-1,0:maxspec)
      real*8 dx, time
      
      real*8 Y(maxspec)
      real*8 HK(maxspec)
      real*8 cpmix,mwmix
      
      real*8 diff(0:nx-1,nscal)

      real*8 RWRK,rho,T
      integer IWRK,i,n
      real*8 divu_max,sum

      real*8 spec_flux_lo(0:nx-1,maxspec)
      real*8 spec_flux_hi(0:nx-1,maxspec)

      call get_temp_visc_terms(scal,beta,diff(0,Temp),dx,time)
      call get_spec_visc_terms(scal,beta,diff(0,FirstSpec),
     $                         spec_flux_lo,spec_flux_hi,dx,time)

      do i = 0,nx-1
         rho = 0.d0
c         do n = 1,Nspec
c            rho = rho + scal(i,FirstSpec+n-1)
c         enddo
         rho = scal(i,Density)
         do n = 1,Nspec
            Y(n) = scal(i,FirstSpec + n - 1) / rho
         enddo
         T = scal(i,Temp)
         call CKMMWY(Y,IWRK,RWRK,mwmix)
         call CKCPBS(T,Y,IWRK,RWRK,cpmix)
         call CKHMS(T,IWRK,RWRK,HK)

         divu(i) = diff(i,Temp)/(rho*cpmix*T)

         sum = 0.0d0
         do n=1,Nspec
            divu(i) = divu(i)
     &           + (diff(i,FirstSpec+n-1) + I_R(i,n))
     &           *invmwt(n)*mwmix/rho - HK(n)*I_R(i,n)/(rho*cpmix*T)
         enddo
       enddo

      divu_max = ABS(divu(0))
      do i = 1,nx-1
         divu_max = MAX(divu_max,ABS(divu(i)))
      enddo
      print *,'*********** DIVU norm = ',divu_max

      end
