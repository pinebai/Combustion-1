      subroutine macproj(macvel,divu,dx)
      implicit none
      include 'spec.h'
      real*8 macvel(0 :nx)
      real*8   divu(0 :nx-1)
      real*8 dx
      
      integer i
      print *,'... mac_projection'
      
      do i=lo(0)+1,hi(0)+1
         macvel(i) = macvel(i-1) + divu(i-1)*dx
      end do
      
c     macvel(0) was set in predict_vel and remains unchanged
      
      end
