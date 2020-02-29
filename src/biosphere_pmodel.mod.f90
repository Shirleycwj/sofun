module md_biosphere

  use md_params_core
  use md_classdefs
  use md_plant, only: plant_type, plant_fluxes_type, initglobal_plant, getout_daily_plant, getout_annual_plant, getpar_modl_plant, initoutput_plant
  use md_params_soil, only: paramtype_soil
  use md_waterbal, only: solartype, waterbal, solar, getout_daily_waterbal, initoutput_waterbal, getpar_modl_waterbal, initio_nc_waterbal, writeout_nc_waterbal, get_rlm_waterbal, getrlm_daily_waterbal  ! , init_rlm_waterbal
  use md_gpp, only: outtype_pmodel, getpar_modl_gpp, initoutput_gpp, gpp, getout_daily_gpp, getout_annual_gpp, initio_nc_gpp, writeout_nc_gpp
  use md_vegdynamics, only: vegdynamics
  use md_tile, only: tile_type, tile_fluxes_type, initglobal_tile, initdaily_tile_fluxes
  use md_interface, only: getout_daily_forcing, initoutput_forcing, initio_nc_forcing, writeout_nc_forcing
  use md_soiltemp, only: getout_daily_soiltemp, soiltemp, initoutput_soiltemp
  use md_sofunutils, only: calc_patm

  implicit none

  private
  public biosphere_annual

  !----------------------------------------------------------------
  ! Module-specific (private) variables
  !----------------------------------------------------------------
  ! derived types from L1 modules
  type(tile_type),         allocatable, dimension(:,:) :: tile             ! has gridcell-dimension because values are stored between years
  type(tile_fluxes_type),  allocatable, dimension(:)   :: tile_fluxes      ! has no gridcell-dimension values need not be recorded

  ! type(plant_type),        allocatable, dimension(:,:) :: plant            ! has gridcell-dimension because values are stored between years
  ! type(plant_fluxes_type), allocatable, dimension(:)   :: plant_fluxes     ! has no gridcell-dimension values need not be recorded

  ! ! derived types from L2 modules
  ! type(solartype) :: solar

contains

  function biosphere_annual() result( out_biosphere )
    !////////////////////////////////////////////////////////////////
    ! function BIOSPHERE_annual calculates net ecosystem exchange (nee)
    ! in response to environmental boundary conditions (atmospheric 
    ! CO2, temperature, Nitrogen deposition. This SR "replaces" 
    ! LPJ, also formulated as subroutine.
    ! Copyright (C) 2015, see LICENSE, Benjamin David Stocker
    ! contact: b.stocker@imperial.ac.uk
    !----------------------------------------------------------------
    use md_interface, only: interface, outtype_biosphere
    use md_sofunutils, only: daily2monthly
  
    ! return variable
    type(outtype_biosphere) :: out_biosphere

    ! local variables
    integer :: dm, moy, jpngr, doy
    logical, save           :: init_daily = .true.   ! is true only on the first day of the simulation 
    logical, parameter      :: verbose = .false.     ! change by hand for debugging etc.

    !----------------------------------------------------------------
    ! INITIALISATIONS
    !----------------------------------------------------------------
    if (interface%steering%init) then

      !----------------------------------------------------------------
      ! GET MODEL PARAMETERS
      ! read model parameters that may be varied for optimisation
      !----------------------------------------------------------------
      if (verbose) print*, 'getpar_modl() ...'
      call getpar_modl_plant()
      call getpar_modl_waterbal()
      call getpar_modl_gpp()
      if (verbose) print*, '... done'

      !----------------------------------------------------------------
      ! Initialise pool variables and/or read from restart file (not implemented)
      !----------------------------------------------------------------
      if (verbose) print*, 'initglobal_() ...'
      allocate( tile(nlu, size(interface%grid)) )
      allocate( tile_fluxes(nlu) )
      ! allocate( plant(       npft, size(interface%grid)) )
      ! allocate( plant_fluxes(npft                      ) )
      call initglobal_tile(  tile(:,:),  size(interface%grid) )
      if (verbose) print*, '... done'

    endif 

    !----------------------------------------------------------------
    ! Open NetCDF output files (one for each year)
    !----------------------------------------------------------------
    if (.not.interface%params_siml%is_calib) then
      if (verbose) print*, 'initio_nc_() ...'
      call initio_nc_forcing()
      call initio_nc_gpp()
      call initio_nc_waterbal()
      if (verbose) print*, '... done'
    end if
    
    !----------------------------------------------------------------
    ! Initialise output variables for this year
    !----------------------------------------------------------------
    if (.not.interface%params_siml%is_calib) then
      if (verbose) print*, 'initoutput_() ...'
      call initoutput_waterbal( size(interface%grid) )
      call initoutput_gpp(      size(interface%grid) )
      call initoutput_plant(    size(interface%grid) )
      call initoutput_forcing(  size(interface%grid) )
      call initoutput_soiltemp( size(interface%grid) )
      if (verbose) print*, '... done'
    end if

    ! ! additional initialisation for rolling annual mean calculations (also needed in calibration mode)
    ! call init_rlm_waterbal( size(interface%grid) )

    !----------------------------------------------------------------
    ! LOOP THROUGH GRIDCELLS
    !----------------------------------------------------------------
    if (verbose) print*,'looping through gridcells ...'
    gridcellloop: do jpngr=1,size(interface%grid)

      if (interface%grid(jpngr)%dogridcell) then

        if (verbose) print*,'----------------------'
        if (verbose) print*,'JPNGR: ', jpngr
        if (verbose) print*,'----------------------'

        !----------------------------------------------------------------
        ! calculate constant atmospheric pressure as a function of elevation
        !----------------------------------------------------------------
        interface%climate(jpngr)%dpatm(:) = calc_patm(interface%grid(jpngr)%elv)

        !----------------------------------------------------------------
        ! LOOP THROUGH MONTHS
        !----------------------------------------------------------------
        doy=0
        monthloop: do moy=1,nmonth

          !----------------------------------------------------------------
          ! LOOP THROUGH DAYS
          !----------------------------------------------------------------
          dayloop: do dm=1,ndaymonth(moy)
            doy=doy+1

            if (verbose) print*,'----------------------'
            if (verbose) print*,'YEAR, Doy ', interface%steering%year, doy
            if (verbose) print*,'----------------------'

            !----------------------------------------------------------------
            ! initialise daily updated variables 
            !----------------------------------------------------------------
            if (verbose) print*,'calling initdaily_() ...'
            call initdaily_tile_fluxes( tile_fluxes(:) )
            if (verbose) print*,'... done.'

            !----------------------------------------------------------------
            ! Get radiation based on daily temperature, sunshine fraction, and 
            ! elevation.
            !----------------------------------------------------------------
            if (verbose) print*,'calling solar() ... '
            if (verbose) print*,'    with argument lat = ', interface%grid(jpngr)%lat
            if (verbose) print*,'    with argument elv = ', interface%grid(jpngr)%elv
            if (verbose) print*,'    with argument dfsun (ann. mean) = ', sum( interface%climate(jpngr)%dfsun(:) / ndayyear )
            if (verbose) print*,'    with argument dppfd (ann. mean) = ', sum( interface%climate(jpngr)%dppfd(:) / ndayyear )
            call solar( tile_fluxes(:) &
                        interface%grid(jpngr), & 
                        interface%climate(doy,jpngr)%dfsun,  &
                        doy
                        )
            if (verbose) print*,'... done'

            !----------------------------------------------------------------
            ! update canopy and tile variables and simulate daily 
            ! establishment / sprouting
            !----------------------------------------------------------------
            if (verbose) print*,'calling vegdynamics() ... '
            call vegdynamics( tile(:,jpngr), &
                              plant(:,jpngr), &
                              solar, &
                              out_pmodel(:,:), &
                              interface%vegcover(jpngr)%dfapar(doy), &
                              interface%fpc_grid(:,jpngr) &
                              )
            if (verbose) print*,'... done'


            !----------------------------------------------------------------
            ! calculate GPP
            !----------------------------------------------------------------
            if (verbose) print*,'calling gpp() ... '
            call gpp( tile(:,jpngr), &
                      tile_fluxes(:), &
                      interface%pco2, &
                      interface%climate(doy,jpngr), &
                      do_soilmstress, &
                      do_tempstress, &
                      init_daily &
                      )
            if (verbose) print*,'... done'

            !----------------------------------------------------------------
            ! get soil moisture, and runoff
            !----------------------------------------------------------------
            if (verbose) print*,'calling waterbal() ... '
            call waterbal(  tile(:,jpngr), &
                            tile_fluxes(:), &
                            interface%grid(jpngr), &
                            interface%climate(doy,jpngr), &
                            doy &
                            )
            if (verbose) print*,'... done'

            

            ! !----------------------------------------------------------------
            ! ! calculate soil temperature
            ! !----------------------------------------------------------------
            ! if (verbose) print*, 'calling soiltemp() ... '
            ! call soiltemp(&
            !               tile(:,jpngr)%soil, &
            !               interface%climate(jpngr)%dtemp(:), &
            !               size(interface%grid), &
            !               interface%steering%init, &
            !               jpngr, & 
            !               moy, & 
            !               doy & 
            !               )
            ! if (verbose) print*, '... done'

            !----------------------------------------------------------------
            ! collect from daily updated state variables for annual variables
            !----------------------------------------------------------------
            if (.not.interface%params_siml%is_calib) then
              if (verbose) print*,'calling getout_daily() ... '
              call getout_daily_waterbal( tile(:,jpngr), tile_fluxes(:), jpngr, doy )

              call getout_daily_gpp( out_pmodel(:,moy), plant_fluxes(:), jpngr, doy )
              call getout_daily_plant( plant(:,jpngr), plant_fluxes(:), jpngr, moy, doy )
              call getout_daily_forcing( jpngr, moy, doy )
              call getout_daily_soiltemp( jpngr, moy, doy, tile(:,jpngr)%soil%phy )
              if (verbose) print*,'... done'
            end if

            call getrlm_daily_waterbal( tile(:,jpngr), tile_fluxes(:), jpngr, doy )

            !----------------------------------------------------------------
            ! populate function return variable
            !----------------------------------------------------------------
            !if (npft>1) stop 'think about npft > 1'
            out_biosphere%fapar(doy)   = plant(1,jpngr)%fapar_ind
            out_biosphere%gpp(doy)     = plant_fluxes(1)%dgpp
            out_biosphere%transp(doy)  = plant_fluxes(1)%dtransp
            out_biosphere%latenth(doy) = plant_fluxes(1)%dlatenth

            init_daily = .false.

          end do dayloop

        end do monthloop

        !----------------------------------------------------------------
        ! collect annual output
        !----------------------------------------------------------------
        if (.not.interface%params_siml%is_calib) then
          if (verbose) print*,'calling getout_annual_() ... '
          call getout_annual_plant( plant(:,jpngr), jpngr )
          call getout_annual_gpp( jpngr )
          if (verbose) print*,'... done'
        end if

      end if
    end do gridcellloop

    !----------------------------------------------------------------
    ! Get rolling multi-year averages (needs to store entire arrays)
    !----------------------------------------------------------------
    call get_rlm_waterbal( tile(:,:)%soil%phy, interface%steering%init )

    !----------------------------------------------------------------
    ! Write to NetCDF output
    !----------------------------------------------------------------
    if (.not.interface%params_siml%is_calib) then
      if (verbose) print*,'calling writeout_nc_() ... '
      call writeout_nc_forcing()
      call writeout_nc_gpp()
      call writeout_nc_waterbal()
      if (verbose) print*,'... done'
    end if


    if (interface%steering%finalize) then
      !----------------------------------------------------------------
      ! Finazlize run: deallocating memory
      !----------------------------------------------------------------
      deallocate( tile )
      deallocate( tile_fluxes )
      deallocate( plant )
      deallocate( plant_fluxes )
      
    end if

    if (verbose) print*,'Done with biosphere for this year. Guete Rutsch!'

  end function biosphere_annual

end module md_biosphere
