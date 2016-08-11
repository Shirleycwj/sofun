module md_forcing_siterun
  !////////////////////////////////////////////////////////////////
  ! Module contains forcing variables (climate, co2, ...), and
  ! subroutines used to read forcing input files for a specific year
  ! ('forcingyear'), specifically for site scale simulations.
  ! This module is only used on the level of 'sofun', but not
  ! within 'biosphere', as these variables are passed on to 'biosphere'
  ! as arguments.
  ! Copyright (C) 2015, see LICENSE, Benjamin David Stocker
  ! contact: b.stocker@imperial.ac.uk
  !----------------------------------------------------------------
  use md_params_core, only: nmonth, ndaymonth, lunat, ndayyear, maxgrid, nlu
  use md_sofunutils, only: daily2monthly, read1year_daily, read1year_monthly, &
    getvalreal, monthly2daily_weather, monthly2daily

  implicit none

  private
  public getco2, getninput, ninput_type, gettot_ninput, getfapar, getclimate_site, getlanduse, landuse_type, climate_type

  type climate_type
    real, dimension(ndayyear) :: dtemp
    real, dimension(ndayyear) :: dprec
    real, dimension(ndayyear) :: dfsun
    real, dimension(ndayyear) :: dvpd
  end type climate_type

  type landuse_type
    real, dimension(nlu)         :: lu_area
    logical, dimension(ndayyear) :: do_grharvest
  end type landuse_type

  type ninput_type
    real, dimension(ndayyear) :: dnoy
    real, dimension(ndayyear) :: dnhx
    real, dimension(ndayyear) :: dtot
  end type ninput_type

contains

  function getco2( runname, sitename, forcingyear, const_co2, firstyeartrend, co2_forcing_file ) result( pco2 )
    !////////////////////////////////////////////////////////////////
    !  Function reads this year's atmospheric CO2 from input
    !----------------------------------------------------------------
    ! arguments
    character(len=*), intent(in) :: runname
    character(len=*), intent(in) :: sitename
    integer, intent(in) :: forcingyear
    logical, intent(in) :: const_co2
    integer, intent(in) :: firstyeartrend
    character(len=*), intent(in) :: co2_forcing_file

    ! function return variable
    real :: pco2

    ! local variables 
    integer :: readyear

    if (const_co2) then
      readyear = firstyeartrend
    else  
      readyear = forcingyear
    end if
    write(0,*) 'GETCO2: use CO2 data of year ', readyear
    pco2 = getvalreal( 'sitedata/co2/'//trim(sitename)//'/'//trim(co2_forcing_file), readyear )

  end function getco2


  function getninput( ntype, runname, sitename, forcingyear, firstyeartrend, const_ninput, ninput_noy_forcing_file, ninput_nhx_forcing_file, climate ) result( out_getninput )
    !////////////////////////////////////////////////////////////////
    ! Dummy function in 'pmodel' setup.
    !----------------------------------------------------------------
    use md_params_core, only: dummy

    ! arguments
    character(len=*), intent(in) :: ntype   ! either "ndep" or "nfert"
    character(len=*), intent(in) :: runname
    character(len=*), intent(in) :: sitename
    integer, intent(in)          :: forcingyear
    integer, intent(in) :: firstyeartrend
    logical, intent(in) :: const_ninput
    character(len=*), intent(in) :: ninput_noy_forcing_file
    character(len=*), intent(in) :: ninput_nhx_forcing_file
    type( climate_type ), dimension(maxgrid), intent(in) :: climate

    ! function return variable
    type( ninput_type ), dimension(maxgrid) :: out_getninput 

    ! local variables
    integer :: jpngr

    do jpngr=1,maxgrid
      out_getninput(jpngr)%dnoy(:) = 0.0 * climate(jpngr)%dprec(:)
      out_getninput(jpngr)%dnhx(:) = 0.0 * climate(jpngr)%dprec(:)
      out_getninput(jpngr)%dtot(:) = out_getninput(jpngr)%dnoy(:) + out_getninput(jpngr)%dnhx(:)
    end do

  end function getninput


  function gettot_ninput( ninput1, ninput2 ) result( out_gettot_ninput )
    !////////////////////////////////////////////////////////////////
    ! Function returns totals of two ninput type variables with 
    ! dimension maxgrid
    !----------------------------------------------------------------
    ! arguments
    type( ninput_type ), dimension(maxgrid), intent(in) :: ninput1, ninput2 

    ! local variables
    integer :: jpngr

    ! function return variable
    type( ninput_type ), dimension(maxgrid) :: out_gettot_ninput 

    do jpngr=1,maxgrid
      out_gettot_ninput(jpngr)%dnoy(:) = ninput1(jpngr)%dnoy(:) + ninput2(jpngr)%dnoy(:)
      out_gettot_ninput(jpngr)%dnhx(:) = ninput1(jpngr)%dnhx(:) + ninput2(jpngr)%dnhx(:)
      out_gettot_ninput(jpngr)%dtot(:) = ninput1(jpngr)%dtot(:) + ninput2(jpngr)%dtot(:)
    end do

  end function gettot_ninput


  function getfapar( runname, sitename, forcingyear, fapar_forcing_source ) result( fapar_field )
    !////////////////////////////////////////////////////////////////
    ! Function reads this year's atmospheric CO2 from input
    !----------------------------------------------------------------
    use md_params_core, only: dummy

    ! arguments
    character(len=*), intent(in) :: runname
    character(len=*), intent(in) :: sitename
    integer, intent(in) :: forcingyear
    character(len=*), intent(in) :: fapar_forcing_source

    ! function return variable
    real, dimension(nmonth,maxgrid) :: fapar_field

    ! local variables 
    integer :: jpngr
    integer :: readyear
    character(len=4) :: faparyear_char

    do jpngr=1,maxgrid
      ! create 4-digit string for year  
      write(faparyear_char,999) min( max( 2000, forcingyear ), 2014 )
      fapar_field(:,jpngr) = read1year_monthly( 'sitedata/fapar/'//trim(sitename)//'/'//faparyear_char//'/'//'fapar_'//trim(fapar_forcing_source)//'_'//trim(sitename)//'_'//faparyear_char//'.txt' )
    end do

    return
    999  format (I4.4)

  end function getfapar


  function getclimate_site( sitename, climateyear ) result ( out_climate )
    !////////////////////////////////////////////////////////////////
    ! SR reads this year's daily temperature and precipitation.
    ! Read year-2013 data after 2013
    !----------------------------------------------------------------    
    ! arguments
    character(len=*), intent(in) :: sitename
    integer, intent(in) :: climateyear

    ! local variables
    integer :: day
    integer :: jpngr = 1
    real, dimension(ndayyear) :: dvapr
    character(len=4) :: climateyear_char

    ! function return variable
    type( climate_type ), dimension(maxgrid) :: out_climate

    ! create 4-digit string for year  
    write(climateyear_char,999) climateyear

    write(0,*) 'prescribe daily climate (temp, prec, fsun, vpd) for ', trim(sitename), ' yr ', climateyear_char,'...'
    
    write(0,*) 'GETCLIMATE_SITE: use climate data of year ', climateyear_char

    jpngr = 1

    out_climate(jpngr)%dtemp(:) = read1year_daily('sitedata/climate/'//trim(sitename)//'/'//climateyear_char//'/'//'dtemp_'//trim(sitename)//'_'//climateyear_char//'.txt')
    out_climate(jpngr)%dprec(:) = read1year_daily('sitedata/climate/'//trim(sitename)//'/'//climateyear_char//'/'//'dprec_'//trim(sitename)//'_'//climateyear_char//'.txt')
    out_climate(jpngr)%dfsun(:) = read1year_daily('sitedata/climate/'//trim(sitename)//'/'//climateyear_char//'/'//'dfsun_'//trim(sitename)//'_'//climateyear_char//'.txt')
    
    dvapr(:) = read1year_daily('sitedata/climate/'//trim(sitename)//'/'//climateyear_char//'/'//'dvapr_'//trim(sitename)//'_'//climateyear_char//'.txt')

    ! calculate daily VPD based on daily vapour pressure and temperature data
    do day=1,ndayyear
      out_climate(jpngr)%dvpd(day) = calc_vpd( out_climate(jpngr)%dtemp(day), dvapr(day) )
    end do
    
    ! print*,'VPD'
    ! print*,out_climate(jpngr)%dvpd(:)

    write(0,*) '... done. Good job, beni.'

    return
    999  format (I4.4)

  end function getclimate_site


  function getlanduse( runname, sitename, forcingyear, do_grharvest_forcing_file, const_lu, firstyeartrend ) result( out_landuse )
    !////////////////////////////////////////////////////////////////
    ! Dummy function in 'pmodel' setup.
    !----------------------------------------------------------------
    ! arguments
    character(len=*), intent(in) :: runname
    character(len=*), intent(in) :: sitename
    integer, intent(in)          :: forcingyear
    character(len=*), intent(in), optional :: do_grharvest_forcing_file
    logical, intent(in) :: const_lu
    integer, intent(in) :: firstyeartrend

    ! function return variable
    type( landuse_type ) :: out_landuse

    ! xxx dummy
    out_landuse%lu_area(lunat)  = 1.0
    out_landuse%do_grharvest(:) = .false.

  end function getlanduse


  function calc_vpd( tc, vap, tmin, tmax ) result( vpd )
    !-----------------------------------------------------------------------
    ! Output:   mean monthly vapor pressure deficit, Pa (vpd)
    ! Features: Returns mean monthly vapor pressure deficit
    ! Ref:      Eq. 5.1, Abtew and Meleese (2013), Ch. 5 Vapor Pressure 
    !           Calculation Methods, in Evaporation and Evapotranspiration: 
    !           Measurements and Estimations, Springer, London.
    !             vpd = 0.611*exp[ (17.27 tc)/(tc + 237.3) ] - ea
    !             where:
    !                 tc = average daily air temperature, deg C
    !                 vap  = actual vapor pressure, kPa
    !-----------------------------------------------------------------------
    ! arguments
    real, intent(in) :: tc            ! mean monthly temperature, deg C
    real, intent(in) :: vap             ! mean monthly vapor pressure, hPa (because CRU data is in hPa)
    real, intent(in), optional :: tmin  ! (optional) mean monthly min daily air temp, deg C 
    real, intent(in), optional :: tmax  ! (optional) mean monthly max daily air temp, deg C 

    ! local variables
    real :: my_tc

    ! function return variable
    real :: vpd       !  mean monthly vapor pressure deficit, Pa

    if ( present(tmin) .and. present(tmax) ) then
      my_tc = 0.5 * (tmin + tmax)
    else
      my_tc = tc
    end if

    !! calculate VPD in units of kPa
    vpd = ( 0.611 * exp( (17.27 * my_tc)/(my_tc + 237.3) ) - 0.10 * vap )    

    !! convert to Pa
    vpd = vpd * 1.0e3

  end function calc_vpd


end module md_forcing_siterun
