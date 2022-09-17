#!/bin/bash
#-----------------------------------------------------------------------------#
# Combine the yearly files into a climatology
#-----------------------------------------------------------------------------#
# For selective climatology, need to use e.g. '200[0-9]01fluxes.nc'
# This has limitations, but easy to use e.g. '[1-2][09][089][0-9]' for 1980-2009
flags="-O" # flags
base=~/data/era-interim
log=$base/eraint_climo_plevs.log # store info in here
logecho() { echo "$@" | tee -a "$log"; }
nclcheck() { cat $1 | grep -v "Execute.c" | grep -v "systemfunc" | grep "fatal:" &>/dev/null; }
cd $base || { echo "Error: Failed to cd into '$base'."; exit 1; }

# Iterate through months
rm $log &>/dev/null
months=({1..12}) # every month
years=({1981..2010}) # range for average
# years=({1980..2015}) # range for average
for month in ${months[@]}; do
  # Test file availability
  logecho "Getting time-average from month $month fluxes and zonmeans..."
  month=$(printf "%02d" $month) # 01 02 etc.
  ncdir=eraint$month # directory
  list=("${years[@]/#/$ncdir/}")
  zlist=("${list[@]/%/${month}zonmeans.nc}")
  flist=("${list[@]/%/${month}fluxes.nc}")
  for zfile in ${zlist[@]}; do
    if [ ! -r $zfile ]; then
      logecho "File ${zfile##*/} not available."
      zlist=("${zlist[@]/$zfile}")
    fi
  done
  for ffile in ${flist[@]}; do
    if [ ! -r $ffile ]; then
      logecho "File ${ffile##*/} not available."
      flist=("${flist[@]/$ffile}")
    fi
  done

  # Merge the data
  cdo $flags -mergetime ${flist[@]} ${month}fluxes.nc 2>&1 | tee -a "$log"
  cdo $flags -mergetime ${zlist[@]} ${month}zonmeans.nc 2>&1 | tee -a "$log"
  cdo $flags -merge \
    -setdate,0001-$month-01 -settime,00:00:00 -timmean \
      -chname,EKE,eke -chname,CKE,cke -chname,EHF,ehf -chname,EMF,emf ${month}fluxes.nc \
    -setdate,0001-$month-01 -settime,00:00:00 -timmean ${month}zonmeans.nc \
    climate${month}.nc 2>&1 | tee -a "$log"
  rm ${month}fluxes.nc ${month}zonmeans.nc
done

# Final merge
# Also make latitudes go south to north like any sane person would want
# Note array index array[-1] added in bash 4 only; older versions, use below
# NOTE: Used to put climatology in one file, but now keep them separate so we
# can add diabatic data (expensive to download) to individual file.
levs=$(seq 2500 2500 100000 | tr $'\n' ',') # interpolate here
for month in ${months[@]}; do
  month=$(printf "%02d" $month)  # 01 02 etc.
  cdo $flags -invertlat -genlevelbounds,ztop=101325,zbot=0 -intlevel,${levs%,} \
    climate${month}.nc climate${month}_interp.nc 2>&1 | tee -a "$log"
  ncatted -O -a units,plev,o,c,"mb" climate${month}_interp.nc 2>&1 | tee -a "$log"
  ncap2 -O -s "plev=plev/100; plev_bnds=plev_bnds/100" climate${month}_interp.nc \
    climate_${years[0]}-${years[@]:(-1)}_${month}.nc 2>&1 | tee -a "$log"
  # -mergetime "climate??.nc" climate.nc
  # rm climate.nc climate??.nc
done
rm climate??.nc climate??_interp.nc

# Method for separate timmean commands
# cdo $flags -merge -timmean -mergetime "$ncdir/????${month}zonmeans.nc" \
#              -timmean -mergetime "$ncdir/????${month}fluxes.nc" \
#   climate${month}.nc 2>>$log # apparently this works somehow
# cdo $flags timmean -mergetime "$ncdir/????${month}zonmeans.nc" \
#   $ncdir/zonmeans${month}.nc 2>>$log # captures files named yyyymmWORDS.nc, ignores hourly
# cdo $flags timmean -mergetime "$ncdir/????${month}fluxes.nc" \
#   $ncdir/fluxes${month}.nc 2>>$log # captures files named yyyymmWORDS.nc, ignores hourly
