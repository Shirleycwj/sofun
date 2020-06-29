from subprocess import call
import os
import os.path

##--------------------------------------------------------------------
## Simulation suite for site-scale simulations. Chose any of ...
## - "swissface"
## - "fluxnet"
## - "fluxnet2015"
## - "fluxnet_cnmodel"
## - "gcme"
## - "campi"
## - "campi_cmodel"
## - "fluxnet_fixalloc"
## - "atkin"
## - "atkinfull"
## - "olson"
## - "olson_cmodel"
## - "swbm"
## - "ameriwue"
## - "fluxnet2015_cmodel"
##--------------------------------------------------------------------
## For global simulations, set name to 'global'.
## - "global"
##--------------------------------------------------------------------
## This links NetCDF input files from directories mirrored locally from
## /work/bstocker/labprentice/data on Imperial's HPC CX1 server into the 
## input directory structure required for SOFUN.
##--------------------------------------------------------------------
name = 'global'
# name = 'fluxnet2015'

##--------------------------------------------------------------------
## For an example simulation (simulation name 'EXAMPLE_global'), set 
## this to true 
##--------------------------------------------------------------------
example = False

##--------------------------------------------------------------------
## Manually edit the root directory for the local mirror of 
## the data directory (e.g., /cluster/home/bestocke/data on Euler; this
## is used for linking input files).
##--------------------------------------------------------------------
# dataroot = '/cluster/home/bestocke/data/'   # to run on Euler
dataroot = '/Users/benjaminstocker/data/'     # to run on Beni's iMac

##--------------------------------------------------------------------
## Link directories
##--------------------------------------------------------------------
## link output direcories
os.system( 'unlink output_nc' )
os.system( 'ln -svf ~/sofun_outputs/output_nc_' + name + ' output_nc'  )

##--------------------------------------------------------------------
## Copy parameter files
##--------------------------------------------------------------------
os.system( 'mkdir params' )
os.system( 'cp params_std/* params' )


## link NetCDF input files for global simulations
if name == 'global':
	##--------------------------------------
	## GLOBAL SIMULATIONS
	##--------------------------------------

	## Grid information
	##--------------------------------------
	dirn = 'input/global/grid'
	os.system( 'mkdir -p ' + dirn )

	## elevation
	call(['ln', '-svf', dataroot + 'watch_wfdei/WFDEI-elevation.nc', dirn ])

	## land masks at 1 deg and 0.5 deg resolution
	call(['ln', '-svf', dataroot + 'landmasks/gicew_1x1deg.cdf', dirn ])
	call(['ln', '-svf', dataroot + 'landmasks/gicew_halfdeg.cdf', dirn ])

	## CO2
	##--------------------------------------
	dirn = 'input/global/co2'
	os.system( 'mkdir -p ' + dirn )
	call(['ln', '-svf', dataroot + 'co2/cCO2_rcp85_const850-1765.dat', dirn ])

	## fapar (fapar3g)
	##--------------------------------------
	dirn = 'input/global/fapar'
	os.system( 'mkdir -p ' + dirn )

	# call(['ln', '-svf', dataroot + 'fAPAR/fAPAR3g_v2/fAPAR3g_v2_1982_2016_FILLED.nc', dirn ])
	# os.system('echo \'fapar_forcing_source                    fapar3g\' >./input/dfapar_source.txt')

	# call(['ln', '-svf', dataroot + 'modis_ndvi_evi_zmaw/halfdeg/modis_vegetation__LPDAAC__v5__0.5deg_FILLED.nc', dirn ])
	# os.system('echo \'fapar_forcing_source                    evi_modis\' >./input/dfapar_source.txt')

	call(['ln', '-svf', dataroot + 'modis_lai_fpar_zmaw/MODIS-C006_MOD15A2__LAI_FPAR__LPDAAC__GLOBAL_0.5degree__UHAM-ICDC__2000_2018__MON__fv0.02.nc', dirn ])
	os.system('echo \'fapar_forcing_source                    fpar_modis\' >./input/dfapar_source.txt')


	## soil
	##--------------------------------------
	dirn = 'input/global/soil'
	os.system( 'mkdir -p ' + dirn )
	call(['ln', '-svf', dataroot + 'soil/soilgrids/whc_soilgrids_halfdeg_FILLED.nc', dirn ])
	call(['ln', '-svf', dataroot + 'soil/hwsd/soil_type_hwsd_halfdeg.cdf', dirn ])

	## land cover
	##--------------------------------------
	dirn = 'input/global/landcover'
	os.system( 'mkdir -p ' + dirn )
	call(['ln', '-svf', dataroot + 'landcover/modis_landcover_halfdeg_2010_FILLED.nc', dirn ])


	## WATCH-WFDEI climate input data
	##--------------------------------------
	dirn = './input/global/climate'
	if not os.path.isdir( dirn ):
		os.system( 'mkdir -p ' + dirn )

	## temperature
	src = dataroot + 'watch_wfdei/Tair_daily/*'
	dst = 'input/global/climate/temp'
	if not os.path.isdir( dst ):
		os.system( 'mkdir -p ' + dst )
	os.system( 'ln -svf ' + src + ' ' + dst )

	## precipitation (rain and snow)
	dst = 'input/global/climate/prec'
	if not os.path.isdir( dst ):
		os.system( 'mkdir -p ' + dst )

	src = dataroot + 'watch_wfdei/Rainf_daily/*'
	os.system( 'ln -svf ' + src + ' ' + dst )

	src = dataroot + 'watch_wfdei/Snowf_daily/*'
	os.system( 'ln -svf ' + src + ' ' + dst )

	## humidity (specific humidity in the case of WATCH-WFDEI)
	src = dataroot + 'watch_wfdei/Qair_daily/*'
	dst = 'input/global/climate/humd'
	if not os.path.isdir( dst ):
		os.system( 'mkdir -p ' + dst )
	os.system( 'ln -svf ' + src + ' ' + dst )

	## solar (shortwave) radiation
	src = dataroot + 'watch_wfdei/SWdown_daily/*'
	dst = 'input/global/climate/srad'
	if not os.path.isdir( dst ):
		os.system( 'mkdir -p ' + dst )
	os.system( 'ln -svf ' + src + ' ' + dst )


	## CRU climate input data (only ccov)
	##--------------------------------------
	dst = 'input/global/climate/ccov'
	if not os.path.isdir( dst ):
		os.system( 'mkdir -p ' + dst )

	## cloud cover
	src = dataroot + 'cru/ts_4.01/cru_ts4.01.1901.2016.cld.dat.nc'
	os.system( 'ln -svf ' + src + ' ' + dst )

	## daily minimum temperature
	src = dataroot + 'cru/ts_4.01/cru_ts4.01.1901.2016.tmn.dat.nc'
	os.system( 'ln -svf ' + src + ' ' + dst )

	## daily maximum temperature
	src = dataroot + 'cru/ts_4.01/cru_ts4.01.1901.2016.tmx.dat.nc'
	os.system( 'ln -svf ' + src + ' ' + dst )


	## Other directories
	##--------------------------------------
	## link 'run' and 'site_paramfils' directories
	if example:
		os.system( 'unlink run')
		os.system( 'unlink site_paramfils')
		os.system( 'ln -sv run_EXAMPLE run')
		os.system( 'ln -sv site_paramfils_EXAMPLE site_paramfils')
	else:
		os.system( 'unlink run')
		os.system( 'unlink site_paramfils')
		os.system( 'ln -svf ~/sofun_inputs/input_' + name + '_sofun/run .')
		os.system( 'ln -svf ~/sofun_inputs/input_' + name + '_sofun/site_paramfils site_paramfils')

else:
	##--------------------------------------
	## SITE-SCALE SIMULATIONS
	##--------------------------------------
	# ## use same site and simulation parameter files for cnmodel and cmodel simulations
	# if name == 'fluxnet_fixalloc':
	#   	name_climate_link = 'fluxnet_cnmodel'
	# elif name == 'olson_cmodel':
	#   	name_climate_link = 'olson'
	# elif name == 'campi_cmodel':
	#   	name_climate_link = 'campi'
	# elif name == 'fluxnet2015_cmodel':
	#   	name_climate_link = 'fluxnet2015'
	# elif name == 'fluxnet2015':
	#   	name_climate_link = 'fluxnet2015'
	# else:
	#   	name_climate_link = name


	os.system( 'unlink run')
	os.system( 'unlink site_paramfils')
	os.system( 'unlink input/global')
	os.system( 'ln -svf ~/sofun_inputs/input_' + name + '_sofun/run .')
	os.system( 'ln -svf ~/sofun_inputs/input_' + name + '_sofun/site_paramfils .')
	os.system( 'ln -svf ~/sofun_inputs/input_' + name + '_sofun/sitedata input/.')


