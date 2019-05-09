#!/bin/bash
flags="-O"
ncfile="$1" # the file
ncdir="${ncfile%/*}" # storage directory
pout="$ncdir/out" # output prefix
log="${ncdir%/*}/log" # original log
cdo=cdo # optionally point to another cdo
# This file gets some basic dynamical quantities using CDO
##############################################################################
# First the simple zonal-mean of data
# Decided against this, may as well get monthly means
# $cdo $flags -zonmean $ncfile ${pout}1.nc 2>>$log
# ncatted -O -a code,,d,, ${pout}1.nc 2>/dev/null # delets all
# ncatted -O -a table,,d,, ${pout}1.nc 2>/dev/null # delets all
##############################################################################
# Flux terms: heat flux, momentum flux, and PV flux
# Use ncatted because it has DELETE feature (delete codenames; otherwise get
# issues in CDO processing during merges) and CREATE feature (when atts don't exist)
# echo "Heat flux"
out=${pout}1.nc
# t=$(date +%s)
$cdo $flags chname,t,ehf -zonmean \
  -mul -sub -selname,t $ncfile -enlarge,$ncfile -zonmean -selname,t $ncfile \
       -sub -selname,v $ncfile -enlarge,$ncfile -zonmean -selname,v $ncfile \
  $out 2>>$log #2> /dev/null # heat flux, with EP scaling
ncatted -O -a code,,d,, $out 2>/dev/null # delets all
ncatted -O -a table,,d,, $out 2>/dev/null # delets all
ncatted -O -a long_name,ehf,c,c,"eddy heat flux" $out 2>/dev/null
ncatted -O -a units,ehf,c,c,"K m/s" $out 2>/dev/null
# echo "ehf time: $(($(date +%s) - $t))s."
# echo "Momentum flux"
out=${pout}2.nc
$cdo $flags chname,u,emf -zonmean \
  -mul -sub -selname,u $ncfile -enlarge,$ncfile -zonmean -selname,u $ncfile \
       -sub -selname,v $ncfile -enlarge,$ncfile -zonmean -selname,v $ncfile \
  $out 2>>$log #2> /dev/null # momentum flux, needs no EP scaling
ncatted -O -a code,,d,, $out 2>/dev/null # delets all
ncatted -O -a table,,d,, $out 2>/dev/null # delets all
ncatted -O -a long_name,emf,c,c,"eddy momentum flux" $out 2>/dev/null
ncatted -O -a units,emf,c,c,"m2/s2" $out 2>/dev/null

##############################################################################
# Energy terms: eke each latitude, KE generation each latitude, total KE each latitude
# echo "Eddy kinetic energy"
out=${pout}3.nc
$cdo $flags chname,u,eke -divc,9.81 -divc,2 \
  -add -zonmean -sqr -sub -selname,u $ncfile -enlarge,$ncfile -zonmean -selname,u $ncfile \
       -zonmean -sqr -sub -selname,v $ncfile -enlarge,$ncfile -zonmean -selname,v $ncfile \
  $out 2>>$log #2> /dev/null # eddy kinetic energy
ncatted -O -a code,,d,, $out 2>/dev/null # delets all
ncatted -O -a table,,d,, $out 2>/dev/null # delets all
ncatted -O -a long_name,eke,c,c,"eddy kinetic energy" $out 2>/dev/null
ncatted -O -a units,eke,c,c,"J/m2 Pa" $out 2>/dev/null
# echo "Kinetic energy conversion"
out=${pout}4.nc
$cdo $flags chname,t,cke -divc,9.81 -mulc,287 \
  -zonmean -mul -sub -selname,t $ncfile -enlarge,$ncfile -zonmean -selname,t $ncfile \
                -sub -selname,omega $ncfile -enlarge,$ncfile -zonmean -selname,omega $ncfile \
  $out 2>>$log #2> /dev/null # vertical heat flux, scaled as energy term
ncatted -O -a code,,d,, $out 2>/dev/null # delets all
ncatted -O -a table,,d,, $out 2>/dev/null # delets all
ncatted -O -a long_name,cke,c,c,"kinetic energy generation" $out 2>/dev/null
ncatted -O -a units,cke,c,c,"W/m2" $out 2>/dev/null

##############################################################################
# Simple terms: zonal eddy-u variance, eddy-T variance
# These are from Held-Suarez ideas
# echo "Eddy zonal wind variance"
out=${pout}5.nc
$cdo $flags chname,t,tvar -zonmean \
  -sqr -sub -selname,t $ncfile -enlarge,$ncfile -zonmean -selname,t $ncfile \
  $out 2>>$log #2> /dev/null # heat flux, with EP scaling
ncatted -O -a code,,d,, $out 2>/dev/null # delets all
ncatted -O -a table,,d,, $out 2>/dev/null # delets all
ncatted -O -a long_name,tvar,c,c,"temperature eddy-variance" $out 2>/dev/null
ncatted -O -a units,tvar,c,c,"K2" $out 2>/dev/null
# echo "Eddy temperature variance"
out=${pout}6.nc
$cdo $flags chname,u,uvar -zonmean \
  -sqr -sub -selname,u $ncfile -enlarge,$ncfile -zonmean -selname,u $ncfile \
  $out 2>>$log #2> /dev/null # heat flux, with EP scaling
ncatted -O -a code,,d,, $out 2>/dev/null # delets all
ncatted -O -a table,,d,, $out 2>/dev/null # delets all
ncatted -O -a long_name,uvar,c,c,"zonal-wind eddy-variance" $out 2>/dev/null
ncatted -O -a units,uvar,c,c,"m2/s2" $out 2>/dev/null

################################################################################
# Combine all the output files
files=(${pout}{1..6}.nc)
for file in ${files[@]}; do
  [ ! -r $file ] && { echo "ERROR: File $file not found."; exit 3; }
done
$cdo $flags merge ${files[@]} ${ncfile%.nc}fluxes.nc 2>>$log
rm ${files[@]} # remove temporary files

