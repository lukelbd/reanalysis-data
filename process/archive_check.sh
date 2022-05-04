#!/bin/bash
#------------------------------------------------------------------------------#
# Detect missing files runs by scanning the logfiles from climate-getting runs
#------------------------------------------------------------------------------#
basedir=~/data/eraint
cd $basedir || { echo "Error: Failed to move to $basedir."; exit 1; }
for month in {01..12}; do
  if [ -d eraint$month ]; then
    # shellcheck disable=2164
    cd eraint$month
    echo "Month ${month}."
    [ -e missing.log ] && rm missing.log  # to overwrite
    # Year-by-year logfiles
    for year in {1986..2015}; do
      if [ -e archive_${year}.log ]; then
        cat archive_${year}.log | grep 'Open failed' | rev | cut -d/ -f1-2 | rev | cut -d\< -f1 | \
          grep -v -e \? -e 0229 -e 0230 -e 0231 -e 0431 -e 0631 -e 0931 -e 1131 \
          >>missing.log  # ignore calendar days that don't exist
      fi
    done
    # Single logfile
    if [ ! -e missing.log ] && [ -e log ]; then # single logfile
      cat log | grep 'Open failed' | rev | cut -d/ -f1-2 | rev | cut -d\< -f1 | \
        grep -v -e \? -e 0229 -e 0230 -e 0231 -e 0431 -e 0631 -e 0931 -e 1131 >missing.log
    fi
    [ -e missing.log ] || echo "No missing.log produced."
    [ -e missing.log ] && mv missing.log $basedir/missing_${month}.log
    cd $basedir || { echo "Error: Failed to move to $basedir."; exit 1; }
  fi
  cat missing_??.log >missing.log
  [ -d missing ] || mkdir missing
  mv missing*.log missing/
done
