module md_allocation
  !////////////////////////////////////////////////////////////////
  ! ALLOCATION MODULE
  ! Binary allocation formulation: either to leaves or to roots.
  ! Copyright (C) 2015, see LICENSE, Benjamin David Stocker
  ! contact: b.stocker@imperial.ac.uk
  !----------------------------------------------------------------
  use md_classdefs
  use md_params_core, only: npft, nlu, maxgrid, ndaymonth, ndayyear, &
    c_molmass, n_molmass, nmonth

  implicit none

  private 
  public allocation_daily, initio_allocation, initoutput_allocation, &
    getout_daily_allocation, writeout_ascii_allocation

  !----------------------------------------------------------------
  ! Module-specific (private) variables
  !----------------------------------------------------------------
  real, dimension(npft) :: dcleaf
  real, dimension(npft) :: dnleaf
  real, dimension(npft) :: dcroot
  real, dimension(npft) :: dnroot

  ! current conditions determining light use and N uptake efficiency
  type statetype_eval_imbalance
    type(orgpool) :: pleaf
    type(orgpool) :: proot
    type(orgpool) :: plabl
    real          :: usepft 
    integer       :: usemoy
    integer       :: usedoy
    integer       :: usejpngr
    real          :: airtemp
    real          :: soiltemp
  end type statetype_eval_imbalance
  type(statetype_eval_imbalance) :: state_eval_imbalance

  logical, parameter :: write_logfile_eval_imbalance = .true.

  !----------------------------------------------------------------
  ! Module-specific output variables
  !----------------------------------------------------------------
  ! output variables
  real, dimension(npft,maxgrid) :: outaCalclm
  real, dimension(npft,maxgrid) :: outaNalclm
  real, dimension(npft,maxgrid) :: outaCalcrm
  real, dimension(npft,maxgrid) :: outaNalcrm  

contains

  subroutine allocation_daily( jpngr, doy, moy, dtemp )
    !//////////////////////////////////////////////////////////////////
    ! Finds optimal shoot:root growth ratio to balance C:N stoichiometry
    ! of a grass (no wood allocation).
    !------------------------------------------------------------------
    use md_classdefs
    use md_plant, only: params_plant, params_pft_plant, pleaf, proot, &
      plabl, drgrow, lai_ind, nind, canopy, leaftraits, &
      get_canopy, get_leaftraits, get_leaftraits_init, frac_leaf
    use md_waterbal, only: solar
    use md_gpp, only: mlue, mrd_unitiabs, mactnv_unitiabs
    use md_soiltemp, only: dtemp_soil
    use md_ntransform, only: pninorg
    use md_params_core, only: eps
    use md_findroot_fzeroin

    ! xxx debug
    use md_nuptake, only: calc_dnup, outtype_calc_dnup
    use md_waterbal, only: solar, evap
    use md_gpp, only: calc_dgpp, calc_drd
    use md_npp, only: calc_resp_maint, calc_cexu, deactivate_root
    use md_gpp, only: dgpp, drd 
    use md_plant, only: dnpp, drleaf, drroot, dcex, dnup
    use md_interface

    ! arguments
    integer, intent(in) :: jpngr
    integer, intent(in) :: doy     ! day of year
    integer, intent(in) :: moy     ! month of year
    real,    intent(in) :: dtemp   ! air temperaure, deg C

    ! local variables
    integer :: lu
    integer :: pft
    real    :: cavl, navl, avl, maxdc_cavl, maxdc_navl
    real    :: frac_leaf_opt
    real, parameter :: freserve = 0.0

    ! variables for root finding algorithm
    real :: max_dcleaf_n_constraint, max_dc, min_dc, max_dc_save
    real :: abserr
    real :: relerr
    real :: dcleaf_opt
    real :: test
    real :: eval_allroots, eval_allleaves
    logical :: cont
    integer, parameter :: nmax = 100
    type(outtype_zeroin)  :: out_zeroin
    logical :: verbose = .false.

    ! xxx debug
    type( orgpool ) :: bal1, bal2, bald
    logical, save :: toleaves = .true.       ! boolean determining whether C and N in this time step are allocated to leaves or roots
    logical, save :: nignore = .true.

    ! ! Variables N balance test
    ! logical, parameter :: baltest_trans = .false.  ! set to true to do mass conservation test during transient simulation
    ! logical :: verbose = .false.  ! set to true to activate verbose mode
    ! logical :: baltest
    ! type( orgpool ) :: orgtmp1, orgtmp2, orgbal1
    ! real :: ctmp

    ! !------------------------------------------------------------------
    ! ! Turn mass conservation tests on and off
    ! !------------------------------------------------------------------
    ! baltest = .false.
    ! verbose = .false.

    abserr=100.0*XMACHEPS !*10e5
    relerr=1000.0*XMACHEPS !*10e5

    !------------------------------------------------------------------
    ! initialise
    !------------------------------------------------------------------
    dcleaf(:) = 0.0
    dnleaf(:) = 0.0
    dcroot(:) = 0.0
    dnroot(:) = 0.0
    drgrow(:) = 0.0


    do pft=1,npft

      lu = params_pft_plant(pft)%lu_category

      if (params_pft_plant(pft)%grass) then

        if ( interface%steering%dofree_alloc ) then
          !------------------------------------------------------------------
          ! Free allocation
          !------------------------------------------------------------------

          if ( plabl(pft,jpngr)%c%c12>0.0 .and. plabl(pft,jpngr)%n%n14>0.0 .and. dtemp>0.0 ) then
            !------------------------------------------------------------------
            ! Calculate maximum C allocatable based on current labile pool size.
            ! Maximum is the lower of all labile C and the C to be matched by all labile N,
            ! discounted by the yield factor.
            !------------------------------------------------------------------
            if (pleaf(pft,jpngr)%c%c12==0.0) then
              leaftraits(pft) = get_leaftraits_init( pft, solar%meanmppfd(:), mactnv_unitiabs(pft,:) )
            end if
            
            ! ! xxx try: not limited by N availability
            ! nignore = .true.
            ! avl = max( 0.0, plabl(pft,jpngr)%c%c12 - freserve * pleaf(pft,jpngr)%c%c12 )
            ! dcleaf(pft) = frac_leaf(pft) * params_plant%growtheff * avl 
            ! dcroot(pft) = (1.0 - frac_leaf(pft)) * params_plant%growtheff * avl
            ! dnroot(pft) = dcroot(pft) * params_pft_plant(pft)%r_ntoc_root          

            ! print*,'----', doy, '----'
            ! print*,'plabl before ', plabl(pft,jpngr)
            ! print*,'frac_leaf    ', frac_leaf(pft)

            !------------------------------------------------------------------
            ! Binary decision: this is good for quickly depleting labile pool 
            ! imbalance but leads to overshoot 
            !------------------------------------------------------------------
            maxdc_cavl = plabl(pft,jpngr)%c%c12 
            maxdc_navl = plabl(pft,jpngr)%n%n14 * ( frac_leaf(pft) * leaftraits(pft)%r_cton_leaf + ( 1.0 - frac_leaf(pft) ) * params_pft_plant(pft)%r_cton_root ) 
            if (maxdc_cavl<maxdc_navl) then
              ! print*,'C is limiting -> should put more to leaves'
              frac_leaf(pft) = 1.0
              ! frac_leaf(pft) = min( frac_leaf(pft) + 0.1, 1.0 )
            else
              ! print*,'N is limiting -> should put more to roots'
              frac_leaf(pft) = 0.0
              ! frac_leaf(pft) = max( frac_leaf(pft) - 0.1, 0.0 )
            end if

            print*,'doy, bnr-frac_leaf', doy, frac_leaf(pft)

            !------------------------------------------------------------------
            ! Safety brakes: if massive imbalance in labile pool accumulates,
            ! do binary allocation as a safety measure to re-balance labile pool's
            ! C:N ratio.
            ! Otherwise (as long as no massive imbalance arises), find optimum
            ! allocation, defined by newly acquired C and N (NPP-Ra-Cex, Nuptake)
            ! are acquired in the same ratio as is needed for new tissue growth.
            !------------------------------------------------------------------
            ! print*,'cton in plabl ', cton( plabl(pft,jpngr) )
            if ( cton( plabl(pft,jpngr) ) > 10.0 * params_pft_plant(pft)%r_cton_root  ) then
              !------------------------------------------------------------------
              ! massive imbalance: too much C -> put all to roots
              !------------------------------------------------------------------
              if (maxdc_cavl<maxdc_navl) stop 'surprise'
              frac_leaf(pft) = 0.0
              frac_leaf_opt  = 0.0 
              print*,'safety: all to roots'
            
            else if ( ntoc( plabl(pft,jpngr) ) > 10.0 * leaftraits(pft)%r_ntoc_leaf ) then
              !------------------------------------------------------------------
              ! massive imbalance: too much N -> put all to leaves
              !------------------------------------------------------------------
              if (.not.maxdc_cavl<maxdc_navl) stop 'surprise'
              frac_leaf(pft) = 1.0
              frac_leaf_opt  = 1.0 
              print*,'safety: all to leaves'
            
            else
              !------------------------------------------------------------------
              ! No massive imbalance. determine allocation so that C:N of return is equal to C:N new tissue
              ! test: if flexible allocation returns 1 or 0 for frac_leaf, then test if this is consistent with what it's set to above
              !------------------------------------------------------------------
              ! print*,'optimum in between'

              !------------------------------------------------------------------
              ! Store state variables for root search of 'eval_imbalance'
              !------------------------------------------------------------------
              state_eval_imbalance%pleaf    = pleaf(pft,jpngr)
              state_eval_imbalance%proot    = proot(pft,jpngr)
              state_eval_imbalance%plabl    = plabl(pft,jpngr)
              state_eval_imbalance%usepft   = pft
              state_eval_imbalance%usemoy   = moy
              state_eval_imbalance%usedoy   = doy
              state_eval_imbalance%usejpngr = jpngr
              state_eval_imbalance%airtemp  = dtemp
              state_eval_imbalance%soiltemp = dtemp_soil(lu,jpngr)

              !------------------------------------------------------------------
              ! Optimum is between 0.0 (=min_dc) and max_dc. Find root of function 
              ! 'eval_imbalance()' in the interval [0.0, max_dc].
              !------------------------------------------------------------------
              max_dcleaf_n_constraint = min( plabl(pft,jpngr)%n%n14 * leaftraits(pft)%r_cton_leaf, &
                plabl(pft,jpngr)%n%n14 * params_pft_plant(pft)%r_cton_root )
              max_dc = min( params_plant%growtheff * plabl(pft,jpngr)%c%c12, max_dcleaf_n_constraint )
              min_dc = 0.0

              !------------------------------------------------------------------
              ! Test I: Evaluate balance if all is put to roots.
              ! If eval quantity is still positive then put all to roots.
              !------------------------------------------------------------------
              cont = .true.
              if (verbose) print*, 'check allocation: all to roots'
              eval_allroots  = eval_imbalance( 0.0 )
              if (verbose) print*, 'eval_allroots', eval_allroots  
              if (eval_allroots > 0.0) then
                dcleaf_opt = 0.0
                cont = .false.
                if (verbose) print*, '* putting all to roots *'
              end if

              !------------------------------------------------------------------
              ! Test II: Evaluate balance if all is put to leaves.
              ! If eval quantity is still negative then put all to leaves.
              !------------------------------------------------------------------
              if (cont) then
                if (verbose) print*, 'check alloation: all to leaves with dcleaf =', max_dc
                eval_allleaves = eval_imbalance( max_dc )
                if (verbose) print*, 'eval_allleaves', eval_allleaves  
                if (eval_allleaves < 0.0) then
                  dcleaf_opt = max_dc
                  cont = .false.
                  if (verbose) print*, '* putting all to leaves *'
                end if
              end if

              !------------------------------------------------------------------
              ! Optimum is between 0.0 (=min_dc) and max_dc. Find root of function 
              ! 'eval_imbalance()' in the interval [0.0, max_dc].
              !------------------------------------------------------------------
              if (cont) then
                if (verbose) print*, '*** finding root of eval_imbalance ***'
                if (write_logfile_eval_imbalance) open(unit=666,file='eval_imbalance.log',status='unknown')
                if (write_logfile_eval_imbalance) write(666,*) "mydcleaf, eval" !, dc, dn, mydcleaf, mydcroot, mydnleaf, mydnroot"
                max_dc_save = max_dc ! necessary because 'zeroin' alters that variable
                out_zeroin = zeroin( eval_imbalance, abserr, relerr, nmax, min_dc, max_dc )
                max_dc = max_dc_save
                if ( out_zeroin%error /= 0 ) then
                  print*, 'error code ', out_zeroin%error
                  stop 'zeroin for eval_imbalance() failed'
                  dcleaf_opt = 9999.0
                else
                  dcleaf_opt = out_zeroin%root
                end if
                if (write_logfile_eval_imbalance) close(unit=666)
                if (verbose) print*, 'no. of iterations   ', out_zeroin%niter
                if (verbose) print*, 'dcleaf_opt is root ', dcleaf_opt
                test = eval_imbalance( dcleaf_opt, .true. )
                if (verbose) print*, 'eval               =', test
                ! if (abs(test)>1e-4) stop 'failed finding a good root'
                if (verbose) print*, '----------------------------------'
                ! break_after_alloc = .true.
                ! print*,'dcleaf_opt ', dcleaf_opt 
                ! print*,'max_dc     ', max_dc
                ! print*,'optimum frac_leaf ', dcleaf_opt / max_dc
                ! stop 'after finding root'
              end if

              print*,'optimum frac_leaf ', dcleaf_opt / max_dc
              frac_leaf_opt = dcleaf_opt / max_dc
              ! stop 'd o b e n i'

            end if

            !-------------------------------------------------------------------
            ! Set to "optimal" solution
            !-------------------------------------------------------------------
            frac_leaf(pft) = frac_leaf_opt

            !-------------------------------------------------------------------
            ! Determine allocation to leaves and roots, limited by N availability 
            !-------------------------------------------------------------------
            nignore = .false.
            avl = max( 0.0, plabl(pft,jpngr)%c%c12 - freserve * pleaf(pft,jpngr)%c%c12 )
            dcleaf(pft) = min( frac_leaf(pft) * params_plant%growtheff * avl, &
              frac_leaf(pft) * plabl(pft,jpngr)%n%n14 * leaftraits(pft)%r_cton_leaf )
            dcroot(pft) = min( (1.0 - frac_leaf(pft)) * params_plant%growtheff * avl, &
              (1.0 - frac_leaf(pft)) * plabl(pft,jpngr)%n%n14 * params_pft_plant(pft)%r_cton_root )
            dnroot(pft) = dcroot(pft) * params_pft_plant(pft)%r_ntoc_root          

            !-------------------------------------------------------------------
            ! LEAF ALLOCATION
            !-------------------------------------------------------------------
            if (dcleaf(pft)>0.0) then

              call allocate_leaf( &
                pft, dcleaf(pft), &
                pleaf(pft,jpngr)%c%c12, pleaf(pft,jpngr)%n%n14, &
                plabl(pft,jpngr)%c%c12, plabl(pft,jpngr)%n%n14, &
                solar%meanmppfd(:), mactnv_unitiabs(pft,:), &
                lai_ind(pft,jpngr), dnleaf(pft), nignore=nignore &
                )

              !-------------------------------------------------------------------  
              ! Update leaf traits
              !-------------------------------------------------------------------  
              leaftraits(pft) = get_leaftraits( pft, lai_ind(pft,jpngr), solar%meanmppfd(:), mactnv_unitiabs(pft,:) )

              !-------------------------------------------------------------------  
              ! Update fpc_grid and fapar_ind (not lai_ind)
              !-------------------------------------------------------------------  
              canopy(pft) = get_canopy( lai_ind(pft,jpngr) )

            end if

            !-------------------------------------------------------------------
            ! ROOT ALLOCATION
            !-------------------------------------------------------------------
            if (dcroot(pft)>0.0) then

              call allocate_root( &
                pft, dcroot(pft), dnroot(pft), &
                proot(pft,jpngr)%c%c12, proot(pft,jpngr)%n%n14, &
                plabl(pft,jpngr)%c%c12, plabl(pft,jpngr)%n%n14, &
                nignore=nignore &
                )

            end if

            !-------------------------------------------------------------------
            ! GROWTH RESPIRATION, NPP
            !-------------------------------------------------------------------
            ! add growth respiration to autotrophic respiration and substract from NPP
            ! (note that NPP is added to plabl in and growth resp. is implicitly removed
            ! from plabl above)
            drgrow(pft)   = ( 1.0 - params_plant%growtheff ) * ( dcleaf(pft) + dcroot(pft) ) / params_plant%growtheff

          end if

        else
          !------------------------------------------------------------------
          ! Fixed allocation 
          !------------------------------------------------------------------
          if ( plabl(pft,jpngr)%c%c12>0.0 .and. dtemp>0.0 ) then

            !------------------------------------------------------------------
            ! Calculate maximum C allocatable based on current labile pool size.
            ! Maximum is the lower of all labile C and the C to be matched by all labile N,
            ! discounted by the yield factor.
            !------------------------------------------------------------------
            if (pleaf(pft,jpngr)%c%c12==0.0) then
              leaftraits(pft) = get_leaftraits_init( pft, solar%meanmppfd(:), mactnv_unitiabs(pft,:) )
            end if

            ! Determine allocation to roots and leaves, fraction given by 'frac_leaf'
            nignore = .true.
            avl = max( 0.0, plabl(pft,jpngr)%c%c12 - freserve * pleaf(pft,jpngr)%c%c12 )
            dcleaf(pft) = frac_leaf(pft) * params_plant%growtheff * avl
            dcroot(pft) = (1.0 - frac_leaf(pft)) * params_plant%growtheff * avl
            dnroot(pft) = dcroot(pft) * params_pft_plant(pft)%r_ntoc_root          

            !-------------------------------------------------------------------
            ! LEAF ALLOCATION
            !-------------------------------------------------------------------
            if (dcleaf(pft)>0.0) then

              call allocate_leaf( &
                pft, dcleaf(pft), &
                pleaf(pft,jpngr)%c%c12, pleaf(pft,jpngr)%n%n14, &
                plabl(pft,jpngr)%c%c12, plabl(pft,jpngr)%n%n14, &
                solar%meanmppfd(:), mactnv_unitiabs(pft,:), &
                lai_ind(pft,jpngr), dnleaf(pft), nignore=nignore &
                )

              !-------------------------------------------------------------------  
              ! Update leaf traits
              !-------------------------------------------------------------------  
              leaftraits(pft) = get_leaftraits( pft, lai_ind(pft,jpngr), solar%meanmppfd(:), mactnv_unitiabs(pft,:) )

              !-------------------------------------------------------------------  
              ! Update fpc_grid and fapar_ind (not lai_ind)
              !-------------------------------------------------------------------  
              canopy(pft) = get_canopy( lai_ind(pft,jpngr) )

            end if

            !-------------------------------------------------------------------
            ! ROOT ALLOCATION
            !-------------------------------------------------------------------
            if (dcroot(pft)>0.0) then

              call allocate_root( &
                pft, dcroot(pft), dnroot(pft), &
                proot(pft,jpngr)%c%c12, proot(pft,jpngr)%n%n14, &
                plabl(pft,jpngr)%c%c12, plabl(pft,jpngr)%n%n14, &
                nignore=nignore &
                )

            end if

            !-------------------------------------------------------------------
            ! GROWTH RESPIRATION, NPP
            !-------------------------------------------------------------------
            ! add growth respiration to autotrophic respiration and substract from NPP
            ! (note that NPP is added to plabl in and growth resp. is implicitly removed
            ! from plabl above)
            drgrow(pft)   = ( 1.0 - params_plant%growtheff ) * ( dcleaf(pft) + dcroot(pft) ) / params_plant%growtheff

          end if

        end if

      else

        stop 'allocation_daily not implemented for trees'

      end if

    end do

    ! print*, '--- END allocation_daily:'

  end subroutine allocation_daily


  subroutine allocate_leaf( pft, mydcleaf, cleaf, nleaf, clabl, nlabl, meanmppfd, nv, lai, mydnleaf, nignore )
    !///////////////////////////////////////////////////////////////////
    ! LEAF ALLOCATION
    ! Sequence of steps:
    ! - increment foliage C pool
    ! - update LAI
    ! - calculate canopy-level foliage N as a function of LAI 
    ! - reduce labile pool by C and N increments
    !-------------------------------------------------------------------
    use md_classdefs
    use md_plant, only: params_plant, get_leaf_n_canopy, get_lai, dnup
    use md_nuptake, only: dnup_fix
    use md_params_core, only: eps

    ! arguments
    integer, intent(in)                 :: pft
    real, intent(in)                    :: mydcleaf
    real, intent(inout)                 :: cleaf, nleaf
    real, intent(inout)                 :: clabl, nlabl
    real, dimension(nmonth), intent(in) :: meanmppfd
    real, dimension(nmonth), intent(in) :: nv
    real, intent(out)                   :: lai
    real, intent(out)                   :: mydnleaf
    logical, intent(in)                 :: nignore

    ! local variables
    real :: nleaf0
    real :: dclabl, dnlabl

    ! Calculate LAI as a function of leaf C
    cleaf  = cleaf + mydcleaf
    lai = get_lai( pft, cleaf, meanmppfd(:), nv(:) )

    ! calculate canopy-level leaf N as a function of LAI
    nleaf0   = nleaf      
    nleaf    = get_leaf_n_canopy( pft, lai, meanmppfd(:), nv(:) )
    mydnleaf = nleaf - nleaf0

    ! depletion of labile C pool is enhanced by growth respiration
    dclabl = 1.0 / params_plant%growtheff * mydcleaf

    ! substract from labile pools
    clabl  = clabl - dclabl
    nlabl  = nlabl - mydnleaf

    if ( clabl < -1.0*eps ) then
      stop 'ALLOCATE_LEAF: trying to remove too much from labile pool: leaf C'
    else if ( clabl < 0.0 ) then
      ! numerical imprecision
      ! print*,'numerical imprecision?'
      ! print*,'clabl ', clabl
      ! stop 'allocate leaf'
      clabl = 0.0
    end if

    if (nignore) then
      ! If labile N gets negative, account gap as N fixation
      if ( nlabl < 0.0 ) then
        ! print*,'not enough N'
        dnup(pft)%n14 = dnup(pft)%n14 - nlabl
        dnup_fix(pft) = dnup_fix(pft) - nlabl
        nlabl = 0.0
      end if
    else
      if ( nlabl < -1.0*eps ) then
        stop 'ALLOCATE_LEAF: trying to remove too much from labile pool: leaf N'
      else if ( nlabl < 0.0 ) then
        ! numerical imprecision
        ! print*,'numerical imprecision?'
        ! print*,'nlabl ', nlabl
        ! stop 'allocate leaf'
        nlabl = 0.0
      end if
    end if  

  end subroutine allocate_leaf


  subroutine allocate_root( pft, mydcroot, mydnroot, croot, nroot, clabl, nlabl, nignore )
    !-------------------------------------------------------------------
    ! ROOT ALLOCATION
    !-------------------------------------------------------------------
    use md_classdefs
    use md_plant, only: params_plant, params_pft_plant, dnup
    use md_nuptake, only: dnup_fix
    use md_params_core, only: eps

    ! arguments
    integer, intent(in) :: pft
    real, intent(in)    :: mydcroot
    real, intent(in)    :: mydnroot
    real, intent(inout) :: croot, nroot
    real, intent(inout) :: clabl, nlabl
    logical, intent(in) :: nignore

    ! local variables
    real :: dclabl
    real :: dnlabl

    ! update root pools
    croot = croot + mydcroot
    nroot = nroot + mydnroot

    ! depletion of labile C pool is enhanced by growth respiration
    dclabl = 1.0 / params_plant%growtheff * mydcroot

    ! substract from labile pools
    clabl  = clabl - dclabl
    nlabl  = nlabl - mydnroot

    if ( clabl < -1.0*eps ) then
      stop 'ALLOCATE_ROOT: trying to remove too much from labile pool: root C'
    else if ( clabl < 0.0 ) then
      ! numerical imprecision
      ! print*,'numerical imprecision?'
      ! stop 'allocate root'
      clabl = 0.0
    end if

    if (nignore) then
      ! If labile N gets negative, account gap as N fixation
      if ( nlabl < 0.0 ) then
        ! print*,'not enough N'
        dnup(pft)%n14 = dnup(pft)%n14 - nlabl
        dnup_fix(pft) = dnup_fix(pft) - nlabl
        nlabl = 0.0
      end if
    else
      if ( nlabl < -1.0*eps ) then
        stop 'ALLOCATE_ROOT: trying to remove too much from labile pool: root N'
      else if ( nlabl < 0.0 ) then
        ! numerical imprecision
        ! print*,'numerical imprecision?'
        ! stop 'allocate leaf'
        nlabl = 0.0
      end if
    end if

  end subroutine allocate_root


  function eval_imbalance( mydcleaf, verbose ) result ( eval )
    !/////////////////////////////////////////////////////////
    ! Evaluates C:N ratio of new assimilation after allocation 
    ! versus whole-plant C:N ratio after allocation. Optimal 
    ! allocation is where the two are equal. 
    ! 
    ! Returns positive value (eval) if C:N ratio of new acquisition
    ! is greater than C:N ratio of new growth => put more to roots
    !
    ! Returns negative value (eval) if C:N ratio of new acquisition
    ! is smaller than C:N ratio of new growth => put more to leaves
    !---------------------------------------------------------
    use md_classdefs, only: orgpool, nitrogen
    use md_plant, only: params_pft_plant, params_plant, get_fapar, &
      canopy_type, get_canopy
    use md_gpp, only: calc_dgpp, calc_drd, mactnv_unitiabs, mlue, mrd_unitiabs
    use md_nuptake, only: calc_dnup, outtype_calc_dnup
    use md_npp, only: calc_resp_maint, calc_cexu, deactivate_root
    use md_findroot_fzeroin
    use md_waterbal, only: solar, evap
    use md_ntransform, only: pninorg

    ! arguments
    real, intent(in)              :: mydcleaf
    logical, intent(in), optional :: verbose

    ! function return variable
    real :: eval

    ! local variables used for shorter writing
    real    :: cleaf, nleaf, croot, nroot, clabl, nlabl, airtemp, soiltemp
    integer :: usepft, usemoy, usedoy, usejpngr, lu

    ! local temporary variables for budget calculation
    real :: mydcroot, mydnleaf, mydnroot, mylai, gpp, npp, rd, mresp_root, &
      cexu, dc, dn, kcleaf, knleaf, kcroot, knroot

    real :: nleaf0
    real :: lai0, lai1

    type( orgpool )           :: proot_tmp
    type( outtype_zeroin )    :: out_zeroin
    type( outtype_calc_dnup ) :: out_calc_dnup
    type( canopy_type )       :: mycanopy

    ! print*,'--- in eval_imbalance with mydcleaf=', mydcleaf

    ! Copy to local variables for shorter writing
    cleaf    = state_eval_imbalance%pleaf%c%c12
    nleaf    = state_eval_imbalance%pleaf%n%n14
    croot    = state_eval_imbalance%proot%c%c12
    nroot    = state_eval_imbalance%proot%n%n14
    clabl    = state_eval_imbalance%plabl%c%c12
    nlabl    = state_eval_imbalance%plabl%n%n14
    usepft   = state_eval_imbalance%usepft
    usemoy   = state_eval_imbalance%usemoy
    usedoy   = state_eval_imbalance%usedoy
    usejpngr = state_eval_imbalance%usejpngr
    airtemp  = state_eval_imbalance%airtemp
    soiltemp = state_eval_imbalance%soiltemp

    !-------------------------------------------------------------------
    ! LEAF ALLOCATION
    !-------------------------------------------------------------------
    call allocate_leaf( &
      usepft, mydcleaf, cleaf, nleaf, clabl, nlabl, &
      solar%meanmppfd(:), mactnv_unitiabs(usepft,:), mylai, mydnleaf, &
      nignore=.false. &
      )

    ! !-------------------------------------------------------------------  
    ! ! Update leaf traits
    ! !-------------------------------------------------------------------  
    ! leaftraits(pft) = get_leaftraits( pft, lai_ind(pft,jpngr), solar%meanmppfd(:), mactnv_unitiabs(pft,:) )

    !-------------------------------------------------------------------  
    ! Update fpc_grid and fapar_ind (not lai_ind)
    !-------------------------------------------------------------------  
    mycanopy = get_canopy( mylai )

    !-------------------------------------------------------------------
    ! ROOT ALLOCATION
    ! use remainder for allocation to roots
    !-------------------------------------------------------------------
    mydcroot = min( params_plant%growtheff * clabl, params_pft_plant(usepft)%r_cton_root * nlabl )
    mydnroot = mydcroot * params_pft_plant(usepft)%r_ntoc_root

    call allocate_root( &
      usepft, mydcroot, mydnroot, croot, nroot, clabl, nlabl, &
      nignore=.false. &
      )

    !-------------------------------------------------------------------
    ! PROJECT NEXT DAY'S C AND N BALANCE:
    ! decay, GPP, respiration, N uptake
    !-------------------------------------------------------------------
    ! Calculate next day's C and N return after assumed allocation (tissue turnover happens before!)
    lu = params_pft_plant(usepft)%lu_category

    gpp           = calc_dgpp( mycanopy%fapar_ind, solar%dppfd(usedoy), mlue(usepft,usemoy), airtemp, evap(lu)%cpa )
    rd            = calc_drd(  mycanopy%fapar_ind, solar%meanmppfd(usemoy), mrd_unitiabs(usepft,usemoy), airtemp, evap(lu)%cpa  )
    mresp_root    = calc_resp_maint( croot, params_plant%r_root, airtemp )
    npp           = gpp - rd - mresp_root
    cexu          = calc_cexu( croot, airtemp ) 
    if ((clabl + npp - cexu)<0.0 .or. (npp - cexu)<0.0) then
      dc          = 0.0
    else
      dc          = npp - cexu
    end if
    out_calc_dnup = calc_dnup( cexu, pninorg(lu,usejpngr)%n14, params_pft_plant(usepft)%nfixer, soiltemp )
    dn            = out_calc_dnup%fix + out_calc_dnup%act

    ! print*,'fapar ', mycanopy%fapar_ind
    ! print*,'cleaf ', cleaf
    ! print*,'lai   ', mylai
    ! print*,'cpa   ', evap(lu)%cpa
    ! print*,'gpp   ', gpp
    ! print*,'rd    ', rd 
    ! print*,'dppfd ', solar%dppfd(usedoy)
    ! print*,'mlue  ', mlue(usepft,usemoy)
    ! print*,'temp  ', airtemp
    ! print*,'pft   ', usepft
    ! print*,'moy   ', usemoy
    ! print*,'doy   ', usedoy


    ! if ( abs( (mydcroot+mydcleaf) / (mydnroot+mydnleaf) - params_plant%growtheff * dc / dn ) > 0.0005 ) print*, 'unsuccessful allocation'

    !-------------------------------------------------------------------
    ! EVALUATION QUANTITY - IS MINIMISED BY OPTIMISATION
    ! Evaluation quantity is the difference between the 
    ! C:N ratio of new assimilates and the C:N ratio 
    ! of the whole plant after allocation.
    !-------------------------------------------------------------------
    ! if ((dn + nlabl)==0.0) then
    !   eval = 999.0
    ! else if (( mydnleaf + mydnroot )==0.0) then
    !   eval = 999.0
    ! else if (dc <= 0.0) then
    !   eval = - 999.0
    ! else
    !   ! ! IMPLEMENTATION A: C:N OF ACQUISITION (incl. labile left) IS EQUAL TO C:N OF CURRENT WHOLE-PLANT
    !   ! !     |---------------------------------------------------|  |------------------------------------|
    !   ! eval = params_plant%growtheff * (dc + clabl) / (dn + nlabl) - ( cleaf + croot ) / ( nleaf + nroot )
    !   ! !     |---------------------------------------------------|  |------------------------------------|
    !   ! !     |lab. pool C:N ratio after acq. nxt. day            |  | current whole-plant C:N ratio      |
    !   ! !     |---------------------------------------------------|  |------------------------------------|

    !   ! IMPLEMENTATION B: C:N OF ACQUISITION (incl. labile left) IS EQUAL TO C:N OF INVESTMENT
    !   !     |---------------------------------------------------|  |-------------------------------------------------|
    !   eval = params_plant%growtheff * (dc + clabl) / (dn + nlabl) - ( mydcleaf + mydcroot ) / ( mydnleaf + mydnroot )
    !   !     |---------------------------------------------------|  |-------------------------------------------------|
    !   !     |lab. pool C:N ratio after acq. nxt. day            |  | C:N ratio of new growth                         |
    !   !     |---------------------------------------------------|  |-------------------------------------------------|
    ! end if

    ! IMPLEMENTATION C: C:N OF ACQUISITION IS EQUAL TO C:N OF INVESTMENT
    if (dn==0.0) then
      eval = 999.0
    else if (( mydnleaf + mydnroot )==0.0) then
      eval = -999.0
    else
      !     |---------------------------------------------------|  |-------------------------------------------------|
      eval = params_plant%growtheff * (dc) / (dn)     - ( mydcleaf + mydcroot ) / ( mydnleaf + mydnroot )
      !     |---------------------------------------|   |-------------------------------------------------|
      !     |lab. pool C:N ratio after acq. nxt. day|   | C:N ratio of new growth                         |
      !     |---------------------------------------|   |-------------------------------------------------|

      ! ! IMPLEMENTATION A: C:N OF ACQUISITION (incl. labile left) IS EQUAL TO C:N OF CURRENT WHOLE-PLANT
      ! !     |---------------------------------------------------|  |------------------------------------|
      ! eval = params_plant%growtheff * (dc) / (dn) - ( cleaf + croot ) / ( nleaf + nroot )
      ! !     |---------------------------------------------------|  |------------------------------------|
      ! !     |lab. pool C:N ratio after acq. nxt. day            |  | current whole-plant C:N ratio      |
      ! !     |---------------------------------------------------|  |------------------------------------|
    end if

    ! print*,'dcleaf, eval', mydcleaf, eval
    ! print*,'returned (C,N, rC:N)', dc, dn, dc / dn
    ! print*,'acq. y*dc/dn ', params_plant%growtheff * dc / dn
    ! print*,'req.   dc/dn ', ( mydcleaf + mydcroot ) / ( mydnleaf + mydnroot )

    if (write_logfile_eval_imbalance) write(666,*) mydcleaf, ",", eval  !, ",", dc, ",", dn, ",", mydcleaf, ",", mydcroot, ",", mydnleaf, ",", mydnroot

  end function eval_imbalance


  subroutine initio_allocation()
    !////////////////////////////////////////////////////////////////
    ! OPEN ASCII OUTPUT FILES FOR OUTPUT
    !----------------------------------------------------------------
    use md_interface

    ! local variables
    character(len=256) :: prefix
    character(len=256) :: filnam

    prefix = "./output/"//trim(interface%params_siml%runname)

    !////////////////////////////////////////////////////////////////
    ! ANNUAL OUTPUT: OPEN ASCII OUTPUT FILES
    !----------------------------------------------------------------

    ! C ALLOCATED TO LEAF GROWTH 
    filnam=trim(prefix)//'.a.calclm.out'
    open(350,file=filnam,err=999,status='unknown')

    ! N ALLOCATED TO LEAF GROWTH 
    filnam=trim(prefix)//'.a.nalclm.out'
    open(351,file=filnam,err=999,status='unknown')

    ! C ALLOCATED TO ROOT GROWTH 
    filnam=trim(prefix)//'.a.calcrm.out'
    open(352,file=filnam,err=999,status='unknown')

    ! N ALLOCATED TO ROOT GROWTH 
    filnam=trim(prefix)//'.a.nalcrm.out'
    open(353,file=filnam,err=999,status='unknown')

    return

    999  stop 'INITIO_ALLOCATION: error opening output files'

  end subroutine initio_allocation


  subroutine initoutput_allocation()
    !////////////////////////////////////////////////////////////////
    !  Initialises nuptake-specific output variables
    !----------------------------------------------------------------
    ! xxx remove their day-dimension
    outaCalclm(:,:) = 0.0
    outaNalclm(:,:) = 0.0
    outaCalcrm(:,:) = 0.0
    outaNalcrm(:,:) = 0.0

    ! print*, 'initialising outaCalloc',outaCalloc

  end subroutine initoutput_allocation


  subroutine getout_daily_allocation( jpngr, moy, doy )
    !////////////////////////////////////////////////////////////////
    !  SR called daily to sum up output variables.
    !----------------------------------------------------------------
    ! arguments
    integer, intent(in) :: jpngr
    integer, intent(in) :: moy
    integer, intent(in) :: doy

    outaCalclm(:,jpngr) = outaCalclm(:,jpngr) + dcleaf(:) 
    outaNalclm(:,jpngr) = outaNalclm(:,jpngr) + dnleaf(:)
    outaCalcrm(:,jpngr) = outaCalcrm(:,jpngr) + dcroot(:) 
    outaNalcrm(:,jpngr) = outaNalcrm(:,jpngr) + dnroot(:)

    ! print*, 'collecting outaCalloc',outaCalloc

  end subroutine getout_daily_allocation


  subroutine writeout_ascii_allocation( year )
    !/////////////////////////////////////////////////////////////////////////
    ! WRITE WATERBALANCE-SPECIFIC VARIABLES TO OUTPUT
    !-------------------------------------------------------------------------
    use md_interface

    ! arguments
    integer, intent(in) :: year       ! simulation year

    ! local variables
    real    :: itime
    integer :: jpngr

    ! xxx implement this: sum over gridcells? single output per gridcell?
    if (maxgrid>1) stop 'writeout_ascii: think of something ...'
    jpngr = 1

    !-------------------------------------------------------------------------
    ! ANNUAL OUTPUT
    ! Write annual value, summed over all PFTs / LUs
    ! xxx implement taking sum over PFTs (and gridcells) in this land use category
    !-------------------------------------------------------------------------
    itime = real(year) + real(interface%params_siml%firstyeartrend) - real(interface%params_siml%spinupyears)

    ! print*, 'writing time, outaCalloc',itime, sum(outaCalloc(:,jpngr))

    write(350,999) itime, sum(outaCalclm(:,jpngr))
    write(351,999) itime, sum(outaNalclm(:,jpngr))
    write(352,999) itime, sum(outaCalcrm(:,jpngr))
    write(353,999) itime, sum(outaNalcrm(:,jpngr))

    return
    
    999 format (F20.8,F20.8)

  end subroutine writeout_ascii_allocation

end module md_allocation
