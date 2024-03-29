#!/usr/bin/env bash
#-----------------------------------------------------------------------------#
# Merge archived pressure level and downloaded model level data
#-----------------------------------------------------------------------------#
# We have archived ERA-Interim data from the student server, and downloaded model-level
# data in the folder mlevs. This file simply merges the times in that folder, gets zonal
# means, interpolates to the same grid as the archived data (assumed in griddes.txt),
# and adds them to that file. We interpolate onto levels every 25hPa.
# WARNING: Not sure if interpolation of 1D slice will work properly!
shopt -s nullglob
cwd=$(pwd)
base=~/data/era-interim
log=$base/eraint_climo_mlevs.log  # store info in here
ncl=$cwd/${0##*/}.ncl  # script for interpolating and averaging
flags=-O  # cdo flags
logecho() { echo "$@" | tee -a "$log"; }
nclcheck() { cat $1 | grep -v "Execute.c" | grep -v "systemfunc" | grep "fatal:" &>/dev/null; }
cd $base || { echo "Erorr: Failed to go to $base."; exit 1; }

# Iterate through months
rm $log &>/dev/null
months=(1 7)
for month in ${months[@]}; do
  # File names
  month=$(printf "%02d" $month) # 01 02 etc.
  tdt_files=(mlevs/tdt_????-????_${month}.grb2) # note glob will be *sorted* by start year
  [ ${#tdt_files[@]} -eq 0 ] && logecho "Warning: No files found." && continue

  # Get time means of each, then combine
  # TODO: Should download tdt and msp in the same file.
  i=0
  year1a=9999 # bash arithmetic expansion does not care about leading zeros
  year2a=0000
  output=()
  for tdt_file in ${tdt_files[@]}; do
    logecho "Interpolating and averaging file: $tdt_file"
    years=${tdt_file#*_}
    years=${years%_*}
    year1=${years%-*}
    year2=${years#*-}
    year1a=$((year1 < year1a ? year1 : year1a))
    year2a=$((year2 > year2a ? year2 : year2a))
    msp_file=${tdt_file/tdt/msp}
    ! [ -r "$msp_file" ] && logecho "Warning: File $msp_file not found." && continue
    ncl -n -Q "tdt_file=\"$tdt_file\"" "msp_file=\"$msp_file\"" \
      "output=\"tmp${i}.nc\"" "$ncl" 2>&1 | tee -a $log
    # ncl -n -Q "tdt_file=\"$tdt_file\"" "msp_file=\"$msp_file\"" \
    #   "output=\"tmp${i}.nc\"" "$ncl" 2>&1 | tee -a $log
    # nclcheck $log && logecho "Error: Average failed." && exit 1
    output+=(tmp${i}.nc)
    i=$((i+1))
    logecho
  done
  [ ${#output[@]} -eq 0 ] && logecho "Error: No files processed." && exit 1

  # Merge and standardize data
  logecho "Found years: ${year1a}-${year2a}"
  if [ ${#output[@]} -eq 1 ]; then
    mv ${output[0]} tmp.nc
  else
    cdo $flags -ensmean ${output[@]} tmp.nc | tee -a "$log" \
      || { logecho "Error: Merge failed."; exit 1; }
    rm ${output[@]}
  fi
  file=tdt_${year1a}-${year2a}_${month}.nc
  cdo $flags -remapbil,griddes.txt -invertlat tmp.nc $file | tee -a "$log" \
    || { logecho "Error: Interpolation failed."; exit 1; }
  rm tmp.nc

  # Optionally add to existing climate file
  climate=climate_${year1a}-${year2a}_${month}.nc
  if [ -r $climate ]; then
    vars=$(cdo $flags -showname $climate)
    if [[ " ${vars[*]} " =~ " tdt " ]]; then
      logecho "Warning: Heating already in file."
    else
      ncks --no-abc -A $file $climate | tee -a "$log"
    fi
  else
    logecho "Warning: Climate file $climate not found."
  fi
done

