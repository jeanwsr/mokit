! written by jxzou at 20210126: convert .fch -> .wfn file

program main
 use util_wrapper, only: formchk
 implicit none
 integer :: i, k
 character(len=3) :: str
 character(len=240) :: fchname
 logical :: read_no

 i = iargc()
 if(i<1 .or. i>2) then
  write(6,'(/,A)') 'ERROR in subroutine fch2wfn: wrong command line arguments!'
  write(6,'(A)')   'Example 1 (HF/DFT): fch2wfn a.fch'
  write(6,'(A,/)') 'Example 2 (NOs)   : fch2wfn a.fch -no'
  stop
 end if

 call getarg(1, fchname)
 call require_file_exist(fchname)

 ! if .chk file provided, convert into .fch file automatically
 k = LEN_TRIM(fchname)
 if(fchname(k-3:k) == '.chk') then
  call formchk(fchname)
  fchname = fchname(1:k-3)//'fch'
 end if

 read_no = .false.
 if(i == 2) then
  call getarg(2, str)
  if(str /= '-no') then
   write(6,'(A)') 'ERROR in subroutine fch2wfn: the 2nd argument is wrong!'
   write(6,'(A)') "It can only be '-no'."
   stop
  else
   read_no = .true.
  end if
 end if

 call fch2wfn(fchname, read_no)
end program main

subroutine fch2wfn(fchname, read_no)
 use fch_content
 implicit none
 integer :: h, i, j, k, m, n, p, q, nmo, nbf1, tot_nprim, fid
 integer, parameter :: shltyp2nprim(-5:5) = [21,15,10,6,4,1,3,6,10,15,21]
! wfn file only uses Cartesian-type basis set, so spherical harmonic functions
! need to be expanded to Cartesian ones
!   Spherical     |     Cartesian
! -5,-4,-3,-2,-1, 0, 1, 2, 3, 4, 5
!  H  G  F  D  L  S  P  D  F  G  H
 integer, parameter :: f10_order(10) = [11,12,13,17,14,15,18,19,16,20]
 integer, parameter :: g15_order(15) = [23,29,32,27,22,28,35,34,26,31,33,30,25,&
                                        24,21]
 integer, allocatable :: eff_nuc_charge(:), tot_nprim_per_shl(:)
 integer, allocatable :: cen_assign(:), type_assign(:), shl_nprim(:)
 ! eff_nuc_charge: effective nuclear charge, size natom
 ! tot_nprim_per_shl: total number of primitive Gaussians per shell, size ncontr
 ! cen_assign: center assignments in .wfn file, size tot_nprim
 ! type_assign: type assignments in .wfn file, size tot_nprim
 ! shl_nprim(i) = shltyp2nprim(shell_type(i))
 real(kind=8), parameter :: up_limit = 2.0000001d0, low_limit = -0.0000001d0
 real(kind=8), allocatable :: exponents(:), mo0(:,:), mo1(:,:), mo2(:,:)
 ! exponents: exponents of Gaussian functions, size tot_nprim
 ! mo0: MOs under spherical harmonic type basis, expanded on contracted Gaussians
 ! mo1: MOs under Cartesian-type basis, expanded on contracted Gaussians
 ! mo2: MOs under Cartesian-type basis, expanded on primitive Gaussians
 ! Note that mo0, mo1 and mo2 contains only (partially) occupied orbitals
 character(len=240) :: wfnname
 character(len=240), intent(in) :: fchname
 logical :: uhf, sph
 logical, intent(in) :: read_no

 i = INDEX(fchname,'.fch')
 if(i == 0) then
  write(6,'(A)') "ERROR in subroutine fch2wfn: '.fch' key not found in file&
                    &name "//TRIM(fchname)
  stop
 end if

 wfnname = fchname(1:i-1)//'.wfn'
 call check_uhf_in_fch(fchname, uhf) ! determine whether UHF
 call read_fch(fchname, uhf) ! read content in .fch(k) file

 ! Only occupied orbitals (including partially occupied) are recorded in .wfn
 if(read_no) then
  nmo = nif
 else
  if(uhf) then ! UHF-type wave function
   nmo = na + nb
  else ! R(O)HF-type wave function
   nmo = na
  end if
 end if

 ! Check values of "Alpha Orbital Energies". If they are among [0,2], they are
 !  probably natural orbital occupation numbers. Print warnings to remind the
 !  user the argument '-no'.
 if(ALL(eigen_e_a<up_limit) .and. ALL(eigen_e_a>low_limit) .and. (.not.read_no)) then
  write(6,'(/,A)') REPEAT('-',71)
  write(6,'(A)') 'Warning from subroutine fch2wfn: it seems that this is a&
                 & .fch(k) file'
  write(6,'(A)') 'including natural orbitals, since all orbital energies are&
                 & among [0,2].'
  write(6,'(A)') "But '-no' argument is not found. You should know what you&
                 & are doing."
  write(6,'(A,/)') REPEAT('-',71)
 end if

 allocate(shl_nprim(ncontr))
 forall(i=1:ncontr) shl_nprim(i) = shltyp2nprim(shell_type(i))

 allocate(tot_nprim_per_shl(ncontr))
 forall(i=1:ncontr) tot_nprim_per_shl(i) = shl_nprim(i)*prim_per_shell(i)
 tot_nprim = SUM(tot_nprim_per_shl)

 open(newunit=fid,file=TRIM(wfnname),status='replace')
 write(fid,'(A)') ' Generated by utility fch2wfn in MOKIT'
 write(fid,'(A,I15,A,I7,A,I9,A)') 'GAUSSIAN',nmo,' MOL ORBITALS',tot_nprim,&
                                 &' PRIMITIVES',natom,' NUCLEI'

 ! calculate effective nuclear chages (remember to minus ECP core, if any)
 allocate(eff_nuc_charge(natom), source=0)
 if(allocated(RNFroz)) then
  forall(i = 1:natom) eff_nuc_charge(i) = ielem(i) - NINT(RNFroz(i))
 else
  forall(i = 1:natom) eff_nuc_charge(i) = ielem(i)
 end if

 do i = 1, natom, 1
  write(fid,'(2X,A2,I4,4X,A,I3,A,1X,3F12.8,2X,A,I3,A)') elem(i),i,'(CENTRE',i,')',&
   coor(1:3,i)/Bohr_const,'CHARGE =',eff_nuc_charge(i),'.0'
 end do ! for i
 deallocate(eff_nuc_charge)

 allocate(cen_assign(tot_nprim))
 k = 0
 do i = 1, ncontr, 1
  j = tot_nprim_per_shl(i)
  cen_assign(k+1:k+j) = shell2atom_map(i)
  k = k + j
 end do ! for i
 deallocate(tot_nprim_per_shl)
 write(fid,"('CENTRE ASSIGNMENTS  ',20I3)") cen_assign
 deallocate(cen_assign)

 ! create arrays type_assign and exponents; update arrays contr_coeff and
 ! contr_coeff_sp by multiplying each contraction coefficient with corresponding
 ! normalization factor
 allocate(type_assign(tot_nprim), exponents(tot_nprim))
 k = 0; q = 0
 do i = 1, ncontr, 1
  j = prim_per_shell(i); p = shell_type(i)
  forall(m = 1:shl_nprim(i)) exponents(k+1+j*(m-1):k+j*m) = prim_exp(q+1:q+j)

  if(p == -1) then ! L, SP
   call contr_coeff_multiply_norm_fac(j, 0, prim_exp(q+1:q+j), &
                                           contr_coeff(q+1:q+j))
   call contr_coeff_multiply_norm_fac(j, 1, prim_exp(q+1:q+j), &
                                           contr_coeff_sp(q+1:q+j))
  else !  S/P/D/F/G/H
   call contr_coeff_multiply_norm_fac(j, p, prim_exp(q+1:q+j), &
                                           contr_coeff(q+1:q+j))
  end if

  select case(p)
  case(0) ! S
   type_assign(k+1:k+j) = 1
  case(1) ! P
   forall(m = 1:3) type_assign(k+1+j*(m-1):k+j*m) = 1 + m
  case(-1) ! L, SP
   forall(m = 1:4) type_assign(k+1+j*(m-1):k+j*m) = m
  case(-2,2) ! D
   forall(m = 1:6) type_assign(k+1+j*(m-1):k+j*m) = 4 + m
  case(-3,3) ! F
   forall(m = 1:10) type_assign(k+1+j*(m-1):k+j*m) = f10_order(m)
  case(-4,4) ! G
   forall(m = 1:15) type_assign(k+1+j*(m-1):k+j*m) = g15_order(m)
  case(-5,5) ! H
   forall(m = 1:21) type_assign(k+1+j*(m-1):k+j*m) = 35 + m
  case default
   write(6,'(/,A)') 'ERROR in subroutine fch2wfn: shell_type out of range.'
   write(6,'(A,I0)') 'shell_type(i)=', shell_type(i)
   stop
  end select
  ! remember to update k and q
  k = k + j*shl_nprim(i)
  q = q + j
 end do ! for i

 write(fid,"('TYPE ASSIGNMENTS    ',20I3)") type_assign
 write(fid,"('EXPONENTS ',5D14.7)") exponents
 deallocate(type_assign, exponents)

 ! transform MO coefficients from spherical harmonic type into Cartesian type,
 ! if needed
 if(ANY(shell_type > 1)) then ! Cartesian-type basis functions
  sph = .false.
  nbf1 = nbf
  allocate(mo1(nbf1,nmo))
  if(read_no) then
   mo1 = alpha_coeff
  else ! R(O)HF, UHF
   mo1(:,1:na) = alpha_coeff(:,1:na)
   if(uhf) mo1(:,na+1:na+nb) = beta_coeff(:,1:nb)
  end if
 else ! spherical harmonic type basis functions
  sph = .true.
  allocate(mo0(nbf,nmo))
  if(read_no) then
   mo0 = alpha_coeff
  else ! R(O)HF, UHF
   mo0(:,1:na) = alpha_coeff(:,1:na)
   if(uhf) mo0(:,na+1:na+nb) = beta_coeff(:,1:nb)
  end if
  nbf1 = nbf + COUNT(shell_type==-2) + 3*COUNT(shell_type==-3) + &
           & 6*COUNT(shell_type==-4) + 10*COUNT(shell_type==-5)
  ! [6D,10F,15G,21H] - [5D,7F,9G,11H] = [1,3,6,10]
  allocate(mo1(nbf1,nmo))
  call mo_sph2cart(ncontr, shell_type, nbf, nbf1, nmo, mo0, mo1)
  deallocate(mo0)
 end if

 deallocate(alpha_coeff)
 if(allocated(beta_coeff)) deallocate(beta_coeff)
 call scale_mo_as_wfn(ncontr, shell_type, nbf1, nmo, mo1)

 ! multiply MO coefficients (Cartesian basis) with contraction coefficients
 allocate(mo2(tot_nprim,nmo),source=0d0)
 h = 0; m = 0; n = 0
 do i = 1, ncontr, 1
  p = shl_nprim(i); q = prim_per_shell(i)

  if(p == 4) then ! L, SP
   do k = 1, q, 1
    mo2(n+k,:) = mo1(m+1,:)*contr_coeff(h+k)
   end do ! for k
   n = n + q; m = m + 1
   do j = 1, 3, 1
    do k = 1, q, 1
     mo2(n+k,:) = mo1(m+j,:)*contr_coeff_sp(h+k)
    end do ! for k
    n = n + q
   end do ! for j
   h = h + q; m = m + 3
  else ! S/P/D/F/G/H
   do j = 1, p, 1
    do k = 1, q, 1
     mo2(n+k,:) = mo1(m+j,:)*contr_coeff(h+k)
    end do ! for k
    n = n + q
   end do ! for j
   h = h + q; m = m + p
  end if

 end do ! for i
 deallocate(mo1)

 ! print MO coefficients and orbital energies into .wfn file
 if(read_no) then ! natural orbitals
  do i = 1, nmo, 1
   write(fid,'(A,I5,A,F13.7,A)') 'MO',i,'     MO 0.0        OCC NO =',&
                             eigen_e_a(i),'  ORB. ENERGY =    0.000000'
   write(fid,'(5(1X,D15.8))') mo2(:,i)
  end do ! for i
 else
  if(uhf) then ! UHF
   do i = 1, na, 1
    write(fid,'(A,I5,A,F12.6)') 'MO',i,'     MO 0.0        OCC NO =    1.00000&
                                &00  ORB. ENERGY =',eigen_e_a(i)
    write(fid,'(5(1X,D15.8))') mo2(:,i)
   end do ! for i
   do i = 1, nb, 1
    write(fid,'(A,I5,A,F12.6)') 'MO',i+nif,'     MO 0.0        OCC NO =    1.000&
                                &0000  ORB. ENERGY =',eigen_e_b(i)
    write(fid,'(5(1X,D15.8))') mo2(:,i+na)
   end do ! for i
  else ! R(O)HF
   do i = 1, nb, 1
    write(fid,'(A,I5,A,F12.6)') 'MO',i,'     MO 0.0        OCC NO =    2.00000&
                                &00  ORB. ENERGY =',eigen_e_a(i)
    write(fid,'(5(1X,D15.8))') mo2(:,i)
   end do ! for i
   do i = nb+1, na, 1
    write(fid,'(A,I5,A,F12.6)') 'MO',i,'     MO 0.0        OCC NO =    1.00000&
                                &00  ORB. ENERGY =',eigen_e_a(i)
    write(fid,'(5(1X,D15.8))') mo2(:,i)
   end do ! for i
  end if
 end if
 deallocate(mo2)

 write(fid,'(A)') 'END DATA'
 write(fid,'(A,F22.12,A,F13.8)') ' TOTAL ENERGY =',tot_e,' THE VIRIAL(-V/T)=',virial
 close(fid)
end subroutine fch2wfn

! multiply each contraction coefficient with corresponding normalization factor
subroutine contr_coeff_multiply_norm_fac(n, p, prim_exp, contr_coeff)
 implicit none
 integer :: i, p0
 integer, intent(in) :: n, p
 real(kind=8) :: r2a_pi(n)
 ! 2*alpha/PI. Because variable cannot begin with a integer, so 'r' is added
 real(kind=8), parameter :: PI = 4d0*DATAN(1d0)
 real(kind=8), parameter :: sqrt_2pi = DSQRT(8d0*DATAN(1d0))
 real(kind=8), intent(in) :: prim_exp(n)
 real(kind=8), intent(inout) :: contr_coeff(n)

 if(p == -1) then
  write(6,'(A)') 'ERROR in subroutine contr_coeff_multiply_norm_fac: p=-1.'
  write(6,'(A)') 'You should divide L/SP into separate S/P before calling &
                    &this subroutine.'
  stop
 end if
 if(p < 0) then
  p0 = -p
 else
  p0 = p
 end if

 forall(i = 1:n)
  r2a_pi(i) = (2d0*prim_exp(i)/PI)**(0.25d0)
  contr_coeff(i) = contr_coeff(i)*(r2a_pi(i)**(2*p0+3))
 end forall
 if(p0 > 0) contr_coeff = contr_coeff*(sqrt_2pi**p0)
end subroutine contr_coeff_multiply_norm_fac

! Scale MOs (Cartesian-type basis) by multiplying some constants
subroutine scale_mo_as_wfn(ncontr, shell_type, nbf, nif, coeff)
 implicit none
 integer :: i, j, k
 integer, intent(in) :: ncontr, nbf, nif
 integer, intent(in) :: shell_type(ncontr)
 real(kind=8), parameter :: s3=DSQRT(3d0), s15=DSQRT(15d0), s45=DSQRT(45d0),&
  s105=DSQRT(105d0), s945=DSQRT(945d0)
 real(kind=8), parameter :: c15g(15) = [s105,s15,3d0,s15,s105,s15,s3,s3,s15,&
  3d0,s3,3d0,s15,s15,s105]
 real(kind=8), parameter :: c21h(21) = [s945,s105,s45,s45,s105,s945,s105,s15,&
  3d0,s15,s105,s45,3d0,3d0,s45,s45,s15,s45,s105,s105,s945]
 real(kind=8), intent(inout) :: coeff(nbf,nif)

 j = 0
 do i = 1, ncontr, 1
  select case(shell_type(i))
  case(0) ! S
   j = j + 1
  case(1) ! P
   j = j + 3
  case(-1) ! L, SP
   j = j + 4
  case(2) ! 6D
   coeff(j+1:j+3,:) = coeff(j+1:j+3,:)/DSQRT(3d0)
   j = j + 6
  case(3) ! 10F
   coeff(j+1:j+3,:) = coeff(j+1:j+3,:)/DSQRT(15d0)
   coeff(j+4:j+9,:) = coeff(j+4:j+9,:)/DSQRT(3d0)
   j = j + 10
  case(4) ! 15G
   forall(k = 1:15) coeff(j+k,:) = coeff(j+k,:)/c15g(k)
   j = j + 15
  case(5) ! 21H
   forall(k = 1:21) coeff(j+k,:) = coeff(j+k,:)/c21h(k)
   j = j + 21
  case default
   write(6,'(A)') 'ERROR in scale_mo_as_wfn: shell_type(i) out of range!'
   write(6,'(A,3I5)') 'i, ncontr, shell_type(i)=', i, ncontr, shell_type(i)
   stop
  end select
 end do ! for i

end subroutine scale_mo_as_wfn

