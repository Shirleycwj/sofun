module md_tile
  !////////////////////////////////////////////////////////////////
  ! Holds all tile-specific variables and procedurs
  ! --------------------------------------------------------------
  use md_params_core, only: npft, nlu
  use md_params_soil, only: paramtype_soil

  implicit none

  private
  public tile_type, tile_fluxes_type, initglobal_tile, psoilphystype, soil_type, initdaily_tile

  !----------------------------------------------------------------
  ! physical soil state variables with memory from year to year (~pools)
  !----------------------------------------------------------------
  type psoilphystype
    real :: temp        ! soil temperature [deg C]
    real :: wcont       ! liquid soil water mass [mm = kg/m2]
    real :: wscal       ! relative soil water content, between 0 and 1
    real :: snow        ! snow depth in liquid-water-equivalents [mm = kg/m2]
    real :: rlmalpha    ! rolling mean of annual mean alpha (AET/PET)
  end type psoilphystype

  !----------------------------------------------------------------
  ! Soil type
  !----------------------------------------------------------------
  type soil_type
    type( psoilphystype )  :: phy
    type( paramtype_soil ) :: params
  end type soil_type
  !----------------------------------------------------------------
  ! Tile type with year-to-year memory
  !----------------------------------------------------------------
  type tile_type

    ! Index that goes along with this instance of 'tile'
    integer :: luno

    ! all organic, inorganic, and physical soil variables
    type( soil_type ) :: soil

  end type tile_type

  !----------------------------------------------------------------
  ! Variables with no memory
  !----------------------------------------------------------------
  type tile_fluxes_type

    real :: sw        ! evaporative supply rate (mm/h)
    real :: dro       ! daily runoff (mm = kg/m2)
    real :: dfleach   ! daily fraction of total mineral soil nutrients leached 

  end type tile_fluxes_type

contains

  subroutine initglobal_tile( tile, ngridcells )
    !////////////////////////////////////////////////////////////////
    !  Initialisation of all _pools on all gridcells at the beginning
    !  of the simulation.
    !  June 2014
    !  b.stocker@imperial.ac.uk
    !----------------------------------------------------------------
    use md_interface, only: interface

    ! argument
    type( tile_type ), dimension(nlu,ngridcells), intent(inout) :: tile
    integer, intent(in) :: ngridcells

    ! local variables
    integer :: lu
    integer :: jpngr

    ! attribute land unit numbers
    do jpngr=1,ngridcells
      do lu=1,nlu
        
        tile(lu,jpngr)%luno = lu

        ! initialise soil variables
        call initglobal_soil( tile(lu,jpngr)%soil )
        ! Copy soil parameters
        tile(lu,jpngr)%soil%params = interface%soilparams(jpngr)

      end do
    end do

  end subroutine initglobal_tile


  subroutine initglobal_soil( soil )
    !////////////////////////////////////////////////////////////////
    ! initialise soil variables globally
    !----------------------------------------------------------------
    ! argument
    type( soil_type ), intent(inout) :: soil

    call initglobal_soil_phy( soil%phy )

  end subroutine initglobal_soil


  subroutine initglobal_soil_phy( phy )
    !////////////////////////////////////////////////////////////////
    ! initialise physical soil variables globally
    !----------------------------------------------------------------
    ! argument
    type( psoilphystype ), intent(inout) :: phy

    ! initialise physical soil variables
    phy%wcont    = 50.0
    phy%temp     = 10.0
    phy%snow     = 0.0
    phy%rlmalpha = 0.0

  end subroutine initglobal_soil_phy


  subroutine initdaily_tile( tile_fluxes )
    !////////////////////////////////////////////////////////////////
    ! Initialises all daily variables within derived type 'soilphys'.
    !----------------------------------------------------------------
    ! arguments
    type(tile_fluxes_type), dimension(nlu), intent(inout) :: tile_fluxes

    tile_fluxes(:)%sw      = 0.0   ! evaporative supply rate (mm/h)
    tile_fluxes(:)%dro     = 0.0   ! daily runoff (mm = kg/m2)
    tile_fluxes(:)%dfleach = 0.0   ! daily fraction of total mineral soil nutrients leached 

  end subroutine initdaily_tile

end module md_tile
