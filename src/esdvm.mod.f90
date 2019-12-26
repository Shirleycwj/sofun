!=============================================================================
! These subroutines are from LM3-PPA that was used in the paper:
! Weng, E. S., Farrior, C. E., Dybzinski, R., Pacala, S. W., 2016. 
! Predicting vegetation type through physiological and environmental 
! interactions with leaf traits: evergreen and deciduous forests in 
! an earth system modeling framework. Global Change Biology, 
! doi: 10.1111/gcb.13542.
!=============================================================================
module esdvm_mod

implicit none

public :: spec_data_type, cohort_type, tile_type

! Constants
integer, public, parameter :: days_per_year  = 365
integer, public, parameter :: hours_per_year = 365 * 24  ! = 8760
integer, public, parameter :: seconds_per_year = 365 * 24 * 3600
real,    public, parameter :: dt_fast_yr = 1.0/365.0 ! daily step

real,    public, parameter :: PI       = 3.1415926
integer, public, parameter :: MSPECIES = 15
integer, public, parameter :: max_lev  = 30 ! Soil layers, for soil water dynamics
integer, public, parameter :: LEAF_ON  = 1
integer, public, parameter :: LEAF_OFF = 0

! Soil SOM reference C/N ratios
real, public, parameter :: CN0metabolicL  = 15.0 ! 25.0 ! 15.0
real, public, parameter :: CN0structuralL = 35.0 ! 55.0 ! 35.0

! Public variables
public :: forcingData,spdata, MaxCohortID, &
  K1, K2, K_nitrogen, MLmixRatio, &
  fsc_fine, fsc_wood,  &
  GR_factor,  l_fract, &
  DBH_mort, A_mort, B_mort

! Public subroutines
public :: initialize_PFT_data, initialize_cohort_from_biomass, &
        initialize_vegn_tile
public :: vegn_phenology,vegn_C_N_budget, vegn_growth_EW
public :: vegn_reproduction, vegn_annualLAImax_update
public :: vegn_starvation, vegn_nat_mortality
public :: relayer_cohorts, vegn_mergecohorts, kill_lowdensity_cohorts
public :: vegn_annual_diagnostics_zero


!////////////////////////////////////////////////////////////////
! Data types
!----------------------------------------------------------------

!----------------------------------------------------------------
! PFT data type
!----------------------------------------------------------------
type :: spec_data_type

  integer :: lifeform     ! 0 for grasses, 1 for trees
  integer :: phenotype    ! phenology type: 0 for deciduous, 1 for evergreen
  integer :: pt           ! photosynthetic physiology of species

  ! leaf traits
  real    :: LMA          ! leaf mass per unit area, kg C/m2
  real    :: leafLS       ! leaf life span
  real    :: alpha_L      ! leaf turn over rate
  real    :: LNA          ! leaf Nitrogen per unit area, kg N/m2
  real    :: LNbase       ! basal leaf Nitrogen per unit area, kg N/m2, (Rubisco)
  real    :: CNleafsupport! leaf structural tissues, 175
  real    :: leaf_size    ! characteristic leaf size
  real    :: alpha_phot   ! photosynthesis efficiency
  real    :: m_cond       ! factor of stomatal conductance
  real    :: Vmax         ! max rubisco rate, mol m-2 s-1
  real    :: Vannual      ! annual productivity per unit area at full fun (kgC m-2 yr-1)
  real    :: gamma_L      ! leaf respiration coeficient
  real    :: gamma_LN     ! leaf respiration coeficient per unit N

  ! root traits
  real    :: rho_FR       ! material density of fine roots (kgC m-3)
  real    :: root_r       ! radius of the fine roots, m
  real    :: SRA          ! speific fine root area, m2/kg C
  real    :: gamma_FR     ! Fine root respiration rate, kgC kgC-1 yr-1
  real    :: alpha_FR     ! Turnover rate of Fine roots, fraction yr-1
  real    :: root_perm    ! fine root membrane permeability per unit area, kg/(m3 s)
  ! real    :: rho_N_up0   ! maximum N uptake rate
  ! real    :: N_roots0    ! root biomass at half of max. N-uptake rate

  ! wood traits
  real    :: rho_wood     ! woody density, kg C m-3 wood
  real    :: gamma_SW     ! sapwood respiration rate, kgC m-2 Acambium yr-1
  real    :: taperfactor

  ! Allometry
  real    :: alphaHT, thetaHT ! height = alphaHT * DBH ** thetaHT
  real    :: alphaCA, thetaCA ! crown area = alphaCA * DBH ** thetaCA
  real    :: alphaBM, thetaBM ! biomass = alphaBM * DBH ** thetaBM
  real    :: phiRL            ! ratio of fine root to leaf area
  real    :: phiCSA           ! ratio of sapwood CSA to target leaf area
  real    :: tauNSC           ! residence time of C in NSC (to define storage capacity)

  ! Default C/N ratios
  real    :: CNleaf0
  real    :: CNroot0
  real    :: CNsw0
  real    :: CNwood0
  real    :: CNseed0

  ! phenology
  real    :: tc_crit         ! K, for turning OFF a growth season
  real    :: tc_crit_on      ! K, for turning ON a growth season
  real    :: gdd_crit        ! K, critical value of GDD5 for turning ON growth season

  !  vital rates
  real    :: maturalage       ! the age that can reproduce
  real    :: v_seed           ! fracton of G_SF to G_F
  real    :: seedlingsize     ! size of the seedlings, kgC/indiv
  real    :: prob_g,prob_e    ! germination and establishment probabilities
  real    :: mortrate_d_c     ! daily mortality rate in canopy
  real    :: mortrate_d_u     ! daily mortality rate in understory

  ! Population level variables
  real    :: LAImax,underLAImax ! max. LAI
  real    :: LAI_light        ! light controlled maximum LAI
  integer :: n_cc             ! for calculating LAImax via cc%LAImax derived from cc%NSN
  real    :: layerfrac        ! species layer fraction
  real    :: internal_gap_frac ! fraction of internal gaps in the canopy

  ! "internal" gaps are the gaps that are created within the canopy by the
  ! branch fall processes.

end type

! PFT-specific parameters
type(spec_data_type), save :: spdata(0:MSPECIES) ! define PFTs

!----------------------------------------------------------------
! Cohort type
!----------------------------------------------------------------
type :: cohort_type
  ! biological prognostic variables
  integer :: ccID    = 0   ! cohort ID
  integer :: species = 0   ! vegetation species
  real    :: gdd     = 0.0   ! for phenology
  integer :: status  = 0   ! growth status of plant: 1 for ON, 0 for OFF
  integer :: layer   = 1   ! the layer of this cohort (numbered from top, top layer=1)
  integer :: firstlayer = 0 ! 0 = never been in the first layer; 1 = at least one year in first layer
  real    :: layerfrac  = 0.0 ! fraction of layer area occupied by this cohort

  ! for populatin structure
  real    :: nindivs      = 1.0 ! density of vegetation, individuals/m2
  real    :: age          = 0.0 ! age of cohort, years 
  real    :: dbh          = 0.0 ! diameter at breast height, m
  real    :: height       = 0.0 ! vegetation height, m
  real    :: crownarea    = 1.0 ! crown area, m2/individual
  real    :: leafarea     = 0.0 ! total area of leaves, m2/individual
  real    :: lai          = 0.0 ! leaf area index, m2/m2
  
  ! carbon pools
  real    :: bl      = 0.0 ! biomass of leaves, kg C/individual
  real    :: br      = 0.0 ! biomass of fine roots, kg C/individual
  real    :: bsw     = 0.0 ! biomass of sapwood, kg C/individual
  real    :: bHW     = 0.0 ! biomass of heartwood, kg C/individual
  real    :: seedC   = 0.0 ! biomass put aside for future progeny, kg C/individual
  real    :: nsc     = 0.0 ! non-structural carbon, kg C/individual

  ! carbon fluxes
  real :: gpp  = 0.0 ! gross primary productivity kg C/timestep
  real :: npp  = 0.0 ! net primary productivity kg C/timestep
  real :: resp = 0.0 ! plant respiration
  real :: resl = 0.0 ! leaf respiration
  real :: resr = 0.0 ! root respiration
  real :: resg = 0.0 ! growth respiration
  real :: NPPleaf, NPProot, NPPwood ! to record C allocated to leaf, root, and wood
  real :: annualGPP
  real :: annualNPP
  real :: annualResp

  ! Nitrogen model related parameters
  real    :: NSN = 0.0    ! non-structural N pool
  real    :: NSNmax = 0.
  real    :: leafN  = 0.
  real    :: sapwdN = 0.
  real    :: woodN = 0.0 ! N of heart wood
  real    :: rootN = 0.0 ! N of fine roots
  real    :: seedN = 0.0 !
  real    :: N_uptake = 0.
  real    :: N_up_yr  = 0.0

  ! TODO: see if we can make bl_max, br_max local variables
  real    :: bl_max  = 0.0 ! Max. leaf biomass, kg C/individual
  real    :: br_max  = 0.0 ! Max. fine root biomass, kg C/individual
  real    :: CSAsw   = 0.0
  real    :: topyear = 0.0 ! the years that a plant in top layer
  real    :: DBH_ys             ! DBH at the begining of a year (growing season)

  ! water uptake-related variables
  real    :: root_length(max_lev) = 0.0 ! individual's root length per unit depth, m of root/m
  real    :: K_r = 0.0 ! root membrane permeability per unit area, kg/(m3 s)
  real    :: r_r = 0.0 ! radius of fine roots, m
  real    :: uptake_frac(max_lev) = 0.0 ! normalized vertical distribution of uptake

  ! for photosynthesis
  !  real :: An_op = 0.0 ! mol C/(m2 of leaf per year)
  !  real :: An_cl = 0.0 ! mol C/(m2 of leaf per year)
  !  real :: w_scale =-9999
  real :: carbon_gain = 0.0 ! carbon gain since last growth, kg C/individual
  real :: extinct = 0.5     ! light extinction coefficient in the canopy for photosynthesis

end type cohort_type


!----------------------------------------------------------------
! Tile type
!----------------------------------------------------------------
type :: tile_type

  integer :: n_cohorts = 0
  integer :: n_years   = 0
  integer :: n_canopycc = 0

  type(cohort_type), pointer :: cohorts(:) => NULL()

  real :: area  ! m2
  real :: age = 0.0 ! tile age

  ! leaf area index
  real :: LAI  ! leaf area index
  real :: CAI  ! crown area index

  real :: LAIlayer(0:9) = 0.0 ! LAI of each crown layer, max. 9

  ! uptake-related variables
  real :: root_distance(max_lev) ! characteristic half-distance between fine roots, m

  ! averaged quantities for PPA phenology
  real :: tc_daily = 0.0
  real :: gdd      = 0.0 ! growing degree-days
  real :: tc_pheno = 0.0 ! smoothed canopy air temperature for phenology

  ! litter and soil carbon pools
  real :: litter = 0.0 ! litter flux
  real :: MicrobialC  = 0.0  ! Microbes (kg C/m2)
  real :: metabolicL  = 0.0  ! fast soil carbon pool, (kg C/m2)
  real :: structuralL = 0.0  ! slow soil carbon pool, (kg C/m2)

  !!  Nitrogen pools, Weng 2014-08-08
  real :: MicrobialN = 0.0
  real :: metabolicN = 0.0  ! fast soil nitrogen pool, (kg N/m2)
  real :: structuralN = 0.0  ! slow soil nitrogen pool, (kg N/m2)
  real :: mineralN = 0.0  ! Mineral nitrogen pool, (kg N/m2)
  real :: N_input        ! annual N input (kgN m-2 yr-1)
  real :: N_uptake  = 0.0  ! kg N m-2 yr-1
  real :: accu_Nup       ! accumulated N uptake kgN m-2
  real :: annualN = 0.0  ! annual available N in a year
  real :: previousN      ! an weighted annual available N
  real :: Wrunoff        ! Water runoff of the veg tile, unit?
  real :: soil_theta     ! volumetric soil water content vol/vol

  !  Carbon fluxes
  real :: gpp = 0.0 ! gross primary production, kgC m-2 yr-1
  real :: npp = 0.0 ! net primary productivity
  real :: resp = 0.0 ! auto-respiration of plants
  real :: nep = 0.0 ! net ecosystem productivity
  real :: rh  = 0.0 ! soil carbon lost to the atmosphere

  ! for annual diagnostics
  real :: annualGPP = 0.0 ! kgC m-2 yr-1
  real :: annualNPP = 0.0
  real :: annualResp = 0.0
  real :: annualRh   = 0.0

  ! for annual reporting
  real :: maxNSC, maxSeedC, maxleafC, maxrootC,SapwoodC, WoodC, maxLAI

end type tile_type


!----------------------------------------------------------------
! Climate forcing type
!----------------------------------------------------------------
type :: climate_data_type
  integer :: year          ! Year
  integer :: doy           ! day of the year
  real    :: hod           ! hour of the day
  real    :: PAR           ! check uit
  real    :: radiation     ! W/m2
  real    :: Tair          ! K
  real    :: Tsoil         ! soil temperature, K
  real    :: RH            ! relative humidity
  real    :: rain          ! kgH2O m-2 s-1
  real    :: windU         ! wind velocity (m s-1)
  real    :: pressure      ! pa
  real    :: soilwater     ! soil moisture, vol/vol
end type climate_data_type

type(climate_data_type),pointer, save :: forcingData(:)

integer :: MaxCohortID = 0

!----------------------------------------------------------------
! Model parameters
!----------------------------------------------------------------
! Constants:
real :: K1 = 3, K2 = 0.05    ! soil decomposition parameters
real :: K_nitrogen = 2.0     ! mineral Nitrogen turnover rate
real :: MLmixRatio = 0.8     ! the ratio of C and N returned to litters from microbes
real :: fsc_fine   = 0.8     ! fraction of fast turnover carbon in fine biomass
real :: fsc_wood   = 0.2     ! fraction of fast turnover carbon in wood biomass
real :: GR_factor  = 0.33 ! growth respiration factor
real :: l_fract    = 0.0 ! 0.25  ! 0.5 ! fraction of the leaves retained after leaf drop

! Ensheng's growth parameters:
real :: wood_fract_min = 0.33
! for understory mortality rate is calculated as:
! deathrate = mortrate_d_u * ( 1 + A * exp(B*(DBH_mort-DBH))/(1 + exp(B*(DBH_mort-DBH)))
real :: DBH_mort   = 0.025 ! characteristic DBH for mortality
real :: A_mort     = 4.0   ! A coefficient in understory mortality rate correction, 1/year
real :: B_mort     = 30.0  ! B coefficient in understory mortality rate correction, 1/m
! for leaf life span and LMA (leafLS = c_LLS * LMA
real :: c_LLS  = 28.57143 ! yr/ (kg C m-2), 1/LMAs, where LMAs = 0.035

! reduction of bl_max and br_max for the understory vegetation, unitless
real :: understory_lai_factor = 0.25


!----------------------------------------------------------------
! PFT-specific model parameters
!----------------------------------------------------------------
! c4grass  c3grass  temp-decid  tropical  evergreen  BE  BD  BN  NE  ND  G  D  T  A
integer :: pt(0:MSPECIES) = 0
!(/1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0/) ! 0 for C3, 1 for C4
integer :: phenotype(0:MSPECIES)= 0
! (/0,  0,  0,  0,  1,  1,  0,  0, 0, 0, 0, 0, 0, 0, 0, 0 /) ! 0 for Deciduous, 1 for evergreen
integer :: lifeform(0:MSPECIES) = 1 ! life form of PFTs: 0 for grasses, 1 for trees
real :: alpha_FR(0:MSPECIES) = 0.5 ! 1.2 ! Fine root turnover rate yr-1
!(/0.8, 0.8,0.8, 0.8, 0.8,0.8,0.8,0.8,1.0,1.0,0.6, 1.0, 0.55, 0.9, 0.55, 0.55/)

! root parameters
real :: rho_FR(0:MSPECIES) = 200 ! woody density, kgC m-3
real :: root_r(0:MSPECIES) = 2.9E-4
!(/1.1e-4, 1.1e-4, 2.9e-4, 2.9e-4, 2.9e-4, 2.9e-4, 2.9e-4, 2.9e-4, 2.9e-4, 2.9e-4, 2.9e-4, 2.9e-4, 1.1e-4, 1.1e-4, 2.2e-4, 2.2e-4/)
real :: root_perm(0:MSPECIES)= 1.0E-5
!(/1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5, 1e-5/)
   ! fine root membrane permeability per unit membrane area, kg/(m3 s).
   ! Root membrane permeability is "high" for the value from Siqueira et al., 2008,
! Water Resource Research Vol. 44, W01432, converted to mass units
!real :: rho_N_up0(0:MSPECIES) = 0.5 ! fraction of mineral N per hour
!real :: N_roots0(0:MSPECIES) = 0.3 ! kgC m-2

real :: leaf_size(0:MSPECIES)= 0.04 !

! photosynthesis parameters
real :: Vmax(0:MSPECIES)= 70.0E-6 !
real :: Vannual(0:MSPECIES) = 1.2 ! kgC m-2 yr-1
!(/1.2,1.2,1.2,1.2,1.2,1.2,1.2,1.2,1.2,1.2,1.2,1.2,1.2,1.2,1.2,1.2/)
real :: m_cond(0:MSPECIES)= 9.0 !
real :: alpha_phot(0:MSPECIES)= 0.06 !
real :: gamma_L(0:MSPECIES)= 0.02 !
real :: gamma_LN(0:MSPECIES)= 25.0 ! kgC kgN-1 yr-1
real :: gamma_SW(0:MSPECIES)= 0.0025 ! kgC m-2 Acambium yr-1
real :: gamma_FR(0:MSPECIES)= 12.0  !kgC kgN-1 yr-1 ! 0.6  ! kgC kgC-1 yr-1
real :: tc_crit(0:MSPECIES)= 283.16
real :: tc_crit_on(0:MSPECIES)= 280.16 !
real :: gdd_crit(0:MSPECIES)= 300.0 !

! Allometry parameters
real    :: alphaHT(0:MSPECIES)      = 36.01
real    :: thetaHT(0:MSPECIES)      = 0.5 !
real    :: alphaCA(0:MSPECIES)      = 200.0
real    :: thetaCA(0:MSPECIES)      = 1.5
real    :: alphaBM(0:MSPECIES)      = 500.0
real    :: thetaBM(0:MSPECIES)      = 2.5

! Reproduction prarameters
real    :: maturalage(0:MSPECIES)   = 5.0  ! year
real    :: v_seed(0:MSPECIES)       = 0.1  ! fraction of allocation to wood+seeds
real    :: seedlingsize(0:MSPECIES) = 0.05 ! kgC
real    :: prob_g(0:MSPECIES)       = 1.0
real    :: prob_e(0:MSPECIES)       = 1.0

! Mortality
real    :: mortrate_d_c(0:MSPECIES) = 0.02
real    :: mortrate_d_u(0:MSPECIES) = 0.05

! Leaf parameters
real    :: LMA(0:MSPECIES)          = 0.035  !  leaf mass per unit area, kg C/m2
!(/0.04,    0.04,    0.035,   0.035,   0.140,  0.032, 0.032,  0.036,   0.036,   0.036,   0.036,   0.036,   0.036,   0.036,   0.036,   0.036  /)
real    :: leafLS(0:MSPECIES) = 1.0
!(/1., 1., 1., 1., 3., 3., 1., 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 /)
real    :: LNbase(0:MSPECIES)        = 0.6E-3 !& !  basal leaf Nitrogen per unit area, kg N/m2
real    :: CNleafsupport(0:MSPECIES) = 60.0 ! CN ratio of leaf supporting tissues
real    :: rho_wood(0:MSPECIES)      = 265.0 ! kgC m-3
real    :: taperfactor(0:MSPECIES)   = 0.65 ! taper factor, from a cylinder to a tree
real    :: LAImax(0:MSPECIES)        = 4.0 ! maximum LAI for a tree
real    :: LAI_light(0:MSPECIES)     = 4.0 ! maximum LAI limited by light
real    :: tauNSC(0:MSPECIES)        = 3.0 ! NSC residence time,years
real    :: phiRL(0:MSPECIES)         = 1.2 ! ratio of fine root area to leaf area
real    :: phiCSA(0:MSPECIES)        = 1.25E-4 ! ratio of sapwood area to leaf area

! C/N ratios for plant pools
real    :: CNleaf0(0:MSPECIES) = 50.0 ! C/N ratios for leaves
real    :: CNsw0(0:MSPECIES)   = 350.0 ! C/N ratios for woody biomass
real    :: CNwood0(0:MSPECIES) = 350.0 ! C/N ratios for woody biomass
real    :: CNroot0(0:MSPECIES) = 60.0 ! C/N ratios for leaves
real    :: CNseed0(0:MSPECIES) = 20.0 ! C/N ratios for leaves

real :: internal_gap_frac(0:MSPECIES)= 0.1 ! The gaps between trees

namelist /vegn_parameters_nml/  &
  pt, phenotype, lifeform, &
  Vmax, Vannual,   &
  gamma_L, gamma_LN, gamma_SW, gamma_FR,  &
  rho_FR, root_r, root_perm, &
  !rho_N_up0, N_roots0, &
  leaf_size, leafLS, LAImax, LAI_light,   &
  LMA, LNbase, CNleafsupport, c_LLS,      &
  K1,K2, K_nitrogen, MLmixRatio,fsc_fine, fsc_wood, &
  GR_factor, l_fract, wood_fract_min,  &
  gdd_crit,tc_crit, tc_crit_on, &
  alphaHT, thetaHT, alphaCA, thetaCA, alphaBM, thetaBM, &
  maturalage, v_seed, seedlingsize, prob_g,prob_e,               &
  mortrate_d_c, mortrate_d_u,                         &
  DBH_mort, A_mort, B_mort,                       &
  phiRL, phiCSA, rho_wood, taperfactor, &
  tauNSC, understory_lai_factor, &
  CNleaf0,CNsw0,CNwood0,CNroot0,CNseed0, &
  internal_gap_frac

!----------------------------------------------------------------
! Initial conditions
!----------------------------------------------------------------
integer, parameter :: MAX_INIT_COHORTS = 10 ! Weng, 2014-10-01
integer :: init_n_cohorts                        = MAX_INIT_COHORTS
integer :: init_cohort_species(MAX_INIT_COHORTS) = 2
real    :: init_cohort_nindivs(MAX_INIT_COHORTS) = 1.0  ! initial individual density, individual/m2
real    :: init_cohort_bl(MAX_INIT_COHORTS)      = 0.0  ! initial biomass of leaves, kg C/individual
real    :: init_cohort_br(MAX_INIT_COHORTS)      = 0.0  ! initial biomass of fine roots, kg C/individual
real    :: init_cohort_bsw(MAX_INIT_COHORTS)     = 0.05 ! initial biomass of sapwood, kg C/individual
real    :: init_cohort_bHW(MAX_INIT_COHORTS)     = 0.0  ! initial biomass of heartwood, kg C/individual
real    :: init_cohort_seedC(MAX_INIT_COHORTS)   = 0.0  ! initial biomass of seeds, kg C/individual
real    :: init_cohort_nsc(MAX_INIT_COHORTS)     = 0.05 ! initial non-structural biomass, kg C/

!  initial soil Carbon and Nitrogen for a vegn tile, Weng 2012-10-24
real   :: init_fast_soil_C  = 0.0  ! initial fast soil C, kg C/m2
real   :: init_slow_soil_C  = 0.0  ! initial slow soil C, kg C/m2
real   :: init_Nmineral = 0.015  ! Mineral nitrogen pool, (kg N/m2)
real   :: N_input    = 0.005 ! annual N input to soil N pool, kgN m-2 yr-1
integer:: model_run_years = 100

namelist /initial_state_nml/ &
    init_n_cohorts, init_cohort_species, init_cohort_nindivs, &
    init_cohort_bl, init_cohort_br, init_cohort_bsw, &
    init_cohort_bHW, init_cohort_seedC, init_cohort_nsc, &
    init_fast_soil_C, init_slow_soil_C,    & 
    init_Nmineral, N_input, &
    model_run_years

contains

  subroutine vegn_C_N_budget(vegn, tsoil, theta)
    !////////////////////////////////////////////////////////////////
    ! Determines 'carbon_gain' available for growth from NSC
    ! hourly; Changed to daily, Weng 2016-11-25
    ! include Nitrogen uptake and carbon budget
    ! carbon_gain is calculated here to drive plant growth and reproduciton
    !----------------------------------------------------------------
    ! arguments
    type(tile_type), intent(inout) :: vegn
    real, intent(in) :: tsoil ! average temperature of soil, deg K
    real, intent(in) :: theta ! average soil wetness, unitless

    ! local variables
    type(cohort_type), pointer :: cc    ! current cohort
    real :: C_input  ! carbon assimilated per tree per fast time step
    real :: dBL, dBR, dBSW ! leaf and fine root carbon tendencies
    real :: turnoverC  ! temporary var for several calculations
    integer :: i

    real :: NSC_supply,LR_demand,LR_deficit
    real :: LeafGrowthMin, RootGrowthMin, NSCtarget, v
    real :: LR_growth,WS_growth
    real :: R_days,fNSC,fLFR,fStem

    ! Carbon gain trhough photosynthesis
    call vegen_C_gain(vegn,forcingData)

    ! update plant carbon and nitrogen for all cohorts
    vegn%gpp  = 0.0
    vegn%npp  = 0.0
    vegn%Resp = 0.0

    ! Respiration and allocation for growth
    do i = 1, vegn%n_cohorts
       
      cc => vegn%cohorts(i)
      associate ( sp => spdata(cc%species) )

      ! increment tha cohort age
      cc%age = cc%age + dt_fast_yr

      ! GPP has been obtained from a photosynthesis model (cc%gpp, kgC tree-1 time step-1)

      ! Maintenance respiration
      call plant_respiration(cc,tsoil) ! get resp per tree per time step
      cc%nsc = cc%nsc + cc%gpp - cc%resp

      ! Carbon gain
      call carbon_for_growth(cc)  ! put carbon into carbon_gain for growth

      cc%resp = cc%resp + cc%resg ! put growth respiration into total resp.
      cc%npp  = cc%gpp  - cc%resp ! kgC tree-1 time step-1

      ! Weng 2015-09-18
      cc%annualGPP  = cc%annualGPP  + cc%gpp  / cc%crownarea  ! * dt_fast_yr
      cc%annualNPP  = cc%annualNPP  + cc%npp  / cc%crownarea  ! * dt_fast_yr
      cc%annualResp = cc%annualResp + cc%resp / cc%crownarea  ! * dt_fast_yr

      ! accumulate tile-level GPP and NPP
      vegn%gpp = vegn%gpp + cc%gpp  * cc%nindivs / dt_fast_yr ! kgC m-2 yr-1
      vegn%npp = vegn%npp + cc%npp  * cc%nindivs / dt_fast_yr ! kgC m-2 yr-1
      vegn%resp= vegn%resp+ cc%resp * cc%nindivs / dt_fast_yr ! kgC m-2 yr-1

      end associate

    enddo

    cc => null()

    call vegn_leaf_fine_root_turnover(vegn, tsoil, theta)

    ! update soil carbon
    call SOMdecomposition(vegn, tsoil, theta)

    ! NEP is equal to NNP minus soil respiration
    vegn%nep = vegn%npp - vegn%rh ! kgC m-2 yr-1, though time step is daily

    ! Annual summary:
    vegn%annualGPP  = vegn%annualGPP  + vegn%gpp * dt_fast_yr
    vegn%annualNPP  = vegn%annualNPP  + vegn%npp * dt_fast_yr
    vegn%annualResp = vegn%annualResp + vegn%resp * dt_fast_yr
    vegn%annualRh   = vegn%annualRh   + vegn%rh   * dt_fast_yr ! annual Rh
    
    ! Nitrogen uptake
    call vegn_N_uptake(vegn, tsoil, theta)

    vegn%age = vegn%age + dt_fast_yr

  end subroutine vegn_C_N_budget


  subroutine vegn_growth_EW( vegn )
    !////////////////////////////////////////////////////////////////
    ! Updates cohort biomass pools, LAI, and height using accumulated 
    ! carbon_gain
    !----------------------------------------------------------------
    ! arguments
    type(tile_type), intent(inout) :: vegn

    ! local variables
    type(cohort_type), pointer :: cc    ! current cohort
    real :: CSAtot       ! total cross section area, m2
    real :: CSAsw        ! Sapwood cross sectional area, m2
    real :: CSAwd        ! Heartwood cross sectional area, m2
    real :: DBHwd        ! diameter of heartwood at breast height, m
    real :: BSWmax       ! max sapwood biomass, kg C/individual
    real :: G_LFR        ! amount of carbon spent on leaf and root growth
    real :: dSeed        ! allocation to seeds, Weng, 2016-11-26
    real :: dBL, dBR     ! tendencies of leaf and root biomass, kgC/individual
    real :: dBSW         ! tendency of sapwood biomass, kgC/individual
    real :: dBHW         ! tendency of wood biomass, kgC/individual
    real :: dDBH         ! tendency of breast height diameter, m
    real :: dCA          ! tendency of crown area, m2/individual
    real :: dHeight      ! tendency of vegetation height
    real :: dNsw         ! Nitrogen from SW to HW
    real :: sw2nsc = 0.0 ! conversion of sapwood to non-structural carbon
    real :: b,BL_u,BL_c
    real :: alphaBL, alphaBR
    real :: DBHtp
    real :: N_supply, N_demand, fNr, Nsupplyratio, extrasapwdN
    integer :: i

    DBHtp = 0.8
    fNr   = 0.25

    do i = 1, vegn%n_cohorts   
      cc => vegn%cohorts(i)

      ! call biomass_allocation(cc)
      associate (sp => spdata(cc%species)) ! F2003

      if (cc%status == LEAF_ON) then

        ! calculate the carbon to be spent on growth of leaves and roots
        G_LFR = max(0.0, min(cc%bl_max + cc%br_max - cc%bl - cc%br,  &
                            (1.0 - Wood_fract_min) * cc%carbon_gain))

        ! and distribute it between roots and leaves
        dBL  = min(G_LFR, max(0.0, &
          (G_LFR * cc%bl_max + cc%bl_max * cc%br - cc%br_max * cc%bl)/(cc%bl_max + cc%br_max) &
          ))
        dBR  = G_LFR - dBL

        ! calculate carbon spent on growth of sapwood growth
        if (cc%layer == 1.AND. cc%age > sp%maturalage) then
          dSeed =        sp%v_seed  * (cc%carbon_gain - G_LFR)
          dBSW  = (1.0 - sp%v_seed) * (cc%carbon_gain - G_LFR)
        else
          dSeed = 0.0
          dBSW  = cc%carbon_gain - G_LFR
        endif

        ! Specially for grasses, temporary
        if (sp%lifeform ==0 ) then
          dSeed = dSeed + 0.15 * G_LFR
          G_LFR = 0.85 * G_LFR
          dBR   = 0.85 * dBR
          dBL   = 0.85 * dBL
        end if
        
        ! Nitrogen effects on allocations between wood and leaves+roots

        ! Nitrogen demand by leaves, roots, and seeds (Their C/N ratios are fixed.)
        N_demand = dBL / sp%CNleaf0 + dBR / sp%CNroot0 + dSeed / sp%CNseed0

        ! Nitrogen available for all tisues, including wood
        N_supply= fNr * cc%NSN

        ! same ratio reduction for leaf, root, and seed if(N_supply < N_demand)
        if (N_demand > 0.0) then
          Nsupplyratio = MIN(1.0, N_supply / N_demand)
        else
          Nsupplyratio = 1.0
        end if

        dBSW  = dBSW + (1.0 - Nsupplyratio) * (dBL + dBR + dSeed)
        dBR   = Nsupplyratio * dBR
        dBL   = Nsupplyratio * dBL
        dSeed = Nsupplyratio * dSeed

        ! update biomass pools
        cc%bl     = cc%bl    + dBL  ! updated in vegn_int
        cc%br     = cc%br    + dBR
        cc%bsw    = cc%bsw   + dBSW
        cc%seedC  = cc%seedC + dSeed

        ! update nitrogen pools, Nitrogen allocation
        cc%NSN    = cc%NSN - N_supply
        cc%leafN  = cc%leafN  + dBL   / sp%CNleaf0
        cc%rootN  = cc%rootN  + dBR   / sp%CNroot0
        cc%seedN  = cc%seedN  + dSeed / sp%CNseed0
        cc%sapwdN = cc%sapwdN + MAX((N_supply - N_demand),0.0)

        ! Return excessiive Nitrogen in SW back to NSN
        extrasapwdN = MAX(0.0, cc%sapwdN - cc%bsw/sp%CNsw0)
        cc%NSN      = cc%NSN    + extrasapwdN ! MAX(0.0, cc%sapwdN - cc%bsw/sp%CNsw0)
        cc%sapwdN   = cc%sapwdN - extrasapwdN ! MAX(0.0, cc%sapwdN - cc%bsw/sp%CNsw0)

        ! accumulated C allocated to leaf, root, and wood
        cc%NPPleaf = cc%NPPleaf + dBL
        cc%NPProot = cc%NPProot + dBR
        cc%NPPwood = cc%NPPwood + dBSW

        ! update breast height diameter given increase of bsw
        dDBH    = dBSW / (sp%thetaBM * sp%alphaBM * cc%DBH**(sp%thetaBM - 1))
        dHeight = sp%thetaHT * sp%alphaHT * cc%DBH**(sp%thetaHT - 1) * dDBH ! Derivative wrt D of Eq. 4, Weng et al. 2015
        dCA     = sp%thetaCA * sp%alphaCA * cc%DBH**(sp%thetaCA - 1) * dDBH ! Derivative wrt D of Eq. 4, Weng et al. 2015

        cc%DBH       = cc%DBH       + dDBH
        cc%height    = cc%height    + dHeight
        cc%crownarea = cc%crownarea + dCA
        cc%leafarea  = leaf_area_from_biomass(cc%bl, cc%species, cc%layer, cc%firstlayer)
        cc%lai       = cc%leafarea / (cc%crownarea * (1.0 - sp%internal_gap_frac))

        ! conversion of sapwood to heartwood
        if (sp%lifeform>0) then

           CSAsw  = cc%bl_max / sp%LMA * sp%phiCSA * cc%height ! with Plant hydraulics, Weng, 2016-11-30
           CSAtot = 0.25 * PI * cc%DBH**2
           CSAwd  = max(0.0, CSAtot - CSAsw)
           DBHwd  = 2*sqrt(CSAwd/PI)
           BSWmax = sp%alphaBM * (cc%DBH**sp%thetaBM - DBHwd**sp%thetaBM)
           dBHW   = max(cc%bsw - BSWmax, 0.0)
           dNsw   = dBHW / cc%bsw * cc%sapwdN
           cc%bHW = cc%bHW + dBHW
           cc%bsw = cc%bsw   - dBHW

           ! Nitrogen from sapwood to heart wood
           cc%sapwdN = cc%sapwdN   - dNsw
           cc%woodN  = cc%woodN + dNsw

        endif
        
        ! update bl_max and br_max daily
        BL_u = sp%LMA * cc%crownarea*(1.0 - sp%internal_gap_frac) * sp%underLAImax
        BL_c = sp%LMA * sp%LAImax * cc%crownarea * (1.0 - sp%internal_gap_frac)

        if (cc%layer > 1 .and. cc%firstlayer == 0) then ! changed back, Weng 2014-01-23
          cc%bl_max = BL_u
          cc%br_max = sp%phiRL * cc%bl_max / (sp%LMA * sp%SRA)     ! Eq. 5 Weng et al., 2015; LAImax = Cleaf_max / LMA
        else
          if (sp%lifeform == 0) then
            cc%bl_max = BL_c
          else
            cc%bl_max = BL_u + min(cc%topyear / 5.0, 1.0) * (BL_c - BL_u)
          endif
          cc%br_max = sp%phiRL * cc%bl_max / (sp%LMA * sp%SRA)
        endif

      else
        ! LEAF_OFF: put carbon_gain back to NSC
        cc%nsc = cc%nsc + cc%carbon_gain

      endif ! LEAF_ON

      ! reset carbon acculmulation terms
      cc%carbon_gain = 0

    end associate ! F2003

    enddo
    cc => null()

  end subroutine vegn_growth_EW


  subroutine vegn_starvation( vegn )
    !////////////////////////////////////////////////////////////////
    ! Starvation due to low NSC:
    ! Kill all individuals in a cohort if NSC falls below critical 
    ! point (0.00001 * bl_max)
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn

    ! local variables
    real :: deathrate ! mortality rate, 1/year
    real :: deadtrees ! number of trees that died over the time step
    real :: loss_fine,loss_wood
    real :: lossN_fine,lossN_wood
    integer :: i, k
    type(cohort_type), pointer :: cc
    type(cohort_type), dimension(:),pointer :: ccold, ccnew

    do i = 1, vegn%n_cohorts

      cc => vegn%cohorts(i)
      associate ( sp => spdata(cc%species)  )

      ! Mortality due to starvation
      deathrate = 0.0

      ! if (cc%bsw<0 .or. cc%nsc < 0.00001*cc%bl_max .OR.(cc%layer >1 .and. sp%lifeform ==0)) then
      if (cc%bsw < 0 .or. cc%nsc < 0.00001 * cc%bl_max) then

        deathrate = 1.0
        deadtrees = cc%nindivs * deathrate !individuals / m2

        ! Carbon to soil pools
        loss_wood = deadtrees * (cc%bHW + cc%bsw)
        loss_fine = deadtrees * (cc%bl + cc%br + cc%seedC + cc%nsc)
        vegn%metabolicL  = vegn%metabolicL + fsc_fine *loss_fine + fsc_wood *loss_wood
        vegn%structuralL = vegn%structuralL + (1.0-fsc_fine)*loss_fine + (1.0-fsc_wood)*loss_wood

        ! Nitrogen to soil pools
        lossN_wood = deadtrees * (cc%woodN + cc%sapwdN)
        lossN_fine = deadtrees * (cc%leafN + cc%rootN + cc%seedN + cc%NSN)
        vegn%metabolicN = vegn%metabolicN + fsc_fine  * lossN_fine +   &
                                        fsc_wood *lossN_wood
        vegn%structuralN = vegn%structuralN +(1.-fsc_fine) * lossN_fine +   &
                                    (1.-fsc_wood)*lossN_wood

        ! update cohort individuals
        cc%nindivs = cc%nindivs*(1.0-deathrate)

      else

        deathrate = 0.0

      endif
      
      end associate

    enddo

  end subroutine vegn_starvation


  subroutine vegn_reproduction( vegn )
    !////////////////////////////////////////////////////////////////
    ! the reproduction of each canopy cohort, yearly time step
    ! calculate the new cohorts added in this step and states:
    ! tree density, DBH, woddy and fine biomass.
    ! Implements Eq. 1 in Weng et al., 2015 BG, caclulating the initial 
    ! population density of a newly produced cohort.
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn

    ! local variables
    type(cohort_type), pointer :: cc ! parent and child cohort pointers
    type(cohort_type), dimension(:),pointer :: ccold, ccnew   ! pointer to old cohort array
    integer,dimension(16) :: reproPFTs
    real,   dimension(16) :: seedC, seedN ! seed pool of productible PFTs
    real :: failed_seeds, N_failedseed !, prob_g, prob_e
    integer :: newcohorts, matchflag, nPFTs ! number of new cohorts to be created
    integer :: nCohorts, istat
    integer :: i, j, k ! cohort indices

    ! Looping through all reproductable cohorts and Check if reproduction happens
    reproPFTs = -999 ! the code of reproductive PFT
    seedC = 0.0
    seedN = 0.0
    nPFTs = 0
    do k = 1, vegn%n_cohorts
      if (cohort_can_reproduce(vegn%cohorts(k))) then
        matchflag = 0
        do i=1,nPFTs
          if (vegn%cohorts(k)%species == reproPFTs(i)) then
             seedC(i) = seedC(i) + vegn%cohorts(k)%seedC * vegn%cohorts(k)%nindivs
             seedN(i) = seedN(i) + vegn%cohorts(k)%seedN * vegn%cohorts(k)%nindivs

             ! reset parent's seed C and N
             vegn%cohorts(k)%seedC = 0.0
             vegn%cohorts(k)%seedN= 0.0
             matchflag = 1
             exit
          endif
        enddo
        if (matchflag==0) then ! when it is a new PFT, put it to the next place
            nPFTs            = nPFTs + 1 ! update the number os reproducible PFTs
            reproPFTs(nPFTs) = vegn%cohorts(k)%species ! PFT number
            seedC(nPFTs) = vegn%cohorts(k)%seedC * vegn%cohorts(k)%nindivs ! seed carbon
            seedN(nPFTs) = vegn%cohorts(k)%seedN * vegn%cohorts(k)%nindivs
            
            ! reset parent's seed C and N
            vegn%cohorts(k)%seedC = 0.0
            vegn%cohorts(k)%seedN= 0.0
        endif
      endif ! cohort_can_reproduce
    enddo ! k, vegn%n_cohorts

    newcohorts = nPFTs
    if (newcohorts == 0) return ! do nothing if no cohorts are ready for reproduction

    ! build new cohorts for seedlings
    ccold => vegn%cohorts ! keep old cohort information
    nCohorts = vegn%n_cohorts + newcohorts
    allocate(ccnew(1:nCohorts), STAT = istat)
    ccnew(1:vegn%n_cohorts) = ccold(1:vegn%n_cohorts) ! copy old cohort information
    vegn%cohorts => ccnew

    deallocate (ccold)

    ! set up new cohorts
    k = vegn%n_cohorts
    do i = 1, newcohorts
      k = k+1 ! increment new cohort index
      cc => vegn%cohorts(k)

      ! Give the new cohort an ID
      cc%ccID = MaxCohortID + i

      ! update child cohort parameters
      associate (sp => spdata(reproPFTs(i))) ! F2003

      cc%species    = reproPFTs(i)
      cc%status     = LEAF_OFF
      cc%firstlayer = 0
      cc%topyear    = 0.0
      cc%age        = 0.0
      cc%bl         = 0.0 ! sp%seedlingsize * seedC_distr(CMPT_LEAF)
      cc%br         = 0.0 ! sp%seedlingsize * seedC_distr(CMPT_ROOT)
      cc%bsw        = 0.05 * sp%seedlingsize ! * seedC_distr(CMPT_SAPWOOD)
      cc%bHW        = 0.0 ! sp%seedlingsize * seedC_distr(CMPT_WOOD)    ! sp%seedlingsize*0.05
      cc%nsc        = sp%seedlingsize - cc%bsw
      cc%seedC      = 0.0

      ! Nitrogen pools
      cc%leafN   = cc%bl  / sp%CNleaf0
      cc%rootN   = cc%br  / sp%CNroot0
      cc%sapwdN  = cc%bsw / sp%CNsw0
      cc%woodN   = cc%bHW / sp%CNwood0
      cc%seedN   = 0.0
      cc%NSN     = MAX(0.001, cc%seedN * (sp%seedlingsize / seedC(i)) - &
                   (cc%leafN + cc%rootN + cc%sapwdN + cc%woodN))
      cc%nindivs = seedC(i) / sp%seedlingsize * sp%prob_g * sp%prob_e  ! *sum(seedC_distr(:)))

      ! put failed seeds to soil carbon pools
      failed_seeds = (1.0 - sp%prob_g * sp%prob_e) * seedC(i)

      vegn%litter      = vegn%litter + failed_seeds
      vegn%metabolicL  = vegn%metabolicL +         fsc_fine  * failed_seeds
      vegn%structuralL = vegn%structuralL + (1.0 - fsc_fine) * failed_seeds

      ! Nitrogen of seeds to soil SOMs
      N_failedseed     = (1.0 - sp%prob_g * sp%prob_e) * seedN(i)
      vegn%metabolicN  = vegn%metabolicN   +        fsc_fine  * N_failedseed
      vegn%structuralN = vegn%structuralN  + (1.0 - fsc_fine) * N_failedseed

      call init_cohort_allometry(cc)

      cc%carbon_gain = 0.0
      
      cc%gpp         = 0.0
      cc%npp         = 0.0  
      cc%resp        = 0.0
      cc%resl        = 0.0
      cc%resr        = 0.0
      cc%resg        = 0.0
      
      cc%annualGPP   = 0.0
      cc%annualNPP   = 0.0 
      cc%NPPleaf     = 0.0
      cc%NPProot     = 0.0
      cc%NPPwood     = 0.0
      cc%N_up_yr     = 0.0 ! annual cohort N uptake

      end associate   ! F2003

    enddo

    MaxCohortID = MaxCohortID + newcohorts
    vegn%n_cohorts = k
    ccnew => null()

  end subroutine vegn_reproduction


  subroutine vegn_nat_mortality( vegn, deltat )
    !////////////////////////////////////////////////////////////////
    ! Natural mortality
    ! the reproduction of each canopy cohort, yearly time step
    ! calculate the new cohorts added in this step and states:
    ! tree density, DBH, woddy and fine biomass
    ! XXX Question: natural mortality is not a function of labile C? 
    !----------------------------------------------------------------
    ! TODO: update background mortality rate as a function of wood density (Weng, Jan. 07 2017)
    type(tile_type), intent(inout) :: vegn
    real, intent(in) :: deltat ! time since last mortality calculations, s

    ! local variables
    type(cohort_type), pointer :: cc => null()
    type(spec_data_type), pointer :: sp
    real :: loss_fine, loss_wood
    real :: lossN_fine,lossN_wood
    real :: deathrate ! mortality rate, 1/year
    real :: deadtrees ! number of trees that died over the time step
    real :: DBHtp, tmp
    integer :: i, k

    real, parameter :: min_nindivs = 1e-5 ! 2e-15 ! 1/m. If nindivs is less than this number, 
    
    ! then the entire cohort is killed; 2e-15 is approximately 1 individual per Earth 
    ! surface area
    !write(*,*)'total cohorts:', vegn%n_cohorts
    !write(*,'(a81)')'i,PFT,layer,density,layerfrac,dDBH,dbh,height,Acrown,wood,nsc,NPPL,NPPW,aGPP,aNPP'
    do i = 1, vegn%n_cohorts

      cc => vegn%cohorts(i)
      associate ( sp => spdata(cc%species))

      ! mortality rate can be a function of growth rate, age, and environmental
      ! conditions. Here, we only used two constants for canopy layer and under-
      ! story layer (mortrate_d_c and mortrate_d_u)
      ! for trees
      if (cc%layer > 1) then
        tmp = (1.0 + A_mort * exp(B_mort * (DBH_mort - cc%dbh)) &
                    /(1.0 +   exp(B_mort * (DBH_mort - cc%dbh))))
        deathrate = spdata(cc%species)%mortrate_d_u * tmp
      else
        deathrate = spdata(cc%species)%mortrate_d_c !sp%mortrate_d_c
      endif

      deadtrees = cc%nindivs * (1.0-exp(-deathrate*deltat/seconds_per_year)) ! individuals / m2

      ! add dead C from leaf and root pools to fast soil carbon
      loss_wood = deadtrees * (cc%bHW + cc%bsw)
      loss_fine = deadtrees * (cc%bl + cc%br + cc%seedC + cc%nsc)
      vegn%metabolicL  = vegn%metabolicL +    fsc_fine *loss_fine +    fsc_wood *loss_wood
      vegn%structuralL = vegn%structuralL + (1.-fsc_fine)*loss_fine + (1.-fsc_wood)*loss_wood

      ! Nitrogen to soil pools
      lossN_wood = deadtrees * (cc%woodN + cc%sapwdN)
      lossN_fine= deadtrees * (cc%leafN + cc%rootN + cc%seedN + cc%NSN)
      vegn%metabolicN = vegn%metabolicN +  fsc_fine * lossN_fine +   &
                                              fsc_wood * lossN_wood
      vegn%structuralN = vegn%structuralN +(1.-fsc_fine) * lossN_fine +   &
                                              (1.-fsc_wood) * lossN_wood
      ! Update plant density
      cc%nindivs = cc%nindivs-deadtrees

      end associate

    enddo

  end subroutine vegn_nat_mortality


  function cohort_can_reproduce( cc ) result( out_cohort_can_reproduce )
    !////////////////////////////////////////////////////////////////
    ! Returns true/false based on whether cohort can reproduce:
    ! - must be in top canopy layer
    ! - must be old enough (maturalage)
    ! - must have seed carbon > 0
    !----------------------------------------------------------------  
    type(cohort_type), intent(in) :: cc
    
    ! function return variable
    logical :: out_cohort_can_reproduce

    out_cohort_can_reproduce = (cc%layer == 1 .and. &
      cc%age   > spdata(cc%species)%maturalage .and. &
      cc%seedC > 0.0)

  end function


  subroutine vegn_phenology( vegn, doy ) ! daily step
    !////////////////////////////////////////////////////////////////
    ! 
    !----------------------------------------------------------------
    ! arguments
    type(tile_type), intent(inout) :: vegn
    integer, intent(in) :: doy

    ! local variables
    type(cohort_type), pointer :: cc
    integer :: i
    real    :: leaf_litter,litterN
    real    :: stem_fall, stem_litter, grassdensity   ! for grasses only
    real    :: leaf_add, root_add       ! per day
    real    :: leaf_fall, leaf_fall_rate ! per day
    real    :: root_mortality, root_mort_rate
    real    :: BL_u,BL_c
    real    :: retransN  ! retranslocation coefficient of Nitrogen
    logical :: cc_firstday = .false.
    logical :: growingseason
    logical :: TURN_ON_life, TURN_OFF_life

    retransN       = 0.5
    leaf_fall_rate = 0.075
    root_mort_rate = 0.0
    vegn%litter    = 0   ! daily litter

    ! update vegn GDD and tc_pheno
    vegn%gdd      = vegn%gdd + max(0.0, vegn%tc_daily - 278.15)
    vegn%tc_pheno = vegn%tc_pheno * 0.85 + vegn%Tc_daily * 0.15  
    
    ! ON and OFF of phenology: change the indicator of growing season for deciduous
    do i = 1,vegn%n_cohorts

      cc => vegn%cohorts(i)

      ! update GDD for each cohort
      cc%gdd = cc%gdd + max(0.0, vegn%tc_daily - 278.15) ! GDD5

      associate (sp => spdata(cc%species) )

      ! EVERGREEN: status = LEAF_ON
      ! Determine maximum leaf and root biomass for evergreen
      if (sp%phenotype==1) then

        if (cc%status==LEAF_OFF) cc%status = LEAF_ON

        BL_u = sp%LMA * cc%crownarea * (1.0 - sp%internal_gap_frac) * &
              sp%underLAImax
        !  MAX(understory_lai_factor*sp%LAImax,1.0)

        BL_c = sp%LMA * sp%LAImax * cc%crownarea * &
              (1.0 - sp%internal_gap_frac)

        if (cc%layer > 1 .and. cc%firstlayer == 0) then ! changed back, Weng 2014-01-23
          
          cc%topyear = 0.0
          cc%bl_max = BL_u
          cc%br_max = 0.8 * cc%bl_max / (sp%LMA * sp%SRA) ! sp%phiRL
        
        else

          ! update the years this cohort is in the canopy layer, Weng 2014-01-06
          if (cc%layer == 1) cc%topyear = cc%topyear + 1./365.  ! daily step
          if (cc%layer > 1) cc%firstlayer = 0 ! Just for the first year, those who were
                                          ! pushed to understory have the
                                          ! characteristics of canopy trees
          cc%bl_max = BL_u + min(cc%topyear / 5.0, 1.0) * (BL_c - BL_u)
          cc%br_max = sp%phiRL * cc%bl_max / (sp%LMA * sp%SRA)

        endif

        ! update NSNmax
        cc%NSNmax = 0.2 * cc%crownarea ! 5.0*(cc%bl_max/(sp%CNleaf0*sp%leafLS)+cc%br_max/sp%CNroot0)

      endif ! sp%phenotype==1, evergreen

      ! Determine whther its the beginning or end of season for deciduous and grasses
      TURN_ON_life = ((sp%lifeform /=0 .OR.(sp%lifeform ==0 .and.cc%layer==1)) &
             .and.          &
             sp%phenotype ==0   .and. cc%status==LEAF_OFF .and.    &
             cc%gdd > sp%gdd_crit .and. vegn%tc_pheno > sp%tc_crit_on)

      TURN_OFF_life = (sp%phenotype  == 0 .and. &
             cc%status == LEAF_ON .and. &
             vegn%tc_pheno < sp%tc_crit )

      ! Change pheno-status
      cc_firstday = .false.

      if (TURN_ON_life) then
         
         cc%status = LEAF_ON ! Turn on a growing season
         cc_firstday = .true.

      else if (TURN_OFF_life ) then
        
        cc%status = LEAF_OFF  ! Turn off a growing season
        cc%gdd   = 0.0        ! Start to counting a new cycle of GDD
        vegn%gdd = 0.0
      
      endif

      ! calculate target ammounts of leaves and fine roots of this growing season
      ! for deciduous species
      if (cc_firstday) then

        BL_u = sp%LMA*cc%crownarea*(1.0 - sp%internal_gap_frac) * &
              sp%underLAImax
          !   MAX(understory_lai_factor*sp%LAImax,1.0)

        BL_c = sp%LMA * sp%LAImax * cc%crownarea * &
            (1.0 - sp%internal_gap_frac)
        
        if (cc%layer > 1 .and. cc%firstlayer == 0) then ! changed back, Weng 2014-01-23
          
          ! update the years this cohort is in the canopy layer, Weng 2014-01-06
          cc%topyear = 0.0
          cc%bl_max = BL_u

          ! Keep understory tree's root low and constant
          cc%br_max = 0.8 * cc%bl_max / (sp%LMA * sp%SRA) ! sp%phiRL
        
        else
          ! update the years this cohort is in the canopy layer, Weng 2014-01-06
          if (cc%layer == 1) cc%topyear = cc%topyear + 1.0 
          cc%bl_max = BL_u + min(cc%topyear / 5.0, 1.0) * (BL_c - BL_u)
          cc%br_max = sp%phiRL * cc%bl_max / (sp%LMA * sp%SRA)
          if (cc%layer>1) cc%firstlayer = 0 ! those who are ushed to understory
                                            ! have the characteristics of canopy trees
        endif
       
        ! update NSNmax
        cc%NSNmax = 0.2 * cc%crownarea ! 5.0*(cc%bl_max/(sp%CNleaf0*sp%leafLS)+cc%br_max/sp%CNroot0)
     
      endif  ! first day

      ! Ending a growing season: leaves fall for deciduous
      if (cc%status == LEAF_OFF .and. cc%bl > 0.) then
        
        leaf_fall = min(leaf_fall_rate * cc%bl_max, cc%bl)
        
        if (sp%lifeform==0) then  ! grasses
            stem_fall = MIN(1.0,leaf_fall/cc%bl) * cc%bsw 
        else                    ! trees
            stem_fall = 0.0
        endif

        root_mortality = min( root_mort_rate * cc%br_max, cc%br)  ! Just for test: keep roots
        cc%nsc     = cc%nsc + l_fract * (leaf_fall+ root_mortality+stem_fall)
        cc%bl      = cc%bl  - leaf_fall
        cc%br      = cc%br  - root_mortality
        cc%bsw     = cc%bsw - stem_fall

        ! update NPP for leaves, fine roots, and wood
        cc%NPPleaf  = cc%NPPleaf - l_fract * leaf_fall
        cc%NPProot  = cc%NPProot - l_fract * root_mortality
        cc%NPPwood  = cc%NPPwood - l_fract * stem_fall
        cc%leafarea =leaf_area_from_biomass(cc%bl,cc%species,cc%layer,cc%firstlayer)
        cc%lai      = cc%leafarea/(cc%crownarea *(1.0-sp%internal_gap_frac))

        leaf_litter      = (1.-l_fract) * (leaf_fall+root_mortality+stem_fall) * cc%nindivs
        vegn%litter      = vegn%litter + leaf_litter
        vegn%metabolicL  = vegn%metabolicL +        fsc_fine *leaf_litter
        vegn%structuralL = vegn%structuralL + (1.0 - fsc_fine)*leaf_litter

        !  Nitrogen retransloaction/resorption
        if (cc%leafN+cc%rootN>0.0) cc%NSN = cc%NSN +  &
                  retransN * (cc%leafN+cc%rootN)

        litterN          = (1.-retransN) * cc%nindivs * (cc%leafN+cc%rootN)
        vegn%metabolicN  = vegn%metabolicN  +        fsc_fine  * litterN
        vegn%structuralN = vegn%structuralN + (1.0 - fsc_fine) * litterN

        ! Because not leaves and roots left in winter:
        cc%leafN = 0.0 ! cc%leafN * (1. - leaf_fall    / cc%bl)
        cc%rootN = 0.0 ! cc%rootN * (1.- root_mortality / cc%br)
        ! It's not correct here !!!!

      endif

      end associate
      cc => null()

    enddo

    ! Annual diagnostics after a growing season
    !  if(TURN_OFF_life .and. vegn%SapwoodC< 0.0000001)then
    !   do i = 1,vegn%n_cohorts
    !      cc => vegn%cohorts(i)
    !      vegn%maxNSC     = vegn%maxNSC   + cc%NSC * cc%nindivs
    !      vegn%maxSeedC   = vegn%maxSeedC + cc%seedC * cc%nindivs
    !      vegn%maxleafC   = vegn%maxleafC + cc%bl * cc%nindivs
    !      vegn%maxrootC   = vegn%maxrootC + cc%br * cc%nindivs
    !      vegn%SapwoodC   = vegn%SapwoodC + cc%bsw * cc%nindivs
    !      vegn%WoodC      = vegn%WoodC    + cc%bHW * cc%nindivs
    !      vegn%maxLAI     = vegn%maxLAI   + cc%leafarea * cc%nindivs
    !  enddo
    !  endif

  end subroutine vegn_phenology


  subroutine relayer_cohorts( vegn )
    !////////////////////////////////////////////////////////////////
    ! Arrange crowns into canopy layers according to their height and 
    ! crown areas. Implements PPA, Eq. 6 in Weng et al., 2015 BG
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn ! input cohorts

    ! local constants
    real, parameter :: tolerance = 1e-6 
    real, parameter :: layer_vegn_cover = 1.0  

    ! local variables
    integer :: idx(vegn%n_cohorts) ! indices of cohorts in decreasing height order
    integer :: i ! new cohort index
    integer :: k ! old cohort index
    integer :: L ! layer index (top-down)
    integer :: N0,N1 ! initial and final number of cohorts 
    real    :: frac ! fraction of the layer covered so far by the canopies
    type(cohort_type), pointer :: cc(:),new(:)
    real    :: nindivs

    !  rand_sorting = .TRUE. ! .False.
    
    ! rank cohorts in descending order by height. For now, assume that they are 
    ! in order
    N0 = vegn%n_cohorts
    cc => vegn%cohorts
    call rank_descending( cc(1:N0)%height, idx )
    
    ! calculate max possible number of new cohorts : it is equal to the number of
    ! old cohorts, plus the number of layers -- since the number of full layers is 
    ! equal to the maximum number of times an input cohort can be split by a layer 
    ! boundary.
    N1 = vegn%n_cohorts + int(sum(cc(1:N0)%nindivs * cc(1:N0)%crownarea))
    allocate(new(N1))

    ! copy cohort information to the new cohorts, splitting the old cohorts that 
    ! stride the layer boundaries
    i = 1
    k = 1
    L = 1
    frac = 0.0
    nindivs = cc(idx(k))%nindivs

    do 
      new(i)         = cc(idx(k))
      new(i)%nindivs = min(nindivs, (layer_vegn_cover-frac) / cc(idx(k))%crownarea)
      new(i)%layer   = L
      if (L==1) new(i)%firstlayer = 1
     
      ! if (L>1)  new(i)%firstlayer = 0  ! switch off "push-down effects"
     
      frac = frac + new(i)%nindivs * new(i)%crownarea
      nindivs = nindivs - new(i)%nindivs

      if (abs(nindivs * cc(idx(k))%crownarea) < tolerance) then
        new(i)%nindivs = new(i)%nindivs + nindivs ! allocate the remainder of individuals to the last cohort
        if (k==N0) exit ! end of loop
        k = k+1
        nindivs = cc(idx(k))%nindivs  ! go to the next input cohort
      endif

      if (abs(layer_vegn_cover - frac) < tolerance) then
        L = L+1
        frac = 0.0              ! start new layer
      endif

      !  write(*,*)i, new(i)%layer
      i = i+1

    enddo
    
    ! replace the array of cohorts
    deallocate(vegn%cohorts)
    vegn%cohorts => new ; vegn%n_cohorts = i

    ! update layer fraction for each cohort
    do i=1, vegn%n_cohorts
      vegn%cohorts%layerfrac = vegn%cohorts%nindivs * vegn%cohorts%crownarea
    enddo

  end subroutine relayer_cohorts

!============================================================================
! Plant physiology
!============================================================================

  subroutine vegen_C_gain(vegn,forcing)
    !////////////////////////////////////////////////////////////////
    ! Calculates daily carbon gain per tree based on V and self-shading of leaves
    ! It is used to generate daily GPP (photosynthesis)
    ! This subroutine can be replaced by a photosynthesis model working at hourly 
    ! time scale
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn
    type(climate_data_type),intent(in):: forcing(:)

    ! local variables
    type(cohort_type), pointer :: cc      ! current cohort
    logical:: extra_light_in_lower_layers
    real   :: f_light(10)                 ! light fraction of each layer
    real   :: V_annual                    ! max V for each layer
    real   :: f_gap                       ! additional GPP for lower layer cohorts due to gaps
    integer:: i, layer

    f_gap = 0.2 ! 0.1

    ! update accumulative LAI for each corwn layer
    vegn%CAI      = 0.0
    vegn%LAI      = 0.0
    vegn%LAIlayer = 0.0

    do i = 1, vegn%n_cohorts

      cc => vegn%cohorts(i)
      associate ( sp => spdata(cc%species) )
      cc%leafarea=leaf_area_from_biomass(cc%bl,cc%species,cc%layer,cc%firstlayer)
      cc%lai     = cc%leafarea/(cc%crownarea *(1.0-sp%internal_gap_frac))

      layer = Max (1, Min(cc%layer,9)) + 1 ! next layer

      ! LAI above this layer: Layer1: 0; Layer2: LAI of Layer1 cohorts; ...
      vegn%LAIlayer(layer) = vegn%LAIlayer(layer) + cc%leafarea * cc%nindivs
      vegn%LAI = vegn%LAI + cc%leafarea * cc%nindivs
      vegn%CAI = vegn%CAI + cc%crownarea * cc%nindivs

      end associate

    enddo

    ! Light fraction of each layer with exponential decrease following 
    ! LAI of above-lying layers
    f_light(1) = 1.0
    do i = 2, layer !MIN(int(vegn%CAI+1.0),9)
        f_light(i) = f_light(i-1) * &
                    (exp(-0.5 * vegn%LAIlayer(i)) * (1.0 - f_gap) + f_gap)
    enddo

    ! do i =1, layer !MIN(int(vegn%CAI+1.0),9)
    ! write(*,*)'f_light',layer,i,vegn%LAIlayer(i),f_light(i)
    ! enddo

    ! Assumption: no gaps  --> GPP of understory trees is too low!
    ! Assimilation of carbon for each cohort considering their light envrionment
    do i = 1, vegn%n_cohorts

      cc => vegn%cohorts(i)

      layer = Max (1, Min(cc%layer,9))

      ! Photosynthesis can be calculated by a photosynthesis model
      V_annual = f_light(layer) * spdata(cc%species)%Vannual

      if(cc%status == LEAF_ON) then
         
        ! Add temperature response function of photosynthesis
        cc%gpp = V_annual/0.5 * (1.0 - exp(-0.5 * cc%LAI))  &
                * cc%crownarea * dt_fast_yr                 &
                * exp(9000.0 * (1.0/298.16 - 1.0/vegn%tc_daily)) ! temperature response function
               ! =1.2/0.5/cc%layer**2 * (1.0 - exp(-0.5* cc%LAI)) & ! 0.5 & !
               ! * cc%crownarea * dt_fast_yr

        ! kgC tree-1 time step-1
      else

        cc%gpp = 0.0

      endif

    enddo

    cc => null()

  end subroutine vegen_C_gain


  subroutine carbon_for_growth( cc )
    !////////////////////////////////////////////////////////////////
    ! Grab carbon from NSC pool and put them into 'carbon_gain'
    ! Amount of C allocated to 'carbon_gain' is driven by NSC_supply
    ! from the NSC pool and the demand from the leaf (root) biomass 
    ! deficit (difference between actual and maximum leaf/root biomass)
    !----------------------------------------------------------------
    ! arguments
    type(cohort_type), intent(inout) :: cc

    ! local variables
    real :: NSC_supply   ! C available for growth, proportional to current NSC pool
    real :: LR_deficit   ! current difference between actual and maximum leaf (root) biomass
    real :: LR_demand    ! demand-for-growth in leaf (root) biomass, proportional to 'LR_deficit'
    real :: NSCtarget    ! target size of NSC pool, proportional to maximum leaf (root) biomass
    !real :: LR_growth,WS_growth
    real :: R_days, fNSC, fLFR, fsup

    ! Grab carbon from NSC pool and put them into "carbon_gain"
    ! modified 9/3/2013 based on Steve's suggestions
    associate ( sp => spdata(cc%species) )

    R_days    = 5.0
    fNSC      = 0.05 * days_per_year * dt_fast_yr ! 0.2(daily) -->0.2/24 (hourly) 2014-10-22
    fLFR      = 0.2 * days_per_year * dt_fast_yr
    fsup      = dt_fast_yr / spdata(cc%species)%tauNSC  ! 0.05
    NSCtarget = 3.0 * (cc%bl_max + cc%br_max)

    LR_demand  = 0.0
    NSC_supply = 0.0

    ! Determine 
    if (cc%nsc > 0.0 .and. cc%status == LEAF_ON) then
      LR_deficit = max(cc%bl_max + cc%br_max - cc%bl - cc%br, 0.0)
      LR_demand  = min(fLFR * LR_deficit, fNSC * cc%nsc)
      NSC_supply = cc%nsc * fsup ! max((cc%nsc - NSCtarget)*fsup,0.0) ! Weng 2014-01-23 for smoothing dDBH
    endif

    cc%nsc = cc%nsc - (LR_demand + NSC_supply)

    ! Deduct growth respirtion from (LR_demand + NSC_supply)
    cc%resg    = GR_factor  / (1.0 + GR_factor) * (LR_demand + NSC_supply) ! kgC tree-1 step-1
    LR_demand  = LR_demand  / (1.0 + GR_factor) ! for building up tissues
    NSC_supply = NSC_supply / (1.0 + GR_factor)

    ! carbon_gain is used to drive plant growth and reproduction
    cc%carbon_gain = cc%carbon_gain + (LR_demand + NSC_supply)

    end associate

  end subroutine carbon_for_growth


  subroutine plant_respiration( cc, tsoil )
    !////////////////////////////////////////////////////////////////
    ! Calculates leaf, root, and stem respiration ('resp')
    !----------------------------------------------------------------
    ! arguments
    type(cohort_type), intent(inout) :: cc
    real, intent(in) :: tsoil
    
    real :: tf,tfs ! thermal inhibition factors for above- and below-ground biomass
    real :: r_leaf, r_stem, r_root
    real :: Acambium  ! cambium area, m2/tree
    ! real :: LeafN     ! leaf nitrogen, kgN/Tree
    real :: NSCtarget ! used to regulation respiration rate
    
    integer :: sp ! shorthand for cohort species
    sp = cc%species

    ! temperature response function
    tf  = exp(9000.0*(1.0/298.16-1.0/tsoil))

    ! tfs = thermal_inhibition(tsoil)  ! original
    tfs = tf ! Rm_T_response_function(tsoil) ! Weng 2014-01-14
    
    ! With nitrogen model, leaf respiration is a function of leaf nitrogen
    NSCtarget = 3.0 * (cc%bl_max + cc%br_max)

    Acambium = PI * cc%DBH * cc%height * 1.2

    ! LeafN    = spdata(sp)%LNA * cc%leafarea
    r_stem   =  spdata(sp)%gamma_SW * Acambium * tf * dt_fast_yr ! kgC tree-1 step-1
    r_root   =  spdata(sp)%gamma_FR * cc%rootN * tf * dt_fast_yr ! root respiration ~ root N
    r_leaf   =  spdata(sp)%gamma_LN * cc%leafN * tf * dt_fast_yr

    cc%resp = (r_leaf + r_stem + r_root) !* max(0.0, cc%nsc/NSCtarget)
    cc%resl = r_leaf  !* max(0.0, cc%nsc/NSCtarget)
    cc%resr = r_root  !* max(0.0, cc%nsc/NSCtarget)

  end subroutine plant_respiration


  subroutine vegn_leaf_fine_root_turnover( vegn, tsoil, theta )
    !////////////////////////////////////////////////////////////////
    ! Calculates leaf and fine root turnover and adds it to soil
    ! carbon pools (metabolic and structural).
    ! Leaf (root) N turnover is proportional to fractional leaf (root) 
    ! turnover and 'leafN' ('rootN').
    !----------------------------------------------------------------
    ! arguments
    type(tile_type), intent(inout) :: vegn
    real, intent(in) :: tsoil ! average temperature of soil, deg K
    real, intent(in) :: theta ! average soil wetness, unitless

    ! local variables
    type(cohort_type), pointer :: cc  ! current cohort
    real    :: dBL, dBR               ! leaf and fine root carbon tendencies
    real    :: turnoverC,turnoverN    ! temporary var for several calculations
    integer :: i

    ! update plant carbon and nitrogen for all cohorts
    do i = 1, vegn%n_cohorts

      cc => vegn%cohorts(i)
      associate ( sp => spdata(cc%species) )

      ! Turnover of leaves and roots regardless of STATUS according to leaf
      ! longevity. Deciduous: 0; Evergreen 0.035/LMa
      ! root turnover
      dBL = cc%bl * sp%alpha_L  * dt_fast_yr
      dBR = cc%br * sp%alpha_FR * dt_fast_yr

      ! update leafN and rootN
      turnoverN = 0.0

      if (cc%bl > 0.0) then
        turnoverN = dBL / cc%bl * cc%leafN
        cc%leafN  = cc%leafN * (1.0 - dBL / cc%bl)
      endif

      if (cc%br > 0.0) then
        turnoverN = turnoverN + dBR / cc%br * cc%rootN
        cc%rootN  = cc%rootN * (1.0 - dBR / cc%br)
      endif

      cc%bl     = cc%bl - dBL
      cc%br     = cc%br - dBR
      turnoverC = dBL + dBR

      ! add turnover of leaf and root pools to soil carbon pools
      vegn%metabolicL  = vegn%metabolicL  +    fsc_fine  * turnoverC * cc%nindivs
      vegn%structuralL = vegn%structuralL + (1-fsc_fine) * turnoverC * cc%nindivs
      
      !! Nitrogen pool
      vegn%metabolicN  = vegn%metabolicN  +     fsc_fine  * turnoverN * cc%nindivs
      vegn%structuralN = vegn%structuralN + (1.-fsc_fine) * turnoverN * cc%nindivs

      end associate
    enddo

  end subroutine vegn_leaf_fine_root_turnover


  subroutine vegn_N_uptake(vegn, tsoil, theta)
    !////////////////////////////////////////////////////////////////
    ! Calculates nitrogen uptake
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn
    real, intent(in) :: tsoil ! average temperature of soil, deg K
    real, intent(in) :: theta ! average soil wetness, unitless

    ! local variables
    type(cohort_type),pointer :: cc
    real    :: rho_N_up0 = 0.02 ! hourly N uptake rate, fraction of the total mineral N
    real    :: N_roots0  = 0.1  ! root biomass at half max N-uptake rate,kg C m-2
    real    :: totNup    ! kgN m-2
    real    :: avgNup
    real    :: rho_N_up,N_roots   ! actual N uptake rate
    logical :: NSN_not_full
    integer :: i

    ! Nitrogen uptake parameter
    ! It considers competition here. How much N one can absorp depends on 
    ! how many roots it has and how many roots other individuals have.
    N_Roots  = 0.0
    vegn%N_uptake = 0.0
    if (vegn%mineralN > 0.0) then
      do i = 1, vegn%n_cohorts
        cc => vegn%cohorts(i)
        associate (sp => spdata(cc%species))
        
        ! A scheme for deciduous to get enough N:
        cc%NSNmax = 0.2 * cc%crownarea  ! 5*(cc%bl_max/sp%CNleaf0 + cc%br_max/sp%CNroot0)) ! XXX deviation from Weng et al. 2016; Eq. S3
        NSN_not_full = (cc%NSN < cc%NSNmax) !
        if (NSN_not_full) N_Roots = N_Roots + cc%br * cc%nindivs

        end associate
      enddo

      ! M-M equation for Nitrogen absoption, McMurtrie et al. 2012, Ecology & Evolution
      ! rate at given root biomass and period of time
      if (N_roots>0.0) then

        ! Add a temperature response equation herefor rho_N_up0 (Zhu Qing 2016)
        ! XXX deviation from Weng et al. 2016; Eq. S1: Additionally included (1 - exp(x)) and temperature-dependence
        rho_N_up = 1.0 - exp(-rho_N_up0 * N_roots / (N_roots0 + N_roots) * hours_per_year * dt_fast_yr) ! rate at given root density and time period
        totNup = rho_N_up * vegn%mineralN  &
                * exp(9000.0 * (1./298.16 - 1./tsoil)) ! kgN m-2 time step-1
        vegn%mineralN = vegn%mineralN - totNup
        vegn%N_uptake = totNup
        vegn%accu_Nup  = vegn%accu_Nup + totNup
        avgNup = totNup / N_roots ! kgN time step-1 kg roots-1

        ! Nitrogen uptaken by each cohort, N_uptake
        ! Distribute N uptake to cohorts proportional to their root biomass
        do i = 1, vegn%n_cohorts
          cc => vegn%cohorts(i)
          associate ( sp => spdata(cc%species) )
          NSN_not_full = (cc%NSN < cc%NSNmax)
          if (NSN_not_full) then
            cc%N_uptake = cc%br  * avgNup
            cc%nsn      = cc%nsn + cc%N_uptake
            cc%N_up_yr  = cc%N_up_yr + cc%N_uptake / cc%crownarea
          endif
          end associate
        enddo
        cc => null()
      endif ! N_roots>0

    endif
    
  end subroutine vegn_N_uptake


  subroutine SOMdecomposition( vegn, soilt, theta )
    !////////////////////////////////////////////////////////////////
    ! Nitrogen mineralization and immoblization with microbial C & N pools
    ! it's a new decomposition model with coupled C & N pools and variable 
    ! carbon use efficiency
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn
    real           , intent(in)    :: soilt ! soil temperature, deg K 
    real           , intent(in)    :: theta

    real :: CUE0 = 0.4                 ! default microbial CUE
    real :: phoMicrobial = 2.5         ! turnover rate of microbes (yr-1)
    real :: CUEfast,CUEslow
    real :: CNm = 10.0                 ! Microbial C/N ratio
    real :: NforM, fNM=0.0             ! mineral N available for microbes
    real :: micr_C_loss, fast_L_loss, slow_L_loss
    real :: runoff                     ! kg m-2 /step
    real :: etaN = 0.05.               ! loss rate of Nmineral with runoff
    real :: N_loss
    real :: DON_fast,DON_slow,DON_loss ! Dissolved organic N loss, kg N m-2 step-1
    real :: fDON = 0.0   ! 0.02        ! fractio of DON production in decomposition
    real :: fast_N_free 
    real :: slow_N_free 
    real :: CNfast, CNslow
    real :: A                          ! decomp rate reduction due to moisture and temperature
    
    ! runoff = vegn%Wrunoff * 365*24*3600 *dt_fast_yr !kgH2O m-2 s-1 ->kg m-2/time step
    runoff = vegn%Wrunoff * dt_fast_yr !kgH2O m-2 yr-1 -> kgH2O m-2/time step
    
    ! C:N ratios of soil C pools
    CNfast = vegn%metabolicL  / vegn%metabolicN
    CNslow = vegn%structuralL / vegn%structuralN

    !! C decomposition
    !  A=A_function(soilt,theta)
    !  micr_C_loss = vegn%microbialC *A*phoMicrobial* dt_fast_yr
    !  fast_L_loss = vegn%metabolicL*A*K1           * dt_fast_yr
    !  slow_L_loss = vegn%structuralL*A*K2          * dt_fast_yr

    ! C decomposition, fast and slow litter decomposition rate is not affected by 
    ! microbial pool.
    A = A_function( soilt, theta )
    micr_C_loss = vegn%microbialC  * (1.0 - exp(-A * phoMicrobial * dt_fast_yr))
    fast_L_loss = vegn%metabolicL  * (1.0 - exp(-A * K1           * dt_fast_yr))
    slow_L_loss = vegn%structuralL * (1.0 - exp(-A * K2           * dt_fast_yr))

    ! Carbon use efficiencies of microbes: Growth of microbes is driven by N
    ! released from litter decomposition (fast_L_loss / CNfast) and C:N ratio of
    ! microbes (CNm). This yields a CUE defined by the ratio of microbial growth
    ! (CNm * (fast_L_loss / CNfast + NforM)) and C from litter decomposition (fast_L_loss).
    ! xxx deviation: Is this equivalent to what's described in Eq. S9, Weng et al. (2016)?
    NforM   = fNM * vegn%mineralN
    CUEfast = MIN(CUE0, CNm * (fast_L_loss / CNfast + NforM) / fast_L_loss)
    CUEslow = MIN(CUE0, CNm * (slow_L_loss / CNslow + NforM) / slow_L_loss)

    ! update C pools
    vegn%microbialC  = vegn%microbialC  - micr_C_loss + fast_L_loss * CUEfast + slow_L_loss * CUEslow
    vegn%metabolicL  = vegn%metabolicL  - fast_L_loss
    vegn%structuralL = vegn%structuralL - slow_L_loss

    ! DON loss, revised by Weng. 2016-03-03
    fDON     = 0.0      ! XXX try: don't set leaching N loss to zero.
    DON_fast = fDON * fast_L_loss / CNfast * (1.0 - exp(-etaN * runoff))
    DON_slow = fDON * slow_L_loss / CNslow * (1.0 - exp(-etaN * runoff))
    DON_loss = DON_fast + DON_slow

    ! Nitrogen pools
    vegn%microbialN  = vegn%microbialC / CNm
    vegn%metabolicN  = vegn%metabolicN  - fast_L_loss / CNfast - DON_fast
    vegn%structuralN = vegn%structuralN - slow_L_loss / CNslow - DON_slow

    ! Mixing of microbes to litters
    ! xxx I don't understand this part: why isn't it receiving inputs from microbial turnover (micr_C_loss)?
    ! used here as a "shortcut" to litter-microbes-litter recycling?
    vegn%metabolicL = vegn%metabolicL + MLmixRatio * fast_L_loss * CUEfast
    vegn%metabolicN = vegn%metabolicN + MLmixRatio * fast_L_loss * CUEfast / CNm

    vegn%structuralL = vegn%structuralL + MLmixRatio * slow_L_loss * CUEslow
    vegn%structuralN = vegn%structuralN + MLmixRatio * slow_L_loss * CUEslow / CNm

    vegn%microbialC = vegn%microbialC - MLmixRatio * (fast_L_loss * CUEfast + slow_L_loss * CUEslow)
    vegn%microbialN = vegn%microbialC / CNm
      
    ! update mineral N pool (mineralN)
    fast_N_free = MAX(0.0, fast_L_loss * (1.0 / CNfast - CUEfast / CNm))
    slow_N_free = MAX(0.0, slow_L_loss * (1.0 / CNslow - CUEslow / CNm))

    ! N_loss = MAX(0.0,vegn%mineralN)        * A * K_nitrogen * dt_fast_yr
    N_loss = MAX(0.0, vegn%mineralN) * (1.0 - exp(-etaN * runoff - A * K_nitrogen * dt_fast_yr))

    ! record N that becomes available for vegetation N uptake
    vegn%mineralN = vegn%mineralN - N_loss + vegn%N_input * dt_fast_yr + fast_N_free + slow_N_free + micr_C_loss / CNm
    vegn%annualN   = vegn%annualN - N_loss + vegn%N_input * dt_fast_yr + fast_N_free + slow_N_free + micr_C_loss / CNm

    ! Check if soil C/N is above CN0
    fast_N_free = MAX(0.0 ,vegn%metabolicN  - vegn%metabolicL  / CN0metabolicL)
    slow_N_free = MAX(0.0 ,vegn%structuralN - vegn%structuralL / CN0structuralL)
    vegn%metabolicN  = vegn%metabolicN  - fast_N_free
    vegn%structuralN = vegn%structuralN - slow_N_free
    vegn%mineralN    = vegn%mineralN + fast_N_free + slow_N_free
    vegn%annualN     = vegn%annualN  + fast_N_free + slow_N_free

    ! Heterotrophic respiration: decomposition of litters and SOM, kgC m-2 yr-1
    vegn%rh =   (micr_C_loss + fast_L_loss * (1.0 - CUEfast) + slow_L_loss * (1.0 - CUEslow)) / dt_fast_yr

  end subroutine SOMdecomposition


  function A_function( soilt, theta ) result( A )
    !////////////////////////////////////////////////////////////////
    ! The combined reduction in decomposition rate as a funciton of TEMP and MOIST
    ! Based on CENTURY Parton et al 1993 GBC 7(4):785-809 and Bolker's copy of
    ! CENTURY code
    !----------------------------------------------------------------
    real :: A                 ! return value, resulting reduction in decomposition rate
    real, intent(in) :: soilt ! effective temperature for soil carbon decomposition
    real, intent(in) :: theta 

    real :: soil_temp ! temperature of the soil, deg C
    real :: Td        ! rate multiplier due to temp
    real :: Wd        ! rate reduction due to mositure

    ! coefficeints and terms used in temperaturex term
    real :: Topt,Tmax,t1,t2,tshl,tshr

    soil_temp = soilt-273.16

    ! EFFECT OF TEMPERATURE , ! from Bolker's century code
    Tmax=45.0;
    if (soil_temp > Tmax) soil_temp = Tmax;
    Topt=35.0;
    tshr=0.2; tshl=2.63;
    t1=(Tmax-soil_temp)/(Tmax-Topt);
    t2=exp((tshr/tshl)*(1.-t1**tshl));
    Td=t1**tshr*t2;

    if (soil_temp > -10) Td=Td+0.05;
    if (Td > 1.) Td=1.;

    ! EFFECT OF MOISTURE
    ! Linn and Doran, 1984, Soil Sci. Amer. J. 48:1267-1272
    ! This differs from the Century Wd
    ! was modified by slm/ens based on the figures from the above paper 
    !  (not the reported function)

    if(theta <= 0.3) then
       Wd = 0.2;
    else if(theta <= 0.6) then
       Wd = 0.2+0.8*(theta-0.3)/0.3
    else 
       Wd = 1.0 ! exp(2.3*(0.6-theta)); ! Weng, 2016-11-26
    endif

    A = (Td*Wd); ! the combined (multiplicative) effect of temp and water
                 ! on decomposition rates
  end function A_function


  !======================================================================
  ! Cohort management
  !======================================================================

  subroutine rank_descending( x, idx )
    !////////////////////////////////////////////////////////////////
    ! ranks array x in descending order: on return, idx() contains indices
    ! of elements of array x in descending order of x values. These codes
    ! were written by Sergey Malyshev for LM3PPA (Weng et al. 2015 Biogeosciences)
    !----------------------------------------------------------------
     real,    intent(in)  :: x(:)
     integer, intent(out) :: idx(:)
     integer :: i,n
     integer, allocatable :: t(:)
     
     n = size(x)
     do i = 1,n
        idx(i) = i
     enddo
     
     allocate(t((n+1)/2))
     call mergerank(x,idx,n,t)
     deallocate(t)

  end subroutine


  subroutine merge(x,a,na,b,nb,c,nc)
    !////////////////////////////////////////////////////////////////
    ! based on:
    ! http://rosettacode.org/wiki/Sorting_algorithms/Merge_sort#Fortran
    !----------------------------------------------------------------
     integer, intent(in) :: na,nb,nc ! Normal usage: NA+NB = NC
     real, intent(in)       :: x(*)
     integer, intent(in)    :: a(na)    ! B overlays C(NA+1:NC)
     integer, intent(in)    :: b(nb)
     integer, intent(inout) :: c(nc)
   
     integer :: i,j,k
   
     i = 1; j = 1; k = 1;
     do while(i <= na .and. j <= nb)
        if (x(a(i)) >= x(b(j))) then
           c(k) = a(i) ; i = i+1
        else
           c(k) = b(j) ; j = j+1
        endif
        k = k + 1
     enddo
     do while (i <= na)
        c(k) = a(i) ; i = i + 1 ; k = k + 1
     enddo
  end subroutine merge
   
  recursive subroutine mergerank(x,a,n,t)
    !////////////////////////////////////////////////////////////////
    !----------------------------------------------------------------
    integer, intent(in) :: n
    real,    intent(in) :: x(*)
    integer, dimension(n), intent(inout) :: a
    integer, dimension((n+1)/2), intent (out) :: t

    integer :: na,nb
    integer :: v

    if (n < 2) return
    if (n == 2) then
       if ( x(a(1)) < x(a(2)) ) then
          v = a(1) ; a(1) = a(2) ; a(2) = v
       endif
       return
    endif      
    na=(n+1)/2
    nb=n-na

    call mergerank(x,a,na,t)
    call mergerank(x,a(na+1),nb,t)

    if (x(a(na)) < x(a(na+1))) then
       t(1:na)=a(1:na)
       call merge(x,t,na,a(na+1),nb,a,n)
    endif

  end subroutine mergerank


  subroutine vegn_mergecohorts( vegn )
    !////////////////////////////////////////////////////////////////
    ! Merge similar cohorts in a tile
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn

    ! local vars
    type(cohort_type), pointer :: cc(:)    ! array to hold new cohorts
    logical :: merged(vegn%n_cohorts)      ! mask to skip cohorts that were already merged
    real, parameter :: mindensity = 1.0E-6
    integer :: i,j,k

    allocate(cc(vegn%n_cohorts))

    merged(:)=.FALSE. ; k = 0
    do i = 1, vegn%n_cohorts 
       if(merged(i)) cycle ! skip cohorts that were already merged
       k = k+1
       cc(k) = vegn%cohorts(i)
       ! try merging the rest of the cohorts into current one
       do j = i+1, vegn%n_cohorts
          if (merged(j)) cycle ! skip cohorts that are already merged
          if (cohorts_can_be_merged(vegn%cohorts(j),cc(k))) then
             call merge_cohorts(vegn%cohorts(j),cc(k))
             merged(j) = .TRUE.
          endif
       enddo
    enddo

    ! at this point, k is the number of new cohorts
    vegn%n_cohorts = k
    deallocate(vegn%cohorts)
    vegn%cohorts => cc

  end subroutine vegn_mergecohorts


  subroutine kill_lowdensity_cohorts(vegn)
    !////////////////////////////////////////////////////////////////
    ! Kill low density cohorts
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn

    ! local vars
    type(cohort_type), pointer :: cp, cc(:) ! array to hold new cohorts
    logical :: merged(vegn%n_cohorts)        ! mask to skip cohorts that were already merged
    real, parameter :: mindensity = 0.1E-4
    real :: loss_fine,loss_wood
    real :: lossN_fine,lossN_wood
    integer :: i,j,k

    ! calculate the number of cohorts with indivs>mindensity
    k = 0
    do i = 1, vegn%n_cohorts
       if (vegn%cohorts(i)%nindivs >  mindensity) k=k+1
    enddo

    if (k==0) write(*,*) 'kill_lowdensity_cohorts','All cohorts died'

    ! exclude cohorts that have low individuals
    if (k < vegn%n_cohorts) then
      
      allocate(cc(k))
      
      k=0
      do i = 1,vegn%n_cohorts
        
        cp =>vegn%cohorts(i)

        if (cp%nindivs > mindensity) then
          k = k+1
          cc(k) = cp
        else
          ! add dead C from leaf and root pools to fast soil carbon (metabolic litter)
          loss_wood  = cp%nindivs * (cp%bHW + cp%bsw)
          loss_fine = cp%nindivs * &
                   (cp%bl   + &
                    cp%br   + &
                    cp%seedC+ &
                    cp%nsc)

          vegn%metabolicL = vegn%metabolicL + fsc_fine * loss_fine +   &
                                             fsc_wood * loss_wood
          vegn%structuralL = vegn%structuralL + (1.-fsc_fine) * loss_fine +   &
                                               (1.-fsc_wood) * loss_wood

          ! Nitrogen to soil SOMs
          lossN_wood  = vegn%cohorts(i)%nindivs * (vegn%cohorts(i)%woodN + vegn%cohorts(i)%sapwdN)
          lossN_fine = vegn%cohorts(i)%nindivs * &
                   (vegn%cohorts(i)%leafN + &
                    vegn%cohorts(i)%rootN + &
                    vegn%cohorts(i)%seedN + &
                    vegn%cohorts(i)%NSN)
          vegn%metabolicN = vegn%metabolicN + fsc_fine  * lossN_fine +   &
                                             fsc_wood * lossN_wood
          vegn%structuralN = vegn%structuralN + (1.-fsc_fine) * lossN_fine +   &
                                               (1.-fsc_wood) * lossN_wood
        endif
      
      enddo
      
      vegn%n_cohorts = k
      deallocate (vegn%cohorts)
      vegn%cohorts => cc

    endif

  end subroutine kill_lowdensity_cohorts


  subroutine merge_cohorts(c1,c2)
    !////////////////////////////////////////////////////////////////
    ! Merge cohorts
    !----------------------------------------------------------------
    type(cohort_type), intent(in) :: c1
    type(cohort_type), intent(inout) :: c2
    
    real :: x1, x2 ! normalized relative weights

    if (c1%nindivs > 0.0 .or. c2%nindivs > 0.0) then
       x1 = c1%nindivs/(c1%nindivs+c2%nindivs)
       x2 = 1.0-x1
    else ! it doesn't matter because these two cohorts will be removed
       x1 = 0.5
       x2 = 0.5
    endif

    ! update number of individuals in merged cohort
    c2%nindivs     = c1%nindivs + c2%nindivs
    c2%bl          = x1*c1%bl + x2*c2%bl
    c2%br          = x1*c1%br + x2*c2%br
    c2%bsw         = x1*c1%bsw + x2*c2%bsw
    c2%bHW         = x1*c1%bHW + x2*c2%bHW
    c2%seedC       = x1*c1%seedC + x2*c2%seedC
    c2%nsc         = x1*c1%nsc + x2*c2%nsc
    c2%dbh         = x1*c1%dbh + x2*c2%dbh
    c2%height      = x1*c1%height + x2*c2%height
    c2%crownarea   = x1*c1%crownarea + x2*c2%crownarea
    c2%age         = x1*c1%age + x2*c2%age
    c2%carbon_gain = x1*c1%carbon_gain + x2*c2%carbon_gain
    c2%topyear     = x1*c1%topyear + x2*c2%topyear
    c2%leafN       = x1*c1%leafN + x2*c2%leafN
    c2%rootN       = x1*c1%rootN + x2*c2%rootN
    c2%sapwdN      = x1*c1%sapwdN + x2*c2%sapwdN
    c2%woodN       = x1*c1%woodN + x2*c2%woodN
    c2%seedN       = x1*c1%seedN + x2*c2%seedN
    c2%NSN         = x1*c1%NSN + x2*c2%NSN

    ! calculate the resulting dry heat capacity
    c2%leafarea = leaf_area_from_biomass(c2%bl, c2%species, c2%layer, c2%firstlayer)

  end subroutine merge_cohorts

  function cohorts_can_be_merged(c1,c2); logical cohorts_can_be_merged
     type(cohort_type), intent(in) :: c1,c2

     real, parameter :: mindensity = 1.0E-4
     logical :: sameSpecies, sameLayer, sameSize, sameSizeTree, sameSizeGrass, lowDensity

     sameSpecies  = c1%species == c2%species
     sameLayer    = (c1%layer == c2%layer) ! .and. (c1%firstlayer == c2%firstlayer)
     sameSizeTree = (spdata(c1%species)%lifeform > 0).and.  &
                    (spdata(c2%species)%lifeform > 0).and.  &
                   ((abs(c1%DBH - c2%DBH)/c2%DBH < 0.2 ) .or.  &
                    (abs(c1%DBH - c2%DBH)        < 0.001))  ! it'll be always true for grasses
     sameSizeGrass= (spdata(c1%species)%lifeform ==0) .and. &
                    (spdata(c2%species)%lifeform ==0) .and. &
                   (((c1%DBH == c2%DBH) .And.(c1%nsc == c2%nsc)) .OR. &
                      c1%topyear==c2%topyear)  ! it'll be always true for grasses
     sameSize = sameSizeTree .OR. sameSizeGrass
     lowDensity  = .FALSE. ! c1%nindivs < mindensity 
                           ! Weng, 2014-01-27, turned off
     cohorts_can_be_merged = sameSpecies .and. sameLayer .and. sameSize

  end function


  subroutine initialize_cohort_from_biomass( cc, btot )
    !/////////////////////////////////////////////////////////////////////////////
    ! Calculate tree height, DBH, height, and crown area by initial biomass
    ! The allometry equations are from Ray Dybzinski et al. 2011 and Forrior et al. in review
    !      HT = alphaHT * DBH ** (gamma-1)   ! DBH --> Height
    !      CA = alphaCA * DBH ** gamma       ! DBH --> Crown Area
    !      BM = alphaBM * DBH ** (gamma + 1) ! DBH --> tree biomass
    !-----------------------------------------------------------------------------
    type(cohort_type), intent(inout) :: cc
    real,intent(in)    :: btot ! total biomass per individual, kg C

    associate(sp=>spdata(cc%species))

    ! Eq. 4 in Weng et al. (2015)
    cc%DBH       = (btot / sp%alphaBM) ** ( 1.0 / sp%thetaBM )
    cc%height    = sp%alphaHT * cc%dbh ** sp%thetaHT
    cc%crownarea = sp%alphaCA * cc%dbh ** sp%thetaCA

    cc%bl_max = sp%LMA   * sp%LAImax          * cc%crownarea
    cc%br_max = sp%phiRL * sp%LAImax / sp%SRA * cc%crownarea    ! Eq. 5 Weng et al., 2015
    cc%NSNmax = 0.2 * cc%crownarea ! 5.0*(cc%bl_max/(sp%CNleaf0*sp%leafLS)+cc%br_max/sp%CNroot0)
    cc%nsc    = 2.0 * (cc%bl_max + cc%br_max)
    
    ! N pools
    cc%NSN    = 5.0 * (cc%bl_max / sp%CNleaf0 + cc%br_max / sp%CNroot0)
    cc%leafN  = cc%bl  / sp%CNleaf0
    cc%rootN  = cc%br  / sp%CNroot0
    cc%sapwdN = cc%bsw / sp%CNsw0
    cc%woodN  = cc%bHW / sp%CNwood0

    end associate

  end subroutine initialize_cohort_from_biomass


  subroutine init_cohort_allometry(cc)
    !/////////////////////////////////////////////////////////////////////////////
    ! Calculate tree height, DBH, height, and crown area by initial biomass
    ! The allometry equations are from Ray Dybzinski et al. 2011 and Forrior et al. in review
    !      HT = alphaHT * DBH ** (gamma-1)   ! DBH --> Height
    !      CA = alphaCA * DBH ** gamma       ! DBH --> Crown Area
    !      BM = alphaBM * DBH ** (gamma + 1) ! DBH --> tree biomass
    !-----------------------------------------------------------------------------
    type(cohort_type), intent(inout) :: cc

    ! local variables
    real    :: btot ! total biomass per individual, kg C

    btot = max(0.0001,cc%bHW+cc%bsw)
    associate(sp=>spdata(cc%species))

    cc%DBH        = (btot / sp%alphaBM) ** ( 1.0 / sp%thetaBM )
    ! cc%treeBM     = sp%alphaBM * cc%dbh ** sp%thetaBM
    cc%height     = sp%alphaHT * cc%dbh ** sp%thetaHT
    cc%crownarea  = sp%alphaCA * cc%dbh ** sp%thetaCA

    ! calculations of bl_max and br_max are here only for the sake of the
    ! diagnostics, because otherwise those fields are inherited from the 
    ! parent cohort and produce spike in the output, even though these spurious
    ! values are not used by the model
    cc%bl_max = sp%LMA   * sp%LAImax          * cc%crownarea
    cc%br_max = sp%phiRL * sp%LAImax / sp%SRA * cc%crownarea      ! Eq. 5 Weng et al., 2015
    cc%NSNmax = 0.2 * cc%crownarea ! 5.0*(cc%bl_max/sp%CNleaf0 + cc%br_max/sp%CNroot0)
    
    end associate

  end subroutine

  subroutine vegn_annualLAImax_update(vegn)
    !////////////////////////////////////////////////////////////////
    ! Updates LAImax according to mineral N in soil availability
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn

    ! ---- local vars
    type(cohort_type), pointer :: cc
    real   :: currLAImax,nextLAImax
    real   :: LAI_Nitrogen,ccLAImax
    integer :: i

    ! smooth inter-annual variations in N mineralization rates ('annualN')
    vegn%previousN = 0.8 * vegn%previousN + 0.2 * vegn%annualN    ! Eq. S5, Weng et al. (2016) GCB

   ! Mineral N-based LAImax
    do i = 0, MSPECIES
      associate (sp => spdata(i) )
      LAI_nitrogen = 0.5 * vegn%previousN * sp%CNleaf0 * sp%leafLS / sp%LMA    ! Eq. S4, Weng et al. (2016) GCB
      spdata(i)%LAImax = MAX(0.05, MIN(LAI_nitrogen,sp%LAI_light))
      spdata(i)%underLAImax = MIN(sp%LAImax,1.2)
      end associate
    enddo

  end subroutine vegn_annualLAImax_update


  function leaf_area_from_biomass( bl, species, layer, firstlayer ) result (area)
    !////////////////////////////////////////////////////////////////
    ! Derives leaf area from biomass using LMA (LMA/2 in understory)
    !----------------------------------------------------------------
    real,    intent(in) :: bl      ! biomass of leaves, kg C/individual
    integer, intent(in) :: species ! species
    integer, intent(in) :: layer, firstlayer

    ! function return variable
    real :: area

    ! modified by Weng 2014-01-09
    if(layer > 1 .and. firstlayer == 0)then
       area = bl / (0.5 * spdata(species)%LMA) ! half thickness for leaves in understory
    else
       area = bl / spdata(species)%LMA    
    endif

  end function


  subroutine vegn_annual_diagnostics_zero( vegn )
    !////////////////////////////////////////////////////////////////
    ! For annual update
    !----------------------------------------------------------------
    type(tile_type), intent(inout) :: vegn

    ! local variables
    type(cohort_type), pointer :: cc
    integer :: i

    vegn%annualN    = 0.0
    vegn%accu_Nup   = 0.0
    vegn%annualGPP  = 0.0
    vegn%annualNPP  = 0.0
    vegn%annualResp = 0.0
    vegn%annualRh   = 0.0
    
    vegn%maxNSC     = 0.0
    vegn%maxSeedC   = 0.0
    vegn%maxleafC   = 0.0
    vegn%maxrootC   = 0.0
    vegn%SapwoodC   = 0.0
    vegn%WoodC      = 0.0
    vegn%maxLAI     = 0.0

    do i = 1, vegn%n_cohorts
      cc => vegn%cohorts(i)
      cc%annualGPP  = 0.0
      cc%annualNPP  = 0.0
      cc%annualResp = 0.0
      cc%N_up_yr    = 0.0
      cc%NPPleaf    = 0.0
      cc%NPProot    = 0.0
      cc%NPPwood    = 0.0
      cc%DBH_ys     = cc%DBH
    enddo

  end subroutine vegn_annual_diagnostics_zero


  subroutine initialize_PFT_data()
    !////////////////////////////////////////////////////////////////
    ! Initialize species
    ! Read values from 'namelistfile', and get derived traits
    !----------------------------------------------------------------
    ! local variables
    logical :: read_from_parameter_file
    integer :: io           ! i/o status for the namelist
    integer :: ierr         ! error code, returned by i/o routines
    integer :: i
    integer :: nml_unit
    character(len=50) :: namelistfile

    namelistfile = 'params/parameters_initialstate.nml'

    read_from_parameter_file = .true.
    
    !  Read parameters from the parameter file (namelist)
    if(read_from_parameter_file)then
        nml_unit = 999
        open(nml_unit, file=namelistfile, form='formatted', action='read', status='old')
        read (nml_unit, nml=vegn_parameters_nml, iostat=io, end=10)
  10    close (nml_unit)
    endif
    write(*,nml=vegn_parameters_nml)

    ! initialize vegetation data structure
    spdata%pt         = pt
    spdata%phenotype  = phenotype
    spdata%Vmax       = Vmax
    spdata%Vannual    = Vannual
    spdata%m_cond     = m_cond
    spdata%alpha_phot = alpha_phot
    spdata%gamma_L  = gamma_L
    spdata%gamma_LN = gamma_LN
    spdata%gamma_SW = gamma_SW
    spdata%gamma_FR = gamma_FR

    spdata%rho_FR    = rho_FR
    spdata%root_r    = root_r
    spdata%root_perm = root_perm
    ! spdata%rho_N_up0 = rho_N_up0
    ! spdata%N_roots0  = N_roots0

    spdata%leaf_size = leaf_size
    spdata%tc_crit   = tc_crit
    spdata%gdd_crit  = gdd_crit

    ! Plant traits
    spdata%LMA            = LMA      ! leaf mass per unit area, kg C/m2
    spdata%LNbase         = LNbase   ! Basal leaf nitrogen per unit area, kg N/m2
    spdata%CNleafsupport  = CNleafsupport
    spdata%lifeform     = lifeform
    spdata%alphaHT      = alphaHT
    spdata%thetaHT      = thetaHT
    spdata%alphaCA      = alphaCA
    spdata%thetaCA      = thetaCA
    spdata%alphaBM      = alphaBM
    spdata%thetaBM      = thetaBM

    spdata%maturalage   = maturalage
    spdata%v_seed       = v_seed
    spdata%seedlingsize = seedlingsize
    spdata%prob_g       = prob_g
    spdata%prob_e       = prob_e
    spdata%mortrate_d_c = mortrate_d_c
    spdata%mortrate_d_u = mortrate_d_u
    spdata%rho_wood     = rho_wood
    spdata%taperfactor  = taperfactor
    spdata%LAImax       = LAImax
    spdata%underLAImax  = LAImax
    spdata%LAI_light    = LAI_light
    spdata%tauNSC       = tauNSC
    spdata%phiRL        = phiRL
    spdata%phiCSA       = phiCSA
    
    ! root turnover rate
    spdata%alpha_FR = alpha_FR

    ! Nitrogen Weng 2012-10-24
    ! spdata%CNleaf0 = CNleaf0
    spdata%CNsw0   = CNsw0
    spdata%CNwood0 = CNwood0
    spdata%CNroot0 = CNroot0
    spdata%CNseed0 = CNseed0

    spdata%internal_gap_frac = internal_gap_frac

    ! get traits derived from state variables
    do i = 0, MSPECIES
       call init_derived_species_data(spdata(i))
    enddo

  end subroutine initialize_pft_data


  subroutine init_derived_species_data( sp )
    !////////////////////////////////////////////////////////////////
    ! Derives a set of species-level traits from state variables
    ! - specific fine root area
    ! - allometry parameter
    ! - Vmax as a function of leaf N (LNbase ~ metabolic leaf N)
    ! - leaf N per unit area (sum of metabolic plus structural leaf N)
    ! - leaf life span (proportional to LMA)
    ! - leaf turnover rate
    !----------------------------------------------------------------
    type(spec_data_type), intent(inout) :: sp

    ! local variables
    integer :: j
    real :: specific_leaf_area  ! m2/kgC
    real :: leaf_life_span      ! months

    ! Specific fine root area, m2/kg C
    sp%SRA = 2.0 / (sp%root_r * sp%rho_FR)

    ! calculate alphaBM parameter of allometry. note that rho_wood was re-introduced for this calculation
    sp%alphaBM = sp%rho_wood * sp%taperfactor * PI / 4.0 * sp%alphaHT

    ! Vmax as a function of LNbase
    sp%Vmax = 0.025 * sp%LNbase ! Vmax/LNbase= 25E-6/0.8E-3 = 0.03125
    
    ! CN0 of leaves
    sp%LNA     = sp%LNbase + sp%LMA / sp%CNleafsupport
    sp%CNleaf0 = sp%LMA / sp%LNA

    !  Leaf life span as a function of LMA
    sp%leafLS = MAX(c_LLS * sp%LMA,1.0)

    ! Leaf turnover rate, (leaf longevity as a function of LMA)
    sp%alpha_L = 1.0 / sp%leafLS * sp%phenotype

  end subroutine init_derived_species_data


  subroutine initialize_vegn_tile( vegn, nCohorts )
    !////////////////////////////////////////////////////////////////
    ! Initialize cohorts and tile
    ! Read values from 'namelistfile'
    !----------------------------------------------------------------
    type(tile_type),intent(inout),pointer :: vegn
    integer,intent(in) :: nCohorts

    !--------local vars -------
    logical :: read_from_parameter_file

    type(cohort_type),dimension(:), pointer :: cc
    type(cohort_type),pointer :: cp
    integer,parameter :: rand_seed = 86456
    real    :: r
    real    :: btotal
    integer :: i, istat
    integer :: io           ! i/o status for the namelist
    integer :: ierr         ! error code, returned by i/o routines
    integer :: nml_unit
    character(len=50) :: namelistfile

    namelistfile = 'params/parameters_initialstate.nml'

    read_from_parameter_file = .true.

    !  Read parameters from the parameter file (namelist)
    if (read_from_parameter_file) then

      ! --- Generate cohorts according to "initial_state_nml" ---
      nml_unit = 999
      open(nml_unit, file=namelistfile, form='formatted', action='read', status='old')
      read (nml_unit, nml=initial_state_nml, iostat=io, end=20)
  20    close (nml_unit)
      write(*,nml=initial_state_nml)

      ! Initialize plant cohorts
      allocate(cc(1:init_n_cohorts), STAT = istat)
      vegn%cohorts => cc
      vegn%n_cohorts = init_n_cohorts
      cc => null()

      do i=1,init_n_cohorts
         cp => vegn%cohorts(i)
         cp%status  = LEAF_OFF ! ON=1, OFF=0 ! ON
         cp%layer   = 1
         cp%species = init_cohort_species(i)
         cp%ccID    =  i
         cp%nsc     = init_cohort_nsc(i)
         cp%nindivs = init_cohort_nindivs(i) ! trees/m2
         cp%bsw     = init_cohort_bsw(i)
         cp%bHW     = init_cohort_bHW(i)
         btotal     = cp%bsw + cp%bHW  ! kgC /tree
         call initialize_cohort_from_biomass(cp,btotal)
      enddo
      MaxCohortID = cp%ccID

      ! Sorting these cohorts
      call relayer_cohorts(vegn)

      ! Initial Soil pools and environmental conditions
      vegn%metabolicL  = init_fast_soil_C ! kgC m-2
      vegn%structuralL = init_slow_soil_C ! slow soil carbon pool, (kg C/m2)
      vegn%metabolicN  = vegn%metabolicL/CN0metabolicL  ! fast soil nitrogen pool, (kg N/m2)
      vegn%structuralN = vegn%structuralL/CN0structuralL  ! slow soil nitrogen pool, (kg N/m2)
      vegn%N_input     = N_input  ! kgN m-2 yr-1, N input to soil
      vegn%mineralN    = init_Nmineral  ! Mineral nitrogen pool, (kg N/m2)
      vegn%previousN   = vegn%mineralN

    else
      ! ------- Generate cohorts randomly --------
      ! Initialize plant cohorts
      allocate(cc(1:nCohorts), STAT = istat)

      vegn%cohorts => cc
      vegn%n_cohorts = nCohorts
      cc => null()
      r = rand(rand_seed)

      do i=1,nCohorts
         cp => vegn%cohorts(i)
         cp%status  = LEAF_OFF ! ON=1, OFF=0 ! ON
         cp%layer   = 1
         cp%species = INT(rand()*5)+1
         cp%nindivs = rand()/10.    ! trees/m2
         btotal     = rand()*100.0  ! kgC /tree
         call initialize_cohort_from_biomass(cp,btotal)
      enddo

      ! Sorting these cohorts
      call relayer_cohorts(vegn)

      ! ID each cohort
      do i=1,nCohorts
         cp => vegn%cohorts(i)
         cp%ccID = MaxCohortID + i
      enddo
      MaxCohortID = cp%ccID

      ! Initial Soil pools and environmental conditions
      vegn%metabolicL  = 0.2 ! kgC m-2
      vegn%structuralL = 7.0 ! slow soil carbon pool, (kg C/m2)
      vegn%metabolicN  = vegn%metabolicL/CN0metabolicL  ! fast soil nitrogen pool, (kg N/m2)
      vegn%structuralN = vegn%structuralL/CN0structuralL  ! slow soil nitrogen pool, (kg N/m2)
      vegn%N_input     = N_input  ! kgN m-2 yr-1, N input to soil
      vegn%mineralN    = 0.005  ! Mineral nitrogen pool, (kg N/m2)
      vegn%previousN   = vegn%mineralN

    endif  ! initialization: random or pre-described

  end subroutine initialize_vegn_tile

end module esdvm_mod



