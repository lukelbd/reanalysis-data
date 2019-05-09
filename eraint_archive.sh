#!/bin/bash
# FUNCTION FOR COMPUTING EXTRA REANALYSIS PARAMETERS
# Install NCL with the temporary fix for unsatisfiable error:
#   conda create -n ncl_fix -c conda-forge -c conda-forge/label/broken ncl \
#     poppler=0.52 xerces-c=3.1 gsl
# Run "cdo sinfon <file>" to check what is in each; to match number, see:
# http://apps.ecmwf.int/codes/grib/param-db
# Summary:
#   * ei.oper.an.pl.regn128uv.yyyymmddhh contains the following:
#     - U (131) component of wind
#     - V (132) component of wind
#   * ei.oper.an.pl.regn128sc.yyyymmddhh contains the following:
#     - PV (60) presumably using something like the NCL method
#     - geopotential (129) in m2/s2
#     - temperature (130) in K
#     - specific humidity (133) in kg/kg
#     - vertical velocity (135) in Pa/s
#     - relative vorticity (138) in 1/s
#     - divergence (155) in 1/s
#     - relative humidity (157) in %
#     - ozone mass mixing ratio (203) in kg/kg
#     - specific cloud liquid water content (246) in kg/kg
#     - specific cloud ice water content (247) in kg/kg
#     - fraction of cloud cover (248) in 0-1
#   * ei.oper.an.sfc.regn128sc.yyyymmddhh contains the following:
#     - low vegetation cover (27)
#     - high vegetation cover (28)
#     - low vegetation type (29)
#     - high vegetation type (30)
#     - 10m U-wind (165) in m/s
#     - 10m V-wind (166) in m/s
#     - skin temp (235) in K
#     - 2m temp (167) in K
#     - 2m dewpoint (168) in K
#     - sea surface temp (34) in K
#     - snow layer temp (238) in K
#     - ice temp layer 1 (35) in K
#     - ice temp layer 2 (36) in K
#     - ice temp layer 3 (37) in K
#     - ice temp layer 4 (38) in K
#     - soil temp level 1 (139) in K
#     - soil temp level 2 (170) in K
#     - soil temp level 3 (183) in K
#     - soil temp level 3 (236) in K
#     - volumetric soil water layer 1 (39) in m3/m3
#     - volumetric soil water layer 2 (40) in m3/m3
#     - volumetric soil water layer 3 (41) in m3/m3
#     - volumetric soil water layer 4 (42) in m3/m3
#     - skin reservoir content (198) in m of equiv. water
#     - total column water (136) in kg/m2
#     - total column water vapor (137) in kg/m2
#     - total column ozone (206) in m of equiv. water
#     - sea-ice cover (31) in 0-1
#     - snow albedo (32) in 0-1
#     - snow density (33) in kg/m3
#     - snow depth (141) in m of equiv. water
#     - surface pressure (134) in Pa
#     - mean sea-level pressure slp (151) in Pa ****this may be needed
#     - stdev of filtered subgrid orography (74) in m
#     - stdev of orography (160) no units
#     - surface geopotential (129) in m2/s2
#     - anisotropy of subgrid orography (161) no units
#     - angle of subgrid orography (162) in radians
#     - slope of subgrid orography (163) no units
#     - land-sea mask (172) in 0-1
#     - surface roughness (173) in m
#     - log of surface roughness length for heat (234) no units
#     - total cloud cover (164) in 0-1
#     - low cloud-cover (186) in 0-1
#     - mid cloud-cover (187) in 0-1
#     - high cloud-cover (188) in 0-1
#     - charnock (148) no units
################################################################################
# Initial stuff
rerun=false # compute values if already exist
testing=false # testing or no
flags="-O" # see if faster
process=./eraint_process
eraroot=~/data/eraint # storage of all data
years=({1979..2015}) # currently 2016 is incomplete; runs to July
years=({1986..2015}) # instead use most recent 30-year period
months=(07 04 10 12 02 06 08 03 05 09 11) # start with winter/summer, then
  # get spring/fall, then get the other in-between months
days=({01..31}) # will check if unavailable
hours=(00 06 12 18) # will check if unavailable
if $testing; then
  years=(2001 2002)
  months=(02)
  days=(29 28 27)
  hours=(00)
fi

# Check that tools are available
if ! hash ncl 2>/dev/null; then
  echo "ERROR: NCL is not in ${PATH}."
  exit 4
fi
if ! hash cdo 2>/dev/null || [ "$(which cdo)" == "/usr/local/bin/cdo" ]; then
  echo "ERROR: CDO is not in ${PATH}, or is the corrupted version."
  exit 4
fi

# Loop through time steps
template="ei.oper.an.pl.regn128??." # general
uvhourly_template=ei.oper.an.pl.regn128uv.
schourly_template=ei.oper.an.pl.regn128sc.
sfchourly_template=ei.oper.an.sfc.regn128sc.
uvmonthly_template=ei.moda.an.pl.regn128uv.
scmonthly_template=ei.moda.an.pl.regn128sc.
sfcmonthly_template=ei.moda.an.sfc.regn128sc.
root=/media/ldm-archive/reanalyses/era_interim
for month in ${months[@]}; do
  # Create monthly climatology from the
  # 6-hourly instantaneous data, each day and year of the month
  # The monthly-mean files should be 1.5GB before taking time-mean
  mt=$(date +%s) # save time
  ncdir=$eraroot/eraint$month # output directory
  $testing && ncdir=$eraroot/testing # so don't overwrite good stuff
  [ ! -d eraint$month ] && mkdir eraint$month
  for year in ${years[@]}; do
    # First get the data we can obtain from monthly means ouput
    # * Why bother? Because want e.g. surface data, which is stored in separate files,
    #   and will take appreciable time to read the surface data
    # * And while we're at it, might as well avoid having to take zonal means
    #   of the other data, just do it here
    if [ $month == "07" ] && [ $year -lt "2000" ]; then
      continue
    fi

    # Start subprocess
    # echo "Starting subprocess for Year ${year} Month ${month}."
    #   { # start subprocess
    log=$ncdir/log$year # logfile
    [ -e $log ] && rm $log # remove if exists
    if [ -r $ncdir/${year}${month}zonmeans.nc ]; then
      echo "Already got zonal means for Year ${year} Month ${month}."
      # and don't continue yet; need to check existence of flux terms
    else
      echo "Year ${year} Month ${month}." | tee -a $log
      echo "Getting zonal means from existing monthly GRIB files..." | tee -a $log
      ot=$(date +%s) # original time
      t=$(date +%s) # get time
      outmonthly=$ncdir/${year}${month}.nc # save here
      uvmonthly=$root/monthly/$uvmonthly_template$year${month}0100
      scmonthly=$root/monthly/$scmonthly_template$year${month}0100
      sfcmonthly=$root/monthly/$sfcmonthly_template$year${month}0100

      # Original method
      cdo $flags -f nc merge -chname,var131,u -chname,var132,v -selcode,131,132 $uvmonthly \
        -chname,var130,t -chname,var135,omega -chname,var129,z -selcode,130,135,129 $scmonthly \
        -chname,var151,slp -selcode,151 $sfcmonthly \
        $outmonthly 2>>$log # save in this simple file

      # Alternate method (just as fast; the merge command did not slow us down)
      # cdo $flags -f nc -selcode,131,132 $uvmonthly uvfile.nc 2>>$log
      # cdo $flags -f nc -selcode,130,135,129 $scmonthly scfile.nc 2>>$log
      # cdo $flags -f nc -selcode,151 $sfcmonthly sfcfile.nc 2>>$log
      # cdo merge -chname,var131,u -chname,var132,v uvfile.nc \
      #   -chname,var130,t -chname,var135,omega -chname,var129,z scfile.nc \
      #   -chname,var151,slp sfcfile.nc \
      #   $outmonthly 2>>$log # save in this simple file

      # Get the zonal means (after verifying we were successful)
      if [ $? != 0 ]; then
        echo "WARNING: Could not find GRIB files for Year ${year} Month ${month}."
        continue
      fi
      cdo $flags merge -zonmean -delname,z $outmonthly \
        -divc,9.80665 -zonmean -selname,z $outmonthly \
        ${outmonthly%.nc}zonmeans.nc 2>>$log
      attedfile=${outmonthly%.nc}zonmeans.nc
      ncatted -O -a code,,d,, $attedfile 2>/dev/null # delets all
      ncatted -O -a table,,d,, $attedfile 2>/dev/null # delets all
      ncatted -O -a long_name,u,c,c,"zonal component of wind" $attedfile 2>/dev/null
      ncatted -O -a units,u,c,c,"m/s" $attedfile 2>/dev/null
      ncatted -O -a long_name,v,c,c,"meridional component of wind" $attedfile 2>/dev/null
      ncatted -O -a units,v,c,c,"m/s" $attedfile 2>/dev/null
      ncatted -O -a long_name,t,c,c,"air temperature" $attedfile 2>/dev/null
      ncatted -O -a units,t,c,c,"K" $attedfile 2>/dev/null
      ncatted -O -a long_name,omega,c,c,"vertical velocity" $attedfile 2>/dev/null
      ncatted -O -a units,omega,c,c,"Pa/s" $attedfile 2>/dev/null
      ncatted -O -a long_name,z,c,c,"geopotential height" $attedfile 2>/dev/null
      ncatted -O -a units,z,c,c,"m" $attedfile 2>/dev/null
      ncatted -O -a long_name,slp,c,c,"sea level pressure" $attedfile 2>/dev/null
      ncatted -O -a units,slp,c,c,"Pa" $attedfile 2>/dev/null
      rm $outmonthly # remove original
      echo "Took $(($(date +%s) - $t)) seconds."
    fi

    # Next get the stuff that has to be computed on synoptic timesteps
    [ ! -d $ncdir/fluxes ] && mkdir $ncdir/fluxes
    for day in ${days[@]}; do
      for hour in ${hours[@]}; do
        if [ -r $ncdir/fluxes/${year}${month}${day}${hour}fluxes.nc ]; then
          echo "Already got flux terms for Year ${year} Month ${month} Day ${day} Hour ${hour}."
          continue # already got these fluxes
        fi
        outhourly=$ncdir/fluxes/${year}${month}${day}${hour}.nc # save here
        uvhourly=$root/6-hourly/$year/$uvhourly_template$year$month$day$hour
        schourly=$root/6-hourly/$year/$schourly_template$year$month$day$hour
        # sfchourly=$root/6-hourly/$year/$sfchourly_template$year$month$day$hour
        # sfccodes=151 # just the SLP

        # Keep the files separate then merge at the final second; only need to 
        # pass glob-command to merge if it is chained, so this avoids glob query
        # Timing tests (reveals bottlneck is just reading files):
        # -28s with z read from file separately from other files
        # -11s with z and other vars at same time; SAME time without z
        # -13s with other vars and slp; MUCH SMALLER file but appreciable time added
        echo "Year ${year} Month ${month} Day ${day} Hour ${hour}." | tee -a $log
        echo "Getting flux terms from GRIB files..." | tee -a $log
        t=$(date +%s) # get time
        cdo $flags -f nc merge -chname,var131,u -chname,var132,v -selcode,131,132 $uvhourly \
          -chname,var130,t -chname,var135,omega -selcode,130,135 $schourly \
          $outhourly 2>>$log
          # -chname,var151,slp -selcode,$sfccodes $sfchourly \
          # -divc,9.80665 -chname,var129,z -selcode,$zcode $schourly \

        # Get the special variables (after verifying we were successful)
        if [ $? != 0 ]; then
          echo "WARNING: Could not find GRIB files for Year ${year} Month ${month} Day ${day} Hour ${hour}."
          continue
        fi
        $process "$outhourly" # computes stuff
        rm $outhourly # remove temporary file
        echo "Took $(($(date +%s) - $t)) seconds."
      done
    done

    # Combine the flux files into a single year-month file
    # * Keep the flux files; they amount to 226KB * (4 * 30 * 30) = 813MB
    #   for each month; times 12 months is only 10GB of data.
    # * Note cannot chain merge file.nc -mergetime "file?.nc" out.nc or
    #   merge file.nc -mergetime ${files[@]} out.nc; both fail
    if [ -r ${outmonthly%.nc}fluxes.nc ]; then
      echo "Already got time-average of flux terms for Year ${year} Month ${month}."
      continue # already got these fluxes
    fi
    echo "Getting time-average from hourly fluxes..." | tee -a $log
    cdo $flags timmean -mergetime "$ncdir/fluxes/${year}${month}????fluxes.nc" \
      ${outmonthly%.nc}fluxes.nc 2>>$log # gets the monthly mean
    # rm $ncdir/${year}${month}????fluxes.nc # removes each hourly file
    echo "Year $year Month $month took $(($(date +%s) - $ot)) seconds."
    #   } &>eraint$month/summary$year & # subshell for processing each year
    # # Exit subprocess management
    # if [ $year == 1999 ] && [ $month != "07" ]; then
    #   echo "Month ${month}: declared subprocesses for years 1986-1999. Waiting now..."
    #   wait # for finish; then continue
    # fi
  done
  # Echo message
  echo "Month $month took $(($(date +%s) - $mt)) seconds."
  # echo "Month ${month}: declared subprocesses for years 2000-2015. Waiting now..."
  # wait # wait for processes afterward; we are parallelizing on 30 cores
done
