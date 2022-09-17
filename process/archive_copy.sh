#!/bin/bash
#-----------------------------------------------------------------------------#
# Function for copying and saving climate parameters from raw archive data.
# Then params_plevs.py is run on the resulting files to add eddy flux terms.
#-----------------------------------------------------------------------------#
# * Install ncl with the temporary fix for unsatisfiable error: conda create -n ncl
#   -c conda-forge -c conda-forge/label/broken ncl poppler=0.52 xerces-c=3.1 gsl
# * Run "cdo sinfon <file>" to check what is in each. To match the number see
#   the eraint_download.py file and http://apps.ecmwf.int/codes/grib/param-db.
# * For low, middle, high cloud cover sigma threshold definitions see
#   https://confluence.ecmwf.int/pages/viewpage.action?pageId=111155326.
# * The ei.oper.an.pl.regn128uv.yyyymmddhh folders contain the following:
#   - u (131) component of wind
#   - v (132) component of wind
# * The ei.oper.an.pl.regn128sc.yyyymmddhh folders contain the following:
#   - pv (60) presumably using something like the NCL method
#   - geopotential (129) in m2/s2
#   - temperature (130) in K
#   - specific humidity (133) in kg/kg
#   - vertical velocity (135) in Pa/s
#   - relative vorticity (138) in 1/s
#   - divergence (155) in 1/s
#   - relative humidity (157) in %
#   - ozone mass mixing ratio (203) in kg/kg
#   - specific cloud liquid water content (246) in kg/kg
#   - specific cloud ice water content (247) in kg/kg
#   - fraction of cloud cover (248) in 0-1
# * The ei.oper.an.sfc.regn128sc.yyyymmddhh folders contain the following:
#   - 10m u-wind (165) in m/s
#   - 10m v-wind (166) in m/s
#   - skin temp (235) in K
#   - 2m temp (167) in K
#   - 2m dewpoint (168) in K
#   - sea surface temp (34) in K
#   - snow layer temp (238) in K
#   - total column water (136) in kg/m2
#   - total column water vapor (137) in kg/m2
#   - total column ozone (206) in m of equiv. water
#   - sea-ice cover (31) in 0-1
#   - snow albedo (32) in 0-1
#   - snow density (33) in kg/m3
#   - snow depth (141) in m of equiv. water
#   - surface pressure (134) in Pa
#   - mean sea-level pressure slp (151) in Pa ****this may be needed
#   - surface geopotential (129) in m2/s2
#   - land-sea mask (172) in 0-1
#   - total cloud cover (164) in 0-1
#   - low cloud-cover (186) in 0-1
#   - mid cloud-cover (187) in 0-1
#   - high cloud-cover (188) in 0-1
rerun=false  # compute values if already exist
testing=false  # testing or no
flags="-O"  # see if faster
process=${0%/*}/params_plevs.sh
storage=~/data/era-interim/  # storage of all data
scratch=~/scratch3/  # storage of flux data
years=({1979..2015})  # currently 2016 is incomplete; runs to July
years=({1986..2015})  # instead use most recent 30-year period
months=(07 04 10 12 02 06 08 03 05 09 11)  # start with winter/summer, then others
days=({01..31})  # will check if unavailable
hours=(00 06 12 18)  # will check if unavailable
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
template='ei.oper.an.pl.regn128??.'  # general
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
  mt=$(date +%s)  # save time
  mscratch=$scratch/eraint$month
  mstorage=$storage/eraint$month  # output directory
  $testing && mstorage=$storage/testing  # so don't overwrite good stuff
  [ -d eraint$month ] || mkdir eraint$month
  for year in ${years[@]}; do
    # Merge, copy, and translate monthly mean data, then get the zonal means.
    # echo "Starting subprocess for Year ${year} Month ${month}."
    # * Why bother? Because want e.g. surface data, which is stored in
    #   separate files, and will take appreciable time to read the surface data
    # * And while we're at it, might as well avoid having to take zonal means
    #   of the other data, just do it here
    # {  # start subprocess
    if [ $month == "07" ] && [ $year -lt "2000" ]; then
      continue  # kludge... missing or corrupt data?
    fi
    log=$mstorage/archive_${year}.log  # logfile
    uvmonthly=$root/monthly/$uvmonthly_template$year${month}0100
    scmonthly=$root/monthly/$scmonthly_template$year${month}0100
    sfcmonthly=$root/monthly/$sfcmonthly_template$year${month}0100
    outmonthly=$mscratch/${year}${month}.nc
    outmonthly_fluxes=$mstorage/${year}${month}fluxes.nc
    outmonthly_zonmeans=$mstorage/${year}${month}zonmeans.nc
    [ -e $log ] && rm $log  # remove if exists
    if [ -r $outmonthly_zonmeans ]; then
      echo "Already got zonal means: Year ${year} Month ${month}."
    else
      echo "Year ${year} Month ${month}." | tee -a $log
      echo "Getting zonal means from existing monthly GRIB files..." | tee -a $log
      ot=$(date +%s)  # original time
      t=$(date +%s)  # get time
      cdo $flags -f nc merge -chname,var131,u -chname,var132,v -selcode,131,132 $uvmonthly \
        -chname,var130,t -chname,var135,omega -chname,var129,z -selcode,130,135,129 $scmonthly \
        -chname,var151,slp -selcode,151 $sfcmonthly \
        $outmonthly 2>>$log \
        || {
          echo "Warning: Could not find GRIB files: Year ${year} Month ${month}."
          continue
        }
      cdo $flags merge -zonmean -delname,z $outmonthly \
        -divc,9.80665 -zonmean -selname,z $outmonthly \
        $outmonthly_zonmeans 2>>$log
      ncatted -O -a code,,d,, $outmonthly_zonmeans 2>/dev/null  # deletes all
      ncatted -O -a table,,d,, $outmonthly_zonmeans 2>/dev/null  # deletes all
      ncatted -O -a long_name,u,c,c,"zonal component of wind" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a units,u,c,c,"m/s" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a long_name,v,c,c,"meridional component of wind" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a units,v,c,c,"m/s" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a long_name,t,c,c,"air temperature" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a units,t,c,c,"K" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a long_name,omega,c,c,"vertical velocity" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a units,omega,c,c,"Pa/s" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a long_name,z,c,c,"geopotential height" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a units,z,c,c,"m" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a long_name,slp,c,c,"sea level pressure" $outmonthly_zonmeans 2>/dev/null
      ncatted -O -a units,slp,c,c,"Pa" $outmonthly_zonmeans 2>/dev/null
      rm $outmonthly  # could also keep this data for convenience?
      echo "Took $(($(date +%s) - $t)) seconds."
    fi

    # Next get the stuff that has to be computed on synoptic timesteps
    # * Keep the flux files; they amount to 226KB * (4 * 30 * 30) = 813MB
    #   for each month; times 12 months is only 10GB of data.
    # * Note cannot chain merge file.nc -mergetime "file?.nc" out.nc or
    #   merge file.nc -mergetime ${files[@]} out.nc; both fail
    [ -d $mscratch ] || mkdir $mscratch
    for day in ${days[@]}; do
      for hour in ${hours[@]}; do
        # sfccodes=151  # just the slp
        # sfchourly=$root/6-hourly/$year/$sfchourly_template$year$month$day$hour
        schourly=$root/6-hourly/$year/$schourly_template$year$month$day$hour
        uvhourly=$root/6-hourly/$year/$uvhourly_template$year$month$day$hour
        outhourly=$mscratch/${year}${month}${day}${hour}fluxes.nc  # save here
        if [ -r $outhourly ]; then
          echo "Already got flux terms: Year ${year} Month ${month} Day ${day} Hour ${hour}."
          continue  # already got these fluxes
        fi
        echo "Year ${year} Month ${month} Day ${day} Hour ${hour}." | tee -a $log
        echo "Getting flux terms from GRIB files..." | tee -a $log
        t=$(date +%s)  # get time
        # -chname,var151,slp -selcode,$sfccodes $sfchourly \
        # -divc,9.80665 -chname,var129,z -selcode,$zcode $schourly \
        cdo $flags -f nc merge -chname,var131,u -chname,var132,v -selcode,131,132 $uvhourly \
          -chname,var130,t -chname,var135,omega -selcode,130,135 $schourly \
          $outhourly 2>>$log \
          || {
            echo "Warning: Could not find GRIB files: Year ${year} Month ${month} Day ${day} Hour ${hour}."
            continue
          }
        $process "$outhourly"  # computes stuff
        rm $outhourly  # remove temporary file
        echo "Took $(($(date +%s) - $t)) seconds."
      done
    done
    if [ -r ${outmonthly%.nc}fluxes.nc ]; then
      echo "Already got time-average of flux terms for Year ${year} Month ${month}."
      continue  # already got these fluxes
    fi
    echo "Getting time-average from hourly fluxes..." | tee -a $log
    cdo $flags timmean -mergetime "$mscratch/${year}${month}????fluxes.nc" \
      $outmonthly_fluxes 2>>$log  # gets the monthly mean
    echo "Year $year Month $month took $(($(date +%s) - $ot)) seconds."
    # } &>eraint$month/summary$year &  # subshell for processing each year
    # Exit subprocess management
    # if [ $year == 1999 ] && [ $month != "07" ]; then
    #   echo "Month ${month}: declared subprocesses for years 1986-1999. Waiting now..."
    #   wait  # for finish; then continue
    # fi
  done
  # Echo message
  echo "Month $month took $(($(date +%s) - $mt)) seconds."
  # echo "Month ${month}: declared subprocesses for years 2000-2015. Waiting now..."
  # wait  # wait for processes afterward; we are parallelizing on 30 cores
done
