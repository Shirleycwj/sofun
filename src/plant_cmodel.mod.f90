module _plant
  !////////////////////////////////////////////////////////////////
  !----------------------------------------------------------------
  use _classdefs
  use _params_core, only: nlu, npft, maxgrid, ndayyear, lunat

  implicit none

  private
  public pleaf, proot, psapw, plabl, pexud, plitt_af, plitt_as, plitt_bg, &
    dnpp, drauto, drleaf, drroot, drsapw, dcex, r_cton_leaf, r_ntoc_leaf, &
    lma, sla, narea, narea_metabolic, narea_structural, nmass, lai_ind,   &
    fapar_ind, ispresent, fpc_grid, nind, height, crownarea, dnup,        &
    params_pft_plant, params_plant, initglobal_plant, initpft,            &
    initdaily_plant, outdnpp, outdnup, outdCleaf, outdCroot, outdClabl,   &
    outdNlabl, outdClitt, outdNlitt, outdCsoil, outdNsoil, outdlai,       &
    dnarea_mb, dnarea_cw, dlma, dcton_lm, outanpp, outanup, outaCveg,     &
    outaCveg2lit, outaNveg2lit, outaNinorg, outanarea_mb, outanarea_cw,   &
    outalai, outalma, outacton_lm, update_fpc_grid, get_fapar,            &
    initoutput_plant, initio_plant, getout_daily_plant,                   &
    getout_annual_plant, writeout_ascii_plant, getpar_modl_plant,         &
    update_foliage_vars

  !----------------------------------------------------------------
  ! Public, module-specific state variables
  !----------------------------------------------------------------
  ! pools
  type(orgpool), dimension(npft,maxgrid) :: pleaf            ! leaf biomass [gC/ind.] (=lm_ind)
  type(orgpool), dimension(npft,maxgrid) :: proot            ! root biomass [gC/ind.] (=rm_ind)
  type(orgpool), dimension(npft,maxgrid) :: psapw            ! sapwood biomass [gC/ind.] (=sm_ind)
  type(orgpool), dimension(npft,maxgrid) :: pwood            ! heartwood (non-living) biomass [gC/ind.] (=hm_ind)
  type(orgpool), dimension(npft,maxgrid) :: plabl            ! labile pool, temporary storage of N and C [gC/ind.] (=bm_inc but contains also N) 
  
  type(carbon),  dimension(npft,maxgrid) :: pexud            ! exudates pool (very short turnover) [gC/m2]
  
  type(orgpool), dimension(npft,maxgrid) :: plitt_af         ! above-ground litter, fast turnover [gC/m2]
  type(orgpool), dimension(npft,maxgrid) :: plitt_as         ! above-ground litter, slow turnover [gC/m2]
  type(orgpool), dimension(npft,maxgrid) :: plitt_bg         ! below-ground litter [gC/m2]

  ! fluxes
  type(carbon), dimension(npft)          :: dnpp             ! net primary production [gC/m2/d]
  real, dimension(npft)                  :: drauto           ! autotrophic respiration (growth+maintenance resp. of all compartments), no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)                  :: drleaf           ! leaf maintenance respiration, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)                  :: drroot           ! root maintenance respiration, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)                  :: drsapw           ! sapwood maintenance respiration, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)                  :: drgrow   ! growth respiration, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]
  real, dimension(npft)                  :: dcex             ! labile C exudation for N uptake, no explicit isotopic signature as it is identical to the signature of GPP [gC/m2/d]

  type(nitrogen), dimension(npft)        :: dnup             ! daily N uptake [gN/m2/d]

  ! plant-specific state variables
  real, dimension(npft,maxgrid)          :: r_cton_leaf      ! leaf C:N ratio [gC/gN] 
  real, dimension(npft,maxgrid)          :: r_ntoc_leaf      ! leaf N:C ratio [gN/gC]
  real, dimension(npft,maxgrid)          :: lma, sla         ! leaf mass per area [gC/m2], specific leaf area [m2/gC]. C, NOT DRY-MASS!
  real, dimension(npft)                  :: narea            ! g N m-2-leaf
  real, dimension(npft)                  :: narea_metabolic  ! g N m-2-leaf
  real, dimension(npft)                  :: narea_structural ! g N m-2-leaf
  real, dimension(npft)                  :: nmass            ! g N / g-dry mass

  real, dimension(npft,maxgrid)          :: lai_ind
  real, dimension(npft,maxgrid)          :: fapar_ind

  logical, dimension(npft,maxgrid)       :: ispresent        ! boolean whether PFT is present
  real, dimension(npft,maxgrid)          :: fpc_grid         ! area fraction within gridcell occupied by PFT
  real, dimension(npft,maxgrid)          :: nind             ! number of individuals [1/m2]

  real, dimension(npft,maxgrid)          :: height           ! tree height (m)
  real, dimension(npft,maxgrid)          :: crownarea        ! individual's tree crown area

  !-----------------------------------------------------------------------
  ! Uncertain (unknown) parameters. Runtime read-in
  !-----------------------------------------------------------------------
  type params_plant_type
    real :: r_root  ! Fine root-specific respiration rate (gC gC-1 d-1)
    real :: r_sapw  ! Sapwood-specific respiration rate (gC gC-1 d-1)
    real :: exurate  ! Fine root-specific C export rate (gC gC-1 d-1)
    real :: kbeer             ! canopy light extinction coefficient
    real :: f_nretain         ! fraction of N retained at leaf abscission 
    real :: fpc_tree_max      ! maximum fractional plant coverage of trees
    real :: growtheff         ! growth respiration coefficient = yield factor [unitless]
  end type params_plant_type

  type( params_plant_type ) :: params_plant


  type params_pft_plant_type
    character(len=4) :: pftname    ! standard PFT name with 4 characters length
    integer :: lu_category         ! land use category associated with PFT
    logical, dimension(nlu) :: islu! islu(ipft,ilu) is true if ipft belongs to ilu
    logical :: grass               ! boolean for growth form 'grass'
    logical :: tree                ! boolean for growth form 'tree'
    logical :: nfixer              ! whether plant is capable of symbiotically fixing N
    logical :: c3grass             ! whether plant follows C3 photosynthesis
    logical :: c4grass             ! whether plant follows C4 photosynthesis
    real    :: k_decay_leaf        ! leaf decay constant [year-1]
    real    :: k_decay_sapw        ! sapwood decay constant [year-1]
    real    :: k_decay_root        ! root decay constant [year-1]
    real    :: r_cton_root         ! C:N ratio in roots
    real    :: r_ntoc_root         ! N:C ratio in roots (inverse of 'r_cton_root')
  end type params_pft_plant_type

  type( params_pft_plant_type ), dimension(npft) :: params_pft_plant


  !----------------------------------------------------------------
  ! Module-specific output variables
  !----------------------------------------------------------------
  ! daily
  real, allocatable, dimension(:,:,:) :: outdnpp
  real, allocatable, dimension(:,:,:) :: outdnup
  real, allocatable, dimension(:,:,:) :: outdCleaf
  real, allocatable, dimension(:,:,:) :: outdCroot
  real, allocatable, dimension(:,:,:) :: outdClabl
  real, allocatable, dimension(:,:,:) :: outdNlabl
  real, allocatable, dimension(:,:,:) :: outdClitt
  real, allocatable, dimension(:,:,:) :: outdNlitt
  real, allocatable, dimension(:,:,:) :: outdCsoil
  real, allocatable, dimension(:,:,:) :: outdNsoil
  real, allocatable, dimension(:,:,:) :: outdlai

  ! These are stored as dayly variables for annual output
  ! at day of year when LAI is at its maximum.
  real, dimension(npft,ndayyear) :: dnarea_mb
  real, dimension(npft,ndayyear) :: dnarea_cw
  real, dimension(npft,ndayyear) :: dlma
  real, dimension(npft,ndayyear) :: dcton_lm

  ! annual
  real, dimension(npft,maxgrid) :: outanpp
  real, dimension(npft,maxgrid) :: outanup
  real, dimension(npft,maxgrid) :: outaCveg
  real, dimension(npft,maxgrid) :: outaCveg2lit
  real, dimension(npft,maxgrid) :: outaNveg2lit
  real, dimension(nlu, maxgrid) :: outaNinorg
  real, dimension(npft,maxgrid) :: outanarea_mb
  real, dimension(npft,maxgrid) :: outanarea_cw
  real, dimension(npft,maxgrid) :: outalai
  real, dimension(npft,maxgrid) :: outalma
  real, dimension(npft,maxgrid) :: outacton_lm

  !----------------------------------------------------------------
  ! MODULE-SPECIFIC, PRIVATE VARIABLES
  !----------------------------------------------------------------
  ! xxx may move many of the public ones here


contains

  subroutine getpar_modl_plant()
    !////////////////////////////////////////////////////////////////
    !  Subroutine reads model parameters from input file.
    !  It was necessary to separate this SR from module _plant
    !  because this SR uses module _waterbal, which also uses
    !  _plant.
    ! Copyright (C) 2015, see LICENSE, Benjamin David Stocker
    ! contact: b.stocker@imperial.ac.uk
    !----------------------------------------------------------------    
    use _sofunutils, only: getparreal
    use _params_site, only: lTeBS, lGrC3, lGrC4

    ! local variables
    integer :: pft
    integer :: npft_site

    !----------------------------------------------------------------
    ! NON-PFT DEPENDENT PARAMETERS
    !----------------------------------------------------------------
    ! canopy light extinction coefficient for Beer's Law
    params_plant%kbeer = getparreal( 'params/params_plant.dat', 'kbeer' )

    ! fraction of N retained at leaf abscission 
    params_plant%f_nretain = getparreal( 'params/params_plant.dat', 'f_nretain' )
    
    ! maximum fractional plant coverage of trees (sum of all tree PFTs)
    params_plant%fpc_tree_max = getparreal( 'params/params_plant.dat', 'fpc_tree_max' )

    ! growth efficiency = yield factor, central value: 0.6, range: 0.5-0.7; Zhang et al. (2009), see Li et al., 2014
    params_plant%growtheff = getparreal( 'params/params_plant.dat', 'growtheff' )

    ! Fine-root mass specific respiration rate (gC gC-1 year-1)
    ! Central value: 0.913 year-1 (Yan and Zhao (2007); see Li et al., 2014)
    params_plant%r_root = getparreal( 'params/params_plant.dat', 'r_root' ) / ndayyear  ! conversion to rate per day

    ! Fine-root specific respiration rate (gC gC-1 year-1)
    ! Central value: 0.044 year-1 (Yan and Zhao (2007); see Li et al., 2014)
    ! (= 0.044 nmol mol-1 s-1; range: 0.5–10, 20 nmol mol-1 s-1 (Landsberg and Sands (2010))
    params_plant%r_sapw = getparreal( 'params/params_plant.dat', 'r_sapw' ) / ndayyear  ! conversion to rate per day

    ! C export rate per unit root mass
    params_plant%exurate = getparreal( 'params/params_plant.dat', 'exurate' )


    !----------------------------------------------------------------
    ! PFT DEPENDENT PARAMETERS
    ! read parameter input file and store values in single array
    ! important: Keep this order of reading PFT parameters fixed.
    !----------------------------------------------------------------
    pft = 0
    if ( lTeBS ) then
      pft = pft + 1
      params_pft_plant(pft) = getpftparams( 'TeBS' )
    end if 
    if ( lGrC3 ) then
      pft = pft + 1
      params_pft_plant(pft) = getpftparams( 'GrC3' )
    end if
    if ( lGrC4 ) then
      pft = pft + 1
      params_pft_plant(pft) = getpftparams( 'GrC4' )
    end if
    npft_site = pft

  end subroutine getpar_modl_plant


  function getpftparams( pftname ) result( out_getpftparams )
    !----------------------------------------------------------------
    ! Read PFT parameters from respective file, given the PFT name
    !----------------------------------------------------------------
    use _sofunutils, only: getparreal

    ! arguments
    character(len=*) :: pftname

    ! local variables
    real :: lu_category_prov    ! land use category associated with PFT (provisional)
    real :: code_growthform
    real :: code_nfixer

    ! function return variable
    type( params_pft_plant_type ) :: out_getpftparams

    ! standard PFT name
    out_getpftparams%pftname = pftname

    ! PFT names
    ! GrC3 : C3 grass                          
    ! GrC4 : C4 grass     
    if (trim(pftname)=='GrC3') then
      out_getpftparams%grass = .true.
      out_getpftparams%tree  = .false.
      out_getpftparams%c3grass = .true.
      out_getpftparams%c4grass = .false.
      out_getpftparams%nfixer = .false.
    else if (trim(pftname)=='GrC4') then
      out_getpftparams%grass = .true.
      out_getpftparams%tree  = .false.
      out_getpftparams%c3grass = .false.
      out_getpftparams%c4grass = .true.
      out_getpftparams%nfixer = .false.
    end if      

    ! land use category associated with PFT (provisional)
    lu_category_prov = getparreal( trim('params/params_plant_'//trim(pftname)//'.dat'), 'lu_category_prov' )
    if (lu_category_prov==1.0) then
      out_getpftparams%lu_category = lunat
      out_getpftparams%islu(lunat) = .true.
    else
      out_getpftparams%islu(lunat) = .false.
    end if

    ! leaf decay constant, read in as [years-1], central value: 0.0 yr-1 for deciduous plants
    out_getpftparams%k_decay_leaf = getparreal( trim('params/params_plant_'//pftname//'.dat'), 'k_decay_leaf' ) / ndayyear 

    ! sapwood decay constant [days], read in as [years-1], central value: xxx
    out_getpftparams%k_decay_sapw = getparreal( trim('params/params_plant_'//pftname//'.dat'), 'k_decay_sapw' ) / ndayyear 

    ! root decay constant [days], read in as [years-1], central value: 1.04 (Shan et al., 1993; see Li et al., 2014)
    out_getpftparams%k_decay_root = getparreal( trim('params/params_plant_'//pftname//'.dat'), 'k_decay_root' ) / ndayyear 

  end function getpftparams


  subroutine initglobal_plant()
    !////////////////////////////////////////////////////////////////
    !  Initialisation of all _pools on all gridcells at the beginning
    !  of the simulation.
    !  June 2014
    !  b.stocker@imperial.ac.uk
    !----------------------------------------------------------------
    use _params_core, only: npft, maxgrid

    ! local variables
    integer :: pft
    integer :: jpngr

    !-----------------------------------------------------------------------------
    ! derive which PFTs are present from fpc_grid (which is prescribed)
    !-----------------------------------------------------------------------------
    do jpngr=1,maxgrid

      do pft=1,npft

        if (fpc_grid(pft,jpngr)>0.0) then
          ispresent(pft,jpngr) = .true.
        else
          ispresent(pft,jpngr) = .false.
        end if

        call initpft( pft, jpngr )

      end do

    end do
 
    ! initialise all _pools with zero
    pexud(:,:)    = carbon(0.0)                           ! exudates in soil, carbon pool [gC/m2]

    plitt_af(:,:) = orgpool(carbon(0.0),nitrogen(0.0))    ! above-ground fine   litter, organic pool [gC/m2 and gN/m2]
    plitt_as(:,:) = orgpool(carbon(0.0),nitrogen(0.0))    ! above-ground coarse litter, organic pool [gC/m2 and gN/m2]
    plitt_bg(:,:) = orgpool(carbon(0.0),nitrogen(0.0))    ! below-ground fine   litter, organic pool [gC/m2 and gN/m2]

    ! initialise other properties
    lai_ind(:,:)   = 0.0
    fapar_ind(:,:) = 0.0
    height(:,:)    = 0.0

    do pft=1,npft
      if (params_pft_plant(pft)%tree) then
        nind(pft,:)      = 0.0
        crownarea(pft,:) = 0.0
      else
        nind(pft,:)      = 1.0
        crownarea(pft,:) = 1.0
      end if
    end do

    lma(:,:) = 0.0
    sla(:,:) = 0.0

  end subroutine initglobal_plant


  subroutine initpft( pft, jpngr )
    !////////////////////////////////////////////////////////////////
    !  Initialisation of specified PFT on specified gridcell
    !  June 2014
    !  b.stocker@imperial.ac.uk
    !----------------------------------------------------------------
    integer, intent(in) :: pft
    integer, intent(in) :: jpngr

    ! initialise all _pools with zero
    pleaf(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
    proot(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
    plabl(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
    if (params_pft_plant(pft)%tree) then
      psapw(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
      pwood(pft,jpngr) = orgpool(carbon(0.0),nitrogen(0.0))
    endif

    ! initialise other properties
    fpc_grid(pft,jpngr)  = 0.0
    lai_ind(pft,jpngr)   = 0.0
    fapar_ind(pft,jpngr) = 0.0
    height(pft,jpngr)    = 0.0
    if (params_pft_plant(pft)%tree) then
      nind(pft,jpngr)      = 0.0
      crownarea(pft,jpngr) = 0.0
    else
      nind(pft,jpngr)      = 1.0
      crownarea(pft,jpngr) = 1.0
    endif

  end subroutine initpft


  subroutine initdaily_plant()
    !////////////////////////////////////////////////////////////////
    ! Initialises all daily variables with zero.
    !----------------------------------------------------------------

    dnpp(:)   = carbon(0.0)
    dcex(:)   = 0.0
    drauto(:) = 0.0
    drleaf(:) = 0.0
    drroot(:) = 0.0
    drgrow(:) = 0.0

  end subroutine initdaily_plant


  subroutine update_foliage_vars( pft, jpngr )
    !//////////////////////////////////////////////////////////////////
    ! Updates PFT-specific state variables after change in LAI.
    !------------------------------------------------------------------
    ! arguments
    integer, intent(in) :: pft
    integer, intent(in) :: jpngr

    if (pleaf(pft,jpngr)%c%c12==0.0) then
      lai_ind(pft,jpngr)  = 0.0
      fapar_ind(pft,jpngr)  = 0.0
      fpc_grid(pft,jpngr) = 0.0
    else
      ! This assumes that leaf canopy-average traits (LMA) do not change upon changes in LAI.
      lai_ind(pft,jpngr) = pleaf(pft,jpngr)%c%c12 / ( lma(pft,jpngr) * crownarea(pft,jpngr) * nind(pft,jpngr) )
      call update_fpc_grid( pft, jpngr )
    end if

  end subroutine update_foliage_vars


  subroutine update_fpc_grid( pft, jpngr )
    !//////////////////////////////////////////////////////////////////
    ! Updates PFT-specific state variables after change in LAI.
    !------------------------------------------------------------------
    ! arguments
    integer, intent(in) :: pft
    integer, intent(in) :: jpngr

    fapar_ind(pft,jpngr) = get_fapar( lai_ind(pft,jpngr) )
    fpc_grid(pft,jpngr)  = get_fpc_grid( crownarea(pft,jpngr), nind(pft,jpngr), fapar_ind(pft,jpngr) ) 

  end subroutine update_fpc_grid


  function get_fpc_grid( crownarea, nind, fapar_ind ) result( fpc_grid )
    !////////////////////////////////////////////////////////////////
    ! FRACTIONAL PLANT COVERAGE
    ! Function returns total fractional plant cover of a PFT
    ! Eq. 8 in Sitch et al., 2003
    !----------------------------------------------------------------
    ! arguments
    real, intent(in) :: crownarea
    real, intent(in) :: nind
    real, intent(in) :: fapar_ind

    ! function return variable
    real, intent(out) :: fpc_grid

    fpc_grid = crownarea * nind * fapar_ind

  end function get_fpc_grid


  function get_fapar( lai ) result( fapar )
    !////////////////////////////////////////////////////////////////
    ! FOLIAGE PROJECTIVE COVER 
    ! = Fraction of Absorbed Photosynthetically Active Radiation
    ! Function returns fractional plant cover an individual
    ! Eq. 7 in Sitch et al., 2003
    !----------------------------------------------------------------
    ! arguments
    real, intent(in) :: lai

    ! function return variable
    real, intent(out) :: fapar

    fapar = ( 1.0 - exp( -1.0 * params_plant%kbeer * lai) )

  end function get_fapar


  subroutine initoutput_plant()
    !////////////////////////////////////////////////////////////////
    ! Initialises all daily variables with zero.
    ! Called at the beginning of each year by 'biosphere'.
    !----------------------------------------------------------------
    use _params_siml, only: & 
        loutdgpp       &
      , loutdnpp       &
      , loutdnup       &
      , loutdCleaf     &
      , loutdCroot     &
      , loutdClabl     &
      , loutdNlabl     &
      , loutdClitt     &
      , loutdNlitt     &
      , loutdCsoil     &
      , loutdNsoil     &
      , loutdlai

    if (loutdnpp      ) allocate( outdnpp      (npft,ndayyear,maxgrid) )
    if (loutdnup      ) allocate( outdnup      (npft,ndayyear,maxgrid) )
    if (loutdCleaf    ) allocate( outdCleaf    (npft,ndayyear,maxgrid) )
    if (loutdCroot    ) allocate( outdCroot    (npft,ndayyear,maxgrid) )
    if (loutdClabl    ) allocate( outdClabl    (npft,ndayyear,maxgrid) )
    if (loutdNlabl    ) allocate( outdNlabl    (npft,ndayyear,maxgrid) )
    if (loutdClitt    ) allocate( outdClitt    (npft,ndayyear,maxgrid) )
    if (loutdNlitt    ) allocate( outdNlitt    (npft,ndayyear,maxgrid) )
    if (loutdCsoil    ) allocate( outdCsoil    (nlu,ndayyear,maxgrid)  )
    if (loutdNsoil    ) allocate( outdNsoil    (nlu,ndayyear,maxgrid)  )
    if (loutdlai      ) allocate( outdlai      (npft,ndayyear,maxgrid) )

    ! annual output variables
    outanpp(:,:)        = 0.0
    outanup(:,:)        = 0.0
    outaCveg(:,:)       = 0.0
    outaCveg2lit(:,:)   = 0.0
    outaNveg2lit(:,:)   = 0.0
    outaninorg(:,:)     = 0.0
    outanarea_mb(:,:)   = 0.0
    outanarea_cw(:,:)   = 0.0
    outalai     (:,:)   = 0.0
    outalma     (:,:)   = 0.0
    outacton_lm (:,:)   = 0.0

  end subroutine initoutput_plant


  subroutine initio_plant()
    !////////////////////////////////////////////////////////////////
    ! Opens input/output files.
    !----------------------------------------------------------------
    use _params_siml, only: & 
        loutdgpp       &
      , loutdnpp       &
      , loutdnup       &
      , loutdCleaf     &
      , loutdCroot     &
      , loutdClabl     &
      , loutdNlabl     &
      , loutdClitt     &
      , loutdNlitt     &
      , loutdCsoil     &
      , loutdNsoil     &
      , loutdlai
    use _params_siml, only: runname

    ! local variables
    character(len=256) :: prefix
    character(len=256) :: filnam

    prefix = "./output/"//trim(runname)

    !////////////////////////////////////////////////////////////////
    ! DAILY OUTPUT: OPEN ASCII OUTPUT FILES 
    !----------------------------------------------------------------
    ! NPP
    if (loutdnpp) then 
      filnam=trim(prefix)//'.d.npp.out'
      open(102,file=filnam,err=999,status='unknown')
    end if

    ! LEAF C
    if (loutdCleaf    ) then
      filnam=trim(prefix)//'.d.cleaf.out'
      open(103,file=filnam,err=999,status='unknown')
    end if 

    ! N UPTAKE
    if (loutdnup      ) then
      filnam=trim(prefix)//'.d.nup.out'
      open(104,file=filnam,err=999,status='unknown')
    end if

    ! ! AIR TEMPERATURE
    ! filnam=trim(prefix)//'.d.temp.out'
    ! open(110,file=filnam,err=999,status='unknown')

    ! ROOT C
    if (loutdCroot    ) then
      filnam=trim(prefix)//'.d.croot.out'
      open(111,file=filnam,err=999,status='unknown')
    end if

    ! LABILE C
    if (loutdClabl    ) then
      filnam=trim(prefix)//'.d.clabl.out'
      open(112,file=filnam,err=999,status='unknown')
    end if

    ! LITTER C
    if (loutdClitt    ) then
      filnam=trim(prefix)//'.d.clitt.out'
      open(113,file=filnam,err=999,status='unknown')
    end if

    ! ! LABILE N
    ! if (loutdNlabl    ) then
    !   filnam=trim(prefix)//'.d.nlabl.out'
    !   open(115,file=filnam,err=999,status='unknown')
    ! end if

    ! LITTER N
    if (loutdNlitt    ) then
      filnam=trim(prefix)//'.d.nlitt.out'
      open(119,file=filnam,err=999,status='unknown')
    end if

    ! LAI
    if (loutdlai      ) then
      filnam=trim(prefix)//'.d.lai.out'
      open(121,file=filnam,err=999,status='unknown')
    end if

    !////////////////////////////////////////////////////////////////
    ! ANNUAL OUTPUT: OPEN ASCII OUTPUT FILES
    !----------------------------------------------------------------

    ! C VEGETATION -> LITTER TRANSFER
    filnam=trim(prefix)//'.a.cveg2lit.out'
    open(307,file=filnam,err=999,status='unknown')

    ! N VEGETATION -> LITTER TRANSFER
    filnam=trim(prefix)//'.a.nveg2lit.out'
    open(308,file=filnam,err=999,status='unknown')

    ! NPP 
    filnam=trim(prefix)//'.a.npp.out'
    open(311,file=filnam,err=999,status='unknown')

    ! VEG C
    filnam=trim(prefix)//'.a.cveg.out'
    open(312,file=filnam,err=999,status='unknown')

    ! INORGANIC N (mean over days)
    filnam=trim(prefix)//'.a.ninorg.out'
    open(316,file=filnam,err=999,status='unknown')

    ! N UPTAKE
    filnam=trim(prefix)//'.a.nup.out'
    open(317,file=filnam,err=999,status='unknown')

    ! LAI (ANNUAL MAXIMUM)
    filnam=trim(prefix)//'.a.lai.out'
    open(318,file=filnam,err=999,status='unknown')

    ! METABOLIC NAREA (AT ANNUAL LAI MAXIMUM)
    filnam=trim(prefix)//'.a.narea_mb.out'
    open(319,file=filnam,err=999,status='unknown')

    ! CELL WALL NAREA (AT ANNUAL LAI MAXIMUM)
    filnam=trim(prefix)//'.a.narea_cw.out'
    open(320,file=filnam,err=999,status='unknown')

    ! LEAF C:N RATIO (AT ANNUAL LAI MAXIMUM)
    filnam=trim(prefix)//'.a.cton_lm.out'
    open(321,file=filnam,err=999,status='unknown')

    ! LMA (AT ANNUAL LAI MAXIMUM)
    filnam=trim(prefix)//'.a.lma.out'
    open(322,file=filnam,err=999,status='unknown')

    return

    999  stop 'INITIO: error opening output files'

  end subroutine initio_plant


  subroutine getout_daily_plant( jpngr, moy, doy )
    !////////////////////////////////////////////////////////////////
    ! SR called daily to sum up daily output variables.
    ! Note that output variables are collected only for those variables
    ! that are global anyway (e.g., outdcex). Others are not made 
    ! global just for this, but are collected inside the subroutine 
    ! where they are defined.
    !----------------------------------------------------------------
    use _params_core, only: ndayyear, npft
    use _params_siml, only: & 
        loutdgpp       &
      , loutdnpp       &
      , loutdnup       &
      , loutdCleaf     &
      , loutdCroot     &
      , loutdClabl     &
      , loutdNlabl     &
      , loutdClitt     &
      , loutdNlitt     &
      , loutdCsoil     &
      , loutdNsoil     &
      , loutdlai

    ! arguments
    integer, intent(in) :: jpngr
    integer, intent(in) :: moy
    integer, intent(in) :: doy

    ! LOCAL VARIABLES
    integer :: pft

    !----------------------------------------------------------------
    ! DAILY
    ! Collect daily output variables
    ! so far not implemented for isotopes
    !----------------------------------------------------------------
    if (loutdnpp      ) outdnpp(:,doy,jpngr)       = dnpp(:)%c12
    if (loutdnup      ) outdnup(:,doy,jpngr)       = dnup(:)%n14
    if (loutdCleaf    ) outdCleaf(:,doy,jpngr)     = pleaf(:,jpngr)%c%c12
    if (loutdCroot    ) outdCroot(:,doy,jpngr)     = proot(:,jpngr)%c%c12
    if (loutdClabl    ) outdClabl(:,doy,jpngr)     = plabl(:,jpngr)%c%c12

    if (loutdNlabl    ) outdNlabl(:,doy,jpngr)     = plabl(:,jpngr)%n%n14
    if (loutdClitt    ) outdClitt(:,doy,jpngr)     = plitt_af(:,jpngr)%c%c12 + plitt_as(:,jpngr)%c%c12 + plitt_bg(:,jpngr)%c%c12
    if (loutdNlitt    ) outdNlitt(:,doy,jpngr)     = plitt_af(:,jpngr)%n%n14 + plitt_as(:,jpngr)%n%n14 + plitt_bg(:,jpngr)%n%n14
    if (loutdlai      ) outdlai(:,doy,jpngr)       = lai_ind(:,jpngr)
    
    dnarea_mb(:,doy)           = narea_metabolic(:)  
    dnarea_cw(:,doy)           = narea_structural(:)
    dcton_lm(:,doy)            = r_cton_leaf(:,jpngr)
    dlma(:,doy)                = lma(:,jpngr)

    !----------------------------------------------------------------
    ! ANNUAL SUM OVER DAILY VALUES
    ! Collect annual output variables as sum of daily values
    !----------------------------------------------------------------
    outanpp(:,jpngr)    = outanpp(:,jpngr) + dnpp(:)%c12
    outanup(:,jpngr)    = outanup(:,jpngr) + dnup(:)%n14

  end subroutine getout_daily_plant


  subroutine getout_annual_plant( jpngr )
    !////////////////////////////////////////////////////////////////
    !  SR called once a year to gather annual output variables.
    !----------------------------------------------------------------
    use _params_core, only: ndayyear, npft

    ! arguments
    integer, intent(in) :: jpngr

    ! local variables
    integer                  :: pft
    integer                  :: doy
    integer, dimension(npft) :: maxdoy
    ! intrinsic                :: maxloc

    ! Output annual value at day of peak LAI
    do pft=1,npft
      maxdoy(pft)=1
      do doy=2,ndayyear
        if ( outdlai(pft,doy,jpngr) > outdlai(pft,(doy-1),jpngr) ) then
          maxdoy(pft) = doy
        end if
      end do

      outaCveg    (pft,jpngr) = outdCleaf(pft,maxdoy(pft),jpngr) + outdCroot(pft,maxdoy(pft),jpngr) 
      outanarea_mb(pft,jpngr) = dnarea_mb(pft,maxdoy(pft))
      outanarea_cw(pft,jpngr) = dnarea_cw(pft,maxdoy(pft))
      outalai     (pft,jpngr) = outdlai(pft,maxdoy(pft),jpngr)
      outalma     (pft,jpngr) = dlma(pft,maxdoy(pft))
      outacton_lm (pft,jpngr) = dcton_lm(pft,maxdoy(pft))
    end do

    open(unit=666,file='cton_vs_lai.log',status='unknown')
    do doy=1,ndayyear
      write(666,*) outdlai(1,doy,1), ",", dcton_lm(1,doy)
    end do
    close(unit=666)

  end subroutine getout_annual_plant


  subroutine writeout_ascii_plant( year )
    !/////////////////////////////////////////////////////////////////////////
    ! Write daily ASCII output
    ! Copyright (C) 2015, see LICENSE, Benjamin David Stocker
    ! contact: b.stocker@imperial.ac.uk
    !-------------------------------------------------------------------------
    use _params_siml, only: spinup, daily_out_startyr, &
      daily_out_endyr, outyear
    use _params_core, only: ndayyear
    use _params_siml, only: & 
        loutdgpp       &
      , loutdnpp       &
      , loutdnup       &
      , loutdCleaf     &
      , loutdCroot     &
      , loutdClabl     &
      , loutdNlabl     &
      , loutdClitt     &
      , loutdNlitt     &
      , loutdCsoil     &
      , loutdNsoil     &
      , loutdlai

    ! arguments
    integer, intent(in) :: year       ! simulation year

    ! local variables
    real :: itime
    integer :: day, moy, jpngr

    ! xxx implement this: sum over gridcells? single output per gridcell?
    if (maxgrid>1) stop 'writeout_ascii: think of something ...'
    jpngr = 1


    !-------------------------------------------------------------------------
    ! Collect variables to output variables
    !-------------------------------------------------------------------------
    !do lu=1,nlu
    !  do pft=1,npft
    !    if (lu==lu_category(pft)) then
    !    end if
    !  end do
    !end do
    if (nlu>1) stop 'Output only for one LU category implemented.'


    !-------------------------------------------------------------------------
    ! DAILY OUTPUT
    ! Write daily value, summed over all PFTs / LUs
    ! xxx implement taking sum over PFTs (and gridcells) in this land use category
    !-------------------------------------------------------------------------
    if ( .not. spinup .and. outyear>=daily_out_startyr .and. outyear<=daily_out_endyr ) then

      ! Write daily output only during transient simulation
      do day=1,ndayyear

        ! Define 'itime' as a decimal number corresponding to day in the year + year
        itime = real(outyear) + real(day-1)/real(ndayyear)
        
        if (loutdnpp      ) write(102,999) itime, sum(outdnpp(:,day,jpngr))
        if (loutdCleaf    ) write(103,999) itime, sum(outdCleaf(:,day,jpngr))
        if (loutdnup      ) write(104,999) itime, sum(outdnup(:,day,jpngr))
        if (loutdCroot    ) write(111,999) itime, sum(outdCroot(:,day,jpngr))
        if (loutdClabl    ) write(112,999) itime, sum(outdClabl(:,day,jpngr))
        if (loutdClitt    ) write(113,999) itime, sum(outdClitt(:,day,jpngr))
        if (loutdNlabl    ) write(115,999) itime, sum(outdNlabl(:,day,jpngr))
        if (loutdNlitt    ) write(119,999) itime, sum(outdNlitt(:,day,jpngr))
        if (loutdlai      ) write(121,999) itime, sum(outdlai(:,day,jpngr))
          
      end do
    end if

    !-------------------------------------------------------------------------
    ! ANNUAL OUTPUT
    ! Write annual value, summed over all PFTs / LUs
    ! xxx implement taking sum over PFTs (and gridcells) in this land use category
    !-------------------------------------------------------------------------
    itime = real(outyear)

    write(307,999) itime, sum(outaCveg2lit(:,jpngr))
    write(308,999) itime, sum(outaNveg2lit(:,jpngr))
    write(311,999) itime, sum(outanpp(:,jpngr))
    write(312,999) itime, sum(outaCveg(:,jpngr))
    write(316,999) itime, sum(outaninorg(:,jpngr))
    write(317,999) itime, sum(outanup(:,jpngr))
    write(318,999) itime, sum(outalai(:,jpngr))
    write(319,999) itime, sum(outanarea_mb(:,jpngr))
    write(320,999) itime, sum(outanarea_cw(:,jpngr))
    write(321,999) itime, sum(outacton_lm(:,jpngr))
    write(322,999) itime, sum(outalma(:,jpngr))

    return

  999     format (F20.8,F20.8)

  end subroutine writeout_ascii_plant

end module _plant
