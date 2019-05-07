module md_tile
  !////////////////////////////////////////////////////////////////
  ! Holds all tile-specific variables and procedurs
  ! --------------------------------------------------------------
  use md_params_core, only: npft, nlu

  implicit none

  private
  public tile_type, initglobal_tile, psoilphystype, soil_type

  !----------------------------------------------------------------
  ! physical soil state variables with memory from year to year (~pools)
  !----------------------------------------------------------------
  type psoilphystype
    real :: temp        ! soil temperature [deg C]
    real :: wcont       ! liquid soil water mass [mm = kg/m2]
    real :: snow        ! snow depth in liquid-water-equivalents [mm = kg/m2]
  end type psoilphystype

  !----------------------------------------------------------------
  ! Soil type
  !----------------------------------------------------------------
  type soil_type
    type( psoilphystype ) :: phy
  end type soil_type

  !----------------------------------------------------------------
  ! Tile type
  !----------------------------------------------------------------
  type tile_type

    ! Index that goes along with this instance of 'tile'
    integer :: luno

    ! all organic, inorganic, and physical soil variables
    type( soil_type ) :: soil

  end type tile_type

contains

  subroutine initglobal_tile( tile, ngridcells )
    !////////////////////////////////////////////////////////////////
    !  Initialisation of all _pools on all gridcells at the beginning
    !  of the simulation.
    !  June 2014
    !  b.stocker@imperial.ac.uk
    !----------------------------------------------------------------
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
    phy%wcont = 50.0
    phy%temp  = 10.0
    phy%snow  = 0.0

  end subroutine initglobal_soil_phy


end module md_tile
