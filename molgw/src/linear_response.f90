!=========================================================================
! This file is part of MOLGW.
!
! This file contains
! the routines to calculate the polarizability within RPA, TDDFT or BSE
! and the corresponding optical spectra
!=========================================================================


!=========================================================================
subroutine polarizability(basis,auxil_basis,nstate,occupation,energy,c_matrix,rpa_correlation,wpol_out)
 use m_definitions
 use m_timing
 use m_warning
 use m_memory
 use m_inputparam
 use m_mpi
 use m_tools
 use m_block_diago
 use m_basis_set
 use m_spectral_function
 use m_eri_ao_mo
 implicit none

 type(basis_set),intent(in)            :: basis,auxil_basis
 integer,intent(in)                    :: nstate
 real(dp),intent(in)                   :: occupation(nstate,nspin)
 real(dp),intent(in)                   :: energy(nstate,nspin),c_matrix(basis%nbf,nstate,nspin)
 real(dp),intent(out)                  :: rpa_correlation
 type(spectral_function),intent(inout) :: wpol_out
!=====
 type(spectral_function)   :: wpol_static
 integer                   :: nmat
 real(dp)                  :: energy_gm
 real(dp)                  :: alpha_local
 real(dp),allocatable      :: amb_diag_rpa(:)
 real(prec_td),allocatable :: amb_matrix(:,:),apb_matrix(:,:)
 real(prec_td),allocatable :: a_diag(:)
 real(prec_td),allocatable :: bigx(:,:),bigy(:,:)
 real(dp),allocatable      :: eigenvalue(:)
 real(dp)                  :: energy_qp(nstate,nspin)
 logical                   :: is_tddft
 logical                   :: is_ij
 logical                   :: is_rpa
 logical                   :: has_manual_tdhf
 integer                   :: reading_status
 integer                   :: tdhffile
 integer                   :: m_apb,n_apb,m_x,n_x
! Scalapack variables
 integer                   :: desc_apb(ndel),desc_x(ndel)
!=====

 call start_clock(timing_pola)

 write(stdout,'(/,a)') ' Calculating the polarizability'
 if(is_triplet) then
   write(stdout,'(a)') ' Triplet state'
 else
   write(stdout,'(a)') ' Singlet state'
 endif

 if( has_auxil_basis ) call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix)

 
 ! Set up all the switches to be able to treat
 ! GW, BSE, TDHF, TDDFT (semilocal or hybrid)

 !
 ! Set up flag is_rpa
 inquire(file='manual_rpa',exist=is_rpa)
 if(is_rpa) then
   msg='RPA calculation is enforced'
   call issue_warning(msg)
 endif
 is_rpa   = calc_type%is_gw .OR. is_rpa

 ! 
 ! Set up flag is_tddft
 is_tddft = calc_type%is_td .AND. calc_type%is_dft .AND. .NOT. is_rpa

 ! 
 ! Set up exchange content alpha_local
 ! manual_tdhf can override anything
 inquire(file='manual_tdhf',exist=has_manual_tdhf)
 if(has_manual_tdhf) then
   open(newunit=tdhffile,file='manual_tdhf',status='old')
   read(tdhffile,*) alpha_local
   close(tdhffile)
   write(msg,'(a,f12.6,3x,f12.6)') 'calculating the TDHF polarizability with alpha ',alpha_local
   call issue_warning(msg)
 else
   if(is_rpa) then
     alpha_local = 0.0_dp
   else if(is_tddft) then
     alpha_local = alpha_hybrid
   else ! TDHF or BSE case
     alpha_local = 1.0_dp
   endif
 endif


 call start_clock(timing_build_h2p)

 !
 ! Prepare the QP energies
 !
 if( calc_type%is_bse .OR. calc_type%gwmethod==GnWn ) then
   ! Get energy_qp 
   call get_energy_qp(nstate,energy,occupation,energy_qp)
 else
   ! For any other type of calculation, just fill energy_qp array with energy
   energy_qp(:,:) = energy(:,:)
 endif

 ! 
 ! BSE needs the static screening from a previous calculation
 ! It is stored in object wpol_static
 !
 if( calc_type%is_bse ) then
   call read_spectral_function(wpol_static,reading_status)

   ! If a SCREENED_COULOMB file cannot be found,
   ! then recalculate it from scratch
   if( reading_status /= 0 ) then
     call init_spectral_function(nstate,occupation,wpol_static)
     wpol_static%nprodbasis = auxil_basis%nbf_local
     call static_polarizability(nstate,basis,auxil_basis,occupation,energy,wpol_static)
   endif

 endif


 !
 ! Prepare the big matrices (A+B) and (A-B)
 ! 
 nmat = wpol_out%npole_reso_apb
 !
 ! The distribution of the two matrices have to be the same for A-B and A+B
 ! This is valid also when SCALAPACK is not used!
 call init_desc('S',nmat,nmat,desc_apb,m_apb,n_apb)
 call clean_allocate('A+B',apb_matrix,m_apb,n_apb)
 call clean_allocate('A-B',amb_matrix,m_apb,n_apb)
 allocate(amb_diag_rpa(nmat))

 ! A diagonal is owned by all procs (= no distribution)
 ! wpol_out%npole_reso_spa are the pole not explictely counted in wpol_out%npole_reso_apb
 allocate(a_diag(wpol_out%npole_reso_spa))

 !
 ! Build the (A+B) and (A-B) matrices in 3 steps
 ! to span all the possible approximations
 ! Only the lower triangle is calculated
 ! the upper part will be filled later by symmetry
 !

 ! Calculate the diagonal separately: it is needed for the single pole approximation
 if( nvirtual_SPA < nvirtual_W .AND. is_rpa ) & 
     call build_a_diag_common(nmat,basis%nbf,nstate,c_matrix,energy_qp,wpol_out,a_diag)

 apb_matrix(:,:) = 0.0_dp
 amb_matrix(:,:) = 0.0_dp
 write(stdout,'(/,a)') ' Build the electron-hole hamiltonian'

 if( has_auxil_basis) then

   !
   ! Step 1
!   call build_amb_apb_common(desc_apb,nmat,basis%nbf,nstate,c_matrix,energy_qp,wpol_out,alpha_local, &
!                             m_apb,n_apb,amb_matrix,apb_matrix,amb_diag_rpa,rpa_correlation)

   call build_amb_apb_diag_auxil(nmat,nstate,energy,wpol_out,m_apb,n_apb,amb_matrix,apb_matrix,amb_diag_rpa)

   call build_apb_hartree_auxil(desc_apb,wpol_out,m_apb,n_apb,apb_matrix)

   call get_rpa_correlation(nmat,wpol_out,m_apb,n_apb,amb_matrix,apb_matrix,rpa_correlation)



   !
   ! Step 2
   if(is_tddft) call build_apb_tddft(nmat,nstate,basis,c_matrix,occupation,wpol_out,m_apb,n_apb,apb_matrix)

   !
   ! Step 3
   if(alpha_local > 1.0e-6_dp) then
     call build_amb_apb_screened_exchange_auxil(alpha_local,desc_apb,wpol_out,wpol_static,m_apb,n_apb,amb_matrix,apb_matrix)
   endif

   if(calc_type%is_bse) then
     call destroy_spectral_function(wpol_static)
   endif


 else

   !
   ! Step 1
   call build_amb_apb_common(desc_apb,nmat,basis%nbf,nstate,c_matrix,energy_qp,wpol_out,alpha_local, &
                             m_apb,n_apb,amb_matrix,apb_matrix,amb_diag_rpa,rpa_correlation)

   !
   ! Step 2
   if(is_tddft) call build_apb_tddft(nmat,nstate,basis,c_matrix,occupation,wpol_out,m_apb,n_apb,apb_matrix)


   !
   ! Step 3
   if(calc_type%is_bse .AND. .NOT. is_rpa) then
     call build_amb_apb_bse(basis%nbf,nstate,wpol_out,wpol_static,m_apb,n_apb,amb_matrix,apb_matrix)
     call destroy_spectral_function(wpol_static)
   endif

 endif



 ! Warning if Tamm-Dancoff flag is on
 if(is_tda) then
   msg='Tamm-Dancoff approximation is switched on'
   call issue_warning(msg)
   ! Tamm-Dancoff approximation consists in setting B matrix to zero
   ! Then A+B = A-B = A
   apb_matrix(:,:) = 0.5_dp * ( apb_matrix(:,:) + amb_matrix(:,:) )
   amb_matrix(:,:) = apb_matrix(:,:) 
 endif
 ! Construction done!
 if(has_auxil_basis) call destroy_eri_3center_eigen()

 call stop_clock(timing_build_h2p)

 if(is_rpa) call clean_deallocate('A-B',amb_matrix)
 

 allocate(eigenvalue(nmat))
 ! bigX, and bigY (if needed)
 call init_desc('S',nmat,nmat,desc_x,m_x,n_x)
 write(stdout,*) 'Allocate eigenvector array'
 call clean_allocate('X',bigx,m_x,n_x)
 if( .NOT. is_rpa) &
   call clean_allocate('Y',bigy,m_x,n_x)

 !
 ! Diago using the 4 block structure and the symmetry of each block
 ! With or Without SCALAPACK
 !
 if( .NOT. is_rpa ) then
#ifndef HAVE_SCALAPACK
   call diago_4blocks_sqrt(nmat,amb_matrix,apb_matrix,eigenvalue,bigx,bigy)
#else
   call diago_4blocks_chol(nmat,desc_apb,m_apb,n_apb,amb_matrix,apb_matrix,eigenvalue,&
                                desc_x,m_x,n_x,bigx,bigy)
#endif
 else
#ifndef HAVE_SCALAPACK
   call diago_4blocks_rpa(nmat,amb_diag_rpa,apb_matrix,eigenvalue,bigx)
#else
   call diago_4blocks_rpa_sca(nmat,desc_apb,m_apb,n_apb,amb_diag_rpa,apb_matrix,eigenvalue,&
                              desc_x,m_x,n_x,bigx)
#endif
 endif

 ! Deallocate the non-necessary matrices
 deallocate(amb_diag_rpa)
 write(stdout,*) 'Deallocate (A+B) and possibly (A-B)'
 call clean_deallocate('A+B',apb_matrix)
 !
 ! (A-B) may have been already deallocated earlier in the case of RPA 
 ! Relax: this is indeed tolerated by clean_deallocate
 call clean_deallocate('A-B',amb_matrix)


 !
 ! Second part of the RPA correlation energy: sum over positive eigenvalues
 rpa_correlation = rpa_correlation + 0.50_dp * SUM( ABS(eigenvalue(:)) )
 if(is_rpa) then
   write(stdout,'(/,a)') ' Calculate the RPA energy using the Tamm-Dancoff decomposition'
   write(stdout,'(a)')   ' Eq. (9) from J. Chem. Phys. 132, 234114 (2010)'
   write(stdout,'(/,a,f16.10)') ' RPA energy (Ha): ',rpa_correlation
 endif

 write(stdout,'(/,a,f12.6)') ' Lowest neutral excitation energy (eV):',MINVAL(ABS(eigenvalue(:)))*Ha_eV

 if( has_auxil_basis ) call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix)

 !
 ! Calculate the optical sprectrum
 ! and the dynamic dipole tensor
 !
 if( calc_type%is_td .OR. calc_type%is_bse ) then
   call optical_spectrum(nstate,basis,occupation,c_matrix,wpol_out,m_x,n_x,bigx,bigy,eigenvalue)
   call stopping_power(nstate,basis,occupation,c_matrix,wpol_out,m_x,n_x,bigx,bigy,eigenvalue)
 endif

 !
 ! Now only the sum ( bigx + bigy ) is needed in fact.
 ! Let us set  bigx = bigx + bigy 
 !    and free bigy 
 if( .NOT. is_rpa) then
   bigx(:,:) = bigx(:,:) + bigy(:,:)
   call clean_deallocate('Y',bigy)
 endif

 !
 ! Calculate Wp= v * chi * v    if necessary
 ! and then write it down on file
 !
 if( print_w_ .OR. calc_type%is_gw ) then
   if( has_auxil_basis) then
     call chi_to_sqrtvchisqrtv_auxil(basis%nbf,auxil_basis%nbf_local,desc_x,m_x,n_x,bigx,eigenvalue,wpol_out,energy_gm)
     ! This following coding of the Galitskii-Migdal correlation energy is only working with
     ! an auxiliary basis
     if(is_rpa) write(stdout,'(a,f16.10,/)') ' Correlation energy in the Galitskii-Migdal formula (Ha): ',energy_gm
     
     ! Add the single pole approximation for the poles that have been neglected
     ! in the diagonalization
     if( nvirtual_SPA < nvirtual_W .AND. is_rpa ) & 
        call chi_to_sqrtvchisqrtv_auxil_spa(basis%nbf,auxil_basis%nbf_local,a_diag,wpol_out)

   else
     call chi_to_vchiv(basis%nbf,nstate,c_matrix,bigx,eigenvalue,wpol_out)
   endif
  
 
   ! If requested write the spectral function on file
   if( print_w_ ) call write_spectral_function(wpol_out)

 endif

 if( .NOT. calc_type%is_gw ) call destroy_spectral_function(wpol_out)

 write(stdout,*) 'Deallocate eigenvector arrays'
 call clean_deallocate('X',bigx)

 if(has_auxil_basis) call destroy_eri_3center_eigen()

 if(ALLOCATED(eigenvalue)) deallocate(eigenvalue)
 if(ALLOCATED(a_diag))     deallocate(a_diag)

 call stop_clock(timing_pola)


end subroutine polarizability


!=========================================================================
subroutine optical_spectrum(nstate,basis,occupation,c_matrix,chi,m_x,n_x,bigx,bigy,eigenvalue)
 use m_definitions
 use m_timing
 use m_warning
 use m_memory
 use m_inputparam
 use m_mpi
 use m_tools
 use m_basis_set
 use m_dft_grid
 use m_spectral_function
 use m_atoms
 implicit none

 integer,intent(in)                 :: nstate,m_x,n_x
 type(basis_set),intent(in)         :: basis
 real(dp),intent(in)                :: occupation(nstate,nspin),c_matrix(basis%nbf,nstate,nspin)
 type(spectral_function),intent(in) :: chi
 real(prec_td),intent(in)           :: bigx(m_x,n_x)
 real(prec_td),intent(in)           :: bigy(m_x,n_x)
 real(dp),intent(in)                :: eigenvalue(chi%npole_reso_apb)
!=====
 integer                            :: t_ij,t_kl
 integer                            :: t_ij_global,t_kl_global
 integer                            :: nmat
 integer                            :: istate,jstate,ijspin
 integer                            :: ibf,jbf
 integer                            :: ni,nj,li,lj,ni_cart,nj_cart,i_cart,j_cart,ibf_cart,jbf_cart
 integer                            :: iomega,idir,jdir
 integer,parameter                  :: nomega=600
 complex(dp)                        :: omega(nomega)
 real(dp)                           :: coeff,trace
 real(dp)                           :: dynamical_pol(nomega,3,3),photoabsorp_cross(nomega,3,3)
 real(dp)                           :: static_polarizability(3,3)
 real(dp)                           :: oscillator_strength,trk_sumrule,mean_excitation
 real(dp),allocatable               :: dipole_basis(:,:,:),dipole_tmp(:,:,:),dipole_state(:,:,:,:)
 real(dp),allocatable               :: dipole_cart(:,:,:)
 real(dp),allocatable               :: residu_left(:,:)
 integer                            :: dynpolfile
 integer                            :: photocrossfile
 integer                            :: parityi,parityj,reflectioni,reflectionj
 integer,external                   :: wfn_parity
 integer,external                   :: wfn_reflection
 character(len=32)                  :: symsymbol
!=====


 call start_clock(timing_spectrum)
 !
 ! Calculate the spectrum now
 !

 write(stdout,'(/,a)') ' Calculate the optical spectrum'

 if (nspin/=1) then
   msg='no nspin/=1 allowed'
   call issue_warning(msg)
   return
 endif

 !
 ! First precalculate all the needed dipole in the basis set
 !
 allocate(dipole_basis(3,basis%nbf,basis%nbf))
 ibf_cart = 1
 ibf      = 1
 do while(ibf_cart<=basis%nbf_cart)
   li      = basis%bf(ibf_cart)%am
   ni_cart = number_basis_function_am('CART',li)
   ni      = number_basis_function_am(basis%gaussian_type,li)

   jbf_cart = 1
   jbf      = 1
   do while(jbf_cart<=basis%nbf_cart)
     lj      = basis%bf(jbf_cart)%am
     nj_cart = number_basis_function_am('CART',lj)
     nj      = number_basis_function_am(basis%gaussian_type,lj)

     allocate(dipole_cart(3,ni_cart,nj_cart))


     do i_cart=1,ni_cart
       do j_cart=1,nj_cart
         call basis_function_dipole(basis%bf(ibf_cart+i_cart-1),basis%bf(jbf_cart+j_cart-1),dipole_cart(:,i_cart,j_cart))
       enddo
     enddo

     do idir=1,3
       dipole_basis(idir,ibf:ibf+ni-1,jbf:jbf+nj-1) = MATMUL( TRANSPOSE( cart_to_pure(li)%matrix(:,:) ) , &
             MATMUL(  dipole_cart(idir,:,:) , cart_to_pure(lj)%matrix(:,:) ) )
     enddo

     deallocate(dipole_cart)

     jbf      = jbf      + nj
     jbf_cart = jbf_cart + nj_cart
   enddo

   ibf      = ibf      + ni
   ibf_cart = ibf_cart + ni_cart
 enddo

 !
 ! Get the dipole oscillator strength on states
 allocate(dipole_state(3,nstate,nstate,nspin))
 allocate(dipole_tmp(3,basis%nbf,nstate))

 do ijspin=1,nspin
   do istate=1,nstate
     do jbf=1,basis%nbf
       dipole_tmp(:,jbf,istate) = MATMUL( dipole_basis(:,:,jbf) , c_matrix(:,istate,ijspin) )
     enddo
   enddo

   do jstate=1,nstate
     do istate=1,nstate
       dipole_state(:,istate,jstate,ijspin) = MATMUL( dipole_tmp(:,:,istate) , c_matrix(:,jstate,ijspin) )
     enddo
   enddo

 enddo
 deallocate(dipole_basis,dipole_tmp)


 allocate(residu_left(3,chi%npole_reso_apb))

 nmat=chi%npole_reso_apb
 residu_left(:,:) = 0.0_dp
 do t_ij=1,m_x
   t_ij_global = rowindex_local_to_global(iprow_sd,nprow_sd,t_ij)
   istate = chi%transition_table_apb(1,t_ij_global)
   jstate = chi%transition_table_apb(2,t_ij_global)
   ijspin = chi%transition_table_apb(3,t_ij_global)

   ! Let use (i <-> j) symmetry to halve the loop
   do t_kl=1,n_x
     t_kl_global = colindex_local_to_global(ipcol_sd,npcol_sd,t_kl)

     residu_left(:,t_kl_global) = residu_left(:,t_kl_global) &
                  + dipole_state(:,istate,jstate,ijspin) * ( bigx(t_ij,t_kl) + bigy(t_ij,t_kl) ) * SQRT(spin_fact)
   enddo

 enddo
 call xsum(residu_left)

 deallocate(dipole_state)


 !
 ! Calculate the dynamical dipole polarizability
 ! and the static dipole polarizability
 !
 ! Set the frequency mesh
 omega(1)     =MAX( 0.0_dp      ,MINVAL(ABS(eigenvalue(:)))-10.00/Ha_eV)
 omega(nomega)=MIN(50.0_dp/Ha_eV,MAXVAL(ABS(eigenvalue(:)))+10.00/Ha_eV)
 do iomega=2,nomega-1
   omega(iomega) = omega(1) + ( omega(nomega)-omega(1) ) /REAL(nomega-1,dp) * (iomega-1) 
 enddo
 ! Add the broadening
 omega(:) = omega(:) + im * 0.10/Ha_eV

 dynamical_pol(:,:,:) = 0.0_dp
 static_polarizability(:,:) = 0.0_dp
 do t_ij=1,nmat
   do idir=1,3
     do jdir=1,3
       dynamical_pol(:,idir,jdir) = dynamical_pol(:,idir,jdir) &
                            + residu_left(idir,t_ij) * residu_left(jdir,t_ij) &
                              * ( AIMAG( -1.0_dp  / ( omega(:) - eigenvalue(t_ij) ) ) - AIMAG( -1.0_dp  / ( omega(:) + eigenvalue(t_ij) ) ) )
       static_polarizability(idir,jdir) = static_polarizability(idir,jdir) &
                      + 2.0_dp * residu_left(idir,t_ij) * residu_left(jdir,t_ij) / eigenvalue(t_ij)
     enddo
   enddo
 enddo
 !
 ! Get the photoabsorption cross section
 do iomega=1,nomega
   photoabsorp_cross(iomega,:,:) = 4.0_dp * pi * REAL(omega(iomega),dp) / c_speedlight * dynamical_pol(iomega,:,:)
 enddo


 write(stdout,'(/,a)') ' Excitation energies (eV)     Oscil. strengths   [Symmetry] '  
 trk_sumrule=0.0_dp
 mean_excitation=0.0_dp
 do t_kl_global=1,nmat
   t_kl = colindex_global_to_local('S',t_kl_global)

   if( is_triplet ) then 
     oscillator_strength = 0.0_dp
   else
     oscillator_strength = 2.0_dp/3.0_dp * DOT_PRODUCT(residu_left(:,t_kl_global),residu_left(:,t_kl_global)) * eigenvalue(t_kl_global)
   endif
   trk_sumrule = trk_sumrule + oscillator_strength
   mean_excitation = mean_excitation + oscillator_strength * LOG( eigenvalue(t_kl_global) )

   if(t_kl_global<=30) then

     if( is_triplet ) then
       symsymbol='3'
     else
       symsymbol='1'
     endif

     !
     ! Test the parity in case of molecule with inversion symmetry
    
     t_ij_global = 0
     do t_ij=1,m_x
       ! t_kl is zero if the proc is not in charge of this process
       if( t_kl /=0 ) then 
         if( ABS(bigx(t_ij,t_kl)) > 0.1_dp ) then
           t_ij_global = rowindex_local_to_global(iprow_sd,nprow_sd,t_ij)
           exit
         endif
       endif
     enddo
     call xmax(t_ij_global)

     istate = chi%transition_table_apb(1,t_ij_global)
     jstate = chi%transition_table_apb(2,t_ij_global)
     ijspin = chi%transition_table_apb(3,t_ij_global)
     if(planar) then
       reflectioni = wfn_reflection(basis,c_matrix,istate,ijspin)
       reflectionj = wfn_reflection(basis,c_matrix,jstate,ijspin)
       select case(reflectioni*reflectionj)
       case( 1)
         symsymbol=TRIM(symsymbol)//'(A1, B2 or Ap )'
       case(-1)
         symsymbol=TRIM(symsymbol)//'(A2, B1 or App)'
       end select
     endif
     if(inversion) then
       parityi = wfn_parity(basis,c_matrix,istate,ijspin)
       parityj = wfn_parity(basis,c_matrix,jstate,ijspin)
       select case(parityi*parityj)
       case( 1)
         symsymbol=TRIM(symsymbol)//'g'
       case(-1)
         symsymbol=TRIM(symsymbol)//'u'
       end select
     endif

     write(stdout,'(1x,i4.4,a3,2(f18.8,2x),5x,a32)') t_kl_global,' : ', &
                  eigenvalue(t_kl_global)*Ha_eV,oscillator_strength,symsymbol

     !
     ! Output the transition coefficients
     do t_ij_global=1,nmat
       t_ij = rowindex_global_to_local('S',t_ij_global)
       istate = chi%transition_table_apb(1,t_ij_global)
       jstate = chi%transition_table_apb(2,t_ij_global)
     
       coeff = 0.0_dp
       if( t_ij /= 0 .AND. t_kl /=0 ) then 
         if( ABS(bigx(t_ij,t_kl)) / SQRT(2.0_dp) > 0.1_dp ) then
           coeff = bigx(t_ij,t_kl) / SQRT(2.0_dp)
         endif
       endif
       call xsum(coeff)
       if( ABS(coeff) > 0.1_dp ) write(stdout,'(8x,i4,a,i4,1x,f12.5)') istate,' -> ',jstate,coeff

       coeff = 0.0_dp
       if( t_ij /= 0 .AND. t_kl /=0 ) then
         if( ABS(bigy(t_ij,t_kl)) / SQRT(2.0_dp) > 1.0e-1_dp ) then
           coeff = bigy(t_ij,t_kl) / SQRT(2.0_dp)
         endif
       endif
       call xsum(coeff)
       if( ABS(coeff) > 0.1_dp ) write(stdout,'(8x,i4,a,i4,1x,f12.5)') istate,' <- ',jstate,coeff
     enddo




     write(stdout,*)
   endif
 enddo

 if( is_triplet ) return

 write(stdout,'(/,a)')     ' TRK sum rule: the two following numbers should compare well'
 write(stdout,'(a,f12.6)') ' Sum over oscillator strengths: ',trk_sumrule
 write(stdout,'(a,f12.6)') '   Number of valence electrons: ',SUM( occupation(ncore_W+1:,:) )

 write(stdout,'(/,a,f12.6)') ' Mean excitation energy (eV): ',EXP( mean_excitation / trk_sumrule ) * Ha_eV

 write(stdout,'(/,a)') ' Static dipole polarizability:'
 trace = 0.0_dp
 do idir=1,3
   write(stdout,'(3(4x,f12.6))') static_polarizability(idir,:)
   trace = trace + static_polarizability(idir,idir) / 3.0_dp
 enddo
 write(stdout,'(a,f12.6)') ' Static dipole polarizability trace: ',trace

 if( is_iomaster ) then

   open(newunit=dynpolfile,file='dynamical_dipole_polarizability.dat',form='formatted')
   open(newunit=photocrossfile,file='photoabsorption_cross_section.dat',form='formatted')
   write(dynpolfile,'(a)') '#  Imaginary part of dynamical dipole polarizability'
   write(dynpolfile,'(a)') '#  omega (eV)   Average     xx    yx    zx    xy    yy    zy    xz    yz    zz'
   write(photocrossfile,'(a)') '#  Imaginary part of dynamical dipole polarizability'
   write(photocrossfile,'(a)') '#  omega (eV)   Average     xx    yx    zx    xy    yy    zy    xz    yz    zz'
   do iomega=1,nomega
     write(dynpolfile,'(11(e18.8,2x))') REAL(omega(iomega),dp)*Ha_eV,                                      &
                                          (dynamical_pol(iomega,1,1)+dynamical_pol(iomega,2,2)+dynamical_pol(iomega,3,3))/3.0_dp, &
                                          dynamical_pol(iomega,:,:)
     write(photocrossfile,'(11(e18.8,2x))') REAL(omega(iomega),dp)*Ha_eV,                                      &
                                              (photoabsorp_cross(iomega,1,1)+photoabsorp_cross(iomega,2,2)+photoabsorp_cross(iomega,3,3))/3.0_dp, &
                                              photoabsorp_cross(iomega,:,:)
   enddo 

   close(dynpolfile)
   close(photocrossfile)

 endif


 deallocate(residu_left)

 call stop_clock(timing_spectrum)

end subroutine optical_spectrum


!=========================================================================
subroutine stopping_power(nstate,basis,occupation,c_matrix,chi,m_x,n_x,bigx,bigy,eigenvalue)
 use m_definitions
 use m_timing
 use m_warning
 use m_memory
 use m_inputparam
 use m_mpi
 use m_tools
 use m_basis_set
 use m_dft_grid
 use m_spectral_function
 use m_atoms
 implicit none

 integer,intent(in)                 :: nstate,m_x,n_x
 type(basis_set),intent(in)         :: basis
 real(dp),intent(in)                :: occupation(nstate,nspin),c_matrix(basis%nbf,nstate,nspin)
 type(spectral_function),intent(in) :: chi
 real(prec_td),intent(in)           :: bigx(m_x,n_x)
 real(prec_td),intent(in)           :: bigy(m_x,n_x)
 real(dp),intent(in)                :: eigenvalue(chi%npole_reso_apb)
!=====
 integer                            :: t_ij,t_kl
 integer                            :: t_ij_global,t_kl_global
 integer                            :: nmat
 integer                            :: istate,jstate,ijspin
 integer                            :: ibf,jbf
 integer                            :: ni,nj,li,lj,ni_cart,nj_cart,i_cart,j_cart,ibf_cart,jbf_cart
 integer                            :: iomega,idir,jdir
 integer,parameter                  :: nomega=600
 complex(dp)                        :: omega(nomega)
 real(dp)                           :: coeff
 real(dp)                           :: dynamical_pol(nomega),structure_factor(nomega)
 complex(dpc)                       :: bethe_sumrule
 complex(dpc),allocatable           :: gos_basis(:,:),gos_tmp(:,:),gos_state(:,:,:)
 complex(dpc),allocatable           :: gos_cart(:,:)
 complex(dpc),allocatable           :: residu_left(:)
 real(dp)                           :: qvec(3)
 integer,parameter                  :: nq=0 ! 1000
 integer                            :: iq
 real(dp)                           :: fnq(chi%npole_reso_apb)
 integer,parameter                  :: nv=20
 integer                            :: iv
 real(dp)                           :: stopping(nv)
 real(dp)                           :: vv
!=====


 call start_clock(timing_spectrum)
 !
 ! Calculate the spectrum now
 !

 write(stdout,'(/,a)') ' Calculate the stopping power'

 if (nspin/=1) then
   msg='no nspin/=1 allowed'
   call issue_warning(msg)
   return
 endif

 !
 ! Prepare the precalculated table of coefficients
 call setup_gos_llp()


 !
 ! Calculate the dynamical dipole polarizability
 ! and the static dipole polarizability
 !
 ! Set the frequency mesh
 omega(1)     =0.1_dp ! MAX( 0.0_dp      ,MINVAL(ABS(eigenvalue(:)))-3.00/Ha_eV)
 omega(nomega)=4.0_dp ! MIN(20.0_dp/Ha_eV,MAXVAL(ABS(eigenvalue(:)))+3.00/Ha_eV)
 do iomega=2,nomega-1
   omega(iomega) = omega(1) + ( omega(nomega)-omega(1) ) /REAL(nomega-1,dp) * (iomega-1)
 enddo
 ! Add the broadening
 omega(:) = omega(:) + im * 0.10/Ha_eV
  

 
!TESTINGOK§ call basis_function_dipole(basis%bf(1),basis%bf(14),qvec)
!TESTINGOK§ write(*,*) 'dipole',qvec(:)
!TESTINGOK§ call overlap_basis_function(basis%bf(1),basis%bf(14),qvec(1))
!TESTINGOK§ write(*,*) 'overlap',qvec(1)
!TESTINGOK§ qvec(1)=0.00001
!TESTINGOK§ qvec(2)=0.00000
!TESTINGOK§ qvec(3)=0.00000
!TESTINGOK§ call gos_basis_function(basis%bf(1),basis%bf(14),qvec,bethe_sumrule)
!TESTINGOK§ write(*,*) 'bethe_sumrule',bethe_sumrule / qvec(1)/im
!TESTINGOK§ call die('ENOUGH')

 do iq=1,nq
   qvec(1) = 0.0_dp
   qvec(2) = 0.0_dp
   qvec(3) = iq*0.01_dp

   !
   ! First precalculate all the needed GOS in the basis set
   !
   allocate(gos_basis(basis%nbf,basis%nbf))
   ibf_cart = 1
   ibf      = 1
   do while(ibf_cart<=basis%nbf_cart)
     li      = basis%bf(ibf_cart)%am
     ni_cart = number_basis_function_am('CART',li)
     ni      = number_basis_function_am(basis%gaussian_type,li)
  
     jbf_cart = 1
     jbf      = 1
     do while(jbf_cart<=basis%nbf_cart)
       lj      = basis%bf(jbf_cart)%am
       nj_cart = number_basis_function_am('CART',lj)
       nj      = number_basis_function_am(basis%gaussian_type,lj)
  
       allocate(gos_cart(ni_cart,nj_cart))
  
  
       do i_cart=1,ni_cart
         do j_cart=1,nj_cart
           call gos_basis_function(basis%bf(ibf_cart+i_cart-1),basis%bf(jbf_cart+j_cart-1),qvec,gos_cart(i_cart,j_cart))
         enddo
       enddo
  
       gos_basis(ibf:ibf+ni-1,jbf:jbf+nj-1) = MATMUL( TRANSPOSE( cart_to_pure(li)%matrix(:,:) ) , &
             MATMUL(  gos_cart(:,:) , cart_to_pure(lj)%matrix(:,:) ) )
  
       deallocate(gos_cart)
  
       jbf      = jbf      + nj
       jbf_cart = jbf_cart + nj_cart
     enddo
  
     ibf      = ibf      + ni
     ibf_cart = ibf_cart + ni_cart
   enddo
  
   !
   ! Get the gos oscillator strength on states
   allocate(gos_state(basis%nbf,basis%nbf,nspin))
   allocate(gos_tmp(basis%nbf,basis%nbf))
  
   do ijspin=1,nspin
     gos_tmp(:,:) = MATMUL( TRANSPOSE( c_matrix(:,:,ijspin) ) , gos_basis(:,:) )
  
     gos_state(:,:,ijspin) = MATMUL( gos_tmp(:,:) , c_matrix(:,:,ijspin) )
  
   enddo
   deallocate(gos_basis,gos_tmp)
  
  
   nmat=chi%npole_reso_apb
   allocate(residu_left(chi%npole_reso_apb))
  
   residu_left(:) = 0.0_dp
   do t_ij=1,m_x
     t_ij_global = rowindex_local_to_global(iprow_sd,nprow_sd,t_ij)
     istate = chi%transition_table_apb(1,t_ij_global)
     jstate = chi%transition_table_apb(2,t_ij_global)
     ijspin = chi%transition_table_apb(3,t_ij_global)
  
     ! Let use (i <-> j) symmetry to halve the loop
     do t_kl=1,n_x
       t_kl_global = colindex_local_to_global(ipcol_sd,npcol_sd,t_kl)
  
       residu_left(t_kl_global) = residu_left(t_kl_global) &
                    + gos_state(istate,jstate,ijspin) * ( bigx(t_ij,t_kl) + bigy(t_ij,t_kl) ) * SQRT(spin_fact)
     enddo
  
   enddo
   call xsum(residu_left)
  
   deallocate(gos_state)

   fnq(:) = 2.0_dp * ABS( residu_left(:) )**2 * eigenvalue(:) / SUM( qvec(:)**2 )

   write(stdout,*) 'bethe_sumrule',NORM2(qvec(:)),SUM(fnq(:))


  
   dynamical_pol(:) = 0.0_dp
   do t_ij=1,nmat
     dynamical_pol(:) = dynamical_pol(:) &
                       + ABS(residu_left(t_ij))**2 &
                        * ( AIMAG( -1.0_dp  / ( omega(:) - eigenvalue(t_ij) ) ) - AIMAG( -1.0_dp  / ( omega(:) + eigenvalue(t_ij) ) ) )
   enddo
!   !
!   ! Get the structure factor
!   write(999,*) '# qvec',qvec(:)
!   do iomega=1,nomega
!     structure_factor(iomega) = 4.0_dp * pi * REAL(omega(iomega),dp) / c_speedlight * dynamical_pol(iomega) * SUM( qvec(:)**2 )
!     write(999,*) REAL(omega(iomega),dp)*Ha_eV,structure_factor(iomega)
!   enddo
!   write(999,*)


   deallocate(residu_left)

!   write(998,*) SUM( qvec(:)**2 ), fnq(6)

!   do iv=1,nv
!     vv = iv * 0.1_dp
!     do t_ij=1,nmat
!       if( NORM2(qvec) < eigenvalue(t_ij) / vv )   &
!          stopping(iv) = stopping(iv) + 1.0_dp / ( pi * vv**2 )  * fnq(t_ij)  * NORM2(qvec)**2
!     enddo
!
!   enddo


 enddo 

! do iv=1,nv
!   vv = iv * 0.1_dp
!   write(997,*) vv,stopping(iv)
! enddo



end subroutine stopping_power


!=========================================================================
subroutine get_energy_qp(nstate,energy,occupation,energy_qp)
 use m_definitions
 use m_timing
 use m_warning
 use m_memory
 use m_inputparam
 use m_mpi
 implicit none

 integer,intent(in)                  :: nstate
 real(dp),intent(in)                 :: energy(nstate,nspin)
 real(dp),intent(in)                 :: occupation(nstate,nspin)
 real(dp),intent(out)                :: energy_qp(nstate,nspin)
!=====
 integer  :: reading_status
 real(dp) :: scissor_energy(nspin)
 integer  :: ispin,istate
!=====

 ! If the keyword scissor is used in the input file,
 ! then use it and ignore the ENERGY_QP file
 if( ABS(scissor) > 1.0e-5_dp ) then

   call issue_warning('Using a manual scissor to open up the fundamental gap')

   write(stdout,'(a,2(1x,f12.6))') ' Scissor operator with value (eV):',scissor*Ha_eV
   do ispin=1,nspin
     do istate=1,nstate
       if( occupation(istate,ispin) > completely_empty/spin_fact ) then
         energy_qp(istate,ispin) = energy(istate,ispin)
       else
         energy_qp(istate,ispin) = energy(istate,ispin) + scissor
       endif
     enddo
   enddo
   write(stdout,'(/,a)') ' Scissor updated energies'
   do istate=1,nstate
     write(stdout,'(i5,4(2x,f16.6))') istate,energy(istate,:)*Ha_eV,energy_qp(istate,:)*Ha_eV
   enddo
   write(stdout,*)

 else

   call read_energy_qp(nstate,energy_qp,reading_status)

   select case(reading_status)
   case(0)
     write(stdout,'(a)') ' Reading OK'
   case(1,2)
     write(stdout,'(a,/,a)') ' Something happened during the reading of energy_qp file',' Fill up the QP energies with KS energies'
     energy_qp(:,:) = energy(:,:)
   case default
     call die('reading_status BUG')
   end select

 endif

end subroutine get_energy_qp


!=========================================================================
subroutine chi_to_vchiv(nbf,nstate,c_matrix,bigx,eigenvalue,wpol)
 use m_definitions
 use m_warning
 use m_basis_set
 use m_eri_ao_mo
 use m_spectral_function
 implicit none
 
 integer,intent(in)                    :: nbf,nstate
 real(dp),intent(in)                   :: c_matrix(nbf,nstate,nspin)
 type(spectral_function),intent(inout) :: wpol
 real(prec_td),intent(in)              :: bigx(wpol%npole_reso_apb,wpol%npole_reso_apb)
 real(dp),intent(in)                   :: eigenvalue(wpol%npole_reso_apb)
!=====
 integer                               :: t_kl,klspin,ijspin
 integer                               :: istate,jstate,kstate,lstate,ijstate,ijstate_spin
 integer                               :: klstate_min
 integer                               :: klstate_max
 integer                               :: nmat,nprodbasis
 real(dp)                              :: eri_eigen_klij
 real(dp),allocatable                  :: eri_eigenstate_klmin(:,:,:,:)
 real(dp)                              :: rtmp
!=====

 call start_clock(timing_buildw)

 write(stdout,'(/,a)') ' Build W = v * chi * v'
 if(has_auxil_basis) then
   call die('you should not be here')
 endif

 allocate(eri_eigenstate_klmin(nbf,nbf,nbf,nspin))
 ! Set this to zero and then enforce the calculation of the first array of Coulomb integrals
 eri_eigenstate_klmin(:,:,:,:) = 0.0_dp

 nprodbasis = index_prodstate(nstate,nstate) * nspin
 call allocate_spectral_function(nprodbasis,wpol)

 wpol%pole(1:wpol%npole_reso_apb) = eigenvalue(:)

 nmat = wpol%npole_reso_apb

 wpol%residu_left(:,:) = 0.0_dp
 do t_kl=1,nmat 
   kstate = wpol%transition_table_apb(1,t_kl)
   lstate = wpol%transition_table_apb(2,t_kl)
   klspin = wpol%transition_table_apb(3,t_kl)

   klstate_min = MIN(kstate,lstate)
   klstate_max = MAX(kstate,lstate)
   call calculate_eri_4center_eigen(nbf,nstate,c_matrix,klstate_min,klspin,eri_eigenstate_klmin)

   ijstate_spin = 0
   do ijspin=1,nspin
     do jstate=1,nstate
       do istate = 1,jstate
         ijstate_spin = ijstate_spin + 1

         eri_eigen_klij = eri_eigenstate_klmin(klstate_max,istate,jstate,ijspin)

         ! Use the symmetry ( k l | i j ) to regroup (kl) and (lk) contributions
         ! and the block structure of eigenvector | X  Y |
         !                                        | Y  X |
         wpol%residu_left(ijstate_spin,:) = wpol%residu_left(ijstate_spin,:) &
                              + eri_eigen_klij * bigx(t_kl,:)

       enddo
     enddo
   enddo

 enddo

 wpol%residu_left(:,:) = wpol%residu_left(:,:) * SQRT(spin_fact)



 if(ALLOCATED(eri_eigenstate_klmin)) deallocate(eri_eigenstate_klmin)

 call stop_clock(timing_buildw)

end subroutine chi_to_vchiv


!=========================================================================
subroutine chi_to_sqrtvchisqrtv_auxil(nbf,nbf_auxil,desc_x,m_x,n_x,bigx,eigenvalue,wpol,energy_gm)
 use m_definitions
 use m_warning
 use m_basis_set
 use m_eri_ao_mo
 use m_spectral_function
 implicit none
 
 integer,intent(in)                    :: nbf,nbf_auxil,m_x,n_x
 integer,intent(in)                    :: desc_x(ndel)
 real(prec_td),intent(inout)           :: bigx(m_x,n_x)
 type(spectral_function),intent(inout) :: wpol
 real(dp),intent(in)                   :: eigenvalue(wpol%npole_reso_apb)
 real(dp),intent(out)                  :: energy_gm
!=====
 integer                               :: t_kl,t_kl_global,klspin
 integer                               :: t_ij,t_ij_global,ijspin
 integer                               :: ibf_auxil,ibf_auxil_global
 integer                               :: nmat
 integer                               :: kstate,lstate
 integer                               :: istate,jstate
 real(dp),allocatable                  :: eri_3center_mat(:,:),residu_local(:,:)
 integer                               :: desc_3center_eigen(ndel)
 integer                               :: desc_residu(ndel)
 integer                               :: m_3center,n_3center
 real(dp)                              :: rtmp
 integer                               :: iprow,ipcol
 integer                               :: m_bigx_block,n_bigx_block
 real(dp),allocatable                  :: bigx_block(:,:)
!=====

 call start_clock(timing_buildw)

 write(stdout,'(/,a)') ' Build v^{1/2} * chi * v^{1/2}'

 call allocate_spectral_function(nbf_auxil,wpol)
 wpol%pole(1:wpol%npole_reso_apb) = eigenvalue(:)

 nmat = wpol%npole_reso_apb

#ifndef HAVE_SCALAPACK

 allocate(eri_3center_mat(nbf_auxil,nmat))
 do t_kl=1,nmat
   kstate = wpol%transition_table_apb(1,t_kl)
   lstate = wpol%transition_table_apb(2,t_kl)
   klspin = wpol%transition_table_apb(3,t_kl)
   eri_3center_mat(:,t_kl) = eri_3center_eigen(:,kstate,lstate,klspin)
 end do

 ! Use the symmetry ( I | k l ) to regroup (kl) and (lk) contributions
 ! and the block structure of eigenvector | X  Y |
 !                                        | Y  X |
 ! => only needs (X+Y)
 wpol%residu_left(:,:) = MATMUL( eri_3center_mat , bigx(:,:) ) * SQRT(spin_fact)

 energy_gm = 0.5_dp * ( SUM( wpol%residu_left(:,:)**2 ) - spin_fact * SUM( eri_3center_mat(:,:)**2 ) )
 !
 ! Since wpol%residu_left and eri_3center_mat are distributed, we have to sum up
 call xsum(energy_gm)

 deallocate(eri_3center_mat)

#else 


! ! bigx = bigx + bigy 
! call PDGEADD('N',nmat,nmat,1.d0,bigy,1,1,desc_x,1.d0,bigx,1,1,desc_x)
! Already done!

 bigx(:,:) = bigx(:,:) * SQRT(spin_fact)

 wpol%residu_left(:,:) = 0.0_dp
 ! First loop over the SCALAPACK grid
 do ipcol=0,npcol_sd-1
   do iprow=0,nprow_sd-1
     m_bigx_block = row_block_size(nmat,iprow,nprow_sd)
     n_bigx_block = col_block_size(nmat,ipcol,npcol_sd)

     allocate(bigx_block(m_bigx_block,n_bigx_block))
     if( ipcol == ipcol_sd .AND. iprow == iprow_sd ) then
       bigx_block(:,:) = bigx(:,:)
     else
       bigx_block(:,:) = 0.0_dp
     endif
     call xsum(bigx_block)

     do t_kl=1,n_bigx_block
       t_kl_global = colindex_local_to_global(ipcol,npcol_sd,t_kl)

       do t_ij=1,m_bigx_block
         t_ij_global = rowindex_local_to_global(iprow,nprow_sd,t_ij)
         istate = wpol%transition_table_apb(1,t_ij_global)
         jstate = wpol%transition_table_apb(2,t_ij_global)
         ijspin = wpol%transition_table_apb(3,t_ij_global)

         wpol%residu_left(:,t_kl_global) = wpol%residu_left(:,t_kl_global) &
                  + eri_3center_eigen(:,istate,jstate,ijspin) * bigx_block(t_ij,t_kl)

       enddo
     enddo


     deallocate(bigx_block)
   enddo
 enddo

 energy_gm = 0.0_dp
 do t_ij_global=1,nmat
   istate = wpol%transition_table_apb(1,t_ij_global)
   jstate = wpol%transition_table_apb(2,t_ij_global)
   ijspin = wpol%transition_table_apb(3,t_ij_global)
   energy_gm = energy_gm - SUM( eri_3center_eigen(:,istate,jstate,ijspin)**2 ) * spin_fact * 0.5_dp
 enddo

 energy_gm = energy_gm + 0.5_dp * ( SUM( wpol%residu_left(:,:)**2 ) )
 call xsum(energy_gm)


#endif



 call stop_clock(timing_buildw)

end subroutine chi_to_sqrtvchisqrtv_auxil


!=========================================================================
subroutine chi_to_sqrtvchisqrtv_auxil_spa(nbf,nbf_auxil,a_diag,wpol)
 use m_definitions
 use m_warning
 use m_basis_set
 use m_eri_ao_mo
 use m_spectral_function
 implicit none
 
 integer,intent(in)                    :: nbf,nbf_auxil
 type(spectral_function),intent(inout) :: wpol
 real(dp),intent(in)                   :: a_diag(wpol%npole_reso_spa)
!=====
 integer                               :: t_kl,klspin
 integer                               :: kstate,lstate
!=====

 call start_clock(timing_buildw)

 write(stdout,'(/,a)') ' Build v^{1/2} * chi * v^{1/2} part from single pole approximation'

 wpol%pole(wpol%npole_reso_apb+1:wpol%npole_reso) = a_diag(:)

 do t_kl=1,wpol%npole_reso_spa
   kstate = wpol%transition_table_spa(1,t_kl)
   lstate = wpol%transition_table_spa(2,t_kl)
   klspin = wpol%transition_table_spa(3,t_kl)


   wpol%residu_left(:,wpol%npole_reso_apb+t_kl) = eri_3center_eigen(:,kstate,lstate,klspin) * SQRT(spin_fact) 

 end do


 call stop_clock(timing_buildw)

end subroutine chi_to_sqrtvchisqrtv_auxil_spa


!=========================================================================