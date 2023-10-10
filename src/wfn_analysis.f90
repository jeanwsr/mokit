! written by jxzou at 20220524: move some subroutines from rwwfn.f90 and
!  pop.f90 to this file

module population
 implicit none
 integer :: ncontr, nbf, nif, natom, nmo, i1, i2
! nmo <= nif, the number of MOs to be analyzed. nmo = i2-i1+1
! i1: the beginning index of MOs to be analyzed
! i2: the final index of MOs to be analyzed
 integer, allocatable :: shl2atm(:), shltyp(:), bfirst(:), mo_center(:,:)
! shl2atm: Shell to atom map. Atom begins from 1, not 0
! shltyp: Shell types
!   Spherical     |     Cartesian
! -5,-4,-3,-2,-1, 0, 1, 2, 3, 4, 5
!  H  G  F  D  L  S  P  D  F  G  H
! bfirst: the beginning index of basis func. of each atom, size natom+1
! mo_center: the center(s) of each MOs (multiple centers allowed), (0:natom,nmo)
! mo_center(0,j) is number of atomic centers of the j-th MO
! mo_center(1:,j) is the atomic centers of the j-th MO

 real(kind=8), allocatable :: mo_dis(:,:)
 ! mo_dis: distances between MOs, defined as the shortest distances of two
 !         atomic centers
 logical :: cart

 type mo_cluster       ! an MO cluster
  integer :: nocc = 0  ! number of occupied MOs
  integer :: nvir = 0  ! number of virtual MOs
  integer, allocatable :: occ_idx(:) ! indices of occupied MOs, size nocc
  integer, allocatable :: vir_idx(:) ! indices of virtual MOs, size nvir
 end type mo_cluster

contains

! get integer array bfirst (the beginning index of basis func. of each atom)
subroutine get_bfirst()
 implicit none
 integer :: i, j
 integer, allocatable :: ang0(:)

 if( ANY(shltyp>1) ) then
  cart = .true. ! 6D 10F
 else
  cart = .false. ! 5D 7F
 end if

 allocate(ang0(ncontr), source=0)
 if(cart) then
  forall(i = 1:ncontr) ang0(i) = (shltyp(i)+1)*(shltyp(i)+2)/2
 else
  where(shltyp == -1)
   ang0 = 4
  elsewhere
   ang0 = 2*IABS(shltyp) + 1
  end where
 end if

 bfirst = 0; bfirst(1) = 1

 do i = 1, ncontr, 1
  j = shl2atm(i) + 1
  bfirst(j) = bfirst(j) + ang0(i)
 end do ! for i

 deallocate(ang0)

 do i = 2, natom+1, 1
  bfirst(i) = bfirst(i) + bfirst(i-1)
 end do ! for i
end subroutine get_bfirst

subroutine init_shltyp_shl2atm_bfirst(fchname)
 implicit none
 character(len=240), intent(in) :: fchname

 call read_ncontr_from_fch(fchname, ncontr)
 allocate(shltyp(ncontr), shl2atm(ncontr))
 call read_shltyp_and_shl2atm_from_fch(fchname, ncontr, shltyp, shl2atm)

 natom = shl2atm(ncontr)
 allocate(bfirst(natom+1))
 call get_bfirst()
 deallocate(shltyp, shl2atm)
end subroutine init_shltyp_shl2atm_bfirst

! Mulliken population for a set of MOs. Atomic centers are stored in integer
! array mo_center. An MO is allowed to have multiple centers since we may deal
! with diradical orbitals
subroutine mulliken_pop_of_mo(fchname, ibegin, iend)
 implicit none
 integer :: i, j, k, m, ak(1)
 integer, intent(in) :: ibegin, iend
 real(kind=8) :: r, ddot
 real(kind=8), parameter :: diff = 0.1d0
 ! diff: difference between the largest and the 2nd largest component
 real(kind=8), allocatable :: mo(:,:), S(:,:), rtmp(:), pop(:,:)
 character(len=240), intent(in) :: fchname

 i1 = ibegin; i2 = iend
 if(i2<i1 .or. i1<1 .or. i2<1) then
  write(6,'(/,A)') 'ERROR in subroutine mulliken_pop_of_mo: invalid i1, i2.'
  write(6,'(2(A,I0))') 'i1=', i1, ', i2=', i2 
  stop
 end if

 ! get integer array bfirst
 call init_shltyp_shl2atm_bfirst(fchname)

 call read_nbf_and_nif_from_fch(fchname, nbf, nif)
 allocate(mo(nbf,nif), S(nbf,nbf))

 ! read MOs and AO-basis overlap integrals
 call read_mo_from_fch(fchname, nbf, nif, 'a', mo)
 call get_ao_ovlp_using_fch(fchname, nbf, S)

 allocate(rtmp(nbf), pop(natom,i1:i2))
 pop = 0d0

 do i = i1, i2, 1
  do j = 1, natom, 1
   k = bfirst(j); m = bfirst(j+1)-1
   rtmp = 0d0
   call dgemv('N', nbf, m-k+1, 1d0, S(:,k:m), nbf, mo(k:m,i), 1, 0d0, rtmp, 1)
   pop(j,i) = ddot(nbf, mo(:,i), 1, rtmp, 1)
  end do ! for j
 end do ! for i

 deallocate(mo, S, rtmp, bfirst)
 allocate(mo_center(0:natom,i1:i2), source=0)

 do i = i1, i2, 1
  ! the largest component on an atom of an orbital
  ak = MAXLOC(pop(:,i)); k = ak(1); r = pop(k,i)
  mo_center(0,i) = 1; mo_center(1,i) = k
  m = 1

  ! find the 2nd largest component and so on
  do j = 1, natom, 1
   if(j == k) cycle
   if(DABS(r - pop(j,i)) < diff) then
    m = m + 1
    mo_center(0,i) = m; mo_center(m,i) = j
   end if
  end do ! for j
 end do ! for i

 deallocate(pop)
! do i = i1, i2, 1
!  do j = 1, mo_center(0,i), 1
!   write(6,'(I3)',advance='no') mo_center(j,i)
!  end do ! for j
!  write(6,'(/)',advance='no')
! end do ! for i

 call gen_mo_dis_from_mo_center(fchname)
end subroutine mulliken_pop_of_mo

subroutine gen_mo_dis_from_mo_center(fchname)
 implicit none
 integer :: i, j, k, m, p, q, i3, i4
 real(kind=8) :: dis0, coor0(3), coor1(3)
 real(kind=8), allocatable :: coor(:,:), dis(:,:)
 character(len=240), intent(in) :: fchname

 allocate(coor(3,natom))
 call read_coor_from_fch(fchname, natom, coor)
 allocate(dis(natom,natom), source=0d0)

 do i = 1, natom-1, 1
  coor0 = coor(:,i)
  do j = i+1, natom, 1
   coor1 = coor(:,j) - coor0
   dis(j,i) = DSQRT(DOT_PRODUCT(coor1, coor1))
   dis(i,j) = dis(j,i)
  end do ! for j
 end do ! for i

 deallocate(coor)
 allocate(mo_dis(i1:i2,i1:i2), source=0d0)

 do i = i1, i2-1, 1
  i3 = mo_center(0,i)
  do j = i+1, i2, 1
   i4 = mo_center(0,j)
   dis0 = dis(mo_center(1,i), mo_center(1,j))

   do k = 1, i3, 1
    p = mo_center(k,i)
    do m = 1, i4, 1
     q = mo_center(m,j)
     if(dis(q,p) < dis0) dis0 = dis(q,p)
    end do ! for m
   end do ! for k

   mo_dis(j,i) = dis0
   mo_dis(i,j) = mo_dis(j,i)
  end do ! for j
 end do ! for i

 deallocate(dis, mo_center)
end subroutine gen_mo_dis_from_mo_center

end module population

! calculate the number of unpaired electrons and generate unpaired electron
! density .fch file
! Note: the input fchname must include natural orbitals and corresponding
! orbital occupation numbers.
subroutine calc_unpaired_from_fch(fchname, wfn_type, gen_dm, unpaired_e)
 implicit none
 integer :: i, j, k, ne, nbf, nif, mult, fid, fid1
 integer, intent(in) :: wfn_type ! 1/2/3 for UNO/GVB/CASSCF NOs
 character(len=240) :: buf, fchname1
 character(len=240), intent(in) :: fchname
 real(kind=8) :: t0, t1, y0, y1, upe(3)
 real(kind=8), intent(out) :: unpaired_e
 real(kind=8), allocatable :: noon(:,:), coeff(:,:), dm(:,:)
 logical, intent(in) :: gen_dm
 ! True/False: generate unpaired/odd electron density or not

 call read_nbf_and_nif_from_fch(fchname, nbf, nif)
 allocate(noon(nif,5))
 call read_eigenvalues_from_fch(fchname, nif, 'a', noon(:,1))

 write(6,'(A)') REPEAT('-',23)//' Radical index '//REPEAT('-',23)
 call read_mult_from_fch(fchname, mult)

 if(mult == 1) then
  open(newunit=fid,file=TRIM(fchname),status='old',position='rewind')
  do while(.true.)
   read(fid,'(A)',iostat=i) buf
   if(i /= 0) exit
   if(buf(1:14) == 'Number of elec') exit
  end do ! for while
  close(fid)
  read(buf(50:),*) ne
  i = ne/2   ! assuming NOs are ordered in decreasing occupation number
  if(wfn_type == 1) then ! UNO
   t0 = (noon(i,1) - noon(i+1,1))*0.5d0
   y0 = 1d0 - 2d0*t0/(1d0+t0*t0)
   t1 = (noon(i-1,1) - noon(i+2,1))*0.5d0
   y1 = 1d0 - 2d0*t1/(1d0+t1*t1)
   write(6,'(A,F7.3)') 'biradical character   (1-2t/(1+t^2)) y0=', y0
   write(6,'(A,F7.3)') 'tetraradical character(1-2t/(1+t^2)) y1=', y1
  else ! GVB/CASSCF NOs
   ! For GVB/CAS NOs, there is no unique way to define radical index.
   ! Here we adopt the occupation numbers of LUNO and LUNO+1.
   ! You can adopt the way of calculating y0/y1 in UHF, if you like.
   y0 = noon(i+1,1); y1 = noon(i+2,1)
   write(6,'(A,F7.3)') 'biradical character   (2c^2) y0=', y0
   write(6,'(A,F7.3)') 'tetraradical character(2c^2) y1=', y1
  end if
 else
  write(6,'(A)') 'Not spin singlet. Biradical character will not be computed.'
 end if

 call prt_unpaired_e(nif, noon, upe)
 unpaired_e = upe(3)

 if(gen_dm) then
  i = index(fchname, '.fch')
  fchname1 = fchname(1:i-1)//'_unpaired.fch'
  open(newunit=fid,file=TRIM(fchname),status='old',position='rewind')
  open(newunit=fid1,file=TRIM(fchname1),status='replace')
  do while(.true.)
   read(fid,'(A)',iostat=i) buf
   if(i /= 0) exit
   write(fid1,'(A)') TRIM(buf)
  end do ! for while
  close(fid)
  close(fid1)
  allocate(coeff(nbf,nif), source=0d0)
  call read_mo_from_fch(fchname, nbf, nif, 'a', coeff)
  allocate(dm(nbf,nbf), source=0d0)

  do i = 1, nbf, 1
   do j = 1, i, 1
    do k = 1, nif, 1
     if(noon(k,5)<1d-5 .or. (2d0-noon(k,5)<1d-5)) cycle
     dm(j,i) = dm(j,i) + noon(k,5)*coeff(j,k)*coeff(i,k)
    end do ! for k
   end do ! for j
  end do ! for i

  call write_dm_into_fch(fchname1, .true., nbf, dm)
  deallocate(dm, coeff)
  call write_eigenvalues_to_fch(fchname1, nif, 'a', noon(:,5), .true.)
 end if

 deallocate(noon)
end subroutine calc_unpaired_from_fch

! calculate the number of unpaired electrons using a GAMESS GVB .dat file
subroutine calc_unpaired_from_gms_dat(datname, mult, unpaired_e)
 implicit none
 integer :: nopen, npair, nif
 integer, intent(in) :: mult
 character(len=240), intent(in) :: datname
 real(kind=8) :: upe(3)
 real(kind=8), intent(out) :: unpaired_e
 real(kind=8), allocatable :: pair_coeff(:,:), noon(:,:)

 if(mult < 1) then
  write(6,'(/,A)') 'ERROR in subroutine calc_unpaired_from_gms_dat: mult<1.'
  write(6,'(A)') 'Wrong parameter for spin multiplicity!'
  stop
 end if

 nopen = mult - 1
 call read_npair_from_dat(datname, npair)
 allocate(pair_coeff(2,npair))
 call read_ci_coeff_from_dat(datname, npair, pair_coeff)
 
 nif = npair*2 + nopen
 allocate(noon(nif,5), source=0d0)
 call gen_noon_from_pair_coeff(npair, pair_coeff, nopen, nif, noon(:,1))
 deallocate(pair_coeff)

 call prt_unpaired_e(nif, noon, upe)
 deallocate(noon)
 unpaired_e = upe(3)
end subroutine calc_unpaired_from_gms_dat

! calculate the number of unpaired electrons using a GAMESS GVB .gms file
subroutine calc_unpaired_from_gms_out(outname, unpaired_e)
 implicit none
 integer :: ncore, nopen, npair, nif
 character(len=240), intent(in) :: outname
 real(kind=8) :: upe(3)
 real(kind=8), intent(out) :: unpaired_e
 real(kind=8), allocatable :: pair_coeff(:,:), noon(:,:)

 call read_npair_from_gms(outname, ncore, nopen, npair)
 allocate(pair_coeff(2,npair))
 call read_ci_coeff_from_gms(outname, npair, pair_coeff)
 
 nif = npair*2 + nopen
 allocate(noon(nif,5), source=0d0)
 call gen_noon_from_pair_coeff(npair, pair_coeff, nopen, nif, noon(:,1))
 deallocate(pair_coeff)

 call prt_unpaired_e(nif, noon, upe)
 deallocate(noon)
 unpaired_e = upe(3)
end subroutine calc_unpaired_from_gms_out

! generate GVB NOON from pair coefficients
subroutine gen_noon_from_pair_coeff(npair, pair_coeff, nopen, nif, noon)
 implicit none
 integer :: i
 integer, intent(in) :: npair, nopen, nif
 real(kind=8), intent(in) :: pair_coeff(2,npair)
 real(kind=8), intent(out) :: noon(nif)

 noon = 0d0
 if(nopen > 0) noon(1:nopen) = 1d0
 if(npair == 0) return

 forall(i = 1:npair)
  noon(nopen+2*i-1) = 2d0*pair_coeff(1,i)*pair_coeff(1,i)
  noon(nopen+2*i) = 2d0*pair_coeff(2,i)*pair_coeff(2,i)
 end forall
end subroutine gen_noon_from_pair_coeff

! print unpaired electron information
subroutine prt_unpaired_e(nif, noon, upe)
 implicit none
 integer :: i
 integer, intent(in) :: nif
 real(kind=8), intent(inout) :: noon(nif,5)
 real(kind=8), intent(out) :: upe(3)

 forall(i = 1:nif) noon(i,2) = 2d0 - noon(i,1)
 forall(i = 1:nif)
  noon(i,3) = noon(i,1)*noon(i,2)
  noon(i,4) = min(noon(i,1), noon(i,2))
 end forall
 forall(i = 1:nif) noon(i,5) = noon(i,3)*noon(i,3)

 upe(1) = SUM(noon(:,3))
 upe(2) = SUM(noon(:,4))
 upe(3) = SUM(noon(:,5))
 write(6,'(A,F7.3)') "Yamaguchi's unpaired electrons  (sum_n n(2-n)      ):",upe(1)
 write(6,'(A,F7.3)') "Head-Gordon's unpaired electrons(sum_n min(n,(2-n))):",upe(2)
 write(6,'(A,F7.3)') "Head-Gordon's unpaired electrons(sum_n (n(2-n))^2  ):",upe(3)
 write(6,'(A)') REPEAT('-',61)
end subroutine prt_unpaired_e

! read ncore, nopen and npair from a GAMESS .gms file
subroutine read_npair_from_gms(gmsname, ncore, nopen, npair)
 implicit none
 integer :: i, fid
 integer, intent(out) :: ncore, nopen, npair
 character(len=240) :: buf
 character(len=240), intent(in) :: gmsname

 ncore = 0; nopen = 0; npair = 0; buf = ' '
 open(newunit=fid,file=TRIM(gmsname),status='old',position='rewind')

 do while(.true.)
  read(fid,'(A)', iostat=i) buf
  if(i /= 0) exit
  if(buf(34:41) == 'NCO    =') exit
 end do

 if(i /= 0) then
  write(6,'(A)') "ERROR in subroutine read_npair_from_gms: no 'NCO    =' found&
                & in file "//TRIM(gmsname)
  close(fid)
  stop
 end if

 read(buf(42:),*) ncore
 read(fid,'(A)') buf
 read(buf(19:),*) npair
 read(buf(42:),*) nopen
 close(fid)
end subroutine read_npair_from_gms

! read CI coefficients from a GAMESS .gms file
! Note: if there exist multiple sets of CI coefficients in the file,
!       only the last set will be read
subroutine read_ci_coeff_from_gms(fname, npair, coeff)
 implicit none
 integer :: i, j, fid
 integer, intent(in) :: npair
 character(len=240) :: buf
 character(len=240), intent(in) :: fname
 real(kind=8), intent(out) :: coeff(2,npair)

 buf = ' '; coeff = 0d0
 open(newunit=fid,file=TRIM(fname),status='old',position='append')

 do while(.true.)
  BACKSPACE(fid,iostat=i)
  if(i /= 0) exit
  BACKSPACE(fid,iostat=i)
  if(i /= 0) exit
  read(fid,'(A)') buf
  if(i/=0 .or. buf(7:18)=='ORBITAL   CI') exit
 end do ! for while

 if(i /= 0) then
  write(6,'(A)') 'ERROR in subroutine read_ci_coeff_from_gms: no GVB CI&
                & coefficients'
  write(6,'(A)') 'found in file '//TRIM(fname)//'!'
  close(fid)
  stop
 end if

 read(fid,'(A)') buf   ! skip one line

 do i = 1, npair, 1
  read(fid,'(A)') buf
  read(buf,*) j, j, j, coeff(1,i), coeff(2,i)
 end do ! for i

 close(fid)
end subroutine read_ci_coeff_from_gms

! perform Mulliken population analysis based on density matrix
!subroutine mulliken_pop_of_dm(nshl, shl2atm, ang, ibas, cart, nbf, P, S, natom, eff_nuc)
! implicit none
! integer :: i, j
! integer, intent(in) :: nshl, nbf, natom
! integer, intent(in) :: shl2atm(nshl), ang(nshl), ibas(nshl), eff_nuc(natom)
! integer, allocatable :: bfirst(:) ! size natom+1
! ! bfirst: the beginning index of basis func. of each atom
! real(kind=8), intent(in) :: P(nbf,nbf), S(nbf,nbf)
! real(kind=8) :: rtmp, ddot
! real(kind=8), allocatable :: gross(:) ! size natom
! logical, intent(in) :: cart
!
! allocate(bfirst(natom+1))
! call get_bfirst(nshl, shl2atm, ang, ibas, cart, natom, bfirst)
!
! allocate(gross(natom), source=0d0)
!
! do i = 1, natom, 1
!  rtmp = 0d0
!  do j = bfirst(i), bfirst(i+1)-1, 1
!   rtmp = rtmp + ddot(nbf, P(j,:), 1, S(:,j), 1)
!  end do ! for j
!  gross(i) = rtmp
! end do ! for i
!
! deallocate(bfirst)
! gross = eff_nuc - gross
! write(6,'(/,A)') 'Mulliken population:'
!
! do i = 1, natom, 1
!  write(6,'(I5,1X,F11.6)') i, gross(i)
! end do ! for i
!
! deallocate(gross)
!end subroutine mulliken_pop_of_dm

! perform lowdin/lowedin population analysis based on density matrix
!subroutine lowdin_pop_of_dm(nshl, shl2atm, ang, ibas, cart, nbf, P, S, natom, eff_nuc)
! implicit none
! integer :: i, j, m, lwork, liwork
! integer, intent(in) :: nshl, nbf, natom
! integer, intent(in) :: shl2atm(nshl), ang(nshl), ibas(nshl), eff_nuc(natom)
! integer, allocatable :: bfirst(:) ! size natom+1
! ! bfirst: the beginning index of basis func. of each atom
! integer, allocatable :: iwork(:), isuppz(:)
! real(kind=8), intent(in) :: P(nbf,nbf), S(nbf,nbf)
! real(kind=8) :: rtmp, ddot
! real(kind=8), allocatable :: gross(:) ! size natom
! real(kind=8), allocatable :: work(:), e(:), ev(:,:), sqrt_S_P(:,:), S0(:,:)
! ! e: eigenvalues, ev: eigenvectors, sqrt_S_P: S^(1/2)*P
! logical, intent(in) :: cart
!
! allocate(bfirst(natom+1))
! call get_bfirst(nshl, shl2atm, ang, ibas, cart, natom, bfirst)
!
! allocate(e(nbf), ev(nbf, nbf), isuppz(2*nbf))
! lwork = -1; liwork = -1
! allocate(work(1), iwork(1))
! allocate(S0(nbf,nbf), source=S)
! call dsyevr('V', 'A', 'L', nbf, S0, nbf, 0d0, 0d0, 0, 0, 1d-6, m, e, ev,&
!             nbf, isuppz, work, lwork, iwork, liwork, i)
! lwork = CEILING(work(1))
! liwork = iwork(1)
! deallocate(work, iwork)
! allocate(work(lwork), iwork(liwork))
! call dsyevr('V', 'A', 'L', nbf, S0, nbf, 0d0, 0d0, 0, 0, 1d-6, m, e, ev,&
!             nbf, isuppz, work, lwork, iwork, liwork, i)
! deallocate(isuppz, work, iwork)
!
! S0 = 0d0
! forall(i = 1:nbf) S0(i,i) = DSQRT(DABS(e(i)))
! deallocate(e)
! allocate(sqrt_S_P(nbf,nbf))
! call dsymm('R', 'U', nbf, nbf, 1d0, S0, nbf, ev, nbf, 0d0, sqrt_S_P, nbf)
! call dgemm('N', 'T', nbf, nbf, nbf, 1d0, sqrt_S_P, nbf, ev, nbf, 0d0, S0, nbf)
! deallocate(ev, sqrt_S_P)
!
! allocate(gross(natom), source=0d0)
! allocate(e(nbf))
!
! do i = 1, natom, 1
!  rtmp = 0d0
!
!  do j = bfirst(i), bfirst(i+1)-1, 1
!   e = S0(j,:)
!   do m = 1, nbf, 1
!    rtmp = rtmp + ddot(nbf,e,1,P(:,m),1)*S0(m,j)
!   end do ! for m
!  end do ! for j
!
!  gross(i) = rtmp
! end do ! for i
!
! deallocate(bfirst, e, S0)
! gross = eff_nuc - gross
!
! write(6,'(/,A)') 'Lowdin population:'
! do i = 1, natom, 1
!  write(6,'(I5,1X,F11.6)') i, gross(i)
! end do ! for i
!
! deallocate(gross)
!end subroutine lowdin_pop_of_dm

