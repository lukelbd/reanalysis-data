#!/bin/bash
#------------------------------------------------------------------------------#
# Detects missing files in climate runs by scanning the logfiles from my
# climate-getting runs
#------------------------------------------------------------------------------#
basedir=~/data/eraint
cd $basedir # the working directory; start here
for month in {01..12}; do
  if [ -d eraint$month ]; then
    echo "Month ${month}."
    cd eraint$month
    [ -e logMISSING ] && rm logMISSING # to overwrite
    # Year-by-year logfiles
    for year in {1986..2015}; do
      if [ -e log$year ]; then
        cat log$year | grep 'Open failed' | rev | cut -d/ -f1-2 | rev | cut -d\< -f1 | \
          grep -v -e \? -e 0229 -e 0230 -e 0231 -e 0431 -e 0631 -e 0931 -e 1131 \
          >>logMISSING # ignore calendar days that don't exist
      fi
    done
    # Single logfile
    if [ ! -e logMISSING ] && [ -e log ]; then # single logfile
      cat log | grep 'Open failed' | rev | cut -d/ -f1-2 | rev | cut -d\< -f1 | \
        grep -v -e \? -e 0229 -e 0230 -e 0231 -e 0431 -e 0631 -e 0931 -e 1131 >logMISSING
    fi
    [ ! -e logMISSING ] && echo "No logMISSING produced."
    [ -e logMISSING ] && mv logMISSING $basedir/log${month}MISSING
    cd $basedir
  fi # end of loop
  cat log??MISSING >logMISSING # into file
  [ ! -d missing ] && mkdir missing # make sure folder exists
  mv log*MISSING missing/
done
