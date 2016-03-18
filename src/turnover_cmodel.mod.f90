module _turnover
  !////////////////////////////////////////////////////////////////
  ! NPP_LPJ MODULE
  ! Contains the "main" subroutine 'npp' and all necessary 
  ! subroutines for handling input/output. 
  ! Every module that implements 'npp' must contain this list 
  ! of subroutines (names that way).
  !   - npp
  !   - getpar_modl_npp
  !   - initio_npp
  !   - initoutput_npp
  !   - getout_daily_npp
  !   - getout_monthly_npp
  !   - writeout_ascii_npp
  ! Required module-independent model state variables (necessarily 
  ! updated by 'waterbal') are:
  !   - daily NPP ('dnpp')
  !   - soil temperature ('xxx')
  !   - inorganic N _pools ('no3', 'nh4')
  !   - xxx 
  ! Copyright (C) 2015, see LICENSE, Benjamin David Stocker
  ! contact: b.stocker@imperial.ac.uk
  !----------------------------------------------------------------
  use _classdefs
  use _plant
    
  implicit none

  private
  public turnover

contains

  subroutine turnover( jpngr, doy )
    !////////////////////////////////////////////////////////////////
    !  Annual vegetation biomass turnover, called at the end of the
    !  year.
    !----------------------------------------------------------------
    use _classdefs
    use _phenology, only: shedleaves, params_pft_pheno
    use _params_core, only: npft

    ! arguments
    integer, intent(in) :: jpngr
    integer, intent(in) :: doy

    ! local variables
    integer :: pft
    integer :: lu
    real :: dleaf
    real :: dsapw
    real :: droot
    real :: dlabl

    do pft=1,npft

      if (ispresent(pft,jpngr)) then

        !--------------------------------------------------------------
        ! Get turnover fractions
        ! Turnover-rates are reciprocals of tissue longevity
        ! dleaf=1.0/long_leaf(pft)
        ! assuming no continuous leaf turnover
        !--------------------------------------------------------------
        if (params_pft_plant(pft)%grass) then
          if (params_pft_pheno(pft)%summergreen) then
            if (shedleaves(doy,pft)) then
              ! write(0,*) 'end of season: labile C, labile N', plabl(pft,jpngr)%c%c12, plabl(pft,jpngr)%n%n14
              dleaf = 1.0
              droot = 1.0
              dlabl = 1.0
              dsapw = 1.0
              ! write(0,*) 'complete die-off on day', doy
            else
              dleaf = params_pft_plant(pft)%k_decay_leaf
              droot = params_pft_plant(pft)%k_decay_root
              dlabl = 0.0
              dsapw = 0.0
            end if
          else
            dleaf = params_pft_plant(pft)%k_decay_leaf
            droot = params_pft_plant(pft)%k_decay_root
            dlabl = 0.0
            dsapw = 0.0
          end if   
        else
          stop 'turnover only implemented for grasses'        
        end if

        !--------------------------------------------------------------
        ! Calculate biomass turnover in this year 
        ! xxx todo         
        ! Make consistent with turnover accounted for in allocation!
        !--------------------------------------------------------------
        if ( dleaf>0.0 )                 call turnover_leaf( dleaf, pft, jpngr )
        if ( droot>0.0 )                 call turnover_root( droot, pft, jpngr )
        if ( params_pft_plant(pft)%tree .and. dsapw>0.0 ) call turnover_sapw( dsapw, pft, jpngr )
        if ( dlabl>0.0 )                 call turnover_labl( dlabl, pft, jpngr )

        ! ! add labile C and N to litter as well
        ! if (dlabl>0.0) then
        !   write(0,*) 'TURNOVER: WARNING LABILE C AND N ARE SET TO ZERO WITHOUT MASS CONSERVATION'
        !   lb_turn%c%c12 = 0.0
        !   lb_turn%n%n14 = 0.0
        !   ! call cmvRec( lb_turn%c, lb_turn%c, plitt_bg(pft,jpngr)%c, outaCveg2lit(pft,jpngr), scale=nind(pft,jpngr) )
        !   ! call nmvRec( lb_turn%n, lb_turn%n, plitt_bg(pft,jpngr)%n, outaNveg2lit(pft,jpngr), scale=nind(pft,jpngr) )
        !   ! write(0,*) 'end of growing season-plabl:', plabl
        !   ! write(0,*) 'moving C and N to exudates and ninorg:', lb_turn
        ! end if

      endif                   !present
    enddo                     !pft

  end subroutine turnover


  subroutine turnover_leaf( dleaf, pft, jpngr )
    !//////////////////////////////////////////////////////////////////
    ! Execute turnover of fraction dleaf for leaf pool
    !------------------------------------------------------------------
    use _plant, only: update_foliage_vars

    ! arguments
    real, intent(in)    :: dleaf
    integer, intent(in) :: pft
    integer, intent(in) :: jpngr

    ! local variables
    type(orgpool) :: lm_turn

    ! determine absolute turnover
    lm_turn = orgfrac( dleaf, pleaf(pft,jpngr) ) ! leaf turnover

    ! reduce leaf mass and root mass
    call orgsub( lm_turn, pleaf(pft,jpngr) )

    ! add all organic (fixed) C to litter
    call cmvRec( lm_turn%c, lm_turn%c, plitt_af(pft,jpngr)%c, outaCveg2lit(pft,jpngr), scale=nind(pft,jpngr))

    ! retain fraction of N
    call nmv( nfrac( params_plant%f_nretain, lm_turn%n ), lm_turn%n, plabl(pft,jpngr)%n )

    ! rest goes to litter
    call nmvRec( lm_turn%n, lm_turn%n, plitt_af(pft,jpngr)%n, outaNveg2lit(pft,jpngr), scale=nind(pft,jpngr) )

    !--------------------------------------------------------------
    ! Update foliage-related state variables (lai_ind, fpc_grid, and fapar_ind)
    ! This assumes that leaf canopy-average traits do not change upon changes in LAI.
    !--------------------------------------------------------------
    call update_foliage_vars( pft, jpngr )

  end subroutine turnover_leaf


  subroutine turnover_root( droot, pft, jpngr )
    !//////////////////////////////////////////////////////////////////
    ! Execute turnover of fraction droot for root pool
    !------------------------------------------------------------------
    use _classdefs

    ! arguments
    real, intent(in)    :: droot
    integer, intent(in) :: pft
    integer, intent(in) :: jpngr

    ! local variables
    type(orgpool) :: rm_turn

    ! determine absolute turnover
    rm_turn = orgfrac( droot, proot(pft,jpngr) ) ! root turnover

    ! reduce leaf mass and root mass
    call orgsub( rm_turn, proot(pft,jpngr) )

    ! add all organic (fixed) C to litter
    call cmvRec( rm_turn%c, rm_turn%c, plitt_bg(pft,jpngr)%c, outaCveg2lit(pft,jpngr), scale=nind(pft,jpngr))

    ! retain fraction of N
    call nmv( nfrac( params_plant%f_nretain, rm_turn%n ), rm_turn%n, plabl(pft,jpngr)%n )

    ! rest goes to litter
    call nmvRec( rm_turn%n, rm_turn%n, plitt_bg(pft,jpngr)%n, outaNveg2lit(pft,jpngr), scale=nind(pft,jpngr) )

  end subroutine turnover_root


  subroutine turnover_labl( dlabl, pft, jpngr )
    !//////////////////////////////////////////////////////////////////
    ! Execute turnover of fraction dlabl for labl pool
    !------------------------------------------------------------------
    ! arguments
    real, intent(in)    :: dlabl
    integer, intent(in) :: pft
    integer, intent(in) :: jpngr

    ! local variables
    type(orgpool) :: lb_turn

    ! determine absolute turnover
    lb_turn = orgfrac( dlabl, plabl(pft,jpngr) ) ! labl turnover

    ! reduce labl mass and root mass
    call orgsub( lb_turn, plabl(pft,jpngr) )

    ! add all organic (fixed) C to litter
    call cmvRec( lb_turn%c, lb_turn%c, plitt_af(pft,jpngr)%c, outaCveg2lit(pft,jpngr), scale=nind(pft,jpngr))

    ! rest goes to litter
    call nmvRec( lb_turn%n, lb_turn%n, plitt_af(pft,jpngr)%n, outaNveg2lit(pft,jpngr), scale=nind(pft,jpngr) )

  end subroutine turnover_labl

  subroutine turnover_sapw( dsapw, pft, jpngr )
    !//////////////////////////////////////////////////////////////////
    ! Execute turnover of fraction dsapw for sapw pool
    !------------------------------------------------------------------
    ! arguments
    real, intent(in)    :: dsapw
    integer, intent(in) :: pft
    integer, intent(in) :: jpngr

    ! ! local variables
    ! type(orgpool) :: lm_turn

    ! ! determine absolute turnover
    ! lm_turn = orgfrac( dsapw, psapw(pft,jpngr) ) ! sapw turnover

    ! ! reduce sapw mass and root mass
    ! call orgsub( lm_turn, psapw(pft,jpngr) )

    ! ! add all organic (fixed) C to litter
    ! call cmvRec( lm_turn%c, lm_turn%c, plitt_af(pft,jpngr)%c, outaCveg2lit(pft,jpngr), scale=nind(pft,jpngr))

    ! ! retain fraction of N
    ! ! xxx try
    ! F_NRETAIN = 0.0
    ! call nmv( nfrac( F_NRETAIN, lm_turn%n ), lm_turn%n, plabl(pft,jpngr)%n )

    ! ! rest goes to litter
    ! call nmvRec( lm_turn%n, lm_turn%n, plitt_af(pft,jpngr)%n, outaNveg2lit(pft,jpngr), scale=nind(pft,jpngr) )

    ! !--------------------------------------------------------------
    ! ! Update foliage-related state variables (lai_ind, fpc_grid, and fapar_ind)
    ! !--------------------------------------------------------------
    ! call update_foliage_vars( pft, jpngr )

  end subroutine turnover_sapw

end module _turnover
